"""Scale definition files (port of R/definition.R) and the catalogue.

A definition is a HEADER plus TABLES. The header (JSON; YAML accepted on the
way in) says what the scale is -- class, key, frames, members, meta -- and
where each table lives: INLINE (column-wise, with a type per column) or in a
FILE next to it (Arrow IPC, or CSV with the types recorded).

    <name>.json          one file, every table inline
    <name>.scale/        a bundle: scale.json + leaftable.arrow + ...

R and Python write and read the same bytes.
"""
from __future__ import annotations

import functools
import json
import math
import os
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.csv as pcsv
import pyarrow.ipc as ipc

from ._utils import _preview, _stop
from .scale_class import (
    NestedScale,
    _check_scale,
    _scale_name,
)

SCHEMA_VERSION = 1
INLINE_MAX_ROWS = 1000
_SCALAR = (str, int, float, bool)

# Tables ----------------------------------------------------------------------


def _col_type(field: pa.Field) -> str:
    ty = field.type
    if pa.types.is_dictionary(ty):
        ty = ty.value_type
    if pa.types.is_string(ty) or pa.types.is_large_string(ty):
        return "string"
    if pa.types.is_boolean(ty):
        return "logical"
    if pa.types.is_integer(ty):
        return "integer"
    if pa.types.is_floating(ty):
        return "double"
    _stop("column `%s` is of type %s, which a definition cannot hold",
          field.name, ty)


def _pa_type(code: str) -> pa.DataType:
    return {"string": pa.string(), "double": pa.float64(),
            "integer": pa.int64(), "logical": pa.bool_()}[code]


def _json_value(v: Any) -> Any:
    if isinstance(v, float) and math.isnan(v):
        return None
    return v


def _table_inline(t: pa.Table) -> dict:
    """Column-wise encoding: `{columns: {name: [...]}, types: {name: code}}`."""
    cols, types = {}, {}
    for f in t.schema:
        types[f.name] = _col_type(f)
        c = t[f.name]
        if pa.types.is_dictionary(c.type):
            c = c.cast(pa.string())
        cols[f.name] = [_json_value(z) for z in c.to_pylist()]
    return {"columns": cols, "types": types}


def _table_ref_inline(t: pa.Table) -> dict:
    return {"inline": _table_inline(t)}


def _table_from_inline(enc: Mapping[str, Any]) -> pa.Table:
    cols, types = enc.get("columns"), enc.get("types")
    if cols is None or types is None:
        _stop("an inline table needs `columns` and `types`")
    arrays = {}
    for name, vals in cols.items():
        code = types.get(name)
        if code is None:
            _stop("inline table: column `%s` has no type", name)
        if code not in ("string", "double", "integer", "logical"):
            _stop('unknown column type "%s"', code)
        vals = vals if isinstance(vals, list) else [vals]
        arrays[name] = pa.array(vals, _pa_type(code))
    if not arrays:
        return pa.table({})
    return pa.table(arrays)


def _table_to_file(t: pa.Table, dir: Path, stem: str, mode: str) -> dict:
    if mode == "arrow":
        file = "%s.arrow" % stem
        with ipc.new_file(dir / file, t.schema) as w:
            w.write_table(t)
        return {"file": file, "format": "arrow"}
    file = "%s.csv" % stem
    pcsv.write_csv(t, dir / file)
    return {"file": file, "format": "csv",
            "types": {f.name: _col_type(f) for f in t.schema}}


def _table_from_ref(ref: Mapping[str, Any], dir: Path | None, what: str) -> pa.Table:
    if ref.get("inline") is not None:
        return _table_from_inline(ref["inline"])
    if ref.get("file") is None:
        _stop("the `%s` table has neither `inline` data nor a `file`", what)
    if dir is None:
        _stop("the `%s` table refers to a file, but the definition is a single file",
              what)
    path = Path(dir) / ref["file"]
    if not path.is_file():
        _stop("the `%s` table's file is missing: %s", what, path)
    fmt = ref.get("format") or path.suffix.lstrip(".")
    if fmt == "arrow":
        t = ipc.open_file(path).read_all()
        for i, f in enumerate(t.schema):
            if pa.types.is_dictionary(f.type):
                t = t.set_column(i, f.name, t[f.name].cast(pa.string()))
        return t
    if fmt == "csv":
        types = ref.get("types") or {}
        opts = pcsv.ConvertOptions(
            column_types={k: _pa_type(v) for k, v in types.items()},
            null_values=[""], strings_can_be_null=True)
        return pcsv.read_csv(path, convert_options=opts)
    _stop('unknown table format "%s" for `%s`', fmt, what)


