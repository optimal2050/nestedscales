# convert_scale(): row-wise conversion with a resolved attribute.

test_that("tonnes -> GJ multiplies row-wise by the resolved lhv", {
  es <- .fuels()
  mass <- data.frame(fuel = c("Anthracite", "Lignite", "Diesel", "Wood"),
                     t = c(1000, 5000, 200, 10))
  out <- convert_scale(mass, es, attribute = "lhv",
                       from_unit = "t", to_unit = "GJ")
  expect_equal(out$t, c(1000 * 26.7, 5000 * 11.9, 200 * 42.5, 10 * 15.0))
  expect_equal(out$lhv, c(26.7, 11.9, 42.5, 15.0))
  expect_equal(out$lhv.origin_frame, c("fuel", "fuel", "carrier", "group"))
  expect_equal(names(out), c("fuel", "t", "lhv", "lhv.origin_frame"))
})

test_that("the inverse works for a property and is refused for a factor", {
  es <- .fuels()
  energy <- data.frame(fuel = c("Anthracite", "Diesel"), gj = c(26700, 4250))
  back <- convert_scale(energy, es, attribute = "lhv",
                        from_unit = "GJ", to_unit = "t")
  expect_equal(back$gj, c(1000, 100))

  tj <- data.frame(fuel = c("Anthracite", "NaturalGas"), tj = c(1, 2))
  em <- convert_scale(tj, es, attribute = "ef_co2",
                      from_unit = "TJ", to_unit = "kg")
  expect_equal(em$tj, c(98300, 2 * 56100))
  expect_equal(em$ef_co2.origin_frame, c("fuel", "carrier"))
  expect_error(
    convert_scale(tj, es, attribute = "ef_co2", from_unit = "kg",
                  to_unit = "TJ"),
    "inverse is refused"
  )
})

test_that("a wrong unit pair errors, naming the direction", {
  expect_error(
    convert_scale(data.frame(fuel = "Anthracite", kt = 1), .fuels(),
                  attribute = "lhv", from_unit = "kt", to_unit = "GJ"),
    "converts t -> GJ"
  )
})

test_that("an unresolved unit errors by default and keeps NA on request", {
  es <- .fuels()
  d <- data.frame(fuel = c("Anthracite", "NaturalGas"), t = c(1, 1))
  expect_error(
    convert_scale(d, es, attribute = "lhv", from_unit = "t", to_unit = "GJ"),
    "no `lhv` value resolves for NaturalGas"
  )
  out <- convert_scale(d, es, attribute = "lhv", from_unit = "t",
                       to_unit = "GJ", na_action = "keep")
  expect_equal(out$t, c(26.7, NA))
})

test_that("unknown codes, collisions and non-numeric inputs are refused", {
  es <- .fuels()
  expect_error(
    convert_scale(data.frame(fuel = "Unobtainium", t = 1), es,
                  attribute = "lhv", from_unit = "t", to_unit = "GJ"),
    "not units of frame"
  )
  expect_error(
    convert_scale(data.frame(fuel = "Anthracite", t = 1, lhv = 0), es,
                  attribute = "lhv", from_unit = "t", to_unit = "GJ"),
    "never overwritten"
  )
  expect_error(
    convert_scale(data.frame(fuel = "Anthracite", note = "x"), es,
                  attribute = "lhv", from_unit = "t", to_unit = "GJ"),
    "no numeric value columns"
  )
  expect_error(
    convert_scale(data.frame(code = "Anthracite", t = 1), es,
                  attribute = "lhv", from_unit = "t", to_unit = "GJ"),
    "cannot infer the code frame"
  )
  expect_error(
    convert_scale(data.frame(code = c("Oil", "Bio"), t = c(10, 10)), es,
                  attribute = "lhv", from_unit = "t", to_unit = "GJ",
                  frame = "carrier", key = "code"),
    "not units of frame `carrier`"
  )
})

test_that("a code at a coarser frame converts with its own value", {
  d <- data.frame(code = c("Oil", "Biomass"), t = c(10, 10))
  out <- convert_scale(d, .fuels(), attribute = "lhv", from_unit = "t",
                       to_unit = "GJ", frame = "carrier", key = "code")
  expect_equal(out$t, c(425, 150))
  expect_equal(out$lhv.origin_frame, c("carrier", "group"))
})

test_that("the kind is read from the table, not from a catalogue", {
  s <- attach_attributes_scale(
    scale_example(),
    data.frame(frame = "sector", unit = c("P", "S"), attribute = "yield",
               value = c(2, 4), unit_of_measure = "kg/kg"),
    source = "t", kind = "factor"
  )
  d <- data.frame(unit = c("U1", "U5"), kg = c(1, 1))
  out <- convert_scale(d, s, attribute = "yield", from_unit = "kg",
                       to_unit = "kg")
  expect_equal(out$kg, c(2, 4))
})

test_that("tibble in, tibble out; data.table in, data.table out", {
  skip_if_not_installed("tibble")
  es <- .fuels()
  d <- tibble::tibble(fuel = c("Anthracite", "Lignite"), t = c(1, 2))
  out <- convert_scale(d, es, attribute = "lhv", from_unit = "t",
                       to_unit = "GJ")
  expect_s3_class(out, "tbl_df")
  expect_equal(out$t, c(26.7, 23.8))
  skip_if_not_installed("data.table")
  dt <- data.table::as.data.table(as.data.frame(d))
  out2 <- convert_scale(dt, es, attribute = "lhv", from_unit = "t",
                        to_unit = "GJ")
  expect_s3_class(out2, "data.table")
  expect_equal(out2$t, c(26.7, 23.8))
})

test_that("arrow in, lazy out unless collected", {
  skip_if_not_installed("arrow")
  skip_if_tier_below("fast")
  es <- .fuels()
  d <- arrow::arrow_table(data.frame(fuel = c("Anthracite", "Lignite"),
                                     t = c(1, 2)))
  q <- convert_scale(d, es, attribute = "lhv", from_unit = "t",
                     to_unit = "GJ")
  expect_true(backend_is_lazy(backend_of(q)))
  out <- convert_scale(d, es, attribute = "lhv", from_unit = "t",
                       to_unit = "GJ", collect = TRUE)
  expect_equal(as.data.frame(out)$t, c(26.7, 23.8))
})
