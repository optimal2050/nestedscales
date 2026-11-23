"""The dataset store: Python's own round trip, and the cross-language ones
(R writes -> Python reads -> Python writes -> R reads) for stores and for
definition files. The R half is skipped when Rscript or the R package's
dependencies are unavailable; the environment variable NESTEDSCALES_RSCRIPT
names the Rscript to run when the one on the path is not the one wanted."""
import os
import shutil
import subprocess
from pathlib import Path

import pyarrow as pa
import pyarrow.compute as pc
import pytest
from conftest import GOLDENS, load_golden, rows

import nestedscales as ns
from nestedscales import NestedScalesError

REPO = Path(__file__).resolve().parents[2]
R_SCRIPT = Path(__file__).with_name("r") / "roundtrip.R"
RSCRIPT = os.environ.get("NESTEDSCALES_RSCRIPT") or "Rscript"


def single_scale():
    lt = ns.scale_example().leaftable
    res = ns.scale_from_leaftable(lt, frames=["sector", "class", "group", "item"],
                                  leaf="item", name="example",
                                  residuals={"item": ["U6"]})
    return ns.filter_scale(res, "sector", ["P", "S"])


def single_data():
    codes = ["U1", "U2", "U3", "U4", "U5", "U6"]
    return pa.table({"item": codes * 2, "year": pa.array([2020] * 6 + [2021] * 6,
                                                         pa.int32()),
                     "cap": [i * 1.5 for i in [*range(1, 7), *range(11, 17)]]})


def product():
    return ns.scale_product(a=ns.scale_example(), b=ns.scale_example2())


def product_data():
    u, p = ["U1", "U2", "OTH"], ["p1", "p3"]
    pairs = [(a, b) for b in p for a in u]
    return pa.table({"item": [a for a, _ in pairs], "period": [b for _, b in pairs],
                     "v": [(i + 1) / 4 for i in range(len(pairs))]})


def same_scale(got, want):
    assert got.frames == want.frames and got.leaf == want.leaf
    assert got.members == want.members
    assert ns.scale_weights(got) == ns.scale_weights(want)
    assert ns.scale_residuals(got) == ns.scale_residuals(want)
    assert ns.scale_coverage(got) == pytest.approx(ns.scale_coverage(want))
    assert got.meta.get("name") == want.meta.get("name")
    assert rows(got.leaftable) == rows(want.leaftable)


def same_data(dset, want):
    got = dset.to_table().select(want.column_names)
    for c in got.column_names:
        if pa.types.is_dictionary(got.schema.field(c).type):
            got = got.set_column(got.column_names.index(c), c,
                                 pc.cast(got[c], got.schema.field(c).type.value_type))
    assert sorted(rows(got), key=repr) == sorted(rows(want), key=repr)


def test_python_round_trip(tmp_path):
    p = ns.write_scale_dataset(single_data(), single_scale(), tmp_path / "s",
                               partitioning="year")
    assert (p / "data" / "year=2020").is_dir()
    sd = ns.open_scale_dataset(p)
    same_scale(sd.scale, single_scale())
    same_data(sd.data, single_data())
    info = ns.scale_dataset_info(p)
    assert info["kind"] == "scale" and info["files"] == 2
    assert "scale over example[sector:P+S]" in str(sd)

    q = ns.write_scale_dataset(product_data(), product(), tmp_path / "p")
    pd_ = ns.open_scale_dataset(q)
    assert ns.scale_is_product(pd_.scale)
    assert ns.product_keys(pd_.scale) == {"a": "item", "b": "period"}
    same_scale(ns.scale_axes(pd_.scale, "a"), ns.scale_example())


def test_stored_data_recasts_without_redeclaring(tmp_path):
    ns.write_scale_dataset(single_data(), single_scale(), tmp_path / "s")
    sd = ns.open_scale_dataset(tmp_path / "s")
    got = ns.recast_scale(sd.data, sd.scale, source="item", target="class", rule="sum",
                          values="cap", collect=True)
    ref = ns.recast_scale(single_data(), single_scale(), source="item", target="class",
                          rule="sum", values="cap")
    assert sorted(rows(got), key=repr) == sorted(rows(ref), key=repr)


