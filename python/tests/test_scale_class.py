"""NestedScale validation, construction and printing (ports of the R
validator and constructor checks)."""
import math

import pyarrow as pa
import pytest

import nestedscales as ns
from nestedscales import NestedScalesError, NestedScalesWarning


def lt3():
    return pa.table({"section": ["A", "A", "A", "B"],
                     "group": ["A1", "A1", "A2", "B1"],
                     "unit": ["A11", "A12", "A21", "B11"],
                     "gva": [100.0, 200.0, 300.0, 400.0]})


def test_constructor_defaults():
    s = ns.scale_from_leaftable(lt3(), frames=["section", "group", "unit"])
    assert ns.scale_key(s) == "unit"
    assert ns.scale_weights(s) == ["gva"]
    assert s.meta["default_weight"] == "gva"
    assert ns.scale_units(s, "group") == ["A1", "A2", "B1"]
    assert repr(s) == "<NestedScale[section/group/unit] atoms=4>"


def test_polars_and_pandas_input():
    pl = pytest.importorskip("polars")
    fr = ["section", "group", "unit"]
    s = ns.scale_from_leaftable(pl.from_arrow(lt3()), frames=fr)
    assert ns.scale_units(s) == ["A11", "A12", "A21", "B11"]
    pytest.importorskip("pandas")
    s2 = ns.scale_from_leaftable(lt3().to_pandas(), frames=fr)
    assert s2 == s


def test_blank_codes_become_null():
    t = lt3().set_column(1, "group", pa.array(["A1", "  ", "A2", ""]))
    s = ns.scale_from_leaftable(t, frames=["section", "group", "unit"])
    assert ns.scale_units(s, "group") == ["A1", "A2"]
    assert s.leaftable["group"].null_count == 2


def test_inverted_frames_warn():
    with pytest.warns(NestedScalesWarning, match="CONTAINS the frame before it"):
        ns.scale_from_leaftable(lt3(), frames=["group", "section"], key="unit")


def test_crosscutting_frames_do_not_warn():
    s = ns.scale_example()
    assert not ns.scale_nests(s, "class", "group")


@pytest.mark.parametrize("frames, msg", [
    (["section", "2bad"], "missing frame column"),
    ([], "non-empty character vector"),
])
def test_constructor_errors(frames, msg):
    with pytest.raises(NestedScalesError, match=msg):
        ns.scale_from_leaftable(lt3(), frames=frames)


def test_missing_key_values_error():
    t = lt3().set_column(2, "unit", pa.array(["A11", None, "A21", "B11"]))
    with pytest.raises(NestedScalesError, match="every atom needs an identifier"):
        ns.scale_from_leaftable(t, frames=["section", "group"], key="unit")


def make(**kw):
    s = ns.scale_example()
    args = dict(leaftable=s.leaftable, frames=s.frames, members=s.members,
                key=s.key, meta=s.meta)
    args.update(kw)
    return ns.NestedScale(**args)


def test_validator_collects_errors():
    with pytest.raises(NestedScalesError) as e:
        make(meta={"weights": ["size", "nope"], "default_weight": "zzz"})
    msg = str(e.value)
    assert msg.startswith("<nestedscales::NestedScale> object is invalid:")
    assert "weight column `nope` not found" in msg
    assert "`meta$default_weight` must be one of `meta$weights`" in msg


@pytest.mark.parametrize("kw, msg", [
    ({"key": ""}, "`key` must be a single non-empty string"),
    ({"frames": ("sector", "sector")}, "`frames` must be unique"),
    ({"frames": ("share", "unit")}, "reserved names: share"),
    ({"frames": ("unit", "group")}, "reserved names: unit"),
    ({"members": {"sector": ["P"], "class": ["G1", "G2", "S1"],
                  "group": ["G1", "GB", "GC"],
                  "unit": ["U1", "U2", "U3", "U4", "U5", "U6", "OTH"]}},
     'members\\[\\["sector"\\]\\]` must contain exactly'),
    ({"meta": {"weights": ["size"], "residuals": {"nope": ["x"]}}},
     "names frame\\(s\\) that are not frames: nope"),
    ({"meta": {"weights": ["size"], "residuals": {"unit": ["ZZ"]}}},
     "names non-member\\(s\\): ZZ"),
    ({"meta": {"weights": ["size"], "coverage": {"size": 1.5}}},
     "values must lie in \\(0, 1\\]"),
    ({"meta": {"weights": ["size"], "coverage": {"size": 0.5},
               "parent_totals": {"size": 3100}}},
     "does not match the leaftable"),
])
def test_validator_rules(kw, msg):
    with pytest.raises(NestedScalesError, match=msg):
        make(**kw)


