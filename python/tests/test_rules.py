"""The rule registry and per-column resolution (port of
tests/testthat/test-rules.R)."""
import pytest

import nestedscales as ns
from nestedscales import NestedScalesError
from nestedscales.rules import _rules_for


def test_round_trip():
    ns.register_scale_rule("cap", "sum")
    ns.register_scale_rule("eff", "weighted_mean", weight="size")
    assert ns.get_scale_rule("cap")["rule"] == "sum"
    assert ns.get_scale_rule("eff")["weight"] == "size"
    assert ns.get_scale_rule("never_registered") is None
    tab = ns.list_scale_rules().to_pylist()
    assert {r["param"] for r in tab} == {"cap", "eff"}
    assert [r["rule"] for r in tab if r["param"] == "cap"] == ["sum"]
    ns.clear_scale_rules("cap")
    assert ns.get_scale_rule("cap") is None
    assert ns.get_scale_rule("eff")["rule"] == "weighted_mean"


def test_scopes_and_fallback():
    ns.register_scale_rule("load", "weighted_mean", scope="calendar")
    ns.register_scale_rule("load", "sum", scope="geoscale")
    ns.register_scale_rule("cost", "sum")
    assert ns.get_scale_rule("load", scope="calendar")["rule"] == "weighted_mean"
    assert ns.get_scale_rule("load", scope="geoscale")["rule"] == "sum"
    assert ns.get_scale_rule("cost", scope="calendar")["rule"] == "sum"
    assert ns.get_scale_rule("load") is None


def test_clear_scope():
    ns.register_scale_rule("load", "weighted_mean", scope="calendar")
    ns.register_scale_rule("load", "sum", scope="geoscale")
    ns.clear_scale_rules(scope="calendar")
    assert ns.get_scale_rule("load", scope="calendar") is None
    assert ns.get_scale_rule("load", scope="geoscale")["rule"] == "sum"


def test_list_by_scope():
    ns.register_scale_rule("a", "sum", scope="calendar")
    ns.register_scale_rule("b", "sum", scope="geoscale")
    assert ns.list_scale_rules(scope="calendar")["param"].to_pylist() == ["a"]
    assert ns.list_scale_rules().num_rows == 2
    assert ns.list_scale_rules().column_names == ["param", "rule", "weight", "scope"]


def test_registration_validates():
    with pytest.raises(NestedScalesError, match="non-empty string"):
        ns.register_scale_rule("", "sum")
    with pytest.raises(NestedScalesError, match="should be one of"):
        ns.register_scale_rule("x", "nope")
    with pytest.raises(NestedScalesError, match="single string"):
        ns.register_scale_rule("x", "sum", weight=["a", "b"])


def test_partial_rule_names_match_like_match_arg():
    assert ns.register_scale_rule("x", "weighted")["rule"] == "weighted_mean"
    with pytest.raises(NestedScalesError, match="should be one of"):
        ns.register_scale_rule("x", "s")  # sum, sd, share: ambiguous


def test_scale_rules_constant():
    assert set(ns.SCALE_RULES) == {"sum", "weighted_mean", "mean", "copy", "sd",
                                   "share", "logshare"}


def test_scalar_rule_applies_to_every_column():
    r = _rules_for(["a", "b"], rule="sum")
    assert r["a"]["rule"] == r["b"]["rule"] == "sum"


def test_named_rules_select_per_column():
    r = _rules_for(["a", "b"], rule={"a": "sum", "b": "mean"})
    assert (r["a"]["rule"], r["b"]["rule"]) == ("sum", "mean")


def test_named_rules_reject_unknown_columns():
    with pytest.raises(NestedScalesError, match="not value columns"):
        _rules_for(["a"], rule={"a": "sum", "zz": "mean"})


def test_unnamed_multi_rule_rejected():
    with pytest.raises(NestedScalesError, match="NAMED vector"):
        _rules_for(["a", "b"], rule=["sum", "mean"])


def test_missing_rule_is_an_error():
    with pytest.raises(NestedScalesError, match="no aggregation rule for value column"):
        _rules_for(["mystery"])


def test_explicit_rule_beats_registry():
    ns.register_scale_rule("cap", "sum")
    assert _rules_for(["cap"], rule="mean")["cap"]["rule"] == "mean"


def test_registry_supplies_weight():
    ns.register_scale_rule("eff", "weighted_mean", weight="size")
    assert _rules_for(["eff"])["eff"]["weight"] == "size"
    assert _rules_for(["eff"], weight="count")["eff"]["weight"] == "count"
