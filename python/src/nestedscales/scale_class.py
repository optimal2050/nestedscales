"""NestedScale -- the dimension-agnostic core type (port of R/scale-class.R).

A `NestedScale` is a nested partition of a set of atoms, in any dimension:

* `leaftable` -- one row per atom: a column per frame, a unique key column
  (named by `key`) and zero or more numeric weight columns
* `frames`    -- frame names, COARSEST first
* `members`   -- frame -> the ordered code vocabulary at that frame
* `key`       -- name of the atom key column (default `"unit"`)
* `meta`      -- name, desc, weights, default_weight, residuals, labels,
                 source, and the sample bookkeeping (coverage,
                 parent_totals, parent_name)

Frames are partitions of the atoms, not necessarily a tree; conversion always
routes through the atoms. Anything derivable is computed on demand.
"""
from __future__ import annotations

import functools
import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any

import pyarrow as pa
import pyarrow.compute as pc

from ._utils import _as_str_tuple, _preview, _stop
from .frames import RESERVED_COLS, is_valid_frame


def _strings(t: pa.Table, col: str) -> list:
    """A leaftable column as Python strings, nulls as None."""
    c = t[col]
    if not (pa.types.is_string(c.type) or pa.types.is_large_string(c.type)):
        c = pc.cast(c, pa.string())
    return c.to_pylist()


def _finite_sum(v: list) -> float:
    """Sum with R's `na.rm = TRUE`: nulls and NaN dropped."""
    return float(sum(z for z in v if z is not None and not math.isnan(z)))


def _is_numeric(t: pa.Table, col: str) -> bool:
    ty = t.schema.field(col).type
    return pa.types.is_integer(ty) or pa.types.is_floating(ty)


@dataclass(frozen=True, eq=False, repr=False)
class NestedScale:
    """A nested discrete partition: a table of atoms plus the frames grouping them.

    Construct with `scale_from_leaftable()`. Treat as immutable: every verb
    returns a new object.
    """

    leaftable: pa.Table
    frames: tuple[str, ...]
    members: dict[str, tuple[str, ...]]
    key: str = "unit"
    meta: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        object.__setattr__(self, "frames", _as_str_tuple(self.frames))
        if isinstance(self.members, Mapping):
            object.__setattr__(self, "members", {
                k: _as_str_tuple(v) for k, v in self.members.items()})
        if isinstance(self.meta, Mapping):
            meta = dict(self.meta)
            if meta.get("weights") is not None:
                meta["weights"] = _as_str_tuple(meta["weights"])
            if isinstance(meta.get("residuals"), Mapping):
                meta["residuals"] = {k: _as_str_tuple(v)
                                     for k, v in meta["residuals"].items()}
            object.__setattr__(self, "meta", meta)
        errs = _validate(self)
        if errs:
            cls = type(self)
            pkg = getattr(cls, "_r_package", cls.__module__.split(".")[0])
            _stop("<%s::%s> object is invalid:\n%s", pkg, cls.__name__,
                  "\n".join("- " + e for e in errs))

    def __eq__(self, other: object) -> bool:
        if type(other) is not type(self):
            return NotImplemented
        return (self.frames == other.frames and self.key == other.key
                and self.members == other.members and self.meta == other.meta
                and self.leaftable.equals(other.leaftable))

    __hash__ = None  # type: ignore[assignment]

    def __getitem__(self, idx: tuple) -> NestedScale:
        """`x[frame, unit]` is `filter_scale(x, frame, unit)`, as in R."""
        from .filter import filter_scale

        if not isinstance(idx, tuple) or len(idx) != 2:
            _stop("subset a scale as `x[frame, unit]`")
        return filter_scale(self, idx[0], idx[1])

    def __repr__(self) -> str:
        return "<%s[%s] atoms=%d>" % (
            type(self).__name__, "/".join(self.frames), self.leaftable.num_rows)

    def __str__(self) -> str:
        return _format_scale(self)


# Validation ------------------------------------------------------------------

