#' Shipped definitions: `carriers` and the IPCC 2006 fuel defaults
#'
#' nestedscales ships one scale definition, `carriers`, under
#' `inst/scales/`, and the IPCC tables it draws on under `inst/extdata/`.
#' `read_scale("carriers")` reads the scale; [`scale_catalog()`] lists it
#' with every other registered definition.
#'
#' @section carriers:
#' A scale of 71 fuels in three nested frames,
#' `group (8) > carrier (17) > fuel (71)`, key `fuel`, taken from the
#' `carriers` palette of the energypal package (its
#' `inst/extdata/palettes/carriers.yml`, which cites the IPCC 2006
#' Guidelines and the IEA World Energy Balances for its classification).
#' energypal remains the editable source of the names, hierarchy, labels
#' and aliases; the definition is a snapshot built by `data-raw/carriers.R`,
#' which stops when the two disagree.
#'
#' The three carriers energypal declares without subtypes (`Electricity`,
#' `Heat`, `Other`) become their own fuel, so every carrier is reachable
#' from the atoms. Five names appear both as a group and as the carrier
#' inside it (`Nuclear`, `Electricity`, `Heat`, `Storage`, `Other`), and
#' `Hydrogen` is both a carrier (under `Synthetic`) and a fuel (under
#' `Storage`): every lookup names its frame.
#'
#' **Attributes** (source `"IPCC2006"`, 26 rows): the default net calorific
#' value `lhv` (kind `property`, GJ/t) and CO2 emission factor `ef_co2`
#' (kind `factor`, kg/TJ) of the IPCC 2006 Guidelines, Vol. 2 Ch. 1,
#' Tables 1.2 and 1.4, attached to the 13 fuels whose definition matches an
#' IPCC fuel exactly. Fuels without a matching IPCC entry carry no value;
#' [`scale_attributes()`] reports them as `NA` rather than inventing one.
#'
#' **Aliases** (136 rows): energypal's alternative spellings (source
#' `"energypal"`) and a set of model commodity codes such as `GAS`, `LIG`,
#' `ELC` (source `"commodity"`). [`scale_match()`] resolves them.
#'
#' `meta$labels` carries energypal's short and long labels per member;
#' `meta$energypal_version` and `meta$palette_version` record the snapshot.
#' Colours are not stored: join them from energypal by name.
#'
#' @section IPCC 2006 default calorific values and CO2 emission factors:
#' `system.file("extdata", "ipcc2006_fuel_defaults.csv", package =
#' "nestedscales")` holds every row of Table 1.2 (default net calorific
#' values, TJ/Gg, with the lower and upper limits of the 95% confidence
#' interval) and Table 1.4 (default CO2 emission factors for combustion,
#' kg/TJ, with the 95% interval) of the IPCC 2006 Guidelines, Vol. 2
#' (Energy), Chapter 1, in long form, together with how each IPCC fuel maps
#' onto `carriers`. TJ/Gg is numerically identical to GJ/t, the unit the
#' `lhv` attribute uses. One row per IPCC fuel and attribute:
#' \describe{
#'   \item{`ipcc_fuel`}{The fuel's English description in the Guidelines.}
#'   \item{`attribute`}{`"lhv"` (Table 1.2) or `"ef_co2"` (Table 1.4).}
#'   \item{`kind`}{`"property"` or `"factor"`, see [`SCALE_ATTRIBUTE_KINDS`].}
#'   \item{`value`, `lower`, `upper`}{The default and its 95% interval.}
#'   \item{`unit_of_measure`}{`"GJ/t"` or `"kg/TJ"`.}
#'   \item{`table`}{`"1.2"` or `"1.4"`.}
#'   \item{`source`}{`"IPCC2006"`.}
#'   \item{`frame`, `unit`}{The `carriers` member the row maps to (`NA`
#'     when not mapped).}
#'   \item{`mapping_status`}{`"mapped"` (an exact or definitional
#'     correspondence), `"review"` (a plausible correspondence awaiting a
#'     ruling; not attached) or `"unmapped"` (no counterpart).}
#'   \item{`primary`}{Whether this IPCC fuel is the one `carriers` carries
#'     for that member. Only `mapped` rows with `primary = TRUE` enter the
#'     scale's attributes.}
#' }
#'
#' @source energypal `carriers.yml`; IPCC (2006), *2006 IPCC Guidelines for
#'   National Greenhouse Gas Inventories*, Volume 2 (Energy), Chapter 1,
#'   Tables 1.2 and 1.4, <https://www.ipcc-nggip.iges.or.jp/public/2006gl/>.
#'   Transcribed in `data-raw/ipcc2006/`.
#' @examples
#' carriers <- read_scale("carriers")
#' carriers
#' scale_units(carriers, "carrier")
#' scale_attributes(carriers, "lhv", frame = "fuel")
#' scale_match(carriers, c("GAS", "LIG", "Hydrogen"))
#'
#' ipcc <- read.csv(system.file("extdata", "ipcc2006_fuel_defaults.csv",
#'                              package = "nestedscales"))
#' table(ipcc$attribute, ipcc$mapping_status)
#' @seealso [`read_scale()`], [`scale_catalog()`], [`convert_scale()`];
#'   `vignette("attributes")`.
#' @name shipped_scales
NULL
