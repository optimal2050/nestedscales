"""The seams a dimension package builds on: a leaftable with numeric columns
of which one is the declared weight, the subset and collapse hooks, the
payload hooks of definition files with the class registry, and the parts a
subclass adds to `scale_tree()`.

The subclass stands in for a time dimension: its leaf column is the finest
frame, `total` is the one weight the engine works with, and `share`, `width`
and `weight` are columns the subclass keeps for itself."""
import json

import pyarrow as pa
import pytest

import nestedscales as ns
from nestedscales import NestedScalesError


class Slices(ns.NestedScale):
    """A subclass with an alias field, extra leaftable columns and its own
    bookkeeping in `meta`."""

    _r_package = "slicepkg"
    timeframes = ns.scale_alias_property("frames")


LENGTHS = ("share", "width", "weight")
SEEN: dict = {}


def with_total(lt):
    cols = {c: lt[c].to_pylist() for c in LENGTHS}
    total = [s * w * k for s, w, k in zip(*cols.values(), strict=True)]
    if "total" in lt.column_names:
        lt = lt.drop_columns(["total"])
    return lt.append_column("total", pa.array(total, pa.float64()))


def slices(weight=(1.0, 1.0, 1.0, 1.0)):
    lt = with_total(pa.table({
        "SEASON": ["W", "W", "S", "S"],
        "DAY": ["w1", "w2", "s1", "s2"],
        "share": [0.125, 0.125, 0.25, 0.5],
        "width": [1.0, 1.0, 1.0, 1.0],
        "weight": list(weight),
    }))
    return Slices(leaftable=lt, frames=("SEASON", "DAY"),
                  members={"SEASON": ("W", "S"), "DAY": ("w1", "w2", "s1", "s2")},
                  leaf="DAY",
                  meta={"name": "s2_d2", "weights": ("total",),
                        "default_weight": "total", "year_fraction": 1.0,
                        "tokens": {"SEASON": "season", "DAY": "day"}})


@ns.scale_vocab.register(Slices)
def _vocab(x):
    return {"object": "Slices", "frame": "timeframe", "frames": "timeframes",
            "member": "timeslice", "members": "timeslices", "leaves": "timeslices"}


@ns.scale_payload_slice.register(Slices)
def _slice(x, i):
    SEEN["slice"] = list(i)
    meta = dict(x.meta)
    meta["year_fraction"] = sum(x.leaftable["total"].to_pylist())
    if meta.get("coverage") is not None:
        meta["coverage_class"] = "sampled"
    return ns.scale_set_props(x, meta=meta)


@ns.scale_payload_collapse.register(Slices)
def _collapse(x, map):
    SEEN["collapse"] = list(map)
    finest = x.frames[-1]
    lt = x.leaftable
    if x.leaf != finest:
        lt = lt.drop_columns([x.leaf])
    meta = dict(x.meta)
    meta["tokens"] = {k: v for k, v in meta["tokens"].items() if k in x.frames}
    n = lt.num_rows
    for c, v in (("share", lt["total"].to_pylist()), ("width", [1.0] * n),
                 ("weight", [1.0] * n)):
        lt = lt.append_column(c, pa.array(v, pa.float64()))
    return ns.scale_set_props(x, leaftable=lt, leaf=finest, meta=meta)


@ns.scale_write_payload.register(Slices)
def _write(x, dir, header):
    header = dict(header)
    header["payload"] = {"lengths": list(LENGTHS)}
    # `tokens` is a named vector for the other binding; `year_start` a list
    header["meta_vectors"] = [v for v in header.get("meta_vectors", [])
                              if v != "year_start"]
    return header


@ns.scale_read_payload.register(Slices)
def _read(x, dir, header):
    assert type(x) is ns.NestedScale
    SEEN["payload"] = header.get("payload")
    return Slices(leaftable=x.leaftable, frames=x.frames, members=x.members,
                  leaf=x.leaf, meta=x.meta, attributes=x.attributes,
                  aliases=x.aliases, labels=x.labels)


@ns.scale_payload_parts.register(Slices)
def _parts(x):
    return [{"part": "total", "parent": "timeframes", "note": "never listed"},
            {"part": "share", "parent": "leaftable", "kind": "length",
             "mark": "mutable", "verb": "set_lengths()"},
            {"part": "meta", "note": "name, tokens, year_fraction"},
            {"part": "tokens", "parent": "meta", "kind": "entry", "mark": "mutable"}]