def _validate(self: NestedScale) -> list[str]:
    errs: list[str] = []
    leaftable, frames, members = self.leaftable, self.frames, self.members
    key, meta = self.key, self.meta

    # leaftable
    if not isinstance(leaftable, pa.Table):
        return ["`leaftable` must be a pyarrow Table"]
    if leaftable.num_rows == 0:
        errs.append("`leaftable` must have at least one row")
    cols = leaftable.column_names

    # key
    if not isinstance(key, str) or key == "":
        return ["`key` must be a single non-empty string"]
    if key not in cols:
        errs.append("`leaftable` must have a `%s` column (the atom key)" % key)

    # frames
    if len(frames) == 0 or not all(isinstance(f, str) for f in frames):
        errs.append("`frames` must be a non-empty character vector")
    elif len(set(frames)) != len(frames):
        errs.append("`frames` must be unique")
    else:
        valid = is_valid_frame(frames)
        bad = [f for f, ok in zip(frames, valid, strict=True) if not ok]
        if bad:
            errs.append("`frames` contains invalid names: %s" % _preview(bad))
        # The key name is allowed as the FINEST frame: there the frame column
        # is the key column. As a coarser frame it would clash with it.
        clash = [f for f in RESERVED_COLS if f in frames]
        if key in frames and frames[-1] != key:
            clash.append(key)
        if clash:
            errs.append("`frames` may not use reserved names: %s" % _preview(clash))
        missing = [f for f in frames if f not in cols]
        if missing:
            errs.append("`leaftable` missing frame columns: %s" % _preview(missing))

    # atom key values
    if key in cols:
        ty = leaftable.schema.field(key).type
        uid = leaftable[key].to_pylist()
        if not (pa.types.is_string(ty) or pa.types.is_large_string(ty)) or \
                any(u is None or u == "" for u in uid):
            errs.append("`leaftable$%s` must be a non-empty character vector" % key)
        elif len(set(uid)) != len(uid):
            seen: set = set()
            dup = list(dict.fromkeys(u for u in uid if u in seen or seen.add(u)))
            errs.append(
                "`leaftable$%s` must be unique; duplicated: %s. "
                "Parallel dimensions belong in separate NestedScale objects."
                % (key, _preview(dup)))

    # members
    if not isinstance(members, Mapping):
        errs.append("`members` must be a list")
    elif not errs:
        missing = [f for f in frames if f not in members]
        if missing:
            errs.append("`members` missing entries for: %s" % _preview(missing))
        for f in [f for f in frames if f in members]:
            mb = members[f]
            if (len(mb) == 0 or not all(isinstance(m, str) and m != "" for m in mb)
                    or len(set(mb)) != len(mb)):
                errs.append('`members[["%s"]]` must be a unique non-empty '
                            "character vector" % f)
                continue
            seen_codes = {v for v in _strings(leaftable, f) if v is not None}
            if seen_codes != set(mb):
                errs.append('`members[["%s"]]` must contain exactly the non-NA '
                            "values present in `leaftable$%s`" % (f, f))

    # meta
    if not isinstance(meta, Mapping):
        errs.append("`meta` must be a list")
        return errs

    # weights
    wts = meta.get("weights")
    if wts is not None:
        if not all(isinstance(w, str) for w in wts):
            errs.append("`meta$weights` must be a character vector")
        else:
            for w in wts:
                if w not in cols:
                    errs.append("weight column `%s` not found in `leaftable`" % w)
                    continue
                if not _is_numeric(leaftable, w):
                    errs.append("weight column `%s` must be numeric" % w)
                    continue
                v = [z for z in leaftable[w].to_pylist() if z is not None]
                if any(not math.isfinite(z) and not math.isnan(z) for z in v):
                    errs.append("weight column `%s` must be finite" % w)
                elif any(z < 0 for z in v if not math.isnan(z)):
                    errs.append("weight column `%s` must be >= 0" % w)
                elif sum(z for z in v if not math.isnan(z)) <= 0:
                    errs.append("weight column `%s` sums to zero" % w)
            dw = meta.get("default_weight")
            if dw is not None and not (isinstance(dw, str) and dw in wts):
                errs.append("`meta$default_weight` must be one of `meta$weights`")

    # residuals: units that carry a value but take no allocation. Declared per
    # frame because codes are not unique across frames.
    res = meta.get("residuals")
    if res is not None:
        if not isinstance(res, Mapping) or any(not isinstance(k, str) or k == ""
                                               for k in res):
            errs.append("`meta$residuals` must be a named list, one entry per frame")
        else:
            bad_fr = [k for k in res if k not in frames]
            if bad_fr:
                errs.append("`meta$residuals` names frame(s) that are not frames: "
                            "%s" % _preview(bad_fr))
            for f in [k for k in res if k in frames]:
                codes = res[f]
                if not all(isinstance(c, str) for c in codes):
                    errs.append('`meta$residuals[["%s"]]` must be a character '
                                "vector" % f)
                    continue
                unknown = [c for c in codes if c not in members.get(f, ())]
                if unknown:
                    errs.append('`meta$residuals[["%s"]]` names non-member(s): %s'
                                % (f, _preview(unknown)))

    # sample bookkeeping: coverage must be verifiable from the object itself
    cov = meta.get("coverage")
    if cov is not None:
        wts = meta.get("weights") or ()
        if not isinstance(cov, Mapping) or not all(
                k in wts and isinstance(v, (int, float)) for k, v in cov.items()):
            errs.append("`meta$coverage` must be a named numeric over declared "
                        "weights")
        elif any(not math.isfinite(v) or v <= 0 or v > 1 for v in cov.values()):
            errs.append("`meta$coverage` values must lie in (0, 1]")
        elif meta.get("parent_totals") is not None:
            pt = meta["parent_totals"]
            for w in [k for k in cov if k in pt]:
                got = sum(z for z in leaftable[w].to_pylist()
                          if z is not None and not math.isnan(z)) / pt[w]
                if abs(got - cov[w]) > 1e-8:
                    errs.append('`meta$coverage["%s"]` (%.6g) does not match the '
                                "leaftable (%.6g)" % (w, cov[w], got))
        pn = meta.get("parent_name")
        if pn is not None and not (isinstance(pn, str) and pn != ""):
            errs.append("`meta$parent_name` must be a single non-empty string")

    return errs