# Meta ------------------------------------------------------------------------


def _meta_encode(meta: Mapping[str, Any], nm: str = "") -> tuple[dict, list[str]]:
    """Encode `meta`: scalars, lists, dicts, tables. A dict of scalars at the
    top level is listed in `vectors` so R reads it back as a named vector."""
    vectors: list[str] = []

    def enc(z: Any, path: list) -> Any:
        if z is None:
            return None
        if isinstance(z, pa.Table):
            return {"_table": _table_inline(z)}
        if isinstance(z, bool) or isinstance(z, (int, float, str)):
            return _json_value(z)
        if isinstance(z, Mapping):
            if (len(path) == 1 and z
                    and all(isinstance(v, _SCALAR) for v in z.values())):
                vectors.append(path[0])
            return {str(k): enc(v, path + [k]) for k, v in z.items()}
        if isinstance(z, (list, tuple)):
            if len(z) == 1 and isinstance(z[0], _SCALAR):
                return _json_value(z[0])  # R unboxes a length-1 vector
            return [enc(v, path + [i]) for i, v in enumerate(z)]
        _stop('the `meta` of "%s" holds a value that cannot be written: %s', nm,
              "$".join(str(p) for p in path))

    values = {str(k): enc(v, [k]) for k, v in meta.items()}
    return values, vectors


def _meta_decode(values: Mapping[str, Any] | None, vectors: Sequence[str] = ()) -> dict:
    def dec(z: Any) -> Any:
        if isinstance(z, Mapping):
            if list(z.keys()) == ["_table"]:
                return _table_from_inline(z["_table"])
            return {k: dec(v) for k, v in z.items()}
        if isinstance(z, list):
            return [dec(v) for v in z]
        return z

    return {k: dec(v) for k, v in (values or {}).items()}


# Header ----------------------------------------------------------------------


def _class_name(x: NestedScale) -> str:
    cls = type(x)
    if cls is NestedScale:
        return "nestedscales::NestedScale"
    pkg = getattr(cls, "_r_package", cls.__module__.split(".")[0])
    return "%s::%s" % (pkg, cls.__name__)


def _scale_header(x: NestedScale, tables: Mapping[str, Any]) -> dict:
    from . import __version__

    nm = _scale_name(x, require=False)
    values, vectors = _meta_encode(x.meta, nm)
    hdr: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "nestedscales": __version__,
        "class": _class_name(x),
        "name": nm or None,
        "key": x.key,
        "frames": list(x.frames),
        "members": {f: list(c) for f, c in x.members.items()},
        "meta": values,
        "tables": dict(tables),
        "payload": {},
    }
    if vectors:
        hdr["meta_vectors"] = vectors
    return hdr


def _scale_from_header(hdr: Mapping[str, Any], dir: Path | None) -> NestedScale:
    sv = hdr.get("schema_version")
    if not isinstance(sv, (int, float)) or sv > SCHEMA_VERSION:
        _stop("this definition has schema_version %s; this version of nestedscales "
              "reads up to %d", "<none>" if sv is None else sv, SCHEMA_VERSION)
    tables = hdr.get("tables") or {}
    if tables.get("leaftable") is None:
        _stop("the definition has no `leaftable`")
    leaftable = _table_from_ref(tables["leaftable"], dir, "leaftable")
    at = (_table_from_ref(tables["attributes"], dir, "attributes")
          if tables.get("attributes") is not None else None)
    al = (_table_from_ref(tables["aliases"], dir, "aliases")
          if tables.get("aliases") is not None else None)
    meta = _meta_decode(hdr.get("meta"), hdr.get("meta_vectors") or ())
    if hdr.get("name") is not None and meta.get("name") is None:
        meta["name"] = hdr["name"]
    return NestedScale(leaftable=leaftable, frames=list(hdr.get("frames") or []),
                       members={f: list(c)
                                for f, c in (hdr.get("members") or {}).items()},
                       key=hdr.get("key") or "unit", meta=meta,
                       attributes=at, aliases=al)


def _write_header(hdr: Mapping[str, Any], file: Path, fmt: str) -> None:
    if fmt == "json":
        file.write_text(json.dumps(hdr, indent=2, ensure_ascii=False,
                                   allow_nan=False) + "\n", encoding="utf-8")
    else:
        import yaml

        file.write_text(yaml.safe_dump(dict(hdr), sort_keys=False,
                                       allow_unicode=True), encoding="utf-8")


