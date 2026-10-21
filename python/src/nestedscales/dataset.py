"""The scale-aware dataset store (port of R/dataset.R).

A folder that reopens as DATA ON SCALES, readable from R and Python alike:

    path/
      data/                    hive-partitioned Arrow IPC files
        year=2021/part-0.arrow
      _scales/
        manifest.json          one definition header per axis
        <axis>-leaftable.arrow

Each axis is described by the same header `write_scale()` writes (see
`definition.py`), with its leaftable as an Arrow file. A store written by an
earlier version carries `manifest.yaml`, which is still read.
"""
from __future__ import annotations

import json
import shutil
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.ipc as ipc

from ._backend import backend_of, scan
from ._utils import _as_str_tuple, _preview, _stop, _warn
from .definition import _scale_from_header, _scale_header, _table_ref_inline
from .product import ScaleProduct, scale_product
from .scale_class import NestedScale, _check_scale, _scale_name

INLINE_MAX_ROWS = 1000


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


def _flatten(v: Any) -> list:
    """YAML gives a length-1 vector back as a scalar and a vector as a list."""
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return [z for z in v]
    return [v]


def _scale_from_legacy_manifest(entry: Mapping[str, Any],
                                leaftable: pa.Table) -> NestedScale:
    """A scale from a manifest.yaml entry written before 0.2.0."""
    meta = dict(entry.get("meta") or {})
    if meta.get("weights") is not None:
        meta["weights"] = [str(z) for z in _flatten(meta["weights"])]
    if isinstance(meta.get("residuals"), Mapping):
        meta["residuals"] = {k: [str(z) for z in _flatten(v)]
                             for k, v in meta["residuals"].items()}
    # R's yaml wrote a named numeric vector as a bare sequence (names lost)
    # rounded to 7 digits. The names are the declared weights, in order;
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


def _axis_header(s: NestedScale, axis: str, sdir: Path, codec: str | None) -> dict:
    """The definition header of one axis, its leaftable as an Arrow file and
    the attribute and alias tables inline when small."""
    opts = ipc.IpcWriteOptions(compression=codec)
    with ipc.new_file(sdir / ("%s-leaftable.arrow" % axis), s.leaftable.schema,
                      options=opts) as w:
        w.write_table(s.leaftable)
    refs: dict[str, Any] = {"leaftable": {"file": "%s-leaftable.arrow" % axis,
                                          "format": "arrow"}}
    for what in ("attributes", "aliases"):
        t = getattr(s, what)
        if t.num_rows <= INLINE_MAX_ROWS:
            refs[what] = _table_ref_inline(t)
        else:
            file = "%s-%s.arrow" % (axis, what)
            with ipc.new_file(sdir / file, t.schema) as w:
                w.write_table(t)
            refs[what] = {"file": file, "format": "arrow"}
    return _scale_header(s, refs)


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

    # headers first: a meta that cannot be written fails before any file
    from .definition import _meta_encode

    for a, s in axes.items():
        _meta_encode(s.meta, a)

    path = Path(path)
    if path.exists():
        if not overwrite:
            _stop("`%s` already exists; pass overwrite = TRUE to replace it", path)
        shutil.rmtree(path)
    sdir = path / "_scales"
    sdir.mkdir(parents=True)

    manifest = {"nestedscales": __version__,
                "kind": "product" if is_prod else "scale",
                "keys": keys,
                "axes": {a: _axis_header(s, a, sdir, codec) for a, s in axes.items()}}
    (sdir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False, allow_nan=False) + "\n",
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


def _read_manifest(path: Path) -> tuple[dict, bool]:
    """The manifest and whether it is the legacy YAML form."""
    mj = path / "_scales" / "manifest.json"
    if mj.is_file():
        return json.loads(mj.read_text(encoding="utf-8")), False
    my = path / "_scales" / "manifest.yaml"
    if my.is_file():
        import yaml

        return yaml.safe_load(my.read_text(encoding="utf-8")), True
    _stop("`%s` is not a scale dataset (no _scales/manifest.json)", path)


def open_scale_dataset(path: str | Path) -> ScaleDataset:
    """Open a folder written by `write_scale_dataset()` (from R or Python)."""
    path = Path(path)
    manifest, legacy = _read_manifest(path)
    sdir = path / "_scales"
    scales = {}
    for a, entry in manifest["axes"].items():
        if legacy:
            lt = ipc.open_file(sdir / ("%s-leaftable.arrow" % a)).read_all()
            scales[a] = _scale_from_legacy_manifest(entry, lt)
        else:
            scales[a] = _scale_from_header(entry, sdir)
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
    manifest, _ = _read_manifest(path)
    files = [f for f in (path / "data").rglob("*") if f.is_file()]
    return {"kind": manifest.get("kind"), "axes": list(manifest["axes"]),
            "keys": {k: str(v) for k, v in (manifest.get("keys") or {}).items()},
            "files": len(files), "bytes": sum(f.stat().st_size for f in files)}
