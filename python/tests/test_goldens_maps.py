"""Replay specs/goldens/maps.json: crosswalks within and between scales,
including warning and error text."""
import warnings

import pytest
from conftest import build_scale, load_golden, rowset

import nestedscales as ns

CASES = load_golden("maps.json")


def replay(call, expect):
    with warnings.catch_warnings(record=True) as rec:
        warnings.simplefilter("always")
        if expect["error"]:
            with pytest.raises(ns.NestedScalesError) as e:
                call()
            assert str(e.value) == expect["message"]
            return
        got = call()
    assert [str(w.message) for w in rec] == expect["warnings"]
    assert rowset(got) == rowset(expect["value"])
    assert got.column_names[2:] == ["n_from", "n_overlap", "w", "w_from"]


@pytest.mark.parametrize("name", sorted(CASES["within"]))
def test_within(name):
    case = CASES["within"][name]
    s = build_scale(case["construct"])
    for c in case["calls"]:
        replay(lambda c=c: ns.scale_map(s, c["from"], c["to"], weight=c["weight"]), c)


@pytest.mark.parametrize("i", range(len(CASES["between"])))
def test_between(i):
    c = CASES["between"][i]
    a, b = build_scale(c["from"]), build_scale(c["to"])
    replay(lambda: ns.scale_map_between(a, b, weight=c["weight"]), c)
