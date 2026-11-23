"""NestedScale -- the dimension-agnostic core type (port of R/scale-class.R).

A `NestedScale` is a nested partition of a set of leaves, in any dimension:

* `leaftable`  -- one row per leaf: a column per frame, a unique leaf column
  (named by `leaf`) and zero or more numeric columns, some of them declared
  as weights
* `frames`     -- frame names, COARSEST first
* `members`    -- frame -> the ordered code vocabulary at that frame
* `leaf`       -- name of the leaf column (default `"leaf"`)
* `attributes` -- long table of member attributes keyed by (frame, member)
* `aliases`    -- long table of alternative spellings keyed by (frame, member)
* `labels`     -- long table of display names keyed by
                  (frame, member, variant)
* `meta`       -- name, desc, weights, default_weight, residuals,
                  default_label, source, and the sample bookkeeping
                  (coverage, parent_totals, parent_name)

Frames are partitions of the leaves, not necessarily a tree; conversion always
routes through the leaves. Anything derivable is computed on demand.

"Unit" means a unit of measure only; one item of a frame is a member.
"""
from __future__ import annotations

import copy
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


# Member attributes, aliases and labels ----------------------------------------
# Long tables keyed by (frame, member): a physical attribute (a calorific
# value, a density) may sit on a leaf or on any coarser member; an alias is
# an alternative spelling; a label is a display name in a named variant, and
# a label row with a null member names the frame itself. Attributes are not
# weights: they are consumed row by row by `convert_scale()`, never
# aggregated.

SCALE_ATTRIBUTE_KINDS = ("property", "factor")
"""`property` = an invertible ratio (lhv, density); `factor` = one-way (an
emission factor, a loss factor)."""

ATTR_SCHEMA = pa.schema([
    ("frame", pa.string()), ("member", pa.string()), ("attribute", pa.string()),
    ("kind", pa.string()), ("value", pa.float64()), ("lower", pa.float64()),
    ("upper", pa.float64()), ("unit_of_measure", pa.string()),
    ("source", pa.string()), ("note", pa.string())])
ALIAS_SCHEMA = pa.schema([
    ("frame", pa.string()), ("member", pa.string()), ("alias", pa.string()),
    ("source", pa.string())])
LABEL_SCHEMA = pa.schema([
    ("frame", pa.string()), ("member", pa.string()), ("variant", pa.string()),
    ("label", pa.string())])
DEFAULT_VARIANT = "label"


def empty_attributes() -> pa.Table:
    return ATTR_SCHEMA.empty_table()


def empty_aliases() -> pa.Table:
    return ALIAS_SCHEMA.empty_table()


def empty_labels() -> pa.Table:
    return LABEL_SCHEMA.empty_table()


def _legacy_member_col(t: pa.Table) -> pa.Table:
    """A member table of schema version 1, which has its codes in `unit`."""
    if "unit" in t.column_names and "member" not in t.column_names:
        return t.rename_columns(["member" if c == "unit" else c
                                 for c in t.column_names])
    return t


def _as_member_table(x: Any, schema: pa.Schema, what: str,
                     optional: Sequence[str] = ()) -> pa.Table:
    """Coerce a table to `schema`: optional columns filled with nulls, the
    rest required, no extras."""
    from ._backend import as_table

    if x is None:
        return schema.empty_table()
    t = as_table(x, what)
    cols = {}
    for f in schema:
        if f.name in t.column_names:
            c = t[f.name]
            if pa.types.is_dictionary(c.type):
                c = c.cast(pa.string())
            cols[f.name] = c.cast(f.type)
        elif f.name in optional:
            cols[f.name] = pa.nulls(t.num_rows, f.type)
        else:
            _stop("`%s` is missing column(s): %s", what,
                  _preview([g.name for g in schema if g.name not in t.column_names
                            and g.name not in optional]))
    extra = [c for c in t.column_names if c not in schema.names]
    if extra:
        _stop("`%s` has unknown column(s): %s", what, _preview(extra))
    return pa.table(cols, schema=schema)


