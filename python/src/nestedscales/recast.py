"""recast_scale() -- the central conversion verb (port of R/recast.R).

Aggregation and disaggregation are one operation. Every conversion routes
through the atom layer; the route is collapsed into a small crosswalk by
`scale_map()`, so the converter is one join plus one grouped aggregation.

The split factor is fixed for every dimension:

    f = w / w_from        when the crosswalk carries weights
    f = n_overlap/n_from  otherwise (the equal split)

NA semantics follow R exactly: aggregates do NOT skip nulls (a null member
makes its group null), and a target whose sources are only partly present in
the data is null (the partial-source poisoning law).
"""
from __future__ import annotations

import functools
from collections.abc import Mapping, Sequence
from typing import Any, Literal

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc

from ._backend import (
    Backend,
    backend_of,
    bind_rows,
    chunks,
    distinct_rows,
    scan,
    schema_of,
)
from ._backend import restore as _restore
from ._utils import _as_str_tuple, _preview, _stop, _warn
from .map import _map_weight, scale_map
from .rules import _SHARE_RULES, _rules_for
from .scale_class import (
    NestedScale,
    _atom_level,
    _check_frame,
    _check_scale,
    _strings,
    scale_key,
    scale_rank,
    scale_residuals,
    scale_vocab,
    scale_weights,
)

# Internal working columns; user columns may not collide with these.
_MS_COLS = (".ms_parent", ".ms_tot", ".ms_to", ".ms_f", ".ms_n_from",
            ".ms_n_overlap", ".ms_w", ".ms_w_from", ".ms_nsrc", ".ms_nexp")

_KEEP_NULLS = pc.ScalarAggregateOptions(skip_nulls=False, min_count=0)
_SKIP_NULLS = pc.ScalarAggregateOptions(skip_nulls=True, min_count=1)
_COUNT_ALL = pc.CountOptions(mode="all")
_COUNT_VALID = pc.CountOptions(mode="only_valid")
_NULL = pa.scalar(None, pa.float64())

#: What to do with atoms that have no code at the source or target frame.
NaAction = Literal["drop", "error", "keep"]
#: Whether to run the checks that scan the data.
Diagnostics = Literal["auto", "on", "off"]
#: What a partly supplied target becomes.
MissingSources = Literal["na", "ignore"]


# -----------------------------------------------------------------------------
# small helpers
# -----------------------------------------------------------------------------

def _match_choice(value: object, choices: Sequence[str], arg: str) -> str:
    """R's `match.arg(value)` over `choices` (exact, else a unique prefix)."""
    if value is None:
        return choices[0]
    if isinstance(value, str):
        if value in choices:
            return value
        hits = [c for c in choices if value and c.startswith(value)]
        if len(hits) == 1:
            return hits[0]
    _stop("`%s` should be one of: %s", arg, ", ".join(choices))


def _f64(c: Any) -> pa.ChunkedArray:
    return pc.cast(c, pa.float64())


def _set(t: pa.Table, name: str, col: Any) -> pa.Table:
    if name in t.column_names:
        return t.set_column(t.column_names.index(name), name, col)
    return t.append_column(name, col)


def _rename(t: pa.Table, mapping: Mapping[str, str]) -> pa.Table:
    return t.rename_columns([mapping.get(c, c) for c in t.column_names])


def _as_string_key(t: pa.Table, key: str) -> pa.Table:
    ty = t.schema.field(key).type
    if not pa.types.is_string(ty):
        t = _set(t, key, pc.cast(t[key], pa.string()))
    return t


def _plain(c: pa.ChunkedArray) -> pa.ChunkedArray:
    """Dictionary columns decoded, for null-safe join keys."""
    if pa.types.is_dictionary(c.type):
        return pc.cast(c, c.type.value_type)
    return c


def _fill_value(ty: pa.DataType) -> pa.Scalar:
    if pa.types.is_string(ty) or pa.types.is_large_string(ty):
        return pa.scalar("\x00", ty)
    if pa.types.is_boolean(ty):
        return pa.scalar(False)
    return pa.scalar(0).cast(ty)


def _join_na(left: pa.Table, right: pa.Table, keys: Sequence[str],
             join_type: str = "left outer") -> pa.Table:
    """Join where null keys match each other (dplyr's `na_matches = "na"`)."""
    keys = list(keys)
    lk, rk = left, right
    jk = []
    for i, k in enumerate(keys):
        lc, rc = _plain(lk[k]), _plain(rk[k])
        if lc.type != rc.type:
            rc = pc.cast(rc, lc.type)
        if lc.null_count == 0 and rc.null_count == 0:
            lk, rk = _set(lk, k, lc), _set(rk, k, rc)
            jk.append(k)
            continue
        fv = _fill_value(lc.type)
        nk, nn = "__ms_jk%d" % i, "__ms_jn%d" % i
        lk = lk.append_column(nk, pc.fill_null(lc, fv)).append_column(
            nn, pc.is_null(lc))
        rk = rk.drop_columns([k]).append_column(nk, pc.fill_null(rc, fv)) \
            .append_column(nn, pc.is_null(rc))
        jk += [nk, nn]
    out = lk.join(rk, keys=jk, join_type=join_type, use_threads=True,
                  coalesce_keys=True)
    return out.drop_columns([c for c in out.column_names if c.startswith("__ms_j")])


def _agg(t: pa.Table, keys: Sequence[str], specs: list) -> pa.Table:
    return t.group_by(list(keys), use_threads=True).aggregate(specs)


def _values_for(schema: pa.Schema, key: str, drop_cols: Sequence[str],
                values: object) -> list[str]:
    """Value columns: the given ones, or every numeric non-key column."""
    names = schema.names
    if values is None:
        out = [c for c in names if c != key and c not in drop_cols
               and (pa.types.is_integer(schema.field(c).type)
                    or pa.types.is_floating(schema.field(c).type))]
        if not out:
            _stop("no numeric value columns found in `x`; specify `values=`")
        return out
    values = list(_as_str_tuple(values))
    missing = [v for v in values if v not in names]
    if missing:
        _stop("value column(s) not in `x`: %s", _preview(missing))
    return values


def _check_ms_cols(schema: pa.Schema) -> None:
    # R reserves `.ms_*`; Python works in `__ms_*` (Acero reads a leading dot
    # as a nested field path), so both are refused.
    clash = [c for c in schema.names if c in _MS_COLS or c.startswith("__ms_")]
    if clash:
        _stop("`x` uses reserved column name(s): %s", _preview(clash))