def test_store_refusals(tmp_path):
    ns.write_scale_dataset(single_data(), single_scale(), tmp_path / "s")
    with pytest.raises(NestedScalesError, match="already exists"):
        ns.write_scale_dataset(single_data(), single_scale(), tmp_path / "s")
    with pytest.raises(NestedScalesError, match="one key column per axis"):
        ns.write_scale_dataset(pa.table({"x": [1]}), single_scale(), tmp_path / "t")
    with pytest.raises(NestedScalesError, match="`partitioning` names column"):
        ns.write_scale_dataset(single_data(), single_scale(), tmp_path / "t",
                               partitioning="nope")
    s = ns.scale_example()
    bad = ns.NestedScale(leaftable=s.leaftable, frames=s.frames, members=s.members,
                         leaf=s.leaf, meta={**s.meta, "crs": object()})
    with pytest.raises(NestedScalesError, match="cannot be written: crs"):
        ns.write_scale_dataset(single_data(), bad, tmp_path / "u")
    with pytest.raises(NestedScalesError, match="is not a scale dataset"):
        ns.open_scale_dataset(tmp_path)


def _r_available():
    if shutil.which(RSCRIPT) is None:
        return False
    r = subprocess.run([RSCRIPT, "-e", "for (p in c('pkgload','arrow','yaml')) "
                        "stopifnot(requireNamespace(p, quietly = TRUE))"],
                       capture_output=True)
    return r.returncode == 0


@pytest.mark.skipif(not _r_available(), reason="Rscript with pkgload/arrow/yaml needed")
def test_cross_language_round_trip(tmp_path):
    run = subprocess.run([RSCRIPT, str(R_SCRIPT), str(REPO), "write", str(tmp_path)],
                         capture_output=True, text=True)
    assert run.returncode == 0, run.stderr

    # R -> Python
    rs = ns.open_scale_dataset(tmp_path / "r_single")
    same_scale(rs.scale, single_scale())
    same_data(rs.data, single_data())
    rp = ns.open_scale_dataset(tmp_path / "r_product")
    assert ns.product_keys(rp.scale) == {"a": "item", "b": "period"}
    same_scale(ns.scale_axes(rp.scale, "b"), ns.scale_example2())
    same_data(rp.data, product_data())

    # Python -> R
    ns.write_scale_dataset(single_data(), single_scale(), tmp_path / "py_single",
                           partitioning="year")
    ns.write_scale_dataset(product_data(), product(), tmp_path / "py_product")
    run = subprocess.run([RSCRIPT, str(R_SCRIPT), str(REPO), "check", str(tmp_path)],
                         capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    assert run.stdout.split("\n")[:2] == ["OK py_single", "OK py_product"], run.stdout


def _python_built(file):
    """The scales of the definition goldens that Python builds by itself,
    by file; the others are read from R's file and written again."""
    if file == "example.json":
        return ns.scale_example()
    if file == "linked.json":
        # a scale object in `meta`, which the writer turns into a reference
        return ns.scale_from_leaftable(ns.scale_example2().leaftable,
                                       frames=["era", "period"], name="linked",
                                       based_on=ns.scale_example())
    if file == "sample.json":
        return single_scale()
    return None


@pytest.mark.skipif(not _r_available(), reason="Rscript with pkgload/arrow/yaml needed")
def test_definitions_written_by_python_read_in_r(tmp_path):
    """Python -> R for definition files: every table, the whole of `meta` and
    the identity are what R reads from its own definition of the same scale.
    (R -> Python is test_goldens_definition.py.)"""
    cases = load_golden("definition.json")
    for c in cases:
        s = _python_built(c["file"])
        if s is None:
            s = ns.read_scale(GOLDENS / "definitions" / c["file"])
        ns.write_scale(s, tmp_path / c["file"], tables=c["tables"])
    run = subprocess.run([RSCRIPT, str(R_SCRIPT), str(REPO), "defs", str(tmp_path),
                          str(GOLDENS / "definitions")],
                         capture_output=True, text=True)
    assert run.returncode == 0, run.stderr
    assert sorted(run.stdout.split()) == sorted(
        w for c in cases for w in ("OK", c["file"])), run.stdout