# Dimension vocabulary -------------------------------------------------------------

@functools.singledispatch
def scale_vocab(x: NestedScale) -> dict[str, str]:
    """The words engine messages use for this scale's dimension.

    Subclasses register their own implementation with
    `scale_vocab.register(Subclass)`.
    """
    _check_scale(x)
    return {"object": "NestedScale", "frame": "frame", "frames": "frames",
            "unit": "unit", "units": "units", "atoms": "atoms"}


@functools.singledispatch
def scale_payload_slice(x: NestedScale, i: Sequence[int]) -> NestedScale:
    """Subset a subclass's per-atom payload to the kept leaftable rows `i`.

    The `NestedScale` default has no payload and returns `x` unchanged.
    """
    _check_scale(x)
    return x


def scale_alias_property(name: str) -> property:
    """A read-only property exposing an inherited field under another name.

    How a `Calendar` keeps `timeframes` and a `Geoscale` keeps `geoframes`
    over the inherited `frames`.
    """
    return property(lambda self: getattr(self, name),
                    doc="Alias of `%s`." % name)


# Accessors --------------------------------------------------------------------------

def scale_rank(x: NestedScale, frame: str | Sequence[str]) -> int | None | list:
    """Position of a frame in the hierarchy; 1 is the coarsest.

    The key ranks one past the last frame when it is not itself a frame. Names
    that are not frames give None.
    """
    _check_scale(x)

    def one(f: str) -> int | None:
        if f in x.frames:
            return x.frames.index(f) + 1
        return len(x.frames) + 1 if f == x.key else None

    if isinstance(frame, str):
        return one(frame)
    return [one(f) for f in frame]


def scale_frames(x: NestedScale, finest: bool = False) -> list[str] | str:
    """Frame names, coarsest first; only the finest when `finest=True`."""
    _check_scale(x)
    return x.frames[-1] if finest else list(x.frames)


