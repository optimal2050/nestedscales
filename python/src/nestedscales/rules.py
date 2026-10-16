"""Aggregation rule registry (port of R/rules.R).

Maps a value-column name to the rule used when recasting it, plus an optional
weight column. `recast_scale()` consults the registry when the caller passes
no `rule=`; an explicit argument always wins. A column with neither is an
error -- there is deliberately no fallback.

Entries are SCOPED so dimension packages cannot collide: "load" in time and
"load" in space are different statements. A scoped lookup falls back to the
unscoped entry.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence

import pyarrow as pa

from ._utils import _preview, _stop

#: Supported rules. Each defines both directions; direction comes from the
#: frame ranks.
#:
#: * `sum` -- up: sum; down: split by weight (extensive quantities)
#: * `weighted_mean` -- up: weighted mean; down: copy (intensive quantities)
#: * `mean` -- up: unweighted mean; down: copy
#: * `copy` -- up: the common value, error if not constant; down: copy
#: * `sd` -- up: standard deviation over the atoms (aggregation only)
#: * `share` -- value / total over its parent group; stays keyed at the
#:   SOURCE frame, so it cannot be mixed with other rules in one call
#: * `logshare` -- the same computation as `share`, drawn on a log scale
SCALE_RULES = ("sum", "weighted_mean", "mean", "copy", "sd", "share", "logshare")

_SHARE_RULES = ("share", "logshare")

_RULE_REGISTRY: dict[str, dict] = {}


def _rule_key(param: str, scope: str | None = None) -> str:
    return param if not scope else "%s:%s" % (scope, param)


def _match_rule(rule: object, arg: str = "rule") -> str:
    """R's `match.arg(rule, SCALE_RULES)`: exact, else a unique prefix."""
    if isinstance(rule, str):
        if rule in SCALE_RULES:
            return rule
        hits = [r for r in SCALE_RULES if rule and r.startswith(rule)]
        if len(hits) == 1:
            return hits[0]
    _stop("`%s` should be one of: %s", arg, ", ".join(SCALE_RULES))


def register_scale_rule(param: str, rule: str, weight: str | None = None,
                        scope: str | None = None) -> dict:
    """Record the rule (and optionally the weight) for a value column."""
    if not isinstance(param, str) or param == "":
        _stop("`param` must be a single non-empty string")
    rule = _match_rule(rule)
    if weight is not None and not isinstance(weight, str):
        _stop("`weight` must be a single string or NULL")
    if scope is not None and not isinstance(scope, str):
        _stop("`scope` must be a single string or NULL")
    entry = {"rule": rule, "weight": weight, "scope": scope}
    _RULE_REGISTRY[_rule_key(param, scope)] = entry
    return entry


def get_scale_rule(param: str, scope: str | None = None) -> dict | None:
    """The registered entry (`rule`, `weight`, `scope`), or None.

    A scoped lookup prefers its own scope and falls back to unscoped.
    """
    if not isinstance(param, str):
        return None
    for k in dict.fromkeys([_rule_key(param, scope), param]):
        if k in _RULE_REGISTRY:
            return dict(_RULE_REGISTRY[k])
    return None


def list_scale_rules(scope: str | None = None) -> pa.Table:
    """Registered rules: columns `param`, `rule`, `weight`, `scope`."""
    keys = sorted(k for k, e in _RULE_REGISTRY.items()
                  if scope is None or e["scope"] == scope)
    entries = [_RULE_REGISTRY[k] for k in keys]
    return pa.table({
        "param": pa.array([k.split(":", 1)[-1] if ":" in k else k for k in keys],
                          pa.string()),
        "rule": pa.array([e["rule"] for e in entries], pa.string()),
        "weight": pa.array([e["weight"] for e in entries], pa.string()),
        "scope": pa.array([e["scope"] for e in entries], pa.string()),
    })


def clear_scale_rules(param: str | Sequence[str] | None = None,
                      scope: str | None = None) -> None:
    """Remove entries: everything, one scope, or the named params."""
    if param is None:
        if scope is None:
            _RULE_REGISTRY.clear()
            return
        present = [k for k in _RULE_REGISTRY if k.startswith(scope + ":")]
    else:
        params = [param] if isinstance(param, str) else list(param)
        present = [k for k in (_rule_key(p, scope) for p in params)
                   if k in _RULE_REGISTRY]
    for k in present:
        del _RULE_REGISTRY[k]


def _per_column(x: object, values: Sequence[str], what: str) -> dict:
    """A scalar applied to every column, or a mapping selecting per column."""
    if x is None:
        return dict.fromkeys(values)
    if isinstance(x, str):
        return dict.fromkeys(values, x)
    if not isinstance(x, Mapping):
        _stop("`%s` must be a single value or a NAMED vector with one entry per "
              "value column", what)
    unknown = [k for k in x if k not in values]
    if unknown:
        _stop("`%s` names columns that are not value columns: %s",
              what, _preview(unknown))
    out = dict.fromkeys(values)
    out.update(x)
    return out


def _rules_for(values: Sequence[str], rule: object = None, weight: object = None,
               scope: str | None = None,
               hint: str = "register_scale_rule()") -> dict[str, dict]:
    """Resolve `{column: {"rule", "weight"}}` for a recast.

    Explicit arguments win over the registry; a column with neither is an
    error.
    """
    rules = _per_column(rule, values, "rule")
    weights = _per_column(weight, values, "weight")
    out: dict[str, dict] = {}
    missing: list[str] = []
    for v in values:
        r, w = rules[v], weights[v]
        if r is None:
            entry = get_scale_rule(v, scope=scope)
            if entry is None:
                missing.append(v)
                continue
            r = entry["rule"]
            if w is None:
                w = entry["weight"]
        out[v] = {"rule": _match_rule(r), "weight": w}
    if missing:
        _stop("no aggregation rule for value column(s): %s. Pass `rule=` or "
              "register one with `%s`.", _preview(missing), hint)
    return out