def _infer_from(x: NestedScale, schema: pa.Schema, key: str | None) -> str:
    fr = x.frames
    if key is not None and key in fr:
        return key
    hit = [f for f in fr if f in schema.names]
    if len(hit) != 1:
        _stop("cannot infer the source %s from the data's columns (found: %s); "
              "pass `source=`", scale_vocab(x)["frame"],
              "none" if not hit else _preview(hit))
    return hit[0]


def _want_diagnostics(diagnostics: str, bk: Backend) -> bool:
    return {"auto": not bk.lazy, "on": True, "off": False}[diagnostics]


def _no_share(rules: Mapping[str, dict], where: str) -> None:
    if any(r["rule"] in _SHARE_RULES for r in rules.values()):
        _stop('rule "share" is not supported by %s(); use recast_scale() with a '
              "parent frame", where)


def _scale_scope(x: NestedScale) -> str | None:
    obj = scale_vocab(x)["object"]
    return None if obj == "NestedScale" else obj.lower()


def _rule_hint(x: NestedScale) -> str:
    return scale_vocab(x).get("register_rule", "register_scale_rule()")


def _check_copy_result(res: pa.Table, copy_cols: Sequence[str],
                       unit: str = "unit") -> None:
    """Constancy guard for `copy` columns, over the per-group max and min."""
    for v in copy_cols:
        rng = pc.subtract(res["__ms_mx_" + v], res["__ms_mn_" + v])
        ok = pc.and_(pc.is_valid(rng), pc.is_valid(res[v]))
        bad = pc.and_(ok, pc.greater(rng, 1e-9))
        if pc.any(pc.fill_null(bad, False)).as_py():
            _stop('rule "copy" for `%s`: values are not constant within a target %s',
                  v, unit)


def _recast_complete(res: pa.Table, idc: pa.Table, out_keys: Sequence[str | None],
                     key: str, id_cols: Sequence[str],
                     values: Sequence[str]) -> pa.Table:
    """Complete a result to the full target vocabulary, in the contract order:
    identifier groups in first-appearance order, target codes in member order,
    the null row (if any) last."""
    id_cols = list(id_cols)
    keys = pa.array(list(out_keys), pa.string())
    nk = len(keys)
    if id_cols and idc.num_rows > 0:
        ni = idc.num_rows
        full = idc.select(id_cols).take(pa.array(np.repeat(np.arange(ni), nk)))
        full = full.append_column(key, keys.take(pa.array(np.tile(np.arange(nk), ni))))
    else:
        full = pa.table({key: keys})
        for c in id_cols:
            full = full.append_column(c, pa.nulls(nk, res.schema.field(c).type))
    full = full.append_column("__ms_ord", pa.array(np.arange(full.num_rows)))
    res = res.select([*id_cols, key, *values])
    out = _join_na(full, res, [*id_cols, key])
    return out.sort_by("__ms_ord").select([key, *id_cols, *values])


# -----------------------------------------------------------------------------
# the aggregation pipeline
# -----------------------------------------------------------------------------

def _rule_parts(v: str, rule: str, val: pa.ChunkedArray, nn: pa.ChunkedArray,
                f: pa.ChunkedArray, ww: pa.ChunkedArray) -> dict:
    """Per-row columns whose group sums make up the rule's aggregate."""
    if rule == "sum":
        return {"s": pc.multiply(val, f)}
    if rule == "mean":
        return {"vn": pc.multiply(val, nn), "n": nn}
    if rule == "weighted_mean":
        return {"vw": pc.multiply(val, ww), "w": ww,
                "vn": pc.multiply(val, nn), "n": nn}
    if rule == "copy":
        return {}
    if rule == "sd":
        return {"v2": pc.multiply(nn, pc.multiply(val, val)),
                "v1": pc.multiply(nn, val), "n": nn}
    _stop("Unknown rule: %s", rule)


def _rule_result(rule: str, g: dict) -> pa.ChunkedArray:
    if rule == "sum":
        return g["s"]
    if rule == "mean":
        return pc.divide(g["vn"], g["n"])
    if rule == "weighted_mean":
        return pc.if_else(pc.greater(g["w"], 0), pc.divide(g["vw"], g["w"]),
                          pc.divide(g["vn"], g["n"]))
    if rule == "copy":
        return g["mean"]
    # sd
    n = g["n"]
    var = pc.divide(pc.subtract(g["v2"], pc.divide(pc.multiply(g["v1"], g["v1"]), n)),
                    pc.subtract(n, 1))
    return pc.if_else(pc.greater(n, 1), pc.sqrt(var), _NULL)


