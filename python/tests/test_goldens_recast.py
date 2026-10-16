"""Replay specs/goldens/recast.json: every rule, direction, NA path, warning
and error of the R recast engine."""
import pytest
from conftest import build_scale, call_args, golden_table, load_golden, replay, rows

import nestedscales as ns

CALLS = load_golden("recast.json")


def label(c):
    a = ", ".join("%s=%s" % kv for kv in c["args"].items() if kv[0] != "map")
    return "%s(%s)" % (c["fn"], a)


@pytest.mark.parametrize("i", range(len(CALLS)), ids=[label(c) for c in CALLS])
def test_recast_golden(i):
    c = CALLS[i]
    _, kw = call_args({k: v for k, v in c["args"].items()
                       if k not in ("to_scale", "map")})
    if "to_scale" in c["args"]:
        kw["target"] = build_scale(c["args"]["to_scale"])
    if "map" in c["args"]:
        kw["map"] = golden_table(c["args"]["map"])
    data = golden_table(c["data"])
    pos = [data] if c["scale"] is None else [data, build_scale(c["scale"])]

    def compare(got):
        want, have = rows(c["value"]), rows(got)
        if c["ordered"]:
            assert have == want
        else:
            assert sorted(have, key=repr) == sorted(want, key=repr)

    replay(getattr(ns, c["fn"]), pos, kw, c, compare)