def _read_header(file: Path) -> dict:
    ext = file.suffix.lower()
    if ext == ".json":
        return json.loads(file.read_text(encoding="utf-8"))
    if ext in (".yaml", ".yml"):
        import yaml

        return yaml.safe_load(file.read_text(encoding="utf-8"))
    _stop("`%s` is not a .json, .yaml or .yml header", file)


# Payload hooks and the class registry ----------------------------------------


@functools.singledispatch
def scale_write_payload(x: NestedScale, dir: Path | None, header: dict) -> dict:
    """Write a subclass's payload next to the header; returns the header."""
    return header


@functools.singledispatch
def scale_read_payload(x: NestedScale, dir: Path | None,
                       header: Mapping) -> NestedScale:
    """Rebuild a subclass from the core scale and its payload files."""
    return x


_SCALE_CLASSES: dict[str, type] = {}


def register_scale_class(cls: type) -> str:
    """Register a NestedScale subclass under its `pkg::Name` so `read_scale()`
    can give it back."""
    if not (isinstance(cls, type) and issubclass(cls, NestedScale)):
        _stop("`class` must inherit from scale_class()")
    if cls is NestedScale:
        key = "nestedscales::NestedScale"
    else:
        pkg = getattr(cls, "_r_package", cls.__module__.split(".")[0])
        key = "%s::%s" % (pkg, cls.__name__)
    _SCALE_CLASSES[key] = cls
    return key


def list_scale_classes() -> list[str]:
    return sorted(_SCALE_CLASSES)


# write_scale / read_scale ----------------------------------------------------

_HEADERS = ("scale.json", "scale.yaml", "scale.yml")


def write_scale(x: NestedScale, path: str | os.PathLike, format: str = "json",
                tables: str = "auto", overwrite: bool = False) -> Path:
    """Write a scale as a definition: one file (`.json`/`.yaml`) with inline
    tables, or a bundle directory with `scale.json` and table files."""
    _check_scale(x, "x")
    if tables not in ("auto", "inline", "arrow", "csv"):
        _stop('`tables` must be one of "auto", "inline", "arrow", "csv"')
    if format not in ("json", "yaml"):
        _stop('`format` must be "json" or "yaml"')
    path = Path(path)
    ext = path.suffix.lower()
    single = ext in (".json", ".yaml", ".yml")
    if single:
        fmt_ext = "json" if ext == ".json" else "yaml"
        if format != fmt_ext and format != "json":
            _stop("`path` ends in %s but `format` is \"%s\"", ext, format)
        format = fmt_ext
        if tables not in ("auto", "inline"):
            _stop("a single-file definition can only inline its tables; write a "
                  'bundle directory for tables = "%s"', tables)
        tables = "inline"

    core = {"leaftable": x.leaftable, "attributes": x.attributes, "aliases": x.aliases}
    if tables == "auto":
        n = sum(t.num_rows for t in core.values())
        tables = "inline" if n <= INLINE_MAX_ROWS else "arrow"

    if single:
        if path.exists() and not overwrite:
            _stop("`%s` already exists; pass overwrite = TRUE to replace it", path)
        dir: Path | None = None
        header_file = path
    else:
        dir = path
        header_file = dir / ("scale.%s" % format)
        if dir.exists():
            present = [p.name for p in dir.iterdir()]
            old = [h for h in _HEADERS if h in present]
            if old:
                if not overwrite:
                    _stop("`%s` already holds a definition; pass overwrite = TRUE", dir)
                _remove_bundle(dir, old)
            elif present:
                _stop("`%s` exists and is not a scale bundle; a bundle is only "
                      "written into an empty directory", dir)
        else:
            dir.mkdir(parents=True)

    refs = {}
    for what, t in core.items():
        if tables == "inline" or t.num_rows == 0:
            refs[what] = _table_ref_inline(t)
        else:
            refs[what] = _table_to_file(t, dir, what, tables)  # type: ignore[arg-type]
    hdr = _scale_header(x, refs)
    hdr = scale_write_payload(x, dir, hdr)
    _write_header(hdr, header_file, format)
    return path


def _remove_bundle(dir: Path, old: Sequence[str]) -> None:
    for h in old:
        try:
            hdr = _read_header(dir / h)
        except Exception:
            hdr = {}
        files = [h]
        for ref in list((hdr.get("tables") or {}).values()) + \
                list((hdr.get("payload") or {}).values()):
            if isinstance(ref, Mapping) and ref.get("file"):
                files.append(ref["file"])
        for f in set(files):
            p = dir / f
            if p.is_file():
                p.unlink()