def _pipeline(t: pa.Table, jmap: pa.Table, key: str, values: Sequence[str],
              rules: Mapping[str, dict], id_cols: Sequence[str],
              map_by: Sequence[str] = (), missing_sources: str = "na",
              sfx: Mapping[str, str] | None = None, unit: str = "unit",
              check_copy: bool = True) -> pa.Table:
    """Join the data to the crosswalk and aggregate; result keyed `__ms_to`."""
    id_cols = list(id_cols)
    shared_ids = [c for c in map_by if c in id_cols]
    xq = t.select([*id_cols, key, *values])
    jm = jmap
    for c in shared_ids:
        if jm.schema.field(c).type != xq.schema.field(c).type:
            jm = _set(jm, c, pc.cast(jm[c], xq.schema.field(c).type))
    if missing_sources == "na":
        # an integer id per source code: counting distinct ints per group is
        # far cheaper than counting distinct strings
        jm = jm.append_column("__ms_sid", pc.index_in(
            jm[key], value_set=pc.unique(jm[key].combine_chunks())))
    joined = xq.join(jm, keys=[*shared_ids, key], join_type="inner",
                     use_threads=True)

    grp = [*id_cols, "__ms_to"]
    nn = _f64(joined["__ms_n_overlap"])
    cols: dict[str, Any] = {c: joined[c] for c in grp}
    specs: list = []
    parts: dict[str, dict] = {}
    copy_cols = [v for v in values if rules[v]["rule"] == "copy"]
    for i, v in enumerate(values):
        sx = (sfx or {}).get(v, "")
        rule = rules[v]["rule"]
        val = _f64(joined[v])
        p = _rule_parts(v, rule, val, nn, _f64(joined["__ms_f" + sx]),
                        _f64(joined["__ms_w" + sx]))
        names = {}
        for part, arr in p.items():
            nm = "__ms_p%d_%s" % (i, part)
            cols[nm] = arr
            specs.append((nm, "sum", _KEEP_NULLS))
            names[part] = nm + "_sum"
        if rule == "copy":
            nm = "__ms_p%d_v" % i
            cols[nm] = val
            specs += [(nm, "mean", _KEEP_NULLS), (nm, "max", _KEEP_NULLS),
                      (nm, "min", _KEEP_NULLS)]
            names.update(mean=nm + "_mean", max=nm + "_max", min=nm + "_min")
        parts[v] = names
    if missing_sources == "na":
        cols["__ms_k"] = joined["__ms_sid"]
        specs.append(("__ms_k", "count_distinct", _COUNT_ALL))
    g = _agg(pa.table(cols), grp, specs)

    res = g.select(grp)
    for v in values:
        names = parts[v]
        res = res.append_column(v, _rule_result(
            rules[v]["rule"], {k: g[n] for k, n in names.items()}))
    for v in copy_cols:
        res = res.append_column("__ms_mx_" + v, g[parts[v]["max"]])
        res = res.append_column("__ms_mn_" + v, g[parts[v]["min"]])

    # THE REPAIR: a group that saw fewer distinct sources than the crosswalk
    # lists for it was only partly supplied, and its value is null.
    if missing_sources == "na":
        res = res.append_column("__ms_nsrc", g["__ms_k_count_distinct"])
        exp = distinct_rows(jm, [*shared_ids, "__ms_to", key])
        exp = exp.append_column("__ms_one", pa.array(np.ones(exp.num_rows, np.int64)))
        exp = _agg(exp, [*shared_ids, "__ms_to"], [("__ms_one", "sum")])
        exp = exp.rename_columns(["__ms_nexp" if c == "__ms_one_sum" else c
                                  for c in exp.column_names])
        res = _join_na(res, exp, [*shared_ids, "__ms_to"])
        short = pc.less(res["__ms_nsrc"], res["__ms_nexp"])
        for v in values:
            res = _set(res, v, pc.if_else(short, _NULL, res[v]))
        res = res.drop_columns(["__ms_nsrc", "__ms_nexp"])

    if check_copy and copy_cols:
        _check_copy_result(res, copy_cols, unit)
    res = res.drop_columns([c for c in res.column_names
                            if c.startswith(("__ms_mx_", "__ms_mn_"))])
    return res.select([*grp, *values])


def _widen_maps(maps: dict[str, pa.Table], source: str, target: str, key: str,
                wt_of: Mapping[str, str],
                residual_targets: Sequence[str] = ()) -> tuple[pa.Table, dict]:
    """Fold the per-weight crosswalks into one, a split factor per weight."""
    wts = list(maps)
    base = maps[wts[0]]
    shared = [c for c in base.column_names if c not in ("w", "w_from")]
    for w in wts[1:]:
        if not maps[w].select(shared).equals(base.select(shared)):
            _stop("the crosswalks for different weights disagree on their "
                  "structure; this should be impossible for derived maps, so a "
                  "registered map is likely malformed")
    jmap = _rename(base.select(shared), {
        source: key, target: "__ms_to", "n_from": "__ms_n_from",
        "n_overlap": "__ms_n_overlap"})

    # A declared residual is not a destination for allocation: the split
    # shares are taken over the ALLOCABLE targets only, renormalised so the
    # parent's total is conserved.
    tos = jmap["__ms_to"].to_pylist()
    grp = _strings(jmap, key)
    is_res = [t is not None and t in set(residual_targets) for t in tos]
    n_ov = [float(z) for z in jmap["__ms_n_overlap"].to_pylist()]
    sfx = dict.fromkeys(wt_of, "")
    for i, wt in enumerate(wts):
        m = maps[wt]
        sx = "" if len(wts) == 1 else "_%d" % (i + 1)
        jmap = jmap.append_column("__ms_w" + sx, _f64(m["w"]))
        if any(is_res):
            w = [float(z) for z in m["w"].to_pylist()]
            w_ok = [0.0 if r else z for r, z in zip(is_res, w, strict=True)]
            n_ok = [0.0 if r else z for r, z in zip(is_res, n_ov, strict=True)]
            w_tot: dict = {}
            n_tot: dict = {}
            for gk, a, b in zip(grp, w_ok, n_ok, strict=True):
                w_tot[gk] = w_tot.get(gk, 0.0) + a
                n_tot[gk] = n_tot.get(gk, 0.0) + b
            dead = list(dict.fromkeys(
                gk for gk in grp if w_tot[gk] <= 0 and n_tot[gk] <= 0))
            if dead:
                _stop("every target of `%s` is a declared residual, so a figure "
                      "at `%s` has nowhere allocable to go: %s",
                      source, source, _preview(dead))
            f = [0.0 if r else (a / w_tot[gk] if w_tot[gk] > 0 else b / n_tot[gk])
                 for r, a, b, gk in zip(is_res, w_ok, n_ok, grp, strict=True)]
            f = pa.array(f, pa.float64())
        else:
            f = pc.if_else(pc.greater(_f64(m["w_from"]), 0),
                           pc.divide(_f64(m["w"]), _f64(m["w_from"])),
                           pc.divide(_f64(jmap["__ms_n_overlap"]),
                                     _f64(jmap["__ms_n_from"])))
        jmap = jmap.append_column("__ms_f" + sx, f)
        for v, w in wt_of.items():
            if w == wt:
                sfx[v] = sx
    return jmap, sfx


# -----------------------------------------------------------------------------
# recast_scale()
# -----------------------------------------------------------------------------

