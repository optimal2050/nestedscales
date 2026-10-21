# IPCC 2006 default factors

Transcribed from the *2006 IPCC Guidelines for National Greenhouse Gas
Inventories*, Volume 2 (Energy), Chapter 1 (Introduction):

| file | table | page | content |
|---|---|---|---|
| `table1-2_ncv.csv` | Table 1.2 | 1.18-1.19 | default net calorific values (TJ/Gg) with the lower and upper limits of the 95% confidence interval |
| `table1-4_ef_co2.csv` | Table 1.4 | 1.23-1.24 | default carbon content (kg/GJ) and effective CO2 emission factor (kg/TJ, full oxidation) with the 95% interval |
| `ipcc_to_energypal.csv` | -- | -- | how each IPCC fuel maps onto the energypal `carriers` taxonomy |

Source PDF: <https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/2_Volume2/V2_1_Ch1_Introduction.pdf>

Transcription date: 2026-10-09, from the PDF page images. Row count: 53
fuels in each table. **To be checked by the maintainer before the row
count is pinned in `data-raw/ipcc2006_fuel_defaults.R`.**

## Units

TJ/Gg (terajoule per gigagram) is numerically identical to GJ/t (gigajoule
per tonne) and to MJ/kg; the `lhv` attribute is stored as `GJ/t`, the unit
energyRt's commodity properties use. The CO2 factor is kg/TJ on a net
calorific basis (1 TJ = 1000 GJ), assuming full oxidation (Table 1.4
oxidation factor = 1).

`Industrial Wastes` has no default NCV in Table 1.2 (NA); its emission
factor exists.

## Mapping policy

`ipcc_to_energypal.csv` places an IPCC fuel on an energypal member only
where the correspondence is exact or definitional; everything else is
`review` (a plausible candidate, listed with its reasoning in `note`) or
`unmapped`. Only `mapped` rows with `primary = TRUE` enter
the `carriers` definition. One `primary` per member.

Country-specific calorific values (Eurostat, national inventories) are a
different `source` attached with `attach_attributes_scale()`, not an
edit to these files.
