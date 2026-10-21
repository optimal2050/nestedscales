import json
import math
import warnings
from pathlib import Path

import pyarrow as pa
import pytest

import nestedscales as ns

GOLDENS = Path(__file__).resolve().parents[2] / "specs" / "goldens"


def load_golden(name):
    return json.loads((GOLDENS / name).read_text(encoding="utf-8"))["cases"]


def build_scale(k):
    """Rebuild a scale from a golden's `construct` entry."""
    if k["build"] == "scale_from_leaftable":
        tables = {t: golden_table(k[t]) for t in ("attributes", "aliases") if k.get(t)}
        return ns.scale_from_leaftable(pa.table(k["leaftable"]), frames=k["frames"],
                                       key=k["key"], name=k["name"],
                                       residuals=k.get("residuals"), **tables)
    return getattr(ns, k["build"])()


def golden_table(spec):
    """A table from a golden's column-wise `{columns, types}` entry."""
    return pa.table({
        name: pa.array(vals, pa.string() if spec["types"][name] == "string"
                       else pa.float64())
        for name, vals in spec["columns"].items()})


def norm(v):
    """Values comparable across bindings: NaN is null, floats to 10 digits."""
    if isinstance(v, float):
        return None if math.isnan(v) else float("%.10g" % v)
    if isinstance(v, dict):
        return {k: norm(z) for k, z in v.items()}
    if isinstance(v, (list, tuple)):
        return [norm(z) for z in v]
    return v


def rows(t):
    """Rows as hashable, normalised tuples."""
    if isinstance(t, pa.Table):
        t = t.to_pylist()
    elif not isinstance(t, list):
        t = ns.backend_pull(t).to_pylist()
    return [tuple(sorted((k, norm(v)) for k, v in r.items())) for r in t]


def rowset(t):
    """Rows of a table (or list of dicts) as a set, for order-free comparison."""
    return set(rows(t))


# Since R 0.2.0 both bindings spell source/target the same way, so golden
# arguments and messages are replayed verbatim; a difference is a defect.
def r_message(msg):
    """An R message, verbatim."""
    return msg


def call_args(args):
    """Golden arguments as Python call arguments: R's argument names
    translated, and numeric keys (R's unnamed list elements) positional."""
    if isinstance(args, list):
        return list(args), {}
    pos = [v for k, v in args.items() if k.isdigit()]
    kw = {k: v for k, v in args.items() if not k.isdigit()}
    return pos, kw


def replay(fn, pos, kw, case, compare):
    """Run a golden call: same error text, same warnings, same result."""
    with warnings.catch_warnings(record=True) as rec:
        warnings.simplefilter("always")
        if case["error"]:
            with pytest.raises(ns.NestedScalesError) as e:
                fn(*pos, **kw)
            assert str(e.value) == r_message(case["message"])
            return None
        got = fn(*pos, **kw)
    assert [str(w.message) for w in rec] == [r_message(w) for w in case["warnings"]]
    compare(got)
    return got


@pytest.fixture(autouse=True)
def _clean_registries():
    ns.clear_scale_rules()
    ns.clear_scale_maps()
    yield
    ns.clear_scale_rules()
    ns.clear_scale_maps()