# One declared weight among several numeric columns --------------------------------


def test_one_declared_weight_among_numeric_columns():
    s = slices()
    assert ns.scale_weights(s) == ["total"]
    assert ns.scale_coverage(s) == {"total": 1.0}
    kinds = {r["part"]: r["kind"] for r in ns.scale_tree(s).table.to_pylist()
             if r["parent"] == "leaftable"}
    assert kinds == {"DAY": "leaf column", "SEASON": "frame", "total": "weight",
                     "share": "length", "width": "column", "weight": "column"}
    # the default weight is what an unnamed weight resolves to
    assert ns.scale_share(s, "SEASON").column_names == ["SEASON", "total", "share"]
    with pytest.raises(NestedScalesError, match='"share" is not a weight column'):
        ns.scale_share(s, "SEASON", weight="share")


def test_default_weight_is_one_of_the_weights():
    s = slices()
    with pytest.raises(NestedScalesError,
                       match="`meta\\$default_weight` must be one of `meta\\$weights`"):
        ns.scale_set_props(s, check=True, meta={**s.meta, "default_weight": "share"})


def test_zero_weights_are_allowed_but_not_an_all_zero_column():
    s = slices(weight=(1.0, 0.0, 1.0, 0.0))
    assert s.leaftable["total"].to_pylist() == [0.125, 0.0, 0.25, 0.0]
    with pytest.raises(NestedScalesError, match="weight column `total` sums to zero"):
        slices(weight=(0.0, 0.0, 0.0, 0.0))
    with pytest.raises(NestedScalesError, match="weight column `total` must be >= 0"):
        slices(weight=(1.0, -1.0, 1.0, 1.0))
    # a column that is not a declared weight is not checked
    lt = s.leaftable.set_column(s.leaftable.column_names.index("width"), "width",
                                pa.array([0.0] * 4))
    ns.scale_set_props(s, check=True, leaftable=lt)


# Subset --------------------------------------------------------------------------


def test_subset_hook_and_coverage_by_weight_name():
    s = slices()
    win = ns.filter_scale(s, "SEASON", "W")
    assert type(win) is Slices and SEEN["slice"] == [0, 1]
    assert win.leaf == "DAY" and win.frames == ("SEASON", "DAY")
    assert win.meta["coverage"] == {"total": 0.25}
    assert win.meta["parent_totals"] == {"total": 1.0}
    assert win.meta["parent_name"] == "s2_d2" and win.meta["name"] == "s2_d2[SEASON:W]"
    assert win.meta["year_fraction"] == 0.25
    assert win.meta["coverage_class"] == "sampled"
    assert win.leaftable.column_names == s.leaftable.column_names

    # a subset of a subset is a fraction of the root parent
    one = win["DAY", "w1"]
    assert one.meta["coverage"] == {"total": 0.125}
    assert one.meta["parent_totals"] == {"total": 1.0}
    assert one.meta["parent_name"] == "s2_d2"
    assert ns.scale_coverage(one, "total") == 0.125

    # a filter that keeps every leaf records no sample; the hook still runs
    same = ns.filter_scale(s, "SEASON", ["W", "S"])
    assert "coverage" not in same.meta and SEEN["slice"] == [0, 1, 2, 3]
    assert same.meta["name"] == "s2_d2"


def test_coverage_must_agree_with_the_leaftable():
    win = ns.filter_scale(slices(), "SEASON", "W")
    with pytest.raises(NestedScalesError, match='coverage\\["total"\\]` \\(0.5\\) does '
                                                "not match the leaftable \\(0.25\\)"):
        ns.scale_set_props(win, check=True,
                           meta={**win.meta, "coverage": {"total": 0.5}})
    with pytest.raises(NestedScalesError, match="named numeric over declared weights"):
        ns.scale_set_props(win, check=True,
                           meta={**win.meta, "coverage": {"share": 0.25}})


# Collapse ------------------------------------------------------------------------