def recast_scale(data: Any, x: NestedScale, source: str | None = None,
                 target: str | NestedScale | None = None, key: str | None = None,
                 values: str | Sequence[str] | None = None,
                 rule: str | Mapping[str, str] | None = None,
                 weight: str | Mapping[str, str] | None = None,
                 na_action: NaAction = "drop", parent: str | None = None,
                 collect: bool | None = None, diagnostics: Diagnostics = "auto",
                 missing_sources: MissingSources = "na",
                 batch: int | None = None,
                 batch_by: str | None = None, **kwargs: Any) -> Any:
    """Recast values from one resolution to another.

    The central conversion verb. Takes a table keyed by unit code at frame
    `source` and returns one keyed at `target`, aggregating (fine to coarse)
    or disaggregating (coarse to fine) with one rule per value column. Frames
    that cross-cut work too: the route always goes through the atoms. A
    crosswalk registered with `register_scale_map()` short-circuits it.

    Columns that are neither the key nor a value column are identifiers (a
    year, a technology) and are preserved as groups, so panel data recasts in
    one call. Columns named like the scale's frames are dropped.

    Parameters
    ----------
    data
        The table: pyarrow, pandas, polars, a dict of columns, or a lazy
        pyarrow Dataset / polars LazyFrame. Returned in the same type.
    x
        The scale the codes in `data` belong to.
    source
        Frame of the codes. None infers it: `key` when that is a frame, else
        the single frame name among the data's columns.
    target
        Target frame of `x`, or another named scale (its atom layer is the
        target, matched on shared atom keys).
    key
        The code column of `data`. Defaults to `source` when that column
        exists, else the scale's key.
    values
        Value columns. Default: every numeric column other than the key and
        the frame columns; numeric identifiers (`year`) must be excluded by
        naming the values.
    rule
        One of `SCALE_RULES` for every value column, or a dict per column.
        None looks each column up with `get_scale_rule()`; a column with no
        rule anywhere is an error.
    weight
        Weight column for `sum` splits and `weighted_mean`; one name or a dict
        per column. None uses the registered weight, else the scale's default;
        with no declared weights every atom weighs 1.
    na_action
        Atoms with no code at `source` or `target`: "drop" (with a warning),
        "error", or "keep" (an explicit null row, so totals conserve).
    parent
        Rule "share" only: the frame the shares are taken within. Default:
        `target` when it differs from `source`, else the frame above.
    collect
        Lazy inputs: True materialises and completes the result; otherwise
        only the observed target units are returned.
    diagnostics
        The checks that scan the data (unknown codes, dropped shares, missing
        sources): "auto" runs them on eager inputs only; "on"/"off" force.
    missing_sources
        "na": a target whose sources are only partly present is null.
        "ignore": aggregate whatever is there (faster, opt-in).
    batch, batch_by
        Process in chunks of at most `batch` values of the identifier column
        `batch_by` (default: the first identifier). Chunking by an identifier
        leaves the numbers unchanged.
    **kwargs
        Passed to `scale_map()`.

    Returns
    -------
    The recast table in the input's type, columns `target`, identifiers,
    values. Rule "share" keeps the `source` key and returns each value as a
    share of its parent-group total.
    """
    na_action = _match_choice(na_action, ("drop", "error", "keep"), "na_action")
    diagnostics = _match_choice(diagnostics, ("auto", "on", "off"), "diagnostics")
    missing_sources = _match_choice(missing_sources, ("na", "ignore"),
                                    "missing_sources")
    _check_scale(x, "x")
    if target is None:
        _stop("`target` is required")
    v = scale_vocab(x)
    bk = backend_of(data, "data")
    schema = schema_of(data, bk)
    _check_ms_cols(schema)

    if source is None:
        source = _infer_from(x, schema, key)
    _check_frame(x, source, "source")
    if key is None:
        key = source if source in schema.names else scale_key(x)
    if key not in schema.names:
        _stop("the data has no column named `%s`; pass `key=`", key)

    # cross-object route: `target` is another scale
    if isinstance(target, NestedScale):
        rule_vals = (list(rule.values()) if isinstance(rule, Mapping)
                     else list(_as_str_tuple(rule)))
        if any(r in _SHARE_RULES for r in rule_vals):
            _stop('rule "share" needs a parent frame of the same scale; it cannot '
                  "recast across objects")
        g = recast_to_atoms(data, x, source=source, key=key, values=values,
                            rule=rule, weight=weight, collect=collect)
        return recast_from_atoms(g, target, target=_atom_level(target), values=values,
                                 rule=rule, na_action=na_action, collect=collect)
    _check_frame(x, target, "target")

    frames_all = list(x.frames)
    values = _values_for(schema, key, frames_all, values)
    id_cols = [c for c in schema.names
               if c != key and c not in values and c not in frames_all]
    rules = _rules_for(values, rule, weight, scope=_scale_scope(x),
                       hint=_rule_hint(x))

    # batching: chunk by IDENTIFIER, which partitions the aggregation groups
    # exactly, so the numbers are unchanged
    if batch is not None:
        if bk.lazy and not collect:
            _stop("`batch` applies when materialising; this call returns a query. "
                  "Pass `collect = TRUE` to batch it.")
        if not id_cols:
            _stop("`batch` needs an identifier column to chunk by, and this data "
                  "has none (every column is the key or a value)")
        if batch_by is None:
            batch_by = id_cols[0]
        if batch_by not in id_cols:
            _stop("`batch_by` must be an identifier column of the data (one of: "
                  "%s); `%s` is not one, and chunking on it would split "
                  "aggregation groups and change the numbers",
                  ", ".join(id_cols), batch_by)
        return _recast_batched(data, bk, batch, batch_by, dict(
            x=x, source=source, target=target, key=key, values=values, rule=rule,
            weight=weight, na_action=na_action, parent=parent,
            diagnostics=diagnostics, missing_sources=missing_sources, **kwargs))

    t = _as_string_key(scan(data, bk, [*id_cols, key, *values]), key)
    lt = x.leaftable
    do_diag = _want_diagnostics(diagnostics, bk)

    src_keys = None
    if do_diag:
        src_keys = [k for k in pc.unique(t[key]).to_pylist() if k is not None]
        known = {k for k in _strings(lt, source) if k is not None}
        unknown = [k for k in src_keys if k not in known]
        if unknown:
            _warn("%d code(s) in the `%s` column are not present at %s `%s` and "
                  "were dropped: %s", len(unknown), key, v["frame"], source,
                  _preview(unknown))
        if not any(k in known for k in src_keys):
            _stop("no rows matched %s `%s`; check `source=` and the `%s` column",
                  v["frame"], source, key)

    # share within parent: result keyed at `source`, one rule for all
    is_share = [r["rule"] in _SHARE_RULES for r in rules.values()]
    if any(is_share):
        if not all(is_share):
            _stop('rule "share" changes the output key to `source` and cannot be '
                  "mixed with other rules in one call; recast the columns "
                  "separately")
        if weight is not None:
            _warn('`weight` is ignored by rule "share": the values are the weights')
        return _recast_share(t, bk, x, source, target, key, values, id_cols, parent,
                             na_action, collect)
    if parent is not None:
        _stop('`parent` applies to rule "share" only')

    if na_action == "error":
        n_bad = sum(a is None or b is None
                    for a, b in zip(_strings(lt, source), _strings(lt, target),
                                    strict=True))
        if n_bad > 0:
            _stop('%d atom(s) have no code at %s `%s` or `%s`; use na_action = '
                  '"drop" or "keep"', n_bad, v["frame"], source, target)

    wt_of = {c: (r["weight"] or "") for c, r in rules.items()}
    need_split = any(r["rule"] in ("sum", "weighted_mean") for r in rules.values())
    if (not scale_weights(x) and weight is None and need_split
            and scale_rank(x, target) > scale_rank(x, source)):
        _warn("no weight column declared; splitting `%s` equally across the "
              "atoms of each `%s`. Declare a weight for a size-proportional "
              "split.", target, source)

    maps = {wt: scale_map(x, source, target, weight=wt or None, **kwargs)
            for wt in dict.fromkeys(wt_of.values())}
    m0 = maps[next(iter(maps))]
    map_by = [c for c in m0.column_names
              if c not in (source, target, "n_from", "n_overlap", "w", "w_from")]

    uncovered = pc.is_null(m0[target])
    uncovered_any = pc.any(uncovered).as_py() or False
    if uncovered_any and na_action == "drop":
        if do_diag:
            unc = m0.filter(uncovered)
            src_set = set(src_keys)
            affected = [k for k in dict.fromkeys(_strings(unc, source))
                        if k in src_set]
            if affected:
                _warn('%d atom(s) have no code at %s `%s`; the share of %d source '
                      "unit(s) falling in them is dropped (%s). Use na_action = "
                      '"keep" to conserve totals.',
                      pc.sum(unc["n_overlap"]).as_py(), v["frame"], target,
                      len(affected), _preview(affected))
        keep = pc.invert(uncovered)
        maps = {w: m.filter(keep) for w, m in maps.items()}
    retained_from = list(dict.fromkeys(_strings(maps[next(iter(maps))], source)))

    res_targets = (scale_residuals(x, target)
                   if scale_rank(x, target) > scale_rank(x, source) else [])
    jmap, sfx = _widen_maps(maps, source, target, key, wt_of, res_targets)
    lazy_out = bk.lazy and not collect
    res = _pipeline(t, jmap, key, values, rules, id_cols, map_by, missing_sources,
                    sfx, unit=v["unit"], check_copy=not lazy_out)
    res = _rename(res, {"__ms_to": target})

    if lazy_out:
        return _restore(res.select([target, *id_cols, *values]), bk, collect)

    if do_diag:
        if id_cols:
            pairs = _distinct(t, [*id_cols, key])
            n_groups = _distinct(t, id_cols).num_rows
            cnt = dict(zip(*_count_by(pairs, key), strict=True))
            all_missing = [k for k in retained_from if cnt.get(k, 0) < n_groups]
            shown = (_missing_in_group_order(pairs, id_cols, key, all_missing,
                                             retained_from)
                     if all_missing else [])
        else:
            present = set(src_keys)
            all_missing = shown = [k for k in retained_from if k not in present]
        if all_missing:
            _warn("%d source unit(s) present in the scale but missing from the "
                  "data (e.g. %s); produced NAs", len(all_missing),
                  _preview_total(shown, len(all_missing)))

    idc = distinct_rows(t, id_cols) if id_cols else pa.table({})
    out_keys = list(x.members[target])
    if na_action == "keep" and uncovered_any:
        out_keys.append(None)
    out = _recast_complete(res, idc, out_keys, target, id_cols, values)
    return _restore(out, bk, collect)


