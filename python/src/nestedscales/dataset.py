"""The scale-aware dataset store (port of R/dataset.R).

A folder that reopens as DATA ON SCALES, readable from R and Python alike:

    path/
      data/                    hive-partitioned Arrow IPC files
        year=2021/part-0.arrow
      _scales/
        manifest.yaml          axes, keys, frames, members, meta
        <axis>-leaftable.arrow

A scale whose meta holds values YAML cannot represent is refused at write
time rather than silently half-saved.
"""
from __future__ import annotations

import shutil
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.ipc as ipc
import yaml

from ._backend import backend_of, scan
from ._utils import _as_str_tuple, _preview, _stop, _warn
from .product import ScaleProduct, scale_product
from .scale_class import NestedScale, _check_scale, _scale_name

_SCALAR = (str, int, float, bool, type(None))


def _ipc_codec(compression: str) -> str | None:
    c = compression.lower()
    if c in ("uncompressed", "none"):
        return None
    if c == "lz4_frame":
        c = "lz4"
    if not pa.Codec.is_available(c):
        _warn("compression codec '%s' is unavailable; writing uncompressed",
              compression)
        return None
    return c


def _plain(v: Any) -> Any:
    """Tuples to lists, recursively, so YAML writes plain sequences."""
    if isinstance(v, (list, tuple)):
        return [_plain(z) for z in v]
    if isinstance(v, Mapping):
        return {k: _plain(z) for k, z in v.items()}
    return v


def _serialisable_meta(meta: Mapping[str, Any], nm: str) -> dict:
    def ok(z: Any) -> bool:
        if isinstance(z, _SCALAR):
            return True
        if isinstance(z, (list, tuple)):
            return all(isinstance(y, _SCALAR) for y in z)
        if isinstance(z, Mapping):
            return all(isinstance(y, _SCALAR) or (isinstance(y, (list, tuple))
                       and all(isinstance(u, _SCALAR) for u in y))
                       for y in z.values())
        return False

    bad = [k for k, z in meta.items() if not ok(z)]
    if bad:
        _stop('the `meta` of scale "%s" holds value(s) that cannot be written as '
              "YAML: %s. Drop them before writing, or store them alongside the "
              "dataset yourself.", nm, _preview(bad))
    return _plain(dict(meta))


def _scale_manifest(s: NestedScale) -> dict:
    nm = _scale_name(s, require=False)
    return {"name": nm or None, "key": s.key, "frames": list(s.frames),
            "members": {f: list(c) for f, c in s.members.items()},
            "meta": _serialisable_meta(s.meta, nm)}


def _flatten(v: Any) -> list:
    """YAML gives a length-1 vector back as a scalar and a vector as a list."""
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return [z for z in v]
    return [v]


def _scale_from_manifest(entry: Mapping[str, Any], leaftable: pa.Table) -> NestedScale:
    meta = dict(entry.get("meta") or {})
    if meta.get("weights") is not None:
        meta["weights"] = [str(z) for z in _flatten(meta["weights"])]
    if isinstance(meta.get("residuals"), Mapping):
        meta["residuals"] = {k: [str(z) for z in _flatten(v)]
                             for k, v in meta["residuals"].items()}
    # R's yaml writes a named numeric vector as a bare sequence (names lost)
    # and rounds it to 7 digits. The names are the declared weights, in order;
    # coverage is recomputed from the parent totals, which is what it is.
    wts = meta.get("weights") or []
    for f in ("coverage", "parent_totals"):
        v = meta.get(f)
        if isinstance(v, Mapping):
            meta[f] = {k: float(z) for k, z in v.items()}
        elif v is not None:
            meta[f] = {w: float(z) for w, z in zip(wts, _flatten(v), strict=False)}
    pt = meta.get("parent_totals")
    if isinstance(meta.get("coverage"), Mapping) and isinstance(pt, Mapping):
        from .scale_class import _finite_sum

        meta["coverage"] = {
            w: (_finite_sum(leaftable[w].to_pylist()) / pt[w] if w in pt else c)
            for w, c in meta["coverage"].items()}
    members = {f: [str(z) for z in _flatten(c)]
               for f, c in (entry.get("members") or {}).items()}
    return NestedScale(leaftable=leaftable,
                       frames=[str(z) for z in _flatten(entry.get("frames"))],
                       members=members, key=entry.get("key") or "unit", meta=meta)