def _check_member_table(t: pa.Table, schema: pa.Schema, what: str,
                        frames: Sequence[str], members: Mapping, v: Mapping,
                        key_cols: Sequence[str]) -> list[str]:
    """Membership, non-empty strings and duplicates; the attribute-specific
    checks are added by `_check_attributes`."""
    errs: list[str] = []
    if t.schema.names != schema.names:
        return ["`%s` must have exactly the columns: %s"
                % (what, ", ".join(schema.names))]
    if t.num_rows == 0:
        return errs
    fr, un = t["frame"].to_pylist(), t["member"].to_pylist()
    bad_frame = list(dict.fromkeys(f for f in fr if f not in frames))
    if bad_frame:
        errs.append("`%s` names %s(s) not in the object: %s"
                    % (what, v["frame"], _preview(bad_frame)))
    bad = list(dict.fromkeys("%s/%s" % (f, u) for f, u in zip(fr, un, strict=True)
                             if f in frames and u not in members.get(f, ())))
    if bad:
        errs.append("`%s` names (%s/%s) pairs that are not members: %s"
                    % (what, v["frame"], v["member"], _preview(bad)))
    for c in [c for c in schema.names if c not in ("value", "lower", "upper", "note")]:
        vals = t[c].to_pylist()
        if any(z is None or z == "" for z in vals):
            errs.append("`%s$%s` must be non-empty strings" % (what, c))
    keys = list(zip(*(t[c].to_pylist() for c in key_cols), strict=True))
    if len(set(keys)) != len(keys):
        seen: set = set()
        dup = [k for k in keys if k in seen or seen.add(k)]
        label = ("duplicate (%s, %s, attribute, source) rows"
                 % (v["frame"], v["member"])
                 if what == "attributes" else "duplicate rows")
        errs.append("`%s` has %s: %s" % (what, label, _preview(
            ["/".join(str(z) for z in d[:2]) for d in dup])))
    return errs


def _check_attributes(t: pa.Table, frames: Sequence[str], members: Mapping,
                      v: Mapping) -> list[str]:
    errs = _check_member_table(t, ATTR_SCHEMA, "attributes", frames, members, v,
                               ("frame", "member", "attribute", "source"))
    if errs and errs[0].startswith("`attributes` must have exactly"):
        return errs
    if t.num_rows == 0:
        return errs
    vals = t["value"].to_pylist()
    if any(z is None or not math.isfinite(z) for z in vals):
        errs.append("`attributes$value` must be finite numeric")
    lo, up = t["lower"].to_pylist(), t["upper"].to_pylist()
    below = any(a is not None and z is not None and a > z
                for a, z in zip(lo, vals, strict=True))
    above = any(b is not None and z is not None and b < z
                for b, z in zip(up, vals, strict=True))
    if below or above:
        errs.append("`attributes` must satisfy lower <= value <= upper")
    kinds = t["kind"].to_pylist()
    bad_kind = list(dict.fromkeys(k for k in kinds if k not in SCALE_ATTRIBUTE_KINDS))
    if bad_kind:
        errs.append("`attributes$kind` must be one of %s; got: %s"
                    % (", ".join(SCALE_ATTRIBUTE_KINDS), _preview(bad_kind)))
    per: dict[str, set] = {}
    for a, k in zip(t["attribute"].to_pylist(), kinds, strict=True):
        per.setdefault(a, set()).add(k)
    mixed = [a for a, ks in per.items() if len(ks) > 1]
    if mixed:
        errs.append("an attribute has one kind; these have several: %s"
                    % _preview(mixed))
    return errs


def _label_keys(t: pa.Table) -> list[tuple]:
    """(frame, member, variant) row keys; a null member is the frame's own."""
    return list(zip(t["frame"].to_pylist(), t["member"].to_pylist(),
                    t["variant"].to_pylist(), strict=True))


def _check_labels(t: pa.Table, frames: Sequence[str], members: Mapping,
                  v: Mapping) -> list[str]:
    errs: list[str] = []
    if t.schema.names != LABEL_SCHEMA.names:
        return ["`labels` must have exactly the columns: %s"
                % ", ".join(LABEL_SCHEMA.names)]
    if t.num_rows == 0:
        return errs
    fr, mb = t["frame"].to_pylist(), t["member"].to_pylist()
    bad_frame = list(dict.fromkeys(f for f in fr if f not in frames))
    if bad_frame:
        errs.append("`labels` names %s(s) not in the object: %s"
                    % (v["frame"], _preview(bad_frame)))
    bad = list(dict.fromkeys(
        "%s/%s" % (f, u) for f, u in zip(fr, mb, strict=True)
        if f in frames and u is not None and u not in members.get(f, ())))
    if bad:
        errs.append("`labels` names (%s/%s) pairs that are not members: %s"
                    % (v["frame"], v["member"], _preview(bad)))
    for c in ("variant", "label"):
        if any(z is None or z == "" for z in t[c].to_pylist()):
            errs.append("`labels$%s` must be non-empty strings" % c)
    keys = _label_keys(t)
    if len(set(keys)) != len(keys):
        seen: set = set()
        dup = [k for k in keys if k in seen or seen.add(k)]
        errs.append("`labels` has more than one label for: %s" % _preview(
            list(dict.fromkeys("%s/%s [%s]" % (
                f, "<frame>" if u is None else u, va) for f, u, va in dup))))
    return errs


