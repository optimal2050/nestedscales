"""Replay specs/goldens/attributes.json: stored and resolved attributes,
aliases and strict matching, row-wise conversion, and the member tables
travelling through attach / filter / prune (same errors, same rows)."""
import warnings

import pytest
from conftest import (
    build_scale,
    call_args,
    golden_table,
    load_golden,
    norm,
    r_message,
    rows,
)

import nestedscales as ns

CASES = load_golden("attributes.json")


def _is_table(v):
    return isinstance(v, dict) and set(v) == {"columns", "types"}


def decode_args(args):
    """Golden arguments with column-wise tables turned into Arrow tables."""
    pos, kw = call_args(args)
    dec = lambda v: golden_table(v) if _is_table(v) else v  # noqa: E731
    return [dec(v) for v in pos], {k: dec(v) for k, v in kw.items()}


def run_steps(s, steps):
    for st in steps:
        pos, kw = decode_args(st["args"])
        s = getattr(ns, st["fn"])(s, *pos, **kw)
    return s


def describe(s):
    return {
        "frames": list(s.frames), "key": s.key,
        "members": {k: list(v) for k, v in s.members.items()},
    }


def label(c):
    pre = "".join("%s > " % st["fn"] for st in c["steps"])
    if c["kind"] == "scale":
        return pre.rstrip(" >")
    args = c["args"] if isinstance(c["args"], dict) else {}  # [] = no arguments
    a = ", ".join("%s=%s" % kv for kv in args.items() if not _is_table(kv[1]))
    return "%s%s(%s)" % (pre, c["fn"], a)


def same_rows(got, want):
    assert sorted(rows(got), key=repr) == sorted(rows(want), key=repr)


@pytest.mark.parametrize("i", range(len(CASES)), ids=[label(c) for c in CASES])
def test_attributes_golden(i):
    c = CASES[i]
    base = build_scale(c["scale"])

    def run():
        s = run_steps(base, c["steps"])
        if c["kind"] == "scale":
            return s
        pos, kw = decode_args(c["args"])
        pos = ([golden_table(c["data"]), s] if c["data"] else [s]) + pos
        return getattr(ns, c["fn"])(*pos, **kw)

    with warnings.catch_warnings(record=True) as rec:
        warnings.simplefilter("always")
        if c["error"]:
            with pytest.raises(ns.NestedScalesError) as e:
                run()
            assert str(e.value) == r_message(c["message"])
            return
        got = run()
    if c["kind"] == "scale":
        want = dict(c["value"])
        at, al = want.pop("attributes"), want.pop("aliases")
        assert norm(describe(got)) == norm(want)
        same_rows(ns.scale_attributes(got), at)
        same_rows(ns.scale_aliases(got), al)
        return
    assert [str(w.message) for w in rec] == [r_message(w) for w in c["warnings"]]
    if c["fn"] in ("scale_match", "convert_scale"):
        assert rows(got) == rows(c["value"])  # row order follows the input
    else:
        same_rows(got, c["value"])
