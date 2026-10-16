"""Replay specs/goldens/filter.json: filter/prune chains (the whole resulting
scale, including the sample bookkeeping), scale_share and join_scale."""
import pytest
from conftest import (
    build_scale,
    call_args,
    golden_table,
    load_golden,
    norm,
    replay,
    rows,
)

import nestedscales as ns

CASES = load_golden("filter.json")


def describe(s):
    m = s.meta
    return {
        "frames": list(s.frames), "key": s.key,
        "members": {k: list(v) for k, v in s.members.items()},
        "name": m.get("name"), "parent_name": m.get("parent_name"),
        "coverage": m.get("coverage"), "parent_totals": m.get("parent_totals"),
        "weights": list(m.get("weights") or ()),
        "default_weight": m.get("default_weight"),
    }


def label(c):
    if c["kind"] == "scale":
        return " > ".join("%s%s" % (st["fn"], st["args"]) for st in c["steps"])
    return "%s(%s)" % (c["fn"], c["args"])


@pytest.mark.parametrize("i", range(len(CASES)), ids=[label(c) for c in CASES])
def test_filter_golden(i):
    c = CASES[i]
    base = build_scale(c["scale"])
    if c["kind"] == "scale":
        def run():
            s = base
            for st in c["steps"]:
                pos, kw = call_args(st["args"])
                s = getattr(ns, st["fn"])(s, *pos, **kw)
            return s

        def compare(s):
            want = dict(c["value"])
            lt = want.pop("leaftable")
            assert norm(describe(s)) == norm(want)
            assert rows(s.leaftable) == rows(lt)

        replay_ignoring_warnings(run, c, compare)
        return

    pos, kw = call_args(c["args"])
    pos = ([golden_table(c["data"]), base] if c["data"] else [base]) + pos
    replay(getattr(ns, c["fn"]), pos, kw, c,
           lambda got: rows(got) == rows(c["value"]) or _fail(got, c))


def replay_ignoring_warnings(run, c, compare):
    import warnings

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        if c["error"]:
            with pytest.raises(ns.NestedScalesError) as e:
                run()
            assert str(e.value) == c["message"]
            return
        compare(run())


def _fail(got, c):
    assert rows(got) == rows(c["value"])
