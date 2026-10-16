"""scale_map(): schema, the split factor, and the registry (port of
tests/testthat/test-map.R)."""
import pyarrow as pa
import pytest

import nestedscales as ns
from nestedscales import NestedScalesError
from nestedscales.map import _finish_map


def fake():
    one = pa.array([1], pa.int32())
    return pa.table({"class": ["G1"], "group": ["GC"], "n_from": one,
                     "n_overlap": one, "w": [1.0], "w_from": [1.0]})


def test_schema():
    m = ns.scale_map(ns.scale_example(), "class", "group")
    assert m.column_names == ["class", "group", "n_from", "n_overlap", "w", "w_from"]
    assert m.schema.field("n_overlap").type == pa.int32()
    assert m.schema.field("w").type == pa.float64()


def test_n_from_and_w_from():
    s = ns.scale_example()
    m = ns.scale_map(s, "class", "unit", weight="size").to_pylist()
    g1 = [r for r in m if r["class"] == "G1"]
    assert {r["n_from"] for r in g1} == {2}
    assert all(r["n_overlap"] == 1 for r in m)
    assert {r["w_from"] for r in g1} == {300.0}
    assert sum(r["w"] for r in g1) == 300.0


def test_uncovered_atoms_have_null_target():
    m = ns.scale_map(ns.scale_example(), "unit", "sector").to_pylist()
    assert [r["unit"] for r in m if r["sector"] is None] == ["OTH"]


def test_equal_split_without_weights():
    s = ns.scale_from_leaftable(
        pa.table({"grp": ["A", "A", "B"], "unit": ["u1", "u2", "u3"]}),
        frames=["grp", "unit"], name="noweights")
    for r in ns.scale_map(s, "grp", "unit").to_pylist():
        assert r["w"] / r["w_from"] == r["n_overlap"] / r["n_from"]


def test_argument_errors():
    s = ns.scale_example()
    with pytest.raises(NestedScalesError, match="the same frame"):
        ns.scale_map(s, "class", "class")
    with pytest.raises(NestedScalesError, match="scale_map_between"):
        ns.scale_map(s, s, "group")
    with pytest.raises(NestedScalesError, match="is not a frame"):
        ns.scale_map(s, "nope", "group")


def test_between_names_and_keys():
    a = ns.scale_example()
    with pytest.raises(NestedScalesError, match="same name"):
        ns.scale_map_between(a, a)
    b = ns.scale_from_leaftable(pa.table({"grp": ["A", "B"], "unit": ["z1", "z2"]}),
                                frames=["grp", "unit"], name="disjoint")
    with pytest.raises(NestedScalesError, match="share no `unit` keys"):
        ns.scale_map_between(a, b)


def test_atom_pairs_seam():
    d = ns.scale_atom_pairs(ns.scale_example(), "class", "group")
    assert d.column_names == ["source", "target", "w"] and d.num_rows == 7


def test_by_columns_are_carried():
    d = ns.scale_atom_pairs(ns.scale_example(), "class", "group")
    d2 = pa.concat_tables([d.append_column("year", pa.array([2020] * 7)),
                           d.append_column("year", pa.array([2021] * 7))])
    m = _finish_map(d2, "class", "group", by=["year"])
    assert m.column_names[0] == "year"
    assert {r["n_from"] for r in m.to_pylist() if r["class"] == "G1"} == {2}


def test_atom_pairs_override_for_subclass():
    class Gen(ns.NestedScale):
        pass

    @ns.scale_atom_pairs.register(Gen)
    def _(x, source, target, weight=None, **kw):
        return pa.table({"source": ["a", "a"], "target": ["b1", "b2"],
                         "w": [1.0, 3.0]})

    s = ns.scale_example2()
    g = Gen(leaftable=s.leaftable, frames=s.frames, members=s.members, key=s.key,
            meta=s.meta)
    m = ns.scale_map(g, "era", "period").to_pylist()
    assert [r["w"] / r["w_from"] for r in m] == [0.25, 0.75]


# Registry --------------------------------------------------------------------

def test_registered_map_is_returned_as_is():
    s = ns.scale_example()
    ns.register_scale_map(s, "class", "group", fake())
    assert ns.scale_map(s, "class", "group").equals(fake())
    assert ns.get_scale_map(s, "class", "group").equals(fake())


def test_registered_maps_are_scoped():
    ns.register_scale_map(ns.scale_example(), "class", "group", fake())
    assert ns.get_scale_map("other_scale", "class", "group") is None


def test_register_none_removes():
    s = ns.scale_example()
    ns.register_scale_map(s, "class", "group", fake())
    ns.register_scale_map(s, "class", "group", None)
    assert ns.get_scale_map(s, "class", "group") is None


def test_registered_map_schema():
    s = ns.scale_example()
    with pytest.raises(NestedScalesError, match="missing column"):
        ns.register_scale_map(s, "class", "group", pa.table({"a": [1]}))
    with pytest.raises(NestedScalesError, match="must be a data.frame"):
        ns.register_scale_map(s, "class", "group", "nope")


def test_list_scale_maps():
    ns.register_scale_map(ns.scale_example(), "class", "group", fake())
    assert ns.list_scale_maps()["key"].to_pylist() == ["example:class->group"]


def test_between_registry():
    m = pa.table({"example": ["U1"], "other": ["X"], "n_from": [1], "n_overlap": [1],
                  "w": [1.0], "w_from": [1.0]})
    key = ns.register_scale_map_between("example", "other", m)
    assert key == "example->other"
    assert ns.get_scale_map_between(ns.scale_example(), "other").equals(m)


def test_clear_by_name():
    s = ns.scale_example()
    k1 = ns.register_scale_map(s, "class", "group", fake())
    ns.register_scale_map(s, "group", "class", fake().rename_columns(
        ["group", "class", "n_from", "n_overlap", "w", "w_from"]))
    ns.clear_scale_maps(k1)
    assert ns.list_scale_maps()["key"].to_pylist() == ["example:group->class"]
    ns.clear_scale_maps()
    assert ns.list_scale_maps().num_rows == 0