def test_collapse_hook_moves_the_leaf_column():
    s = slices()
    p = ns.prune_scale(s, "SEASON")
    assert type(p) is Slices and SEEN["collapse"] == [0, 0, 1, 1]
    assert p.frames == ("SEASON",) and p.leaf == "SEASON"
    assert p.timeframes == ("SEASON",)
    assert p.leaftable.to_pydict() == {
        "SEASON": ["W", "S"], "total": [0.25, 0.75], "share": [0.25, 0.75],
        "width": [1.0, 1.0], "weight": [1.0, 1.0]}
    assert p.meta["name"] == "s2_d2@SEASON" and p.meta["parent_name"] == "s2_d2"
    # every other entry of `meta` is kept as it was
    assert p.meta["weights"] == ("total",) and p.meta["default_weight"] == "total"
    assert p.meta["tokens"] == {"SEASON": "season"}
    assert "coverage" not in p.meta
    assert ns.scale_id(p) != ns.scale_id(s)


def test_collapse_without_a_hook_fills_the_leaf_column():
    s = ns.scale_example()
    seen = {}

    class Tagged(ns.NestedScale):
        pass

    @ns.scale_payload_collapse.register(Tagged)
    def _(x, map):
        seen["map"] = list(map)
        seen["rows"] = x.leaftable.num_rows
        return x

    t = Tagged(leaftable=s.leaftable, frames=s.frames, members=s.members,
               leaf=s.leaf, meta=s.meta)
    p = ns.prune_scale(t, "class")
    # one entry per former row: its new row, None for the dropped leaf
    assert seen == {"map": [0, 0, 1, 1, 2, 2, None], "rows": 3}
    assert type(p) is Tagged and p.leaf == "item"
    assert p.leaftable.column_names == ["sector", "class", "size", "count", "item"]
    assert p.leaftable["item"].to_pylist() == ["G1", "G2", "S1"]
    assert p.meta["coverage"] == pytest.approx({"size": 2100 / 3100, "count": 1.0})
    # the default hook leaves a core scale as the engine built it
    assert ns.prune_scale(s, "class").leaftable.equals(p.leaftable)
    # collapsing to the finest frame keeps every leaf and renames the scale
    same = ns.prune_scale(s, "item")
    assert same.meta["name"] == "example@item" and same.leaftable.num_rows == 7
    assert ns.scale_id(same).split("@")[-1] == ns.scale_id(s).split("@")[-1]


def test_a_hook_that_leaves_the_object_inconsistent_is_reported():
    class Broken(ns.NestedScale):
        pass

    @ns.scale_payload_collapse.register(Broken)
    def _(x, map):
        return ns.scale_set_props(x, leaf="nope")

    s = ns.scale_example()
    b = Broken(leaftable=s.leaftable, frames=s.frames, members=s.members,
               leaf=s.leaf, meta=s.meta)
    with pytest.raises(NestedScalesError, match="must have a `nope` column"):
        ns.prune_scale(b, "class")


def test_set_props_copies_and_validates_on_request():
    s = slices()
    t = ns.scale_set_props(s, meta={**s.meta, "name": "other"})
    assert type(t) is Slices and t is not s and s.meta["name"] == "s2_d2"
    assert t.meta["name"] == "other" and t.leaftable is s.leaftable
    bad = ns.scale_set_props(s, frames=("SEASON", "nope"))  # unchecked
    with pytest.raises(NestedScalesError, match="<slicepkg::Slices> object is invalid"):
        ns.scale_validate(bad)
    assert ns.scale_validate(t) is t


# Definition files ----------------------------------------------------------------


