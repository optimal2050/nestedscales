"""Backends, laziness, batching, and the parts of the recast contract the
goldens (eager pyarrow only) do not reach."""
import pyarrow as pa
import pyarrow.dataset as ds
import pytest

import nestedscales as ns
from nestedscales import NestedScalesError

U = ["U1", "U2", "U3", "U4", "U5", "U6", "OTH"]


def panel():
    return pa.table({"unit": U[:6] * 2, "year": [2020] * 6 + [2021] * 6,
                     "cap": [float(i) for i in range(12)]})


def canon(t):
    if not isinstance(t, pa.Table):
        t = ns.as_table(t)
    return sorted(map(repr, t.to_pylist()))


def test_pandas_and_polars_round_trip_their_type():
    pd = pytest.importorskip("pandas")
    pl = pytest.importorskip("polars")
    s, t = ns.scale_example(), panel()
    ref = ns.recast_scale(t, s, from_="unit", to="class", rule="sum", values="cap")
    got_pd = ns.recast_scale(t.to_pandas(), s, from_="unit", to="class", rule="sum",
                             values="cap")
    assert isinstance(got_pd, pd.DataFrame)
    got_pl = ns.recast_scale(pl.from_arrow(t), s, from_="unit", to="class",
                             rule="sum", values="cap")
    assert isinstance(got_pl, pl.DataFrame)
    assert canon(got_pd) == canon(ref) == canon(got_pl)


def test_lazy_inputs_return_observed_rows_unless_collected(tmp_path):
    pl = pytest.importorskip("polars")
    s = ns.scale_example()
    d = pa.table({"unit": ["U1"], "value": [1.0]})
    eager = ns.recast_scale(d, s, from_="unit", to="class", rule="sum",
                            diagnostics="off")
    assert eager.num_rows == 3

    lazy = ns.recast_scale(pl.from_arrow(d).lazy(), s, from_="unit", to="class",
                           rule="sum")
    assert isinstance(lazy, pl.LazyFrame)
    assert lazy.collect().to_dicts() == [{"class": "G1", "value": None}]

    ds.write_dataset(d, tmp_path, format="ipc")
    dset = ds.dataset(tmp_path, format="ipc")
    assert ns.recast_scale(dset, s, from_="unit", to="class",
                           rule="sum").num_rows == 1
    full = ns.recast_scale(dset, s, from_="unit", to="class", rule="sum",
                           collect=True)
    assert full.equals(eager)


def test_lazy_skips_diagnostics_by_default(tmp_path):
    s = ns.scale_example()
    d = pa.table({"unit": ["U1", "ZZ"], "value": [1.0, 2.0]})
    ds.write_dataset(d, tmp_path, format="parquet")
    dset = ds.dataset(tmp_path, format="parquet")
    ns.recast_scale(dset, s, from_="unit", to="class", rule="sum")  # no warning
    with pytest.warns(ns.NestedScalesWarning, match="not present at frame"):
        ns.recast_scale(dset, s, from_="unit", to="class", rule="sum",
                        diagnostics="on")


def test_batching_does_not_change_numbers(tmp_path):
    s, t = ns.scale_example(), panel()
    ref = ns.recast_scale(t, s, from_="unit", to="sector", rule="sum",
                          values="cap", diagnostics="off")
    got = ns.recast_scale(t, s, from_="unit", to="sector", rule="sum", values="cap",
                          batch=1)
    assert canon(got) == canon(ref)
    ds.write_dataset(t, tmp_path, format="ipc", partitioning=["year"],
                     partitioning_flavor="hive")
    dset = ds.dataset(tmp_path, format="ipc", partitioning="hive")
    got_ds = ns.recast_scale(dset, s, from_="unit", to="sector", rule="sum",
                             values="cap", batch=1, collect=True)
    assert sorted(r["cap"] for r in got_ds.to_pylist()) == \
        sorted(r["cap"] for r in ref.to_pylist())


def test_batch_argument_errors(tmp_path):
    s, t = ns.scale_example(), panel()
    with pytest.raises(NestedScalesError, match="`batch_by` must be an identifier"):
        ns.recast_scale(t, s, from_="unit", to="class", rule="sum", values="cap",
                        batch=1, batch_by="cap")
    ds.write_dataset(t, tmp_path, format="ipc")
    with pytest.raises(NestedScalesError, match="applies when materialising"):
        ns.recast_scale(ds.dataset(tmp_path, format="ipc"), s, from_="unit",
                        to="class", rule="sum", values="cap", batch=1)


def test_registered_crosswalk_defines_the_expected_sources():
    s = ns.scale_example()
    one = pa.table({"unit": ["U1"], "class": ["G1"], "n_from": [1], "n_overlap": [1],
                    "w": [1.0], "w_from": [1.0]})
    ns.register_scale_map(s, "unit", "class", one)
    out = ns.recast_scale(pa.table({"unit": ["U1"], "value": [1.0]}), s,
                          from_="unit", to="class", rule="sum")
    assert [r["value"] for r in out.to_pylist() if r["class"] == "G1"] == [1.0]


def test_registry_supplies_the_rule():
    ns.register_scale_rule("cap", "sum")
    out = ns.recast_scale(pa.table({"sector": ["P", "S"], "cap": [10.0, 20.0]}),
                          ns.scale_example(), to="class")
    assert out["cap"].to_pylist() == pytest.approx([3.0, 7.0, 20.0])


def test_recast_generic_dispatches_on_the_scale():
    s = ns.scale_example()
    d = pa.table({"unit": U[:6], "capacity": [1.0, 2, 3, 4, 5, 6]})
    a = ns.recast(d, s, to="sector", rule="sum")
    b = ns.recast_scale(d, s, to="sector", rule="sum")
    assert a.equals(b)


def test_reserved_columns_are_refused():
    s = ns.scale_example()
    for bad in (".ms_to", "__ms_x"):
        with pytest.raises(NestedScalesError, match="reserved column name"):
            ns.recast_scale(pa.table({"unit": ["U1"], bad: [1.0], "v": [1.0]}), s,
                            from_="unit", to="class", rule="sum", values="v")


def test_dictionary_keys_are_accepted():
    s = ns.scale_example()
    t = pa.table({"unit": pa.array(U[:6]).dictionary_encode(),
                  "v": [1.0, 2, 3, 4, 5, 6]})
    out = ns.recast_scale(t, s, to="sector", rule="sum")
    assert out["v"].to_pylist() == [10.0, 11.0]
