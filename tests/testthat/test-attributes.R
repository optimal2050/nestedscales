# Member attributes: the table, inheritance along the hierarchy, sources,
# the kind vocabulary, and the empty default on every scale.

test_that("every scale has an empty attribute table by default", {
  s <- scale_example()
  at <- scale_attributes(s)
  expect_s3_class(at, "data.frame")
  expect_identical(nrow(at), 0L)
  expect_named(at, c("frame", "unit", "attribute", "kind", "value", "lower",
                     "upper", "unit_of_measure", "source", "note"))
  expect_identical(nrow(scale_aliases(s)), 0L)
})

test_that("the stored table round-trips through the constructor", {
  es <- .fuels()
  at <- scale_attributes(es)
  expect_equal(nrow(at), 6L)
  expect_setequal(unique(at$attribute), c("lhv", "ef_co2"))
  expect_equal(nrow(scale_attributes(es, "lhv")), 4L)
  expect_equal(nrow(scale_attributes(es, source = "example")), 6L)
  expect_error(scale_attributes(es, "density"), "not stored")
  expect_error(scale_attributes(es, source = "nope"), "not stored")
})

test_that("inheritance: own value, then carrier, then group; NA otherwise", {
  es <- .fuels()
  r <- scale_attributes(es, "lhv", frame = "fuel")
  expect_equal(nrow(r), 9L)
  expect_equal(r$unit, scale_units(es))
  v <- stats::setNames(r$value, r$unit)
  expect_equal(v[["Anthracite"]], 26.7)
  expect_equal(v[["Diesel"]], 42.5)      # from carrier Oil
  expect_equal(v[["Wood"]], 15.0)        # from group Bio
  expect_true(is.na(v[["NaturalGas"]]))
  expect_true(is.na(v[["Electricity"]]))
  o <- stats::setNames(r$origin_frame, r$unit)
  expect_equal(o[["Anthracite"]], "fuel")
  expect_equal(o[["Diesel"]], "carrier")
  expect_equal(o[["Wood"]], "group")
  expect_true(is.na(o[["NaturalGas"]]))
  expect_equal(r$origin_unit[r$unit == "Wood"], "Bio")
  expect_equal(unique(r$kind[!is.na(r$value)]), "property")
})

test_that("a carrier resolves through a silent cross-cutting frame", {
  es <- .fuels()
  r <- scale_attributes(es, "lhv", frame = "carrier")
  v <- stats::setNames(r$value, r$unit)
  expect_equal(v[["Oil"]], 42.5)
  expect_equal(v[["Biomass"]], 15.0)   # phase holds nothing -> group
  expect_true(is.na(v[["Coal"]]))      # fuels have values, the carrier not
})

test_that("inherit = FALSE reports stored values only", {
  r <- scale_attributes(.fuels(), "lhv", frame = "fuel", inherit = FALSE)
  expect_equal(sum(!is.na(r$value)), 2L)
})

test_that("a cross-cutting ancestor that holds the attribute is ambiguous", {
  es <- attach_attributes_scale(
    .fuels(),
    data.frame(frame = "phase", unit = "gas", attribute = "lhv", value = 48,
               unit_of_measure = "GJ/t"),
    source = "example", kind = "property"
  )
  expect_error(scale_attributes(es, "lhv", frame = "carrier"), "ambiguous")
  r <- scale_attributes(es, "lhv", frame = "fuel")
  v <- stats::setNames(r$value, r$unit)
  expect_equal(v[["NaturalGas"]], 48)
  expect_equal(v[["Biogas"]], 48)          # phase is nearer than group
  expect_equal(r$origin_frame[r$unit == "Biogas"], "phase")
})

test_that("two sources for one member error unless `source=` selects", {
  es <- attach_attributes_scale(
    .fuels(),
    data.frame(frame = "fuel", unit = "Anthracite", attribute = "lhv",
               value = 27.5, unit_of_measure = "GJ/t"),
    source = "other", kind = "property"
  )
  expect_error(scale_attributes(es, "lhv", frame = "fuel"), "several sources")
  r1 <- scale_attributes(es, "lhv", frame = "fuel", source = "example")
  r2 <- scale_attributes(es, "lhv", frame = "fuel", source = "other")
  expect_equal(r1$value[r1$unit == "Anthracite"], 26.7)
  expect_equal(r2$value[r2$unit == "Anthracite"], 27.5)
  expect_true(is.na(r2$value[r2$unit == "Lignite"]))
})