def _distinct(t: pa.Table, cols: Sequence[str]) -> pa.Table:
    """Distinct combinations of `cols`, in no particular order."""
    return _agg(t.select(list(cols)), cols, [])


def _paste(t: pa.Table, cols: Sequence[str]) -> pa.ChunkedArray:
    """R's `paste(..., sep = "\\r")` over columns, vectorised (NA as "NA")."""
    parts = [pc.cast(_plain(t[c]), pa.string()) for c in cols]
    if len(parts) == 1:
        return pc.fill_null(parts[0], "NA")
    return pc.binary_join_element_wise(*parts, "\r", null_handling="replace",
                                       null_replacement="NA")


def _preview_total(first: Sequence[str], total: int, n: int = 3) -> str:
    """`_preview()` of a vector known only by its leading items and length."""
    if total <= n:
        return ", ".join(first[:total])
    return "%s, ... (%d total)" % (", ".join(first[:n]), total)


def _missing_in_group_order(pairs: pa.Table, id_cols: Sequence[str], key: str,
                            missing: Sequence[str], retained: Sequence[str],
                            n: int = 3) -> list[str]:
    """The leading missing sources in R's report order: identifier groups
    sorted by their pasted key, each group's gaps in crosswalk order.

    Only the first `n` are needed for the message, so only the first
    deficient groups are inspected.
    """
    want = min(n, len(missing))
    rset = pa.array(list(retained), pa.string())
    kept = pairs.filter(pc.is_in(pairs[key], value_set=rset))
    gk = _paste(kept, id_cols)
    counts = dict(zip(*_count_by(pa.table({"g": gk}), "g"), strict=True))
    groups = pc.unique(_paste(pairs, id_cols)).to_pylist()
    out: dict[str, None] = {}
    for g in sorted(groups):
        if counts.get(g, 0) >= len(retained):
            continue
        present = set(kept.filter(pc.equal(gk, g))[key].to_pylist())
        for k in retained:
            if k not in present:
                out[k] = None
        if len(out) >= want:
            break
    return list(out)


def _count_by(t: pa.Table, col: str) -> tuple[list, list]:
    t = t.append_column("__ms_one", pa.array(np.ones(t.num_rows, np.int64)))
    g = _agg(t, [col], [("__ms_one", "sum")])
    return g[col].to_pylist(), g["__ms_one_sum"].to_pylist()


