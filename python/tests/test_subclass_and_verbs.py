"""Dimension subclasses, products, arrays, and the table verbs on non-Arrow
inputs. The subclass here stands in for a dimension package (timescales'
Calendar); the real ones live in those packages."""
import numpy as np
import pyarrow as pa
import pytest

import nestedscales as ns
from nestedscales import NestedScalesError


class Calendar(ns.NestedScale):
    """A minimal dimension subclass: an alias field and its own vocabulary."""

    _r_package = "timescales"
    timeframes = ns.scale_alias_property("frames")


@ns.scale_vocab.register(Calendar)
def _(x):
    return {"object": "Calendar", "frame": "timeframe", "frames": "timeframes",
            "unit": "timeslice", "units": "timeslices", "atoms": "timebase",
            "register_rule": "register_calendar_rule()",
            "register_map": "register_calendar_map_between()"}


def tiny_calendar():
    hours = [(d, h) for h in ("h00", "h01") for d in ("d001", "d002")]
    t = pa.table({"YDAY": [d for d, _ in hours], "HOUR": [h for _, h in hours],
                  "weight": [1.0] * 4,
                  "timeslice": ["%s_%s" % dh for dh in hours]})
    s = ns.scale_from_leaftable(t, frames=["YDAY", "HOUR"], key="timeslice",
                                name="d2_h2")
    return Calendar(leaftable=s.leaftable, frames=s.frames, members=s.members,
                    key=s.key, meta=s.meta)


def test_subclass_speaks_its_vocabulary():
    cal = tiny_calendar()
    assert cal.timeframes == ("YDAY", "HOUR")
    assert ns.scale_atom_level(cal) == "timeslice"
    with pytest.raises(NestedScalesError, match="is not a timeframe of this Calendar"):
        ns.scale_units(cal, "MONTH")
    with pytest.raises(NestedScalesError, match="register_calendar_rule"):
        ns.recast_scale(pa.table({"timeslice": ["d001_h00"], "v": [1.0]}), cal,
                        source="timeslice", target="YDAY")


def test_subclass_rules_resolve_in_its_scope():
    ns.register_scale_rule("load", "weighted_mean", scope="calendar")
    ns.register_scale_rule("load", "sum", scope="geoscale")
    d = pa.table({"timeslice": ["d001_h00", "d001_h01"], "load": [2.0, 4.0]})
    out = ns.recast_scale(d, tiny_calendar(), source="timeslice", target="YDAY",
                          diagnostics="off")
    assert out.to_pylist()[0] == {"YDAY": "d001", "load": 3.0}


def test_subclass_validation_names_its_class():
    s = tiny_calendar()
    with pytest.raises(NestedScalesError, match=r"^<timescales::Calendar> object"):
        Calendar(leaftable=s.leaftable, frames=s.frames, members={}, key=s.key,
                 meta=s.meta)


def test_filter_preserves_subclass():
    sub = ns.filter_scale(tiny_calendar(), "YDAY", "d001")
    assert isinstance(sub, Calendar) and sub.meta["name"] == "d2_h2[YDAY:d001]"
    assert sub["HOUR", "h00"].leaftable.num_rows == 1


def test_product_container():
    p = ns.scale_product(a=ns.scale_example(), b=ns.scale_example2())
    assert ns.product_keys(p) == {"a": "unit", "b": "period"}
    assert ns.product_size(p) == {"axes": {"a": 7, "b": 4}, "total": 28.0}
    assert ns.scale_axes(p, "b") == ns.scale_example2()
    q = ns.scale_product(a=ns.scale_example(), b=ns.scale_example())
    with pytest.raises(NestedScalesError, match="axes resolve to the same key"):
        ns.scale_product(a=ns.scale_example(), b=ns.scale_example(),
                         keys={"a": "unit", "b": "unit"})
    assert ns.product_keys(q) == {"a": "a", "b": "b"}
    with pytest.raises(NestedScalesError, match="is a ScaleProduct, not a single"):
        ns.scale_frames(p)


def test_arrays_round_trip():
    s = ns.scale_example()
    d = pa.table({"unit": ["U1", "U3"], "v": [5.0, 7.0]})
    a = ns.as_scale_array(d, s)
    assert a.shape == (7,) and a[0] == 5.0 and np.isnan(a[1])
    back = ns.as_scale_table(a, s, value="v")
    assert back.to_pylist() == [{"unit": "U1", "v": 5.0}, {"unit": "U3", "v": 7.0}]
    with pytest.raises(NestedScalesError, match="not units of axis"):
        ns.as_scale_array(pa.table({"unit": ["ZZ"], "v": [1.0]}), s)
    with pytest.raises(NestedScalesError, match="above `limit`"):
        ns.as_scale_array(d, s, limit=3)


def test_join_keeps_row_order_and_backend():
    pd = pytest.importorskip("pandas")
    pl = pytest.importorskip("polars")
    s = ns.scale_example()
    d = pa.table({"class": ["S1", "G1", "G2", "G1"], "v": [1, 2, 3, 4]})
    out = ns.join_scale(d, s, attach=True)
    assert out["example"].to_pylist() == ["S1", "G1", "G2", "G1"]
    assert out["example.sector"].to_pylist() == ["S", "P", "P", "P"]
    assert isinstance(ns.join_scale(d.to_pandas(), s, attach=True), pd.DataFrame)
    got = ns.join_scale(pl.from_arrow(d), s, attach=True)
    assert isinstance(got, pl.DataFrame)
    assert got["example.sector"].to_list() == ["S", "P", "P", "P"]
