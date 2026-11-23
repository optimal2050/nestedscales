"""Replay specs/goldens/labels.json: the label table (attach, read, look up,
join), its travel through filter / prune, and the printed scale, identity and
tree of scales that carry member tables (same errors, same rows)."""
import warnings

import pytest
from conftest import (
    build_scale,
    golden_table,
    load_golden,
    norm,
    printed,
    r_message,
    rows,
)
from test_goldens_attributes import decode_args, describe, label, run_steps, same_rows

import nestedscales as ns

CASES = load_golden("labels.json")


@pytest.mark.parametrize("i", range(len(CASES)),
                         ids=["%d %s" % (i, c["kind"] if c["kind"] == "print"
                                         else label(c)) for i, c in enumerate(CASES)])
def test_labels_golden(i):
    c = CASES[i]
    base = build_scale(c["scale"])

    def run():
        s = run_steps(base, c["steps"])
        if c["kind"] != "table":
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
    want = c["value"]
    if c["kind"] == "print":
        assert ns.scale_id(got) == want["id"]
        assert repr(got) == want["format"]
        assert printed(got) == printed(want["print"])
        tree = ns.scale_tree(got)
        assert tree.table.to_pylist() == want["tree"]
        assert tree.lines(ascii=True) == want["tree_lines"]
        return
    if c["kind"] == "scale":
        want = dict(want)
        at, al, lb = (want.pop(k) for k in ("attributes", "aliases", "labels"))
        want.setdefault("default_label", None)
        assert norm(describe(got)) == norm(want)
        same_rows(ns.scale_attributes(got), at)
        same_rows(ns.scale_aliases(got), al)
        assert rows(ns.scale_labels(got)) == rows(lb)  # stored order
        return
    assert [str(w.message) for w in rec] == [r_message(w) for w in c["warnings"]]
    if c["fn"] == "scale_label":
        # one name per code, in the order asked; R unboxes a single name
        assert got == (want if isinstance(want, list) else [want])
    else:
        assert rows(got) == rows(want)  # row order follows the table or the data
