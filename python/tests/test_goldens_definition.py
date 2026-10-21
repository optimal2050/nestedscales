"""Replay specs/goldens/definition.json: read every definition R wrote (single
JSON files, arrow and csv bundles), compare the scale, write it again and
compare the header with R's."""
import json

import pytest
from conftest import GOLDENS, load_golden, norm, rows

import nestedscales as ns

CASES = load_golden("definition.json")
DEFS = GOLDENS / "definitions"


def describe(s):
    m = s.meta
    tokens = m.get("tokens")
    return {
        "frames": list(s.frames), "key": s.key,
        "members": {k: list(v) for k, v in s.members.items()},
        "weights": list(m.get("weights") or ()),
        "default_weight": m.get("default_weight"),
        "name": m.get("name"), "desc": m.get("desc"),
        "tokens": None if tokens is None else dict(tokens),
    }


def header_of(path):
    if path.is_dir():
        path = path / "scale.json"
    hdr = json.loads(path.read_text(encoding="utf-8"))
    hdr.pop("nestedscales", None)  # the writing binding's version
    return hdr


def same_rows(got, want):
    assert sorted(rows(got), key=repr) == sorted(rows(want), key=repr)


@pytest.mark.parametrize("c", CASES, ids=[c["file"] for c in CASES])
def test_definition_golden(c, tmp_path):
    src = DEFS / c["file"]
    s = ns.read_scale(src)
    want = dict(c["value"])
    lt, at, al = (want.pop(k) for k in ("leaftable", "attributes", "aliases"))
    assert norm(describe(s)) == norm(want)
    assert rows(s.leaftable) == rows(lt)
    same_rows(s.attributes, at)
    same_rows(s.aliases, al)

    out = ns.write_scale(s, tmp_path / c["file"], tables=c["tables"])
    assert norm(header_of(out)) == norm(header_of(src))
    same_rows(ns.read_scale(out).leaftable, lt)