test_that("resolution works at the key level of a product-shaped scale", {
  # the key is the atom level: no frame enumerates the atoms
  grid <- expand.grid(m = c("m1", "m2"), h = c("h1", "h2"),
                      stringsAsFactors = FALSE)
  grid$unit <- paste(grid$m, grid$h, sep = "_")
  s <- scale_from_leaftable(grid, frames = c("m", "h"), key = "unit",
                            name = "grid")
  s <- attach_attributes_scale(
    s, data.frame(frame = "m", unit = "m1", attribute = "price", value = 3,
                  unit_of_measure = "EUR/MWh"),
    source = "t", kind = "factor"
  )
  r <- scale_attributes(s, "price", frame = "unit")
  expect_equal(r$value[r$unit == "m1_h2"], 3)
  expect_true(is.na(r$value[r$unit == "m2_h1"]))
})

test_that("attach refuses collisions, bad kinds and mixed kinds", {
  es <- .fuels()
  expect_error(
    attach_attributes_scale(
      es, data.frame(frame = "fuel", unit = "Anthracite", attribute = "lhv",
                     value = 1, unit_of_measure = "GJ/t"),
      source = "example", kind = "property"),
    "never overwritten"
  )
  expect_error(
    attach_attributes_scale(
      es, data.frame(frame = "fuel", unit = "Lignite", attribute = "hhv",
                     value = 1, unit_of_measure = "GJ/t"),
      source = "x", kind = "ratio"),
    "kind"
  )
  expect_error(
    attach_attributes_scale(
      es, data.frame(frame = "fuel", unit = "Lignite", attribute = "lhv",
                     value = 1, unit_of_measure = "GJ/t"),
      source = "x", kind = "factor"),
    "one kind"
  )
  expect_error(
    attach_attributes_scale(
      es, data.frame(frame = "fuel", unit = "Lignite", attribute = "hhv",
                     value = 1, unit_of_measure = "GJ/t", source = "s"),
      source = "x", kind = "property"),
    "already has a `source`"
  )
  es2 <- attach_attributes_scale(
    es, data.frame(frame = "carrier", unit = "Coal", attribute = "hhv",
                   value = 28, unit_of_measure = "GJ/t"),
    source = "new", kind = "property")
  expect_equal(nrow(scale_attributes(es2)), 7L)
  expect_equal(nrow(scale_attributes(es)), 6L)   # input untouched
})

test_that("the validator rejects malformed tables with the vocabulary", {
  es <- .fuels()
  bad <- function(at) S7::prop(es, "attributes") <- at
  base <- S7::prop(es, "attributes")
  expect_error(bad(base[-1L]), "exactly the columns")
  x <- base; x$frame[1L] <- "nope"
  expect_error(bad(x), "frame\\(s\\) not in the object")
  x <- base; x$unit[1L] <- "Unobtainium"
  expect_error(bad(x), "not members")
  x <- base; x$value[1L] <- Inf
  expect_error(bad(x), "finite")
  x <- base; x$lower[1L] <- x$value[1L] + 1
  expect_error(bad(x), "lower <= value <= upper")
  x <- base; x$source[1L] <- ""
  expect_error(bad(x), "non-empty strings")
  expect_error(bad(rbind(base, base[1L, ])), "duplicate")
  expect_error(bad("not a table"), "data.frame or NULL")
})

test_that("SCALE_ATTRIBUTE_KINDS is the vocabulary", {
  expect_identical(SCALE_ATTRIBUTE_KINDS, c("property", "factor"))
})

test_that("print and summary report attributes and aliases when present", {
  es <- .fuels()
  expect_output(print(es), "Attributes: lhv, ef_co2")
  expect_output(print(es), "Aliases: 5")
  expect_no_match(paste(utils::capture.output(print(scale_example())),
                        collapse = "\n"), "Attributes")
  s <- summary(es)
  expect_named(s$attributes, c("attribute", "frame", "source", "n"))
  expect_equal(sum(s$attributes$n), 6L)
  expect_equal(s$aliases$n, 5L)
  expect_output(print(s), "lhv at fuel: 2 \\(example\\)")
  expect_output(print(s), "aliases:        example \\(5\\)")
})