def _member_keys(x: NestedScale) -> set:
    return {(f, u) for f, cs in x.members.items() for u in cs}


def _slice_member_tables(x: NestedScale) -> tuple[pa.Table, pa.Table, pa.Table]:
    """The attribute, alias and label rows of the members `x` still has; a
    frame's own label stays while the frame does."""
    keep = _member_keys(x)
    out = []
    for t in (x.attributes, x.aliases, x.labels):
        if t.num_rows == 0:
            out.append(t)
            continue
        mask = [(f in x.frames) if u is None else ((f, u) in keep)
                for f, u in zip(t["frame"].to_pylist(),
                                t["member"].to_pylist(), strict=True)]
        out.append(t.filter(pa.array(mask, pa.bool_())))
    return out[0], out[1], out[2]


@dataclass(frozen=True, eq=False, repr=False)
class NestedScale:
    """A nested discrete partition: a table of leaves plus the frames grouping
    them.

    Construct with `scale_from_leaftable()`. Treat as immutable: every verb
    returns a new object.
    """

    leaftable: pa.Table
    frames: tuple[str, ...]
    members: dict[str, tuple[str, ...]]
    leaf: str = "leaf"
    meta: dict[str, Any] = field(default_factory=dict)
    attributes: pa.Table = field(default_factory=empty_attributes)
    aliases: pa.Table = field(default_factory=empty_aliases)
    labels: pa.Table = field(default_factory=empty_labels)

    def __post_init__(self) -> None:
        self._normalise()
        self._raise_if_invalid(self._errors())

    def _errors(self) -> list[str]:
        """Validation errors. A subclass returns its parents' errors followed by
        its own -- S7's order, duplicates included."""
        return _validate(self)

    def _construct(self) -> None:
        """Validate a newly built subclass object as S7's constructor does: the
        parent object is created (and validated) first, so a parent-level
        failure names the parent class; then the whole object is validated."""
        self._normalise()
        self._raise_if_invalid(_validate(self), NestedScale)
        self._raise_if_invalid(self._errors())

    def _raise_if_invalid(self, errs: list[str], cls: type | None = None) -> None:
        if not errs:
            return
        cls = cls or type(self)
        pkg = getattr(cls, "_r_package", cls.__module__.split(".")[0])
        if cls is NestedScale:
            pkg = "nestedscales"
        _stop("<%s::%s> object is invalid:\n%s", pkg, cls.__name__,
              "\n".join("- " + e for e in errs))

    def _normalise(self) -> None:
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
        object.__setattr__(self, "attributes", _as_member_table(
            self.attributes, ATTR_SCHEMA, "attributes", ("lower", "upper", "note")))
        object.__setattr__(self, "aliases", _as_member_table(
            self.aliases, ALIAS_SCHEMA, "aliases"))
        # read from the instance dictionary: a subclass with its own
        # `__init__` may not set the field, and the class attribute of a
        # dataclass field with a default factory is not the default
        object.__setattr__(self, "labels", _as_member_table(
            self.__dict__.get("labels"), LABEL_SCHEMA, "labels"))
        if "leaf" not in self.__dict__:
            object.__setattr__(self, "leaf", "leaf")

    def __eq__(self, other: object) -> bool:
        if type(other) is not type(self):
            return NotImplemented
        return (self.frames == other.frames and self.leaf == other.leaf
                and self.members == other.members and self.meta == other.meta
                and self.leaftable.equals(other.leaftable)
                and self.attributes.equals(other.attributes)
                and self.aliases.equals(other.aliases)
                and self.labels.equals(other.labels))

    __hash__ = None  # type: ignore[assignment]

    def __getitem__(self, idx: tuple) -> NestedScale:
        """`x[frame, member]` is `filter_scale(x, frame, member)`, as in R."""
        from .filter import filter_scale

        if not isinstance(idx, tuple) or len(idx) != 2:
            _stop("subset a scale as `x[frame, member]`")
        return filter_scale(self, idx[0], idx[1])

    def __repr__(self) -> str:
        return "<%s[%s] leaves=%d>" % (
            type(self).__name__, "/".join(self.frames), self.leaftable.num_rows)

    def __str__(self) -> str:
        return _format_scale(self)


