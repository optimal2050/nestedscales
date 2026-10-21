# The shipped `carriers` definition (inst/scales/carriers.json) and the IPCC
# table (inst/extdata/ipcc2006_fuel_defaults.csv). The definition is a
# snapshot of energypal's carriers palette, checked against it at build time
# by data-raw/check_energypal.R.

.ipcc <- function() {
  f <- system.file("extdata", "ipcc2006_fuel_defaults.csv",
                   package = "nestedscales")
  skip_if(!nzchar(f))
  utils::read.csv(f, stringsAsFactors = FALSE, na.strings = "")
}

test_that("carriers is in the catalogue and reads as a NestedScale", {
  cat <- scale_catalog()
  row <- cat[cat$id == "carriers", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$package, "nestedscales")
  expect_identical(row$frames, "group/carrier/fuel")
  expect_identical(row$n_atoms, 71L)
  s <- read_scale("carriers")
  expect_true(scale_is(s))
  expect_identical(S7::prop(s, "meta")[["name"]], "carriers")
})

test_that("carriers has the documented shape", {
  s <- read_scale("carriers")
  expect_identical(scale_frames(s), c("group", "carrier", "fuel"))
  expect_identical(scale_key(s), "fuel")
  expect_identical(nrow(scale_leaftable(s)), 71L)
  expect_identical(unname(vapply(S7::prop(s, "members"), length, 1L)),
                   c(8L, 17L, 71L))
  expect_true(scale_nests(s, "group", "carrier"))
  expect_true(scale_nests(s, "carrier", "fuel"))
  expect_identical(scale_weights(s), character())
  for (u in c("Electricity", "Heat", "Other")) {
    expect_identical(scale_children(s, "carrier", u), u)
  }
  # codes repeat across frames: every lookup names its frame
  expect_true("Nuclear" %in% scale_units(s, "group"))
  expect_true("Nuclear" %in% scale_units(s, "carrier"))
  expect_true("Hydrogen" %in% scale_units(s, "carrier"))
  expect_true("Hydrogen" %in% scale_units(s, "fuel"))
  lab <- S7::prop(s, "meta")[["labels"]]
  expect_s3_class(lab, "data.frame")
  expect_named(lab, c("frame", "unit", "label_short", "label_long"))
  expect_identical(lab$label_short[lab$frame == "carrier" & lab$unit == "FossilCoal"],
                   "Coal")
  expect_true(nzchar(S7::prop(s, "meta")[["palette_version"]]))
})

test_that("the attributes are the mapped primary IPCC rows, in GJ/t and kg/TJ", {
  s <- read_scale("carriers")
  at <- scale_attributes(s)
  expect_setequal(unique(at$source), "IPCC2006")
  expect_setequal(unique(at$frame), "fuel")
  expect_identical(unique(at$unit_of_measure[at$attribute == "lhv"]), "GJ/t")
  expect_identical(unique(at$unit_of_measure[at$attribute == "ef_co2"]), "kg/TJ")
  expect_identical(unique(at$kind[at$attribute == "lhv"]), "property")
  expect_identical(unique(at$kind[at$attribute == "ef_co2"]), "factor")
  d <- .ipcc()
  want <- d[d$mapping_status == "mapped" & d$primary & !is.na(d$value), ]
  expect_identical(nrow(at), nrow(want))
  expect_setequal(paste(at$unit, at$attribute, at$value),
                  paste(want$unit, want$attribute, want$value))
  r <- scale_attributes(s, "lhv", frame = "fuel")
  expect_equal(r$value[r$unit == "Anthracite"], 26.7)
  expect_equal(r$value[r$unit == "Lignite"], 11.9)
  expect_equal(r$value[r$unit == "NaturalGas"], 48.0)
  e <- scale_attributes(s, "ef_co2", frame = "fuel")
  expect_equal(e$value[e$unit == "Lignite"], 101000)
  expect_true(is.na(r$value[r$unit == "SolarPV"]))   # no guess
})

test_that("the IPCC table is complete and consistent", {
  d <- .ipcc()
  expect_named(d, c("ipcc_fuel", "attribute", "kind", "value", "lower", "upper",
                    "unit_of_measure", "table", "source", "frame", "unit",
                    "mapping_status", "primary"))
  expect_identical(nrow(d), 2L * 53L)
  expect_identical(sum(is.na(d$value)), 1L)
  expect_identical(d$ipcc_fuel[is.na(d$value)], "Industrial Wastes")
  ok <- !is.na(d$value)
  expect_true(all(d$lower[ok] <= d$value[ok] & d$value[ok] <= d$upper[ok]))
  expect_true(all(d$mapping_status %in% c("mapped", "review", "unmapped")))
  expect_true(all(!is.na(d$frame[d$mapping_status == "mapped"])))
  expect_true(all(is.na(d$frame[d$mapping_status == "unmapped"])))
  prim <- d[d$mapping_status == "mapped" & d$primary & d$attribute == "lhv", ]
  expect_false(anyDuplicated(paste(prim$frame, prim$unit)) > 0)
})

test_that("carriers converts and resolves commodity codes", {
  s <- read_scale("carriers")
  m <- scale_match(s, c("GAS", "LIG", "ELC", "coal", "Hydrogen"))
  expect_identical(m$method, c("alias", "alias", "alias", "alias", "ambiguous"))
  expect_identical(m$unit[1:4], c("FossilGas", "Lignite", "Electricity",
                                  "FossilCoal"))
  expect_identical(scale_match(s, "Hydrogen", frame = "carrier")$method, "exact")
  mass <- data.frame(fuel = c("Anthracite", "Lignite"), t = c(1000, 1000))
  gj <- convert_scale(mass, s, "lhv", from_unit = "t", to_unit = "GJ")
  expect_equal(gj$t, c(26700, 11900))
  expect_error(convert_scale(data.frame(fuel = "Anthracite", tj = 1), s,
                             "ef_co2", from_unit = "kg", to_unit = "TJ"),
               "inverse is refused")
})