def _recast_batched(data: Any, bk: Backend, batch: int, batch_by: str,
                    args: dict) -> Any:
    """Run a recast in chunks of identifier values and bind the results.

    Diagnostics are off inside chunks: a source absent from one chunk is
    usually present in another.
    """
    vals = distinct_rows(scan(data, bk, [batch_by]), [batch_by])[batch_by]
    args.update(diagnostics="off", collect=True)
    parts = []
    for ch in chunks(vals.to_pylist(), batch):
        flt = pc.field(batch_by).isin(pa.array(ch, vals.type))
        d = scan(data, bk, None, filter=flt)
        parts.append(recast_scale(d, **args))
    return _restore(bind_rows(parts), bk, collect=True)


def _share_parent(x: NestedScale, source: str, target: str, parent: str | None) -> str:
    """Explicit `parent`, else `target` when it differs, else the frame above."""
    if parent is not None:
        _check_frame(x, parent, "parent")
        if target != source and target != parent:
            _stop('conflicting parents: `target = "%s"` vs `parent = "%s"`; for rule '
                  '"share" pass the parent once', target, parent)
    elif target != source:
        parent = target
    else:
        fr = list(x.frames)
        i = fr.index(source) if source in fr else -1
        if i <= 0:
            _stop("`%s` has no coarser frame; pass `parent=`", source)
        parent = fr[i - 1]
    if scale_rank(x, parent) >= scale_rank(x, source):
        _stop('rule "share": parent `%s` must be coarser than `source = "%s"`',
              parent, source)
    return parent


def _recast_share(t: pa.Table, bk: Backend, x: NestedScale, source: str, target: str,
                  key: str, values: Sequence[str], id_cols: Sequence[str],
                  parent: str | None, na_action: str, collect: bool | None) -> Any:
    """Each source unit's value over its parent-group total, keyed at `source`."""
    parent = _share_parent(x, source, target, parent)
    m = scale_map(x, source, parent)
    mem = distinct_rows(m, [source, parent])

    n_par: dict = {}
    for a, b in zip(_strings(mem, source), _strings(mem, parent), strict=True):
        if b is not None:
            n_par[a] = n_par.get(a, 0) + 1
    split_codes = sorted(k for k, n in n_par.items() if n > 1)
    if split_codes:
        _stop('rule "share": %d unit(s) of `%s` straddle more than one `%s` (%s); '
              "`source` must nest within the parent", len(split_codes), source,
              parent, _preview(split_codes))

    orphan = pc.is_null(mem[parent])
    n_orphan = pc.sum(pc.cast(orphan, pa.int64())).as_py() or 0
    if n_orphan:
        if na_action == "error":
            _stop('%d unit(s) of `%s` have no code at parent `%s`; use na_action = '
                  '"drop" or "keep"', n_orphan, source, parent)
        if na_action == "drop":
            _warn('%d unit(s) of `%s` have no code at parent `%s` and get NA '
                  'shares (%s). Use na_action = "keep" to treat them as one group.',
                  n_orphan, source, parent,
                  _preview(_strings(mem.filter(orphan), source)))
            mem = mem.filter(pc.invert(orphan))

    jmem = mem.rename_columns([key, "__ms_parent"])
    id_cols = list(id_cols)
    joined = t.select([*id_cols, key, *values]).join(
        jmem, keys=key, join_type="inner", use_threads=True)
    tot_nms = ["__ms_tot_%d" % (i + 1) for i in range(len(values))]
    tot = _agg(joined, [*id_cols, "__ms_parent"],
               [(vv, "sum", _KEEP_NULLS) for vv in values])
    tot = _rename(tot, {vv + "_sum": tn for vv, tn in zip(values, tot_nms,
                                                            strict=True)})
    res = _join_na(joined, tot, [*id_cols, "__ms_parent"])
    for vv, tn in zip(values, tot_nms, strict=True):
        tt = _f64(res[tn])
        res = _set(res, vv, pc.if_else(pc.not_equal(tt, 0),
                                        pc.divide(_f64(res[vv]), tt), _NULL))
    res = _rename(res.select([key, *id_cols, *values]), {key: source})

    if bk.lazy and not collect:
        return _restore(res.select([source, *id_cols, *values]), bk, collect)
    idc = distinct_rows(t, id_cols) if id_cols else pa.table({})
    out = _recast_complete(res, idc, list(x.members[source]), source, id_cols,
                           values)
    return _restore(out, bk, collect)


# -----------------------------------------------------------------------------
# recast_crosswalk()
# -----------------------------------------------------------------------------

def recast_crosswalk(data: Any, map: Any, source: str, target: str,
                     key: str | None = None,
                     values: str | Sequence[str] | None = None,
                     rule: str | Mapping[str, str] | None = None,
                     ids: Sequence[str] | None = None, by: Sequence[str] = (),
                     targets: Sequence[str | None] | None = None,
                     missing_sources: MissingSources = "na", unit: str = "unit",
                     collect: bool | None = None) -> Any:
    """Recast values through a given crosswalk.

    `map` has one row per (source, target) pair: the codes in columns `source`
    and `target`, `n_from`, `n_overlap`, optionally `w` (weighted-mean weight;
    default `n_overlap`) and `w_from` (with both, `sum` splits by
    `w / w_from`; otherwise by `n_overlap / n_from`), and any `by` columns.
    """
    from ._backend import as_table

    missing_sources = _match_choice(missing_sources, ("na", "ignore"),
                                    "missing_sources")
    if key is None:
        key = source
    bk = backend_of(data, "data")
    schema = schema_of(data, bk)
    _check_ms_cols(schema)
    if isinstance(map, (str, bytes, int, float)) or map is None:
        _stop("`map` must be a data.frame")
    mp = as_table(map, "map")
    by = list(_as_str_tuple(by))
    absent = [c for c in [source, target, "n_from", "n_overlap", *by]
              if c not in mp.column_names]
    if absent:
        _stop("`map` is missing column(s): %s", _preview(absent))
    if key not in schema.names:
        _stop("the data has no column named `%s`; pass `key=`", key)

    ids = None if ids is None else list(_as_str_tuple(ids))
    values = _values_for(schema, key, ids or [], values)
    if ids is None:
        ids = [c for c in schema.names if c != key and c not in values]
    bad_by = [c for c in by if c not in ids]
    if bad_by:
        _stop("`by` column(s) are not identifier columns of the data: %s",
              _preview(bad_by))
    rules = _rules_for(values, rule)
    _no_share(rules, "recast_crosswalk")

    jmap = pa.table({
        key: pc.cast(mp[source], pa.string()),
        "__ms_to": pc.cast(mp[target], pa.string()),
        "__ms_n_from": mp["n_from"], "__ms_n_overlap": mp["n_overlap"],
        **{c: mp[c] for c in by}})
    n_ov, n_fr = _f64(mp["n_overlap"]), _f64(mp["n_from"])
    has_w = "w" in mp.column_names and "w_from" in mp.column_names
    jmap = jmap.append_column("__ms_w", _f64(mp["w"]) if "w" in mp.column_names
                              else n_ov)
    if has_w:
        f = pc.if_else(pc.greater(_f64(mp["w_from"]), 0),
                       pc.divide(_f64(mp["w"]), _f64(mp["w_from"])),
                       pc.divide(n_ov, n_fr))
    else:
        f = pc.divide(n_ov, n_fr)
    jmap = jmap.append_column("__ms_f", f)

    lazy_out = bk.lazy and not collect
    t = _as_string_key(scan(data, bk, [*ids, key, *values]), key)
    res = _pipeline(t, jmap, key, values, rules, ids, map_by=by,
                    missing_sources=missing_sources, unit=unit,
                    check_copy=not lazy_out)
    res = _rename(res, {"__ms_to": target})
    if lazy_out:
        return _restore(res.select([target, *ids, *values]), bk, collect)
    if targets is None:
        out = res.select([target, *ids, *values])
    else:
        idc = distinct_rows(t, ids) if ids else pa.table({})
        out = _recast_complete(res, idc, list(targets), target, ids, values)
    return _restore(out, bk, collect)


