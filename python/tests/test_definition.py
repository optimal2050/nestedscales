"""Definition files: round trips in Python, the files R wrote
(specs/goldens/definitions), the vendored `carriers`, and the catalogue."""
import filecmp
import json
from pathlib import Path

import pyarrow as pa
import pytest
from conftest import rows

import nestedscales as ns
from nestedscales import NestedScalesError

REPO = Path(__file__).resolve().parents[2]
DEFS = REPO / "specs" / "goldens" / "definitions"
VENDORED = Path(ns.__file__).with_name("data")


def fuels():
    lt = pa.table({
        "group": ["Fossil"] * 5 + ["Bio"] * 3 + ["Power"],
        "phase": ["solid", "solid", "liquid", "liquid", "gas",
                  "solid", "liquid", "gas", None],
        "carrier": ["Coal", "Coal", "Oil", "Oil", "Gas",
                    "Biomass", "Biomass", "Biomass", "Electricity"],
        "fuel": ["Anthracite", "Lignite", "Diesel", "Gasoline", "NaturalGas",
                 "Wood", "Biodiesel", "Biogas", "Electricity"]})
    at = pa.table({
        "frame": ["fuel", "fuel", "carrier", "group", "fuel", "carrier"],
        "unit": ["Anthracite", "Lignite", "Oil", "Bio", "Anthracite", "Gas"],
        "attribute": ["lhv", "lhv", "lhv", "lhv", "ef_co2", "ef_co2"],
        "kind": ["property"] * 4 + ["factor"] * 2,
        "value": [26.7, 11.9, 42.5, 15.0, 98300.0, 56100.0],
        "lower": [21.6, 5.5, 40.0, 7.9, 94600.0, 54300.0],
        "upper": [32.2, 21.6, 45.0, 31.0, 101000.0, 58300.0],
        "unit_of_measure": ["GJ/t"] * 4 + ["kg/TJ"] * 2,
        "source": ["example"] * 6})
    al = pa.table({
        "frame": ["fuel", "carrier", "fuel", "carrier", "carrier"],
        "unit": ["Anthracite", "Coal", "Electricity", "Electricity", "Electricity"],
        "alias": ["hard coal", "coal", "elc", "elc", "power"],
        "source": ["example"] * 5})
    return ns.scale_from_leaftable(lt, frames=["group", "phase", "carrier", "fuel"],
                                   key="fuel", name="fuels", attributes=at,
                                   aliases=al, tokens={"group": "g", "carrier": "c"},
                                   flag=True)


def same(a, b, meta=True):
    assert a.frames == b.frames and a.key == b.key and a.members == b.members
    assert rows(a.leaftable) == rows(b.leaftable)
    assert rows(a.attributes) == rows(b.attributes)
    assert rows(a.aliases) == rows(b.aliases)
    if meta:
        assert a.meta == b.meta
    else:
        assert a.meta["name"] == b.meta["name"]


def test_single_file_round_trip(tmp_path):
    s = fuels()
    f = tmp_path / "fuels.json"
    ns.write_scale(s, f)
    hdr = json.loads(f.read_text(encoding="utf-8"))
    assert hdr["schema_version"] == 1
    assert hdr["class"] == "nestedscales::NestedScale"
    assert hdr["tables"]["attributes"]["inline"]["types"]["value"] == "double"
    assert hdr["tables"]["leaftable"]["inline"]["columns"]["phase"][8] is None
    assert hdr["meta_vectors"] == ["tokens"]
    same(ns.read_scale(f), s)
    with pytest.raises(NestedScalesError, match="already exists"):
        ns.write_scale(s, f)
    with pytest.raises(NestedScalesError, match="can only inline"):
        ns.write_scale(s, f, tables="arrow", overwrite=True)


def test_bundle_round_trip(tmp_path):
    s = fuels()
    d = tmp_path / "fuels.scale"
    ns.write_scale(s, d, tables="arrow")
    assert sorted(p.name for p in d.iterdir()) == [
        "aliases.arrow", "attributes.arrow", "leaftable.arrow", "scale.json"]
    same(ns.read_scale(d), s)
    with pytest.raises(NestedScalesError, match="already holds a definition"):
        ns.write_scale(s, d)
    ns.write_scale(s, d, tables="csv", overwrite=True)
    assert (d / "attributes.csv").is_file() and not (d / "attributes.arrow").exists()
    same(ns.read_scale(d), s)
    (tmp_path / "junk").mkdir()
    (tmp_path / "junk" / "x.txt").write_text("x")
    with pytest.raises(NestedScalesError, match="not a scale bundle"):
        ns.write_scale(s, tmp_path / "junk")


def test_yaml_in_and_out(tmp_path):
    s = fuels()
    ns.write_scale(s, tmp_path / "f.yaml", format="yaml")
    same(ns.read_scale(tmp_path / "f.yaml"), s)


def test_meta_refused_by_name(tmp_path):
    s = ns.scale_example()
    bad = ns.NestedScale(leaftable=s.leaftable, frames=s.frames, members=s.members,
                         key=s.key, meta={**s.meta, "crs": object()})
    with pytest.raises(NestedScalesError, match="cannot be written: crs"):
        ns.write_scale(bad, tmp_path / "bad.json")
    assert not (tmp_path / "bad.json").exists()


@pytest.mark.skipif(not DEFS.is_dir(), reason="R-written definitions not generated")
def test_reads_what_r_wrote():
    same(ns.read_scale(DEFS / "example.json"), ns.scale_example())
    same(ns.read_scale(DEFS / "fuels.json"), fuels(), meta=False)  # R's has no tokens
    grid = ns.read_scale(DEFS / "grid.scale")
    assert grid.frames == ("m", "h") and grid.leaftable.num_rows == 6


def test_vendored_carriers_is_the_r_file():
    r_file = REPO / "inst" / "scales" / "carriers.json"
    assert filecmp.cmp(r_file, VENDORED / "carriers.json", shallow=False)
    s = ns.read_scale("carriers")
    assert s.frames == ("group", "carrier", "fuel")
    assert s.leaftable.num_rows == 71
    assert s.attributes.num_rows == 26
    cat = {r["id"]: r for r in ns.scale_catalog()}
    assert cat["carriers"]["n_atoms"] == 71
    assert cat["carriers"]["package"] == "nestedscales"
    m = ns.scale_match(s, ["GAS", "LIG", "Hydrogen"])
    assert m["method"].to_pylist() == ["alias", "alias", "ambiguous"]
    out = ns.convert_scale(pa.table({"fuel": ["Anthracite"], "t": [1000.0]}), s,
                           "lhv", from_unit="t", to_unit="GJ")
    assert out["t"].to_pylist() == [26700.0]
    with pytest.raises(NestedScalesError, match="inverse is refused"):
        ns.convert_scale(pa.table({"fuel": ["Anthracite"], "tj": [1.0]}), s,
                         "ef_co2", from_unit="kg", to_unit="TJ")


def test_catalog_ids_and_ambiguity(tmp_path):
    d = tmp_path / "scales"
    d.mkdir()
    ns.write_scale(ns.scale_example2(), d / "carriers.json")
    key = ns.register_scale_dir(d, package="other")
    try:
        with pytest.raises(NestedScalesError, match="several packages"):
            ns.read_scale("carriers")
        s = ns.read_scale("carriers", package="other")
        assert s.frames == ns.scale_example2().frames
    finally:
        ns.clear_scale_dirs()
        ns.definition._register_shipped()
    assert key == "other"