def scale_units(x: NestedScale, frame: str | None = None) -> list[str]:
    """The code vocabulary at one frame, in canonical order (default: atoms)."""
    _check_scale(x)
    if frame is None:
        frame = _atom_level(x)
    _check_frame(x, frame)
    if frame == x.key and frame not in x.frames:
        return list(dict.fromkeys(_strings(x.leaftable, frame)))
    return list(x.members[frame])


def scale_atom_level(x: NestedScale) -> str:
    """The finest frame when it has one code per atom, otherwise the key."""
    _check_scale(x)
    return _atom_level(x)


def _atom_level(x: NestedScale) -> str:
    finest = x.frames[-1]
    if len(x.members.get(finest, ())) == x.leaftable.num_rows:
        return finest
    return x.key


def _nav_levels(x: NestedScale) -> list[str]:
    """The frames, plus the key as the finest level when it is the atom level."""
    at = _atom_level(x)
    return list(x.frames) if at in x.frames else [*x.frames, at]


def scale_key(x: NestedScale) -> str:
    """The atom key column name."""
    _check_scale(x)
    return x.key


def scale_leaftable(x: NestedScale) -> pa.Table:
    """The one-row-per-atom table the scale is built on."""
    _check_scale(x)
    return x.leaftable


def scale_weights(x: NestedScale) -> list[str]:
    """Weight column names (possibly empty)."""
    _check_scale(x)
    return list(x.meta.get("weights") or ())


def scale_residuals(x: NestedScale, frame: str | None = None) -> dict | list[str]:
    """Residual units: the frame -> codes mapping, or one frame's codes."""
    _check_scale(x)
    res = x.meta.get("residuals")
    if res is None:
        return {} if frame is None else []
    if frame is None:
        return {k: list(v) for k, v in res.items()}
    _check_frame(x, frame)
    return list(res.get(frame, ()))


def scale_is(x: object) -> bool:
    """Is `x` a NestedScale (or a subclass)?"""
    return isinstance(x, NestedScale)


def scale_class() -> type[NestedScale]:
    """The NestedScale class, for subclassing and dispatch."""
    return NestedScale


# Argument checks ----------------------------------------------------------------------

def _check_scale(x: object, arg: str = "x") -> None:
    if not isinstance(x, NestedScale):
        if type(x).__name__ == "ScaleProduct":
            _stop("`%s` is a ScaleProduct, not a single NestedScale. Its atoms are "
                  "not materialised -- use `scale_axes()` for the component "
                  "scales, or `product_atoms()` to build the grid.", arg)
        _stop("`%s` must be a NestedScale object", arg)


def _check_frame(x: NestedScale, frame: object, arg: str | None = None) -> None:
    v = scale_vocab(x)
    if arg is None:
        arg = v["frame"]
    if not isinstance(frame, str):
        _stop("`%s` must be a single %s name; one of: %s",
              arg, v["frame"], ", ".join(x.frames))
    if frame not in x.frames and frame != x.key:
        _stop('`%s` = "%s" is not a %s of this %s; one of: %s',
              arg, frame, v["frame"], v["object"],
              ", ".join(dict.fromkeys([*x.frames, x.key])))


def _scale_name(x: NestedScale, require: bool = True, arg: str = "x") -> str:
    """`meta$name`; conversion and attach need one, as columns are named by it."""
    nm = x.meta.get("name") or ""
    if require and not (isinstance(nm, str) and nm != ""):
        _stop("`%s` has no name; conversion and attach need a named scale -- set "
              "meta$name, or pass `name=` to scale_from_leaftable()", arg)
    return nm


def _resolve_weight(x: NestedScale, weight: str | None = None) -> str:
    wts = scale_weights(x)
    if weight is None:
        weight = x.meta.get("default_weight") or (wts[0] if wts else None)
    if weight is None:
        _stop("no weight column available; declare one via `meta$weights` or "
              "pass `weight=`")
    if weight not in wts:
        _stop('`weight` = "%s" is not a weight column; one of: %s',
              weight, ", ".join(wts) if wts else "<none>")
    return weight


# Format / print --------------------------------------------------------------