# -----------------------------------------------------------------------------
# the route halves
# -----------------------------------------------------------------------------

def recast_to_atoms(data: Any, x: NestedScale, source: str | None = None,
                    key: str | None = None,
                    values: str | Sequence[str] | None = None,
                    rule: str | Mapping[str, str] | None = None,
                    weight: str | Mapping[str, str] | None = None,
                    attach_weight: bool = True, collect: bool | None = None) -> Any:
    """Project unit-keyed data DOWN to the atom layer (one row per atom).

    Extensive columns (rule `sum`) are split across a unit's atoms by weight
    so totals conserve; intensive columns are repeated. A `weight` column is
    attached so the return trip's `weighted_mean` reproduces the weighting.
    """
    _check_scale(x, "x")
    bk = backend_of(data, "data")
    schema = schema_of(data, bk)
    _check_ms_cols(schema)
    if source is None:
        source = _infer_from(x, schema, key)
    _check_frame(x, source, "source")
    if key is None:
        key = source if source in schema.names else scale_key(x)
    if key not in schema.names:
        _stop("the data has no column named `%s`; pass `key=`", key)

    frames_all = list(x.frames)
    values = _values_for(schema, key, frames_all, values)
    id_cols = [c for c in schema.names
               if c != key and c not in values and c not in frames_all]
    rules = _rules_for(values, rule, weight, scope=_scale_scope(x),
                       hint=_rule_hint(x))
    _no_share(rules, "recast_to_atoms")

    akey = scale_key(x)
    lt = x.leaftable
    wcol = _map_weight(x, weight if isinstance(weight, str) or weight is None
                       else None)
    frm = _strings(lt, source)
    atom = _strings(lt, akey)
    w = ([1.0] * lt.num_rows if wcol is None else
         [0.0 if z is None else float(z) for z in lt[wcol].to_pylist()])
    rows = [(a, b, c) for a, b, c in zip(frm, atom, w, strict=True) if a is not None]
    w_from: dict = {}
    n: dict = {}
    for a, _, c in rows:
        w_from[a] = w_from.get(a, 0.0) + c
        n[a] = n.get(a, 0) + 1
    f = [c / w_from[a] if w_from[a] > 0 else 1.0 / n[a] for a, _, c in rows]
    src = "__ms_src" if key == akey else key
    jmap = pa.table({src: pa.array([r[0] for r in rows], pa.string()),
                     akey: pa.array([r[1] for r in rows], pa.string()),
                     "weight": pa.array([r[2] for r in rows], pa.float64()),
                     "__ms_f": pa.array(f, pa.float64())})
    if key == akey:
        jmap = jmap.drop_columns([akey])

    t = _as_string_key(scan(data, bk, [*id_cols, key, *values]), key)
    out = t.join(jmap, keys=key, right_keys=src, join_type="inner",
                 use_threads=True)
    for vv in values:
        if rules[vv]["rule"] == "sum":
            out = _set(out, vv, pc.multiply(_f64(out[vv]), out["__ms_f"]))
    out = out.select([akey, *id_cols, *values, *(["weight"] if attach_weight else [])])
    return _restore(out, bk, collect)


def _group_parts(rule: str, val: pa.ChunkedArray, ww: pa.ChunkedArray,
                 na_rm: bool) -> tuple[dict, list]:
    """Columns and aggregates for one value column of recast_from_atoms()."""
    if na_rm:
        # R's na.rm drops NaN too
        val = pc.if_else(pc.is_nan(val), _NULL, val)
    cols = {"v": val}
    specs = []
    opt = _SKIP_NULLS if na_rm else _KEEP_NULLS
    if rule in ("sum", "mean", "copy"):
        specs.append(("v", "sum" if rule == "sum" else "mean", opt))
    elif rule == "weighted_mean":
        if na_rm:
            ok = pc.is_valid(val)
            cols["vw"] = pc.if_else(ok, pc.multiply(val, ww), 0.0)
            cols["w"] = pc.if_else(ok, ww, 0.0)
        else:
            cols["vw"] = pc.multiply(val, ww)
            cols["w"] = ww
        specs += [("vw", "sum", opt), ("w", "sum", _KEEP_NULLS), ("v", "mean", opt)]
    elif rule == "sd":
        specs.append(("v", "stddev", pc.VarianceOptions(
            ddof=1, skip_nulls=na_rm, min_count=0)))
    else:
        _stop("Unknown rule: %s", rule)
    if rule == "copy":
        specs += [("v", "max", _KEEP_NULLS), ("v", "min", _KEEP_NULLS)]
    if na_rm:
        specs.append(("v", "count", _COUNT_VALID))
    return cols, specs


