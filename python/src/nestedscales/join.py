"""join_scale() -- attach a scale's labels and memberships (port of R/join.R).

Attached columns are named after the scale, so several scales can sit side by
side on one dataset. The attach is a positional lookup into a small table
(`index_in` + `take`), so the data's row order is kept.
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._backend import backend_of, restore, scan, schema_of
from ._utils import _as_str_tuple, _preview, _stop, _warn
from .recast import _match_choice, _want_diagnostics
from .scale_class import (
    NestedScale,
    _atom_level,
    _check_frame,
    _check_scale,
    _resolve_weight,
    _scale_name,
    _strings,
    scale_key,
    scale_rank,
    scale_vocab,
)


def join_scale(data: Any, x: NestedScale, key: str | None = None,
               frame: str | None = None,
               attach: bool | str | Sequence[str] | None = None,
               meta: bool = False, weight: str | None = None,
               as_factor: bool = True, collect: bool | None = None,
               diagnostics: str = "auto") -> Any:
    """Attach a label column named after the scale, optionally the codes of
    coarser frames (`"<name>.<frame>"`) and the unit's share and weight
    (`"<name>.share"`, `"<name>.weight"`). Existing columns are never
    overwritten. With `as_factor`, memberships are dictionary columns over the
    frame's full vocabulary."""
    diagnostics = _match_choice(diagnostics, ("auto", "on", "off"), "diagnostics")
    _check_scale(x, "x")
    bk = backend_of(data, "data")
    nm = _scale_name(x)
    schema = schema_of(data, bk)
    v = scale_vocab(x)
    lt = x.leaftable
    fr_all = list(x.frames)

    if frame is None:
        hit = [f for f in fr_all if f in schema.names]
        if not hit:
            hit = [f for f in [_atom_level(x)] if f in schema.names]
        if len(hit) != 1:
            _stop("cannot infer the code %s from the data's columns (found: %s); "
                  "pass `frame=`", v["frame"], "none" if not hit else _preview(hit))
        frame = hit[0]
    _check_frame(x, frame, "frame")
    if key is None:
        for cand in (nm, frame, scale_key(x)):
            if cand in schema.names:
                key = cand
                break
        else:
            _stop("the data has no `%s`, `%s`, or `%s` column; pass `key=`",
                  nm, frame, scale_key(x))
    if key not in schema.names:
        _stop("the data has no column named `%s`; pass `key=`", key)

    coarser = fr_all[:scale_rank(x, frame) - 1]
    if attach is True:
        attach = coarser
    if attach is not None and attach is not False:
        attach = list(_as_str_tuple(attach))
        bad = [a for a in attach if a not in coarser]
        if bad:
            _stop("`attach` must be coarser than '%s'; not: %s", frame,
                  _preview(bad))
    else:
        attach = []
    new_cols = ([nm] if key != nm else []) + ["%s.%s" % (nm, a) for a in attach] \
        + (["%s.share" % nm, "%s.weight" % nm] if meta else [])
    clash = [c for c in new_cols if c in schema.names]
    if clash:
        _stop('attaching "%s" would overwrite existing column(s): %s', nm,
              _preview(clash))
    if not new_cols:
        return data

    known = list(dict.fromkeys(z for z in _strings(lt, frame) if z is not None))
    t = scan(data, bk)
    kcol = t[key]
    if not pa.types.is_string(kcol.type):
        kcol = pc.cast(kcol, pa.string())
    if _want_diagnostics(diagnostics, bk):
        known_arr = pa.array(known, pa.string())
        if not pc.any(pc.is_in(kcol, value_set=known_arr)).as_py():
            _stop("no rows of the `%s` column match units at %s '%s'", key,
                  v["frame"], frame)
        bad = pc.and_(pc.is_valid(kcol),
                      pc.invert(pc.is_in(kcol, value_set=known_arr)))
        unknown = pc.unique(kcol.filter(bad)).to_pylist()
        if unknown:
            _warn("%d code(s) in the `%s` column are not %s at %s '%s': %s",
                  len(unknown), key, v["units"], v["frame"], frame,
                  _preview(unknown))

    # the small attach table, one row per known code
    attach_cols: dict[str, Any] = {}
    fcodes = _strings(lt, frame)
    for cl in attach:
        pairs = list(dict.fromkeys(
            (a, b) for a, b in zip(fcodes, _strings(lt, cl), strict=True)
            if a is not None))
        n_par: dict = {}
        for a, _ in pairs:
            n_par[a] = n_par.get(a, 0) + 1
        multi = sorted(k for k, n in n_par.items() if n > 1)
        if multi:
            _warn("%s '%s' does not nest in '%s'; %d code(s) have multiple parents "
                  "and get NA (e.g. %s)", v["frame"], frame, cl, len(multi),
                  _preview(multi))
        parent = {a: b for a, b in pairs if a not in set(multi)}
        val = [parent.get(k) for k in known]
        if as_factor:
            levels = list(x.members[cl])
            pos = {c: i for i, c in enumerate(levels)}
            arr = pa.DictionaryArray.from_arrays(
                pa.array([pos.get(z) if z is not None else None for z in val],
                         pa.int32()),
                pa.array(levels, pa.string()))
        else:
            arr = pa.array(val, pa.string())
        attach_cols["%s.%s" % (nm, cl)] = arr
    if meta:
        try:
            wcol = _resolve_weight(x, weight)
        except ValueError:
            wcol = None
        if wcol is None:
            _warn('"%s" declares no weight columns; `meta = TRUE` share/weight '
                  "skipped", nm)
        else:
            tot: dict = {}
            for c, z in zip(fcodes, lt[wcol].to_pylist(), strict=True):
                if c is not None:
                    ok = z is not None and z == z
                    tot[c] = tot.get(c, 0.0) + (float(z) if ok else 0.0)
            grand = sum(tot.values())
            ww = [tot.get(k) for k in known]
            attach_cols["%s.weight" % nm] = pa.array(ww, pa.float64())
            attach_cols["%s.share" % nm] = pa.array(
                [z / grand if z is not None else None for z in ww], pa.float64())

    idx = pc.index_in(kcol, value_set=pa.array(known, pa.string()))
    out = t
    for name, arr in attach_cols.items():
        out = out.append_column(name, arr.take(idx))
    if key != nm:
        out = out.append_column(nm, pa.array(known, pa.string()).take(idx))
    return restore(out, bk, collect)
