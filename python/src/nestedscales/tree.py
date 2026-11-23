"""scale_tree() -- the parts of a scale, and which of them may change (port of
R/tree.R).

The identity of a scale (`scale_id()`) is a hash of the leaf column, the frame
names and the frame codes. A part is

* fixed    when it enters that hash: changing it makes another scale;
* derived  when it is computed from another part;
* mutable  when changing it leaves the identity as it was.

Shapes are spelled as R spells them (`data.frame [7 x 6]`, `chr [4]`,
`list [4]`), so both bindings list the same table for the same scale.
"""
from __future__ import annotations

import dataclasses
import functools
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

import pyarrow as pa

from ._backend import as_table
from ._utils import _preview, _stop
from .link import scale_id
from .product import ScaleProduct
from .scale_class import (
    _CORE_PROPS,
    NestedScale,
    _AliasProperty,
    _check_scale,
    _strings,
)

TREE_COLS = ("part", "parent", "kind", "shape", "mark", "verb", "note")
SCALE_MARKS = ("fixed", "derived", "mutable")

_PROP_ROLES = {
    "attributes": "member values, by (frame, member)",
    "aliases": "alternative spellings, by (frame, member)",
    "labels": "display names, by (frame, member, variant)",
}


def _row(part: str, parent: str = "", kind: str = "property", shape: str = "",
         mark: str = "", verb: str = "", note: str = "") -> dict[str, str]:
    return {"part": part, "parent": parent, "kind": kind, "shape": shape,
            "mark": mark, "verb": verb, "note": note}


def _shape(v: Any) -> str:
    """The size of a part, in R's words."""
    if v is None:
        return "NULL"
    if isinstance(v, pa.Table):
        return "data.frame [%d x %d]" % (v.num_rows, v.num_columns)
    if isinstance(v, str):
        return "chr [1]"
    if isinstance(v, (list, tuple)) and all(isinstance(z, str) for z in v):
        return "chr [%d]" % len(v)
    if isinstance(v, (Mapping, list, tuple)):
        return "list [%d]" % len(v)
    try:
        n = len(v)
    except TypeError:
        n = 1
    return "%s [%d]" % (type(v).__name__, n)


@functools.singledispatch
def scale_payload_parts(x: NestedScale) -> Any:
    """Describe the parts a subclass adds to a scale.

    The seam a dimension package overrides so that `scale_tree()` can mark
    the fields it adds and name its own verbs. The method returns a table
    (or a list of dicts) with a `part` column and any of `parent`, `kind`,
    `shape`, `mark`, `verb` and `note`. A row whose `part` and `parent`
    match a part the core already lists replaces the fields it gives; any
    other row is added. A top-level part is a field of the object; `parent`
    names the field a part belongs to. `mark` is one of `"fixed"`,
    `"derived"` or `"mutable"`. The `NestedScale` default adds nothing.
    """
    return None


def _as_part_rows(rows: Any) -> list[dict]:
    """Rows a subclass returned, completed to the full set of columns; a
    field the subclass did not give is None."""
    if rows is None:
        return []
    if isinstance(rows, list) and all(isinstance(r, Mapping) for r in rows):
        names = list(dict.fromkeys(k for r in rows for k in r))
        records = [dict(r) for r in rows]
    else:
        try:
            t = as_table(rows, "rows")
        except Exception:
            t = None
        if t is None:
            names, records = [], []
        else:
            names, records = t.column_names, t.to_pylist()
    if "part" not in names:
        _stop("`scale_payload_parts()` must return a data.frame with a `part` column")
    out = []
    for r in records:
        row = {c: (None if r.get(c) is None else str(r[c])) for c in TREE_COLS}
        if row["parent"] is None:
            row["parent"] = ""
        out.append(row)
    bad = list(dict.fromkeys(r["mark"] for r in out
                             if r["mark"] and r["mark"] not in SCALE_MARKS))
    if bad:
        _stop("unknown mark(s) %s; a part is %s", _preview(bad),
              ", ".join(SCALE_MARKS))
    return out


def _frame_counts(x: NestedScale) -> str:
    return ", ".join("%s %d" % (
        f, len({v for v in _strings(x.leaftable, f) if v is not None}))
        for f in x.frames)