# Validation ------------------------------------------------------------------

def _validate(self: NestedScale) -> list[str]:
    errs: list[str] = []
    leaftable, frames, members = self.leaftable, self.frames, self.members
    leaf, meta = self.leaf, self.meta

    # leaftable
    if not isinstance(leaftable, pa.Table):
        return ["`leaftable` must be a pyarrow Table"]
    if leaftable.num_rows == 0:
        errs.append("`leaftable` must have at least one row")
    cols = leaftable.column_names

    # leaf column
    if not isinstance(leaf, str) or leaf == "":
        return ["`leaf` must be a single non-empty string"]
    if leaf not in cols:
        errs.append("`leaftable` must have a `%s` column (the leaf column)" % leaf)

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
        # The name of the leaf column is allowed as the FINEST frame: there
        # the frame column is the leaf column. As a coarser frame it would
        # clash with it.
        clash = [f for f in frames if f in RESERVED_COLS]
        if leaf in frames and frames[-1] != leaf:
            clash.append(leaf)
        if clash:
            errs.append("`frames` may not use reserved names: %s" % _preview(clash))
        missing = [f for f in frames if f not in cols]
        if missing:
            errs.append("`leaftable` missing frame columns: %s" % _preview(missing))

    # leaf column values
    if leaf in cols:
        ty = leaftable.schema.field(leaf).type
        uid = leaftable[leaf].to_pylist()
        if not (pa.types.is_string(ty) or pa.types.is_large_string(ty)) or \
                any(u is None or u == "" for u in uid):
            errs.append("`leaftable$%s` must be a non-empty character vector" % leaf)
        elif len(set(uid)) != len(uid):
            seen: set = set()
            dup = list(dict.fromkeys(u for u in uid if u in seen or seen.add(u)))
            errs.append(
                "`leaftable$%s` must be unique; duplicated: %s. "
                "Parallel dimensions belong in separate NestedScale objects."
                % (leaf, _preview(dup)))

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

    # attributes, aliases and labels, against the members (so only once
    # those are sound)
    if not errs and isinstance(members, Mapping):
        v = scale_vocab(self)
        errs += _check_attributes(self.attributes, frames, members, v)
        errs += _check_member_table(self.aliases, ALIAS_SCHEMA, "aliases", frames,
                                    members, v,
                                    ("alias", "frame", "member", "source"))
        errs += _check_labels(self.labels, frames, members, v)

    # meta
    if not isinstance(meta, Mapping):
        errs.append("`meta` must be a list")
        return errs
    dl = meta.get("default_label")
    if dl is not None and not (isinstance(dl, str) and dl != ""):
        errs.append("`meta$default_label` must be a single non-empty string")

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

    # residuals: members that carry a value but take no allocation. Declared per
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
            "member": "member", "members": "members", "leaves": "leaves"}


@functools.singledispatch
def scale_payload_slice(x: NestedScale, i: Sequence[int]) -> NestedScale:
    """Subset a subclass's per-leaf payload to the kept leaftable rows `i`.

    Called whenever the engine rebuilds an object from a row subset, with
    the core fields already set to the subset and the object not yet
    validated; `i` holds the 0-based indices of the kept rows of the
    former leaftable. The method returns the object, changed with
    `scale_set_props()`. The `NestedScale` default has no payload and
    returns `x` unchanged.
    """
    _check_scale(x)
    return x


@functools.singledispatch
def scale_payload_collapse(x: NestedScale, map: Sequence[int | None]) -> NestedScale:
    """Merge a subclass's per-leaf payload after a collapse.

    The companion of `scale_payload_slice()` for the rebuilds that MERGE
    leaves -- `prune_scale()`, which makes a coarser frame the leaf layer.
    `map` has one entry per row of the FORMER leaftable: the 0-based index
    of the new row that leaf was merged into, or None for a leaf that was
    dropped. The object arrives with the new core fields set and not yet
    validated; the method may change any field, the name of the leaf column
    included, with `scale_set_props()`. The `NestedScale` default returns
    `x` unchanged, which is right for a payload keyed by member codes.
    """
    _check_scale(x)
    return x