def read_scale(path: str | os.PathLike, package: str | None = None,
               cls: str = "stored") -> NestedScale:
    """Read a definition file, a bundle directory or a catalogue id."""
    if cls not in ("stored", "core"):
        _stop('`class` must be "stored" or "core"')
    p = Path(path)
    if p.is_dir():
        hdrs = [h for h in _HEADERS if (p / h).is_file()]
        if not hdrs:
            _stop("`%s` is a directory but holds no scale.json or scale.yaml", p)
        if len(hdrs) > 1:
            _stop("`%s` holds both %s; keep one", p, " and ".join(hdrs))
        dir, header_file = p, p / hdrs[0]
    elif p.is_file():
        dir, header_file = p.parent, p
    else:
        header_file = Path(_resolve_scale_id(str(path), package))
        dir = header_file.parent
    hdr = _read_header(header_file)
    core = _scale_from_header(hdr, dir)
    stored = hdr.get("class") or "nestedscales::NestedScale"
    if cls == "core" or stored == "nestedscales::NestedScale":
        return core
    klass = _SCALE_CLASSES.get(stored)
    if klass is None:
        _stop("this definition was written from a %s, and no such class is "
              "registered (is its package loaded?); pass class = \"core\" for the "
              "plain NestedScale", stored)
    impl = scale_read_payload.dispatch(klass)
    if impl is scale_read_payload.dispatch(NestedScale):
        _stop("class %s is registered but has no scale_read_payload() method",
              stored)
    return impl(core, dir, hdr)


# Catalogue -------------------------------------------------------------------

_SCALE_DIRS: dict[str, dict] = {}


def register_scale_dir(path: str | os.PathLike, package: str | None = None) -> str:
    p = Path(path)
    if not p.is_dir():
        _stop("`%s` is not a directory", path)
    p = p.resolve()
    key = package or str(p)
    _SCALE_DIRS[key] = {"package": package, "path": str(p)}
    return key


def list_scale_dirs() -> list[dict]:
    return [dict(_SCALE_DIRS[k]) for k in sorted(_SCALE_DIRS)]


def clear_scale_dirs() -> None:
    _SCALE_DIRS.clear()


def _dir_definitions(path: Path) -> list[tuple[str, Path]]:
    out = []
    for e in sorted(path.iterdir()):
        if e.is_dir():
            hdrs = [h for h in _HEADERS if (e / h).is_file()]
            if hdrs:
                out.append((e.name[:-6] if e.name.endswith(".scale") else e.name,
                            e / hdrs[0]))
        elif e.suffix.lower() in (".json", ".yaml", ".yml"):
            out.append((e.stem, e))
    return out


def scale_catalog() -> list[dict]:
    """Every definition the registered directories hold (headers only)."""
    rows = []
    for d in list_scale_dirs():
        for id_, file in _dir_definitions(Path(d["path"])):
            try:
                hdr = _read_header(file)
            except Exception:
                continue
            ref = (hdr.get("tables") or {}).get("leaftable") or {}
            if ref.get("inline") is not None:
                cols = ref["inline"].get("columns") or {}
                n = len(next(iter(cols.values()))) if cols else 0
            else:
                try:
                    n = _table_from_ref(ref, file.parent, "leaftable").num_rows
                except Exception:
                    n = None
            cls = hdr.get("class") or "nestedscales::NestedScale"
            rows.append({"id": id_, "name": hdr.get("name"),
                         "kind": cls.split("::")[-1],
                         "key": hdr.get("key") or "unit",
                         "frames": "/".join(hdr.get("frames") or []),
                         "n_atoms": n, "package": d["package"], "path": str(file)})
    return sorted(rows, key=lambda r: (r["id"], r["package"] or ""))


def _resolve_scale_id(id_: str, package: str | None = None) -> str:
    cat = scale_catalog()
    hit = [r for r in cat if r["id"] == id_]
    if package is not None:
        hit = [r for r in hit if r["package"] == package]
    if not hit:
        _stop("`%s` is neither a file nor a definition in the catalogue (ids: %s)",
              id_, _preview(sorted({r["id"] for r in cat}), 6) if cat else "<none>")
    if len(hit) > 1:
        _stop("`%s` is shipped by several packages (%s); pass `package=`", id_,
              ", ".join(str(r["package"]) for r in hit))
    return hit[0]["path"]


def _register_shipped() -> None:
    """The definitions vendored with the binding (`data/`)."""
    d = Path(__file__).with_name("data")
    if d.is_dir():
        register_scale_dir(d, package="nestedscales")


_register_shipped()