def write_scale_dataset(data: Any, x: NestedScale | ScaleProduct, path: str | Path,
                        partitioning: str | Sequence[str] | None = None,
                        compression: str = "zstd", overwrite: bool = False) -> Path:
    """Write data and the scales that index it to one folder."""
    from . import __version__

    is_prod = isinstance(x, ScaleProduct)
    if not is_prod:
        _check_scale(x, "x")
    bk = backend_of(data, "data")
    d = scan(data, bk)
    if is_prod:
        axes, keys = dict(x.axes), dict(x.keys)
    else:
        nm = _scale_name(x, require=False) or "scale"
        axes, keys = {nm: x}, {nm: x.key}
    missing = [k for k in keys.values() if k not in d.column_names]
    if missing:
        _stop("the data has no column(s) %s (one key column per axis)",
              _preview(missing))
    parts = list(_as_str_tuple(partitioning))
    bad = [c for c in parts if c not in d.column_names]
    if bad:
        _stop("`partitioning` names column(s) not in the data: %s", _preview(bad))
    codec = _ipc_codec(compression)

    path = Path(path)
    if path.exists():
        if not overwrite:
            _stop("`%s` already exists; pass overwrite = TRUE to replace it", path)
        shutil.rmtree(path)
    sdir = path / "_scales"
    sdir.mkdir(parents=True)

    # scales first: fail before writing data that would then describe nothing
    manifest = {"nestedscales": __version__,
                "kind": "product" if is_prod else "scale",
                "keys": keys, "axes": {a: _scale_manifest(s) for a, s in axes.items()}}
    opts = ipc.IpcWriteOptions(compression=codec)
    for a, s in axes.items():
        with ipc.new_file(sdir / ("%s-leaftable.arrow" % a), s.leaftable.schema,
                          options=opts) as w:
            w.write_table(s.leaftable)
    (sdir / "manifest.yaml").write_text(
        yaml.safe_dump(manifest, sort_keys=False, allow_unicode=True),
        encoding="utf-8")

    fmt = ds.IpcFileFormat()
    ds.write_dataset(d, path / "data", format=fmt,
                     file_options=fmt.make_write_options(compression=codec),
                     partitioning=parts or None,
                     partitioning_flavor="hive" if parts else None,
                     basename_template="part-{i}.arrow")
    return path


@dataclass(frozen=True)
class ScaleDataset:
    """An opened store: `data` (a lazily read pyarrow Dataset) and `scale`."""

    data: ds.Dataset
    scale: NestedScale | ScaleProduct
    path: Path

    def __str__(self) -> str:
        info = scale_dataset_info(self.path)
        return "\n".join([
            "<scale_dataset> %s" % self.path,
            "  rows:  %s" % format(self.data.count_rows(), ","),
            "  files: %d (%s KB)" % (info["files"], format(round(info["bytes"] / 1024),
                                                           ",")),
            "  scale: %s over %s" % (info["kind"], " x ".join(info["axes"]))])


def _read_manifest(path: Path) -> dict:
    mf = path / "_scales" / "manifest.yaml"
    if not mf.is_file():
        _stop("`%s` is not a scale dataset (no _scales/manifest.yaml)", path)
    return yaml.safe_load(mf.read_text(encoding="utf-8"))


def open_scale_dataset(path: str | Path) -> ScaleDataset:
    """Open a folder written by `write_scale_dataset()` (from R or Python)."""
    path = Path(path)
    manifest = _read_manifest(path)
    sdir = path / "_scales"
    scales = {}
    for a, entry in manifest["axes"].items():
        lt = ipc.open_file(sdir / ("%s-leaftable.arrow" % a)).read_all()
        scales[a] = _scale_from_manifest(entry, lt)
    if manifest.get("kind") == "product":
        keys = {k: str(v) for k, v in (manifest.get("keys") or {}).items()}
        sc = scale_product(keys={a: keys[a] for a in scales}, **scales)
    else:
        sc = next(iter(scales.values()))
    data = ds.dataset(path / "data", format="ipc", partitioning="hive")
    return ScaleDataset(data=data, scale=sc, path=path)


def scale_dataset_info(path: str | Path) -> dict[str, Any]:
    """Describe a stored dataset without opening it: kind, axes, keys, files,
    bytes."""
    path = Path(path)
    manifest = _read_manifest(path)
    files = [f for f in (path / "data").rglob("*") if f.is_file()]
    return {"kind": manifest.get("kind"), "axes": list(manifest["axes"]),
            "keys": {k: str(v) for k, v in (manifest.get("keys") or {}).items()},
            "files": len(files), "bytes": sum(f.stat().st_size for f in files)}
