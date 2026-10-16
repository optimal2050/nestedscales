"""Structure queries over a NestedScale (port of R/navigate.R).

Pure leaftable queries, no conversion engine. Tables are returned as
`pyarrow.Table`; rows are sorted by code point, where R sorts in the session
locale, so compare rows as sets across bindings.
"""
from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field

import pyarrow as pa

from ._utils import _as_str_tuple, _preview, _stop
from .scale_class import (
    NestedScale,
    _check_frame,
    _check_scale,
    _nav_levels,
    _strings,
    scale_units,
    scale_vocab,
    scale_weights,
)

_FAMILY_SCHEMA = pa.schema([("parent_frame", pa.string()), ("parent", pa.string()),
                            ("child_frame", pa.string()), ("child", pa.string())])


@dataclass(frozen=True, eq=False)
class Verdict:
    """A yes/no answer with its evidence (R: a logical with attributes).

    Truthy as `ok`, and equal to a bool of the same value, so
    `if scale_nests(...)` and `scale_nests(...) == True` both read naturally.
    `offenders` names the codes that broke the test; `sizes` carries the
    per-unit totals of `scale_is_uniform()`.
    """

    ok: bool
    offenders: tuple[str, ...] = ()
    sizes: dict[str, float] | None = field(default=None)

    def __bool__(self) -> bool:
        return self.ok

    def __eq__(self, other: object) -> bool:
        if isinstance(other, bool):
            return self.ok is other
        if isinstance(other, Verdict):
            return (self.ok, self.offenders, self.sizes) == \
                (other.ok, other.offenders, other.sizes)
        return NotImplemented

    def __hash__(self) -> int:
        return hash(self.ok)


def _family_rows(x: NestedScale, parent: str, child: str) -> list[tuple[str, str]]:
    lt = x.leaftable
    cols = zip(_strings(lt, parent), _strings(lt, child), strict=True)
    pairs = {(p, c) for p, c in cols
             if p is not None and c is not None}
    return sorted(pairs)


def _family_table(rows: list[tuple[str, str, str, str]]) -> pa.Table:
    cols = list(zip(*rows, strict=True)) if rows else [(), (), (), ()]
    return pa.Table.from_arrays([pa.array(c, pa.string()) for c in cols],
                                schema=_FAMILY_SCHEMA)


def scale_family(x: NestedScale, parent: str | None = None,
                 child: str | None = None) -> pa.Table:
    """Immediate parent-child table between two frames.

    Defaults to every adjacent pair. Columns `parent_frame`, `parent`,
    `child_frame`, `child`; atoms unassigned at either frame are omitted.
    """
    _check_scale(x)
    fr = x.frames
    if parent is None and child is None:
        rows = [(a, p, b, c) for a, b in zip(fr[:-1], fr[1:], strict=True)
                for p, c in _family_rows(x, a, b)]
        return _family_table(rows)
    _check_frame(x, parent, "parent")
    _check_frame(x, child, "child")
    return _family_table([(parent, p, child, c)
                          for p, c in _family_rows(x, parent, child)])


def scale_nests(x: NestedScale, parent: str, child: str) -> Verdict:
    """Does every code at `child` fall within a single code at `parent`?

    A diagnostic: nesting is not required. When not, `offenders` holds the
    child codes with more than one parent.
    """
    _check_scale(x)
    _check_frame(x, parent, "parent")
    _check_frame(x, child, "child")
    seen: set = set()
    multi: dict = {}
    for _, c in _family_rows(x, parent, child):
        if c in seen:
            multi[c] = None
        seen.add(c)
    return Verdict(not multi, tuple(multi))


def scale_crosses(x: NestedScale, a: str, b: str) -> Verdict:
    """Does every unit of `a` combine with the same set of units of `b`?

    True for overlaying frames such as MONTH x HOUR. When not, `offenders`
    names the units of `a` whose set differs from the first one's.
    """
    _check_scale(x)
    _check_frame(x, a, "parent")
    _check_frame(x, b, "child")
    sets: dict[str, set] = {}
    for p, c in _family_rows(x, a, b):
        sets.setdefault(p, set()).add(c)
    if not sets:
        return Verdict(False)
    first = next(iter(sets.values()))
    off = tuple(p for p, s in sets.items() if s != first)
    return Verdict(not off, off)


def scale_is_uniform(x: NestedScale, frame: str, weight: str | None = None,
                     tolerance: float = 1e-9) -> Verdict:
    """Do all units of `frame` hold the same number of atoms (or weight total)?

    Atoms with no code at `frame` are ignored. When not, `sizes` holds the
    per-unit counts or totals.
    """
    _check_scale(x)
    _check_frame(x, frame, "frame")
    lt = x.leaftable
    if weight is None:
        w = [1.0] * lt.num_rows
    else:
        wts = scale_weights(x)
        if weight not in wts:
            _stop("unknown weight `%s`; declared: %s", weight, _preview(wts))
        w = lt[weight].to_pylist()
    sizes: dict[str, float] = {}
    for u, v in zip(_strings(lt, frame), w, strict=True):
        if u is None:
            continue
        sizes[u] = sizes.get(u, 0.0) + (v if v is not None and v == v else 0.0)
    if not sizes:
        return Verdict(False)
    sizes = dict(sorted(sizes.items()))
    ref = next(iter(sizes.values()))
    ok = all(abs(s - ref) <= tolerance * max(1.0, abs(ref)) for s in sizes.values())
    return Verdict(ok, sizes=None if ok else sizes)


