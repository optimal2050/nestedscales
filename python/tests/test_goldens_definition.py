"""Replay specs/goldens/definition.json: read every definition R wrote (single
JSON files, arrow and csv bundles; schema version 2), compare the scale and
its identity, write it again and compare the header with R's.

specs/goldens/definitions_v1/ holds definitions of schema version 1;
definition_v1.json says what each reads back as."""
import json

import pytest
from conftest import GOLDENS, load_golden, norm, rows

import nestedscales as ns

CASES = load_golden("definition.json")
CASES_V1 = load_golden("definition_v1.json")
DEFS = GOLDENS / "definitions"
DEFS_V1 = GOLDENS / "definitions_v1"


def describe(s):
    m = s.meta
    tokens = m.get("tokens")
    res = m.get("residuals")
    return {
        "frames": list(s.frames), "leaf": s.leaf,
        "members": {k: list(v) for k, v in s.members.items()},
        "weights": list(m.get("weights") or ()),
        "default_weight": m.get("default_weight"),
        "default_label": m.get("default_label"),
        "name": m.get("name"), "desc": m.get("desc"),
        "tokens": None if tokens is None else dict(tokens),
        "parent_name": m.get("parent_name"),
        "coverage": m.get("coverage"), "parent_totals": m.get("parent_totals"),
        # R unboxes a single code
        "residuals": None if res is None else {
            k: (v[0] if len(v) == 1 else list(v)) for k, v in res.items()},
        "refs": {k: v for k, v in m.items()
                 if isinstance(v, dict) and list(v) == ["_scale"]},
        "id": ns.scale_id(s),
    }


def header_of(path):
    if path.is_dir():
        path = path / "scale.json"
    hdr = json.loads(path.read_text(encoding="utf-8"))
    hdr.pop("nestedscales", None)  # the writing binding's version
    return hdr


def same_rows(got, want):
    assert sorted(rows(got), key=repr) == sorted(rows(want), key=repr)


def check(s, value):
    want = dict(value)
    lt, at, al, lb = (want.pop(k) for k in ("leaftable", "attributes", "aliases",
                                            "labels"))
    want.setdefault("default_label", None)
    if isinstance(want.get("residuals"), dict):
        want["residuals"] = {k: (v[0] if isinstance(v, list) and len(v) == 1 else v)
                             for k, v in want["residuals"].items()}
    if want.get("refs") in ([], None):
        want["refs"] = {}
    assert norm(describe(s)) == norm(want)
    assert rows(s.leaftable) == rows(lt)
    same_rows(s.attributes, at)
    same_rows(s.aliases, al)
    same_rows(s.labels, lb)
    return lt


@pytest.mark.parametrize("c", CASES, ids=[c["file"] for c in CASES])
def test_definition_golden(c, tmp_path):
    src = DEFS / c["file"]
    assert header_of(src)["schema_version"] == 2
    s = ns.read_scale(src)
    lt = check(s, c["value"])

    out = ns.write_scale(s, tmp_path / c["file"], tables=c["tables"])
    assert norm(header_of(out)) == norm(header_of(src))
    back = ns.read_scale(out)
    same_rows(back.leaftable, lt)
    assert ns.scale_id(back) == c["value"]["id"]


@pytest.mark.parametrize("c", CASES_V1, ids=[c["file"] for c in CASES_V1])
def test_definition_schema_1(c, tmp_path):
    src = DEFS_V1 / c["file"]
    hdr = header_of(src)
    assert hdr["schema_version"] == 1 and "key" in hdr and "leaf" not in hdr
    s = ns.read_scale(src)
    check(s, c["value"])
    assert s.leaf == hdr["key"]
    for t in (s.attributes, s.aliases):
        assert "member" in t.column_names and "unit" not in t.column_names

    # written back, it is a schema 2 definition of the same scale
    out = ns.write_scale(s, tmp_path / c["file"])
    again = header_of(out)
    assert again["schema_version"] == 2 and again["leaf"] == hdr["key"]
    assert "key" not in again
    check(ns.read_scale(out), c["value"])


def test_meta_scale_is_written_as_a_reference(tmp_path):
    ex = ns.scale_example()
    s = ns.scale_from_leaftable(ns.scale_example2().leaftable,
                                frames=["era", "period"], name="linked",
                                based_on=ex)
    out = ns.write_scale(s, tmp_path / "linked.json")
    assert norm(header_of(out)) == norm(header_of(DEFS / "linked.json"))
    back = ns.read_scale(out)
    assert back.meta["based_on"] == {"_scale": {"name": "example",
                                                "id": ns.scale_id(ex)}}
    assert ns.scale_id(back) == ns.scale_id(s)


def test_newer_schema_is_refused(tmp_path):
    hdr = json.loads((DEFS / "example.json").read_text(encoding="utf-8"))
    hdr["schema_version"] = 3
    f = tmp_path / "future.json"
    f.write_text(json.dumps(hdr), encoding="utf-8")
    with pytest.raises(ns.NestedScalesError, match="reads up to 2"):
        ns.read_scale(f)