def test_payload_hooks_and_the_class_registry(tmp_path):
    s = ns.scale_set_props(slices(), check=True, meta={
        **slices().meta, "year_start": {"month": 1, "day": 1}})
    f = ns.write_scale(s, tmp_path / "s.json")
    hdr = json.loads(f.read_text(encoding="utf-8"))
    assert hdr["class"] == "slicepkg::Slices" and hdr["leaf"] == "DAY"
    assert hdr["payload"] == {"lengths": ["share", "width", "weight"]}
    assert hdr["meta_vectors"] == ["tokens"]

    with pytest.raises(NestedScalesError, match="written from a slicepkg::Slices, and "
                                                "no such class is registered"):
        ns.read_scale(f)
    core = ns.read_scale(f, cls="core")
    assert type(core) is ns.NestedScale and core.leaf == "DAY"

    assert ns.register_scale_class(Slices) == "slicepkg::Slices"
    assert "slicepkg::Slices" in ns.list_scale_classes()
    back = ns.read_scale(f)
    assert type(back) is Slices and SEEN["payload"] == hdr["payload"]
    assert back.leaftable.equals(s.leaftable) and back.frames == s.frames
    assert back.meta["weights"] == ("total",) and back.meta["default_weight"] == "total"
    assert back.meta["tokens"] == s.meta["tokens"]
    assert ns.scale_id(back) == ns.scale_id(s)

    # the bookkeeping of a subset travels by weight name
    win = ns.filter_scale(s, "SEASON", "W")
    back = ns.read_scale(ns.write_scale(win, tmp_path / "win.scale", tables="arrow"))
    assert type(back) is Slices
    assert back.meta["coverage"] == {"total": 0.25}
    assert back.meta["parent_totals"] == {"total": 1.0}
    assert back.meta["coverage_class"] == "sampled"

    class Unread(ns.NestedScale):
        _r_package = "slicepkg"

    ns.register_scale_class(Unread)
    u = Unread(leaftable=s.leaftable, frames=s.frames, members=s.members,
               leaf=s.leaf, meta=s.meta)
    g = ns.write_scale(u, tmp_path / "u.json")
    with pytest.raises(NestedScalesError, match="has no scale_read_payload\\(\\)"):
        ns.read_scale(g)
    with pytest.raises(NestedScalesError, match="must inherit from scale_class"):
        ns.register_scale_class(dict)


# Tree ----------------------------------------------------------------------------


def test_tree_of_a_subclass():
    s = slices()
    tree = ns.scale_tree(s)
    assert tree.header == "<Slices> " + ns.scale_id(s)
    rows = tree.table.to_pylist()
    top = [r["part"] for r in rows if r["parent"] == ""]
    # the alias names the inherited field
    assert top == ["leaftable", "timeframes", "members", "leaf", "meta",
                   "attributes", "aliases", "labels"]
    by = {(r["parent"], r["part"]): r for r in rows}
    # a row of the subclass replaces the fields it gives of a part the core lists
    assert by[("leaftable", "share")] == {
        "part": "share", "parent": "leaftable", "kind": "length", "shape": "",
        "mark": "mutable", "verb": "set_lengths()", "note": ""}
    assert by[("", "meta")]["note"] == "name, tokens, year_fraction"
    assert by[("", "meta")]["mark"] == "mutable"
    # a new part goes after the last child of its parent
    parts = [r["part"] for r in rows]
    assert parts[parts.index("meta") + 1] == "tokens"
    assert parts[parts.index("timeframes") + 1] == "total"
    assert by[("timeframes", "total")]["kind"] == "property"
    assert tree.lines(ascii=True)[0] == tree.header
    assert "+- timeframes" in tree.lines(ascii=True)[8]

    marks = {r["part"]: r["mark"] for r in rows if r["parent"] == ""}
    assert marks["timeframes"] == "fixed" and marks["members"] == "derived"


def test_tree_hook_refusals_and_product():
    class Odd(ns.NestedScale):
        pass

    s = ns.scale_example()
    o = Odd(leaftable=s.leaftable, frames=s.frames, members=s.members, leaf=s.leaf,
            meta=s.meta)
    impl = {"rows": [{"part": "x", "mark": "frozen"}]}

    @ns.scale_payload_parts.register(Odd)
    def _(x):
        return impl["rows"]

    with pytest.raises(NestedScalesError, match="unknown mark\\(s\\) frozen; a part is "
                                                "fixed, derived, mutable"):
        ns.scale_tree(o)
    impl["rows"] = [{"name": "x"}]
    with pytest.raises(NestedScalesError, match="with a `part` column"):
        ns.scale_tree(o)
    impl["rows"] = pa.table({"part": ["extra"], "note": ["a table works too"]})
    assert ns.scale_tree(o).table.to_pylist()[-1]["note"] == "a table works too"

    p = ns.scale_product(a=ns.scale_example(), b=ns.scale_example2())
    rows = ns.scale_tree(p).table.to_pylist()
    assert [r["part"] for r in rows] == ["axes", "a", "b", "keys", "joint_weights",
                                         "meta"]
    assert rows[1]["note"] == ns.scale_id(ns.scale_example())
    assert rows[3]["note"] == "a = item, b = period"
    with pytest.raises(NestedScalesError, match="must be a NestedScale object"):
        ns.scale_tree("x")