def _group_result(rule: str, g: dict, na_rm: bool) -> pa.ChunkedArray:
    if rule in ("sum", "mean", "copy"):
        r = g["v_sum" if rule == "sum" else "v_mean"]
    elif rule == "weighted_mean":
        r = pc.if_else(pc.greater(g["w_sum"], 0), pc.divide(g["vw_sum"], g["w_sum"]),
                       g["v_mean"])
    else:
        r = g["v_stddev"]
    r = _f64(r)
    if na_rm and rule != "sd":
        r = pc.if_else(pc.greater(g["v_count"], 0), r, _NULL)
    return r


def recast_from_atoms(data: Any, x: NestedScale, target: str, key: str | None = None,
                      values: str | Sequence[str] | None = None,
                      rule: str | Mapping[str, str] | None = None,
                      weight: str | None = None, na_rm: bool = False,
                      na_action: NaAction = "drop",
                      collect: bool | None = None) -> Any:
    """Aggregate atom-keyed data UP into the units of frame `target`.

    `weight` names a column of the data to weight by (so it may vary by
    identifier); None uses a `weight` column if present, else the scale's
    declared weight. With `na_rm=True` a null member says nothing rather than
    making its group null. Unlike `recast_scale()`, a missing atom simply
    does not contribute (no partial-source poisoning).
    """
    na_action = _match_choice(na_action, ("drop", "error", "keep"), "na_action")
    _check_scale(x, "x")
    _check_frame(x, target, "target")
    bk = backend_of(data, "data")
    schema = schema_of(data, bk)
    _check_ms_cols(schema)

    akey = scale_key(x)
    if key is None:
        key = akey
    if key not in schema.names:
        _stop("the data has no column named `%s`; pass `key=`", key)
    wt_col = weight if weight is not None else (
        "weight" if "weight" in schema.names else None)
    if wt_col is not None and wt_col not in schema.names:
        _stop("`weight` column `%s` is not in the data", wt_col)

    frames_all = list(x.frames)
    drop = [*frames_all, "weight", *([wt_col] if wt_col else [])]
    values = _values_for(schema, key, drop, values)
    id_cols = [c for c in schema.names
               if c != key and c not in values and c not in drop]
    rules = _rules_for(values, rule, None, scope=_scale_scope(x),
                       hint=_rule_hint(x))
    _no_share(rules, "recast_from_atoms")

    lt = x.leaftable
    ks, ts = _strings(lt, akey), _strings(lt, target)
    n_unc = sum(z is None for z in ts)
    uncovered_any = n_unc > 0
    pairs = list(zip(ks, ts, strict=True))
    if uncovered_any:
        if na_action == "error":
            _stop('%d atom(s) have no code at `%s`; use na_action = "drop" or '
                  '"keep"', n_unc, target)
        if na_action == "drop":
            _warn("%d atom(s) have no code at `%s` and were dropped", n_unc, target)
            pairs = [p for p in pairs if p[1] is not None]
    jmem = pa.table({key: pa.array([p[0] for p in pairs], pa.string()),
                     "__ms_to": pa.array([p[1] for p in pairs], pa.string())})

    t = _as_string_key(scan(data, bk, [*id_cols, key, *values,
                                       *([wt_col] if wt_col else [])]), key)
    if wt_col is None:
        wcol = _map_weight(x, None)
        aw = pa.table({key: pa.array(ks, pa.string()),
                       "__ms_w": (pa.array([1.0] * len(ks)) if wcol is None
                                 else _f64(lt[wcol]))})
        t = t.join(aw, keys=key, join_type="left outer", use_threads=True)
        wt_col = "__ms_w"

    joined = t.join(jmem, keys=key, join_type="inner", use_threads=True)
    grp = [*id_cols, "__ms_to"]
    ww = _f64(joined[wt_col])
    cols: dict[str, Any] = {c: joined[c] for c in grp}
    specs: list = []
    names: dict[str, dict] = {}
    copy_cols = [v for v in values if rules[v]["rule"] == "copy"]
    for i, v in enumerate(values):
        c, s = _group_parts(rules[v]["rule"], _f64(joined[v]), ww, na_rm)
        pref = "__ms_g%d_" % i
        for nm, arr in c.items():
            cols[pref + nm] = arr
        specs += [(pref + col, fn, opt) for col, fn, opt in s]
        names[v] = {"%s_%s" % (col, fn): "%s%s_%s" % (pref, col, fn)
                    for col, fn, _ in s}
    g = _agg(pa.table(cols), grp, specs)
    res = g.select(grp)
    for v in values:
        gv = {k: g[n] for k, n in names[v].items()}
        res = res.append_column(v, _group_result(rules[v]["rule"], gv, na_rm))
        if rules[v]["rule"] == "copy":
            res = res.append_column("__ms_mx_" + v, gv["v_max"])
            res = res.append_column("__ms_mn_" + v, gv["v_min"])
    lazy_out = bk.lazy and not collect
    if copy_cols and not lazy_out:
        _check_copy_result(res, copy_cols, scale_vocab(x)["unit"])
    res = _rename(res.select([*grp, *values]), {"__ms_to": target})
    if lazy_out:
        return _restore(res.select([target, *id_cols, *values]), bk, collect)

    idc = distinct_rows(t, id_cols) if id_cols else pa.table({})
    out_keys = list(x.members[target])
    if na_action == "keep" and uncovered_any:
        out_keys.append(None)
    out = _recast_complete(res, idc, out_keys, target, id_cols, values)
    return _restore(out, bk, collect)


# -----------------------------------------------------------------------------
# the bare pipeline generic
# -----------------------------------------------------------------------------

@functools.singledispatch
def _recast_method(scale: object, x: Any, *args: Any, **kwargs: Any) -> Any:
    _stop("no recast() method for a `%s`", type(scale).__name__)


@_recast_method.register
def _(scale: NestedScale, x: Any, target: Any = None, source: str | None = None,
      **kwargs: Any) -> Any:
    return recast_scale(x, scale, source=source, target=target, **kwargs)


def recast(x: Any, scale: Any, *args: Any, **kwargs: Any) -> Any:
    """Recast data `x` through `scale`, dispatching on the scale's class.

    For a NestedScale the arguments are those of `recast_scale()`: `target`
    is the target frame (or scale) and `source` the source frame, inferred
    when omitted. Dimension packages register methods with
    `recast.register(TheirClass)`.
    """
    return _recast_method(scale, x, *args, **kwargs)


recast.register = _recast_method.register  # type: ignore[attr-defined]