def test_weight_rules():
    s = ns.scale_example()
    neg = s.leaftable.set_column(4, "size", pa.array([-1.0, 1, 1, 1, 1, 1, 1]))
    with pytest.raises(NestedScalesError, match="must be >= 0"):
        make(leaftable=neg)
    inf = s.leaftable.set_column(4, "size", pa.array([math.inf, 1, 1, 1, 1, 1, 1]))
    with pytest.raises(NestedScalesError, match="must be finite"):
        make(leaftable=inf)
    nan_ok = s.leaftable.set_column(4, "size", pa.array([math.nan, 1, 1, 1, 1, 1, 1]))
    make(leaftable=nan_ok)


def test_coverage_consistent_with_parent_totals():
    s = make(meta={"weights": ["size"], "coverage": {"size": 0.5},
                   "parent_totals": {"size": 6200}})
    assert ns.scale_coverage(s, "size") == 0.5
    assert ns.scale_summary(s).sampled


def test_residuals_accessor():
    s = make(meta={"weights": ["size"], "residuals": {"unit": ["OTH"]}})
    assert ns.scale_residuals(s) == {"unit": ["OTH"]}
    assert ns.scale_residuals(s, "unit") == ["OTH"]
    assert ns.scale_residuals(ns.scale_example()) == {}
    assert ns.scale_residuals(ns.scale_example(), "unit") == []


def test_check_frame_messages():
    s = ns.scale_example()
    with pytest.raises(NestedScalesError, match='`frame` = "zz" is not a frame of this '
                                                "NestedScale"):
        ns.scale_units(s, "zz")
    with pytest.raises(NestedScalesError, match="is the finest frame"):
        ns.scale_children(s, "unit", "U1")
    with pytest.raises(NestedScalesError, match="code\\(s\\) not found"):
        ns.scale_children(s, "sector", ["Q", "P"])


def test_print_and_summary():
    s = ns.scale_example()
    txt = str(s)
    assert txt.splitlines()[0] == "NestedScale: example"
    assert "      - unit (7)" in txt
    assert "  - sector (2)  [1 unit unassigned]" in txt
    assert "Weights: size, count (default: size)" in txt
    sm = ns.scale_summary(s)
    assert sm.n_atoms == 7 and sm.weight_totals == {"size": 3100.0, "count": 300.0}
    assert [r["nests"] for r in sm.nesting] == [True, False, True]
    assert "class > group: CROSS-CUTTING (1 offender(s))" in str(sm)


def test_value_semantics():
    a, b = ns.scale_example(), ns.scale_example()
    assert a == b and a is not b
    with pytest.raises(AttributeError):
        a.key = "x"
    assert ns.scale_is(a) and not ns.scale_is(a.leaftable)
    assert ns.scale_class() is ns.NestedScale


def test_verdict_behaves_like_bool():
    v = ns.scale_nests(ns.scale_example(), "class", "group")
    assert not v and v == False  # noqa: E712
    assert v.offenders == ("GB",)


def test_subclass_vocab_and_alias():
    class Calendar(ns.NestedScale):
        timeframes = ns.scale_alias_property("frames")

    @ns.scale_vocab.register(Calendar)
    def _(x):
        return {"object": "Calendar", "frame": "timeframe", "frames": "timeframes",
                "unit": "timeslice", "units": "timeslices", "atoms": "timeslices"}

    s = ns.scale_example2()
    c = Calendar(leaftable=s.leaftable, frames=s.frames, members=s.members,
                 key=s.key, meta=s.meta)
    assert c.timeframes == ("era", "period")
    with pytest.raises(NestedScalesError, match="is not a timeframe of this Calendar"):
        ns.scale_units(c, "zz")
    assert str(c).startswith("Calendar: example2\n")


@pytest.mark.parametrize("name, ok", [
    ("industry", True), ("reg32", True), (".x", True), ("a_b.c", True),
    ("", False), ("2bad", False), ("_x", False), (".2x", False), ("if", False),
    ("NA", False), ("a-b", False),
])
def test_is_valid_frame(name, ok):
    assert ns.is_valid_frame(name) is ok