def _format_scale(x: NestedScale) -> str:
    meta, f, lf = x.meta, x.frames, x.leaftable
    v = scale_vocab(x)
    name = meta.get("name") or ""
    out = ["%s: %s" % (v["object"], name or "<unnamed>")]
    if meta.get("desc"):
        out.append("Description: %s" % meta["desc"])
    out.append("%s (%d, coarsest first):" % (v["frames"].capitalize(), len(f)))
    for i, fr in enumerate(f):
        n_na = lf[fr].null_count
        out.append("  %s- %s (%d)%s" % (
            "  " * i, fr, len(x.members.get(fr, ())),
            "  [%d %s unassigned]" % (n_na, v["unit"]) if n_na else ""))
    out.append("Atoms: %d" % lf.num_rows)
    wts = scale_weights(x)
    if wts:
        out.append("Weights: %s (default: %s)" % (
            ", ".join(wts), meta.get("default_weight") or wts[0]))
    if meta.get("source") is not None:
        out.append("Source: %s" % meta["source"])
    return "\n".join(out)


# Summary ---------------------------------------------------------------------

@dataclass(frozen=True)
class ScaleSummary:
    """The quantitative view of a scale (R: `summary()` -> `summary_Scale`)."""

    name: str
    desc: str
    frames: dict[str, int]
    unassigned: dict[str, int]
    n_atoms: int
    weights: list[str]
    weight_totals: dict[str, float]
    default_weight: str | None
    coverage: dict[str, float]
    sampled: bool
    parent_name: str | None
    nesting: list[dict] | None
    source: str | None
    vocab: dict[str, str]

    def __str__(self) -> str:
        v = self.vocab
        out = ["<summary of %s%s>" % (v["object"],
                                       " '%s'" % self.name if self.name else "")]
        if self.desc:
            out.append("  desc:          %s" % self.desc)
        out.append("  %-16s%s" % (v["frames"] + ":", " / ".join(
            "%s (%d)" % kv for kv in self.frames.items())))
        out.append("  atoms:          %d" % self.n_atoms)
        ua = {k: n for k, n in self.unassigned.items() if n > 0}
        if ua:
            out.append("  unassigned:     " + ", ".join(
                "%s (%d)" % kv for kv in ua.items()))
        if self.weights:
            out.append("  weight totals:  " + ", ".join(
                "%s = %s" % (k, f"{t:,.6g}") for k, t in self.weight_totals.items())
                + ("  (default: %s)" % self.default_weight
                   if self.default_weight else ""))
        if self.sampled:
            out.append("  SAMPLED:        " + ", ".join(
                "%s %.1f%%" % (k, 100 * c) for k, c in self.coverage.items())
                + (" of '%s'" % self.parent_name if self.parent_name else ""))
        for r in self.nesting or []:
            out.append("  nesting:        %s > %s: %s" % (
                r["parent"], r["child"], "nested" if r["nests"] else
                "CROSS-CUTTING (%d offender(s))" % r["n_offenders"]))
        if self.source is not None:
            out.append("  source:         %s" % self.source)
        return "\n".join(out)


def scale_summary(x: NestedScale) -> ScaleSummary:
    """Per-weight totals, coverage and the adjacent-frame nesting table."""
    from .navigate import scale_coverage, scale_nests

    _check_scale(x)
    meta, lt, fr = x.meta, x.leaftable, x.frames
    wts = scale_weights(x)
    cov = scale_coverage(x)
    nesting = None
    if len(fr) > 1:
        nesting = []
        for a, b in zip(fr[:-1], fr[1:], strict=True):
            ok = scale_nests(x, a, b)
            nesting.append({"parent": a, "child": b, "nests": ok.ok,
                            "n_offenders": len(ok.offenders)})
    return ScaleSummary(
        name=meta.get("name") or "", desc=meta.get("desc") or "",
        frames={f: len(x.members[f]) for f in fr},
        unassigned={f: lt[f].null_count for f in fr},
        n_atoms=lt.num_rows, weights=wts,
        weight_totals={w: _finite_sum(lt[w].to_pylist()) for w in wts},
        default_weight=meta.get("default_weight"), coverage=cov,
        sampled=any(c < 1 for c in cov.values()),
        parent_name=meta.get("parent_name"), nesting=nesting,
        source=meta.get("source"), vocab=scale_vocab(x))