def scale_ancestry(x: NestedScale) -> pa.Table:
    """Every (coarser, finer) code pair sharing at least one atom, all frame pairs.

    Atom-mediated, not a transitive closure of `scale_family()`: closing a
    cross-cutting hierarchy manufactures false relationships.
    """
    _check_scale(x)
    fr = x.frames
    rows = [(fr[i], p, fr[j], c)
            for i in range(len(fr) - 1) for j in range(i + 1, len(fr))
            for p, c in _family_rows(x, fr[i], fr[j])]
    return _family_table(rows)


def _level_index(x: NestedScale, frame: str) -> tuple[list[str], int]:
    fr = _nav_levels(x)
    if frame not in fr:
        _stop("`%s` is not a navigable %s of this %s", frame,
              scale_vocab(x)["frame"], scale_vocab(x)["object"])
    return fr, fr.index(frame)


def scale_children(x: NestedScale, frame: str, unit: str | Sequence[str],
                   target: str | None = None) -> list[str]:
    """Codes one frame down (or at `target`) sharing an atom with `unit`."""
    _check_scale(x)
    _check_frame(x, frame)
    fr, i = _level_index(x, frame)
    if target is None:
        if i == len(fr) - 1:
            _stop("`%s` is the finest %s; it has no children", frame,
                  scale_vocab(x)["frame"])
        target = fr[i + 1]
    _check_frame(x, target, "target")
    return _related(x, frame, unit, target)


def scale_parents(x: NestedScale, frame: str, unit: str | Sequence[str],
                  target: str | None = None) -> list[str]:
    """Codes one frame up (or at `target`) sharing an atom with `unit`."""
    _check_scale(x)
    _check_frame(x, frame)
    fr, i = _level_index(x, frame)
    if target is None:
        if i == 0:
            _stop("`%s` is the coarsest %s; it has no parents", frame,
                  scale_vocab(x)["frame"])
        target = fr[i - 1]
    _check_frame(x, target, "target")
    return _related(x, frame, unit, target)


def scale_descendants(x: NestedScale, frame: str, unit: str | Sequence[str],
                      target: str | None = None) -> pa.Table:
    """Related codes at every finer frame (or `target`): columns `frame`, `unit`."""
    _check_scale(x)
    _check_frame(x, frame)
    fr, i = _level_index(x, frame)
    if target is None:
        targets = fr[i + 1:]
    else:
        _check_frame(x, target, "target")
        targets = [target]
    return _related_table(x, frame, unit, targets)


def scale_ancestors(x: NestedScale, frame: str, unit: str | Sequence[str],
                    target: str | None = None) -> pa.Table:
    """Related codes at every coarser frame (or `target`): columns `frame`, `unit`."""
    _check_scale(x)
    _check_frame(x, frame)
    fr, i = _level_index(x, frame)
    if target is None:
        targets = fr[:i]
    else:
        _check_frame(x, target, "target")
        targets = [target]
    return _related_table(x, frame, unit, targets)


def _related_table(x: NestedScale, frame: str, unit: str | Sequence[str],
                   targets: Sequence[str]) -> pa.Table:
    fs: list[str] = []
    us: list[str] = []
    for t in targets:
        codes = _related(x, frame, unit, t)
        fs += [t] * len(codes)
        us += codes
    return pa.table({"frame": pa.array(fs, pa.string()),
                     "unit": pa.array(us, pa.string())})


def _related(x: NestedScale, frame: str, unit: str | Sequence[str],
             target: str) -> list[str]:
    """Codes at `target` that share at least one atom with `unit` at `frame`."""
    asked = _as_str_tuple(unit)
    known = set(scale_units(x, frame))
    unknown = [u for u in dict.fromkeys(asked) if u not in known]
    unit = set(asked)
    if unknown:
        _stop("code(s) not found at %s `%s`: %s", scale_vocab(x)["frame"],
              frame, _preview(unknown))
    hit = {t for f, t in zip(_strings(x.leaftable, frame),
                             _strings(x.leaftable, target), strict=True)
           if f in unit and t is not None}
    return [c for c in scale_units(x, target) if c in hit]


def scale_coverage(x: NestedScale, weight: str | None = None
                   ) -> dict[str, float] | float:
    """Fraction of the root parent's weight surviving in a sampled scale.

    A scale never subset covers all of itself: every weight reports 1.
    """
    _check_scale(x)
    wts = scale_weights(x)
    full = {w: 1.0 for w in wts}
    for k, v in (x.meta.get("coverage") or {}).items():
        full[k] = float(v)
    if weight is None:
        return full
    if weight not in wts:
        _stop("unknown weight `%s`; declared: %s", weight, _preview(wts))
    return full[weight]