_CORE_PROPS = ("leaftable", "frames", "members", "leaf", "meta", "attributes",
               "aliases", "labels")


def scale_set_props(x: NestedScale, check: bool = False, **props: Any) -> NestedScale:
    """A copy of `x` with fields replaced, keeping the concrete class.

    The counterpart of R's `S7::set_props(x, ..., .check = FALSE)`, for the
    payload hooks of a subclass: a hook receives an object whose parts are
    consistent only once it has finished, so the copy is not validated
    unless `check=True`. Any field of the object may be named, a subclass's
    own included.
    """
    _check_scale(x)
    out = copy.copy(x)
    for k, v in props.items():
        object.__setattr__(out, k, v)
    if check:
        scale_validate(out)
    return out


def scale_validate(x: NestedScale) -> NestedScale:
    """Normalise and validate `x` in place and return it (R: `S7::validate()`).

    Raises `NestedScalesError` listing every problem.
    """
    _check_scale(x)
    x._normalise()
    x._raise_if_invalid(x._errors())
    return x


def scale_alias_property(name: str) -> property:
    """A read-only property exposing an inherited field under another name.

    How a `Calendar` keeps `timeframes` and a `Geoscale` keeps `geoframes`
    over the inherited `frames`.
    """
    prop = _AliasProperty(lambda self: getattr(self, name),
                          doc="Alias of `%s`." % name)
    prop.alias_of = name
    return prop


class _AliasProperty(property):
    """A read-only property that names an inherited field (`alias_of`)."""

    alias_of: str = ""


# Accessors --------------------------------------------------------------------------

def scale_rank(x: NestedScale, frame: str | Sequence[str]) -> int | None | list:
    """Position of a frame in the hierarchy; 1 is the coarsest.

    The leaf column ranks one past the last frame when it is not itself a
    frame. Names that are not frames give None.
    """
    _check_scale(x)

    def one(f: str) -> int | None:
        if f in x.frames:
            return x.frames.index(f) + 1
        return len(x.frames) + 1 if f == x.leaf else None

    if isinstance(frame, str):
        return one(frame)
    return [one(f) for f in frame]


def scale_frames(x: NestedScale, finest: bool = False) -> list[str] | str:
    """Frame names, coarsest first; only the finest when `finest=True`."""
    _check_scale(x)
    return x.frames[-1] if finest else list(x.frames)


def scale_members(x: NestedScale, frame: str | None = None) -> list[str]:
    """The code vocabulary at one frame, in canonical order (default: the
    leaves)."""
    _check_scale(x)
    if frame is None:
        frame = _leaf_frame(x)
    _check_frame(x, frame)
    if frame == x.leaf and frame not in x.frames:
        return list(dict.fromkeys(_strings(x.leaftable, frame)))
    return list(x.members[frame])


def scale_leaf_frame(x: NestedScale) -> str:
    """The frame whose members are the leaves: the finest frame when it has
    one code per leaftable row, otherwise the leaf column."""
    _check_scale(x)
    return _leaf_frame(x)


def _leaf_frame(x: NestedScale) -> str:
    finest = x.frames[-1]
    if len(x.members.get(finest, ())) == x.leaftable.num_rows:
        return finest
    return x.leaf


def _nav_levels(x: NestedScale) -> list[str]:
    """The frames, plus the leaf column as the finest level when no frame
    enumerates the leaves."""
    at = _leaf_frame(x)
    return list(x.frames) if at in x.frames else [*x.frames, at]


def scale_leaf_column(x: NestedScale) -> str:
    """The name of the leaf column: the column of the leaftable that
    identifies the leaves."""
    _check_scale(x)
    return x.leaf


def scale_leaftable(x: NestedScale) -> pa.Table:
    """The one-row-per-leaf table the scale is built on."""
    _check_scale(x)
    return x.leaftable


def scale_weights(x: NestedScale) -> list[str]:
    """Weight column names (possibly empty)."""
    _check_scale(x)
    return list(x.meta.get("weights") or ())


def scale_residuals(x: NestedScale, frame: str | None = None) -> dict | list[str]:
    """Residual members: the frame -> codes mapping, or one frame's codes."""
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
            _stop("`%s` is a ScaleProduct, not a single NestedScale. Its leaves "
                  "are not materialised -- use `scale_axes()` for the component "
                  "scales, or `product_leaves()` to build the grid.", arg)
        _stop("`%s` must be a NestedScale object", arg)