def _scale_parts(x: NestedScale) -> list[dict]:
    """The parts of one scale, core rows first."""
    lt, frames, leaf, meta = x.leaftable, x.frames, x.leaf, x.meta
    vals = {"leaftable": lt, "frames": frames, "members": x.members, "leaf": leaf,
            "meta": meta, "attributes": x.attributes, "aliases": x.aliases,
            "labels": x.labels}

    # a subclass property that only renames a core field is the same value
    # twice: the part is listed once, under the subclass's name
    shown = {c: c for c in _CORE_PROPS}
    for klass in reversed(type(x).__mro__):
        for name, attr in vars(klass).items():
            if isinstance(attr, _AliasProperty) and attr.alias_of in shown:
                shown[attr.alias_of] = name
    extra = [f.name for f in dataclasses.fields(x) if f.name not in _CORE_PROPS]

    weights = [w for w in (meta.get("weights") or ()) if w in lt.column_names]
    rank = {"leaf column": 0, "frame": 1, "weight": 2, "column": 3}
    cols = []
    for c in lt.column_names:
        kind = ("leaf column" if c == leaf else "frame" if c in frames
                else "weight" if c in weights else "column")
        cols.append(_row(c, parent=shown["leaftable"], kind=kind,
                         mark="fixed" if rank[kind] < 2 else "mutable"))
    cols.sort(key=lambda r: rank[r["kind"]])

    out = [_row(shown["leaftable"], shape=_shape(lt), note="one row per leaf"), *cols,
           _row(shown["frames"], shape=_shape(frames), mark="fixed",
                note=_preview(frames, 6)),
           _row(shown["members"], shape=_shape(x.members), mark="derived",
                note="from %s: %s" % (shown["leaftable"], _frame_counts(x))),
           _row(shown["leaf"], shape=_shape(leaf), mark="fixed", note=leaf),
           _row(shown["meta"], shape=_shape(meta), mark="mutable",
                note=_preview(meta, 8))]
    for what in ("attributes", "aliases", "labels"):
        out.append(_row(shown[what], shape=_shape(vals[what]), mark="mutable",
                        verb="attach_%s_scale()" % what, note=_PROP_ROLES[what]))
    for p in extra:
        out.append(_row(p, shape=_shape(getattr(x, p, None)),
                        note="added by the subclass"))

    # the subclass's own account of its parts
    for add in _as_part_rows(scale_payload_parts(x)):
        hit = [i for i, r in enumerate(out)
               if r["part"] == add["part"] and r["parent"] == add["parent"]]
        if hit:
            for c in TREE_COLS[2:]:
                if add[c] is not None:
                    out[hit[0]][c] = add[c]
            continue
        row = {c: ("" if add[c] is None else add[c]) for c in TREE_COLS}
        if row["kind"] == "":
            row["kind"] = "property"
        # a new child goes after the last child of its parent
        at = len(out)
        if row["parent"]:
            own = [i for i, r in enumerate(out)
                   if r["parent"] == row["parent"]
                   or (r["part"] == row["parent"] and r["parent"] == "")]
            if own:
                at = max(own) + 1
        out.insert(at, row)
    return out


def _product_parts(x: ScaleProduct) -> list[dict]:
    axes, keys, meta = x.axes, x.keys, x.meta
    return [
        _row("axes", shape=_shape(axes), note="one scale per axis"),
        *[_row(a, parent="axes", kind="axis", mark="fixed",
               shape=type(s).__name__, note=scale_id(s)) for a, s in axes.items()],
        _row("keys", shape="chr [%d]" % len(keys), mark="fixed",
             note=", ".join("%s = %s" % kv for kv in keys.items())),
        _row("joint_weights", shape=_shape(x.joint_weights), mark="mutable",
             note="reserved"),
        _row("meta", shape=_shape(meta), mark="mutable", note=_preview(meta, 8)),
    ]


@dataclass(frozen=True, eq=False)
class ScaleTree:
    """The parts of a scale (R: a `scale_tree` data frame).

    `table` has one row per part: `part`, the `parent` field it belongs to
    (`""` for a field of the object), its `kind`, `shape`, `mark`, the
    `verb` that changes it and a `note`. `header` names the class and the
    identity. `str()` draws the tree, with `+`, `-` and `|` for the branches
    unless the output stream is UTF-8; `lines(ascii=)` chooses.
    """

    header: str
    table: pa.Table

    def lines(self, ascii: bool = False) -> list[str]:
        g = (("+- ", "+- ", "|  ", "   ") if ascii
             else ("├─ ", "└─ ", "│  ", "   "))
        tee, end, bar, gap = g
        rows = self.table.to_pylist()
        top = [r for r in rows if r["parent"] == ""]
        drawn: list[tuple[str, dict]] = []
        for k, r in enumerate(top):
            last = k == len(top) - 1
            drawn.append(((end if last else tee) + r["part"], r))
            kids = [c for c in rows if c["parent"] == r["part"]]
            for j, c in enumerate(kids):
                drawn.append(((gap if last else bar)
                              + (end if j == len(kids) - 1 else tee) + c["part"], c))
        info = [r["shape"] if r["parent"] == "" else
                ("%s %s" % (r["kind"], r["shape"]) if r["shape"] else r["kind"])
                for _, r in drawn]
        w_label = max((len(lab) for lab, _ in drawn), default=0)
        w_info = max((len(i) for i in info), default=0)
        w_mark = max((len(r["mark"]) for _, r in drawn), default=0)
        body = ["  ".join([lab.ljust(w_label), i.ljust(w_info),
                           r["mark"].ljust(w_mark), r["verb"] or r["note"]]).rstrip()
                for (lab, r), i in zip(drawn, info, strict=True)]
        return [self.header or "<scale>", *body]

    def __str__(self) -> str:
        # box-drawing branches only where the output stream can encode them
        enc = (getattr(sys.stdout, "encoding", None) or "").lower().replace("-", "")
        return "\n".join(self.lines(ascii=enc != "utf8"))


def scale_tree(x: NestedScale | ScaleProduct) -> ScaleTree:
    """The parts of a scale or a product, and which of them may change.

    Lists the fields of the object, the columns of its leaftable and what a
    subclass adds. Each part carries one of three marks, defined by the
    identity of the scale (`scale_id()`): `fixed` (the part enters the
    identity; changing it gives another scale), `derived` (computed from
    another part) or `mutable` (it can change and the scale stays the same
    scale; the function that changes it is named where there is one). The
    marks describe the object; they are not enforced.
    """
    if isinstance(x, ScaleProduct):
        rows = _product_parts(x)
        id_ = x.meta.get("name") or ""
    else:
        _check_scale(x)
        rows = _scale_parts(x)
        id_ = scale_id(x)
    table = pa.table({c: pa.array([r[c] for r in rows], pa.string())
                      for c in TREE_COLS})
    return ScaleTree(header=("<%s> %s" % (type(x).__name__, id_)).strip(), table=table)