def _check_frame(x: NestedScale, frame: object, arg: str | None = None) -> None:
    v = scale_vocab(x)
    if arg is None:
        arg = v["frame"]
    if not isinstance(frame, str):
        _stop("`%s` must be a single %s name; one of: %s",
              arg, v["frame"], ", ".join(x.frames))
    if frame not in x.frames and frame != x.leaf:
        _stop('`%s` = "%s" is not a %s of this %s; one of: %s',
              arg, frame, v["frame"], v["object"],
              ", ".join(dict.fromkeys([*x.frames, x.leaf])))


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
            "  [%d %s unassigned]" % (n_na, v["member"]) if n_na else ""))
    out.append("Leaves: %d" % lf.num_rows)
    wts = scale_weights(x)
    if wts:
        out.append("Weights: %s (default: %s)" % (
            ", ".join(wts), meta.get("default_weight") or wts[0]))
    at = x.attributes
    if at.num_rows > 0:
        per: dict[str, int] = {}
        for fr_ in at["frame"].to_pylist():
            per[fr_] = per.get(fr_, 0) + 1
        out.append("Attributes: %s (sources: %s) -- %s" % (
            ", ".join(dict.fromkeys(at["attribute"].to_pylist())),
            ", ".join(dict.fromkeys(at["source"].to_pylist())),
            ", ".join("%d at %s" % (per[fr_], fr_) for fr_ in f if fr_ in per)))
    al = x.aliases
    if al.num_rows > 0:
        out.append("Aliases: %d (%s)" % (
            al.num_rows, ", ".join(dict.fromkeys(al["source"].to_pylist()))))
    lb = x.labels
    if lb.num_rows > 0:
        per_frame: dict[str, list] = {}
        for fr_, va in zip(lb["frame"].to_pylist(), lb["variant"].to_pylist(),
                           strict=True):
            per_frame.setdefault(fr_, [])
            if va not in per_frame[fr_]:
                per_frame[fr_].append(va)
        out.append("Labels: %s (default: %s)" % (
            ", ".join("%s [%s]" % (fr_, ", ".join(vs))
                      for fr_, vs in per_frame.items()),
            _label_variant(x)))
    if meta.get("source") is not None:
        out.append("Source: %s" % meta["source"])
    return "\n".join(out)


def _label_variant(x: NestedScale, variant: str | None = None) -> str:
    """The variant a lookup uses: the one asked for, else the declared
    default, else the first in the table."""
    have = x.labels["variant"].to_pylist()
    if variant is None:
        variant = x.meta.get("default_label")
        if variant is None or variant not in have:
            variant = have[0] if have else DEFAULT_VARIANT
        return variant
    if not isinstance(variant, str) or variant == "":
        _stop("`variant` must be a single string")
    if have and variant not in have:
        _stop('no labels of variant "%s"; available: %s', variant,
              _preview(dict.fromkeys(have)))
    return variant


# Summary ---------------------------------------------------------------------

@dataclass(frozen=True)
class ScaleSummary:
    """The quantitative view of a scale (R: `summary()` -> `summary_Scale`)."""

    name: str
    desc: str
    frames: dict[str, int]
    unassigned: dict[str, int]
    n_leaves: int
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
        out.append("  leaves:         %d" % self.n_leaves)
        ua = {k: n for k, n in self.unassigned.items() if n > 0}
        if ua:
            out.append("  unassigned:     " + ", ".join(
                "%s (%d)" % kv for kv in ua.items()))
        if self.weights:
            # R formats the totals as one vector: right-justified to a
            # common width
            tot = {k: f"{t:,.6g}" for k, t in self.weight_totals.items()}
            width = max(len(z) for z in tot.values())
            out.append("  weight totals:  " + ", ".join(
                "%s = %s" % (k, z.rjust(width)) for k, z in tot.items())
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
        n_leaves=lt.num_rows, weights=wts,
        weight_totals={w: _finite_sum(lt[w].to_pylist()) for w in wts},
        default_weight=meta.get("default_weight"), coverage=cov,
        sampled=any(c < 1 for c in cov.values()),
        parent_name=meta.get("parent_name"), nesting=nesting,
        source=meta.get("source"), vocab=scale_vocab(x))
