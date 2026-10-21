# =========================================================================== #
# recast_scale(): the conversion engine.
#
# Aggregation and disaggregation are one operation, so most tests state a
# CONSERVATION or IDENTITY law rather than a hard-coded number.
# =========================================================================== #

.d6 <- function(v = c(1, 2, 3, 4, 5, 6)) {
  data.frame(
    unit = c("U1", "U2", "U3", "U4", "U5", "U6"), value = v,
    stringsAsFactors = FALSE
  )
}

test_that("sum conserves the total going up", {
  s <- scale_example()
  out <- recast_scale(.d6(), s, source = "unit", target = "sector", rule = "sum")
  expect_named(out, c("sector", "value"))
  # U1..U4 are sector P (1+2+3+4), U5..U6 are S (5+6); OTH has no sector
  expect_equal(out$value[out$sector == "P"], 10)
  expect_equal(out$value[out$sector == "S"], 11)
  expect_equal(sum(out$value, na.rm = TRUE), 21)
})

test_that("sum splits proportionally to the weight going down", {
  s <- scale_example()
  y <- data.frame(
    sector = c("P", "S"), value = c(10, 20),
    stringsAsFactors = FALSE
  )
  out <- recast_scale(y, s,
    source = "sector", target = "class", rule = "sum",
    weight = "size"
  )
  # P's classes: G1 (size 100+200) and G2 (300+400) -> 3/7 and 4/7 of 10
  expect_equal(out$value[out$class == "G1"], 10 * 300 / 1000)
  expect_equal(out$value[out$class == "G2"], 10 * 700 / 1000)
  # S has one class, so it takes all 20
  expect_equal(out$value[out$class == "S1"], 20)
  expect_equal(sum(out$value, na.rm = TRUE), 30)
})

test_that("down-then-up round-trips an extensive quantity", {
  s <- scale_example()
  y <- data.frame(
    sector = c("P", "S"), value = c(10, 20),
    stringsAsFactors = FALSE
  )
  down <- recast_scale(y, s,
    source = "sector", target = "unit", rule = "sum",
    weight = "size"
  )
  # `down` is completed to the full unit vocabulary, so it carries an NA row
  # for the unassigned atom -- the return trip warns about it, as designed
  up <- suppressWarnings(
    recast_scale(down, s, source = "unit", target = "sector", rule = "sum")
  )
  expect_equal(up$value[up$sector == "P"], 10)
  expect_equal(up$value[up$sector == "S"], 20)
})

test_that("weighted_mean weights by the atom weight, mean does not", {
  s <- scale_example()
  d <- .d6()
  wm <- recast_scale(d, s,
    source = "unit", target = "class",
    rule = "weighted_mean", weight = "size"
  )
  mn <- recast_scale(d, s, source = "unit", target = "class", rule = "mean")
  # class G1 = U1 (size 100, v 1) and U2 (size 200, v 2)
  expect_equal(wm$value[wm$class == "G1"], (1 * 100 + 2 * 200) / 300)
  expect_equal(mn$value[mn$class == "G1"], 1.5)
  # they differ exactly because the weights differ
  expect_false(isTRUE(all.equal(
    wm$value[wm$class == "G1"],
    mn$value[mn$class == "G1"]
  )))
})

test_that("weighted_mean is invariant going down and back up", {
  s <- scale_example()
  z <- data.frame(
    class = c("G1", "G2", "S1"), eff = c(0.3, 0.5, 0.6),
    stringsAsFactors = FALSE
  )
  down <- recast_scale(z, s,
    source = "class", target = "unit",
    rule = "weighted_mean", weight = "size"
  )
  up <- suppressWarnings(
    recast_scale(down, s,
      source = "unit", target = "class",
      rule = "weighted_mean", weight = "size"
    )
  )
  expect_equal(up$eff[up$class == "G1"], 0.3)
  expect_equal(up$eff[up$class == "G2"], 0.5)
  expect_equal(up$eff[up$class == "S1"], 0.6)
})

test_that("copy requires constancy within a target unit", {
  s <- scale_example()
  ok <- data.frame(
    unit = c("U1", "U2"), r = c(0.5, 0.5),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(ok, s, source = "unit", target = "class", rule = "copy")
  )
  expect_equal(out$r[out$class == "G1"], 0.5)

  bad <- data.frame(
    unit = c("U1", "U2"), r = c(0.5, 0.9),
    stringsAsFactors = FALSE
  )
  expect_error(
    suppressWarnings(
      recast_scale(bad, s, source = "unit", target = "class", rule = "copy")
    ),
    "not constant"
  )
})

test_that("sd aggregates over the atoms", {
  s <- scale_example()
  d <- .d6()
  out <- recast_scale(d, s, source = "unit", target = "class", rule = "sd")
  expect_equal(out$value[out$class == "G1"], stats::sd(c(1, 2)))
  expect_equal(out$value[out$class == "G2"], stats::sd(c(3, 4)))
})

test_that("share sums to 1 within each parent and stays keyed at `from`", {
  s <- scale_example()
  out <- suppressWarnings(
    recast_scale(.d6(), s, source = "unit", target = "sector", rule = "share")
  )
  expect_true("unit" %in% names(out))
  tot <- tapply(out$value, scale_leaftable(s)$sector[
    match(out$unit, scale_leaftable(s)$unit)
  ], sum, na.rm = TRUE)
  expect_equal(unname(tot[["P"]]), 1)
  expect_equal(unname(tot[["S"]]), 1)
  # U1's share of sector P is 1/(1+2+3+4)
  expect_equal(out$value[out$unit == "U1"], 1 / 10)
})

test_that("logshare is the same computation as share", {
  s <- scale_example()
  a <- suppressWarnings(
    recast_scale(.d6(), s, source = "unit", target = "sector", rule = "share")
  )
  b <- suppressWarnings(
    recast_scale(.d6(), s, source = "unit", target = "sector", rule = "logshare")
  )
  expect_equal(a, b)
})

test_that("share refuses to mix with other rules", {
  s <- scale_example()
  d <- .d6()
  d$other <- 1
  expect_error(
    suppressWarnings(
      recast_scale(d, s,
        source = "unit", target = "sector",
        rule = c(value = "share", other = "sum")
      )
    ),
    "cannot be mixed"
  )
})

test_that("share requires `from` to nest within the parent", {
  s <- scale_example()
  d <- data.frame(
    group = c("G1", "GB", "GC"), value = c(1, 2, 3),
    stringsAsFactors = FALSE
  )
  # group cross-cuts class, so shares within class are not well-defined
  expect_error(
    suppressWarnings(
      recast_scale(d, s, source = "group", target = "class", rule = "share")
    ),
    "must nest within the parent"
  )
})

test_that("cross-cutting frames recast through the atom layer", {
  s <- scale_example()
  d <- data.frame(
    class = c("G1", "G2", "S1"), value = c(10, 20, 30),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(d, s,
      source = "class", target = "group", rule = "sum",
      weight = "size"
    )
  )
  # totals still conserve even though class and group cross-cut
  expect_equal(sum(out$value, na.rm = TRUE), 60)
})

test_that("identifier columns are preserved as groups", {
  s <- scale_example()
  d <- rbind(cbind(.d6(), year = 2020), cbind(.d6(c(2, 4, 6, 8, 10, 12)),
    year = 2021
  ))
  out <- recast_scale(d, s,
    source = "unit", target = "sector", rule = "sum",
    values = "value"
  )
  expect_true(all(c("sector", "year", "value") %in% names(out)))
  expect_equal(out$value[out$sector == "P" & out$year == 2020], 10)
  expect_equal(out$value[out$sector == "P" & out$year == 2021], 20)
})

test_that("the result is completed to the full target vocabulary", {
  s <- scale_example()
  d <- data.frame(
    unit = c("U1", "U2"), value = c(1, 2),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(d, s, source = "unit", target = "class", rule = "sum")
  )
  expect_setequal(out$class, scale_units(s, "class"))
  expect_true(anyNA(out$value))
})

test_that("na_action controls uncovered atoms", {
  s <- scale_example()
  d <- .d6()
  d <- rbind(d, data.frame(unit = "OTH", value = 100))
  # OTH has no sector: "drop" warns and loses it
  expect_warning(
    out <- recast_scale(d, s, source = "unit", target = "sector", rule = "sum"),
    "dropped|no code"
  )
  expect_equal(sum(out$value, na.rm = TRUE), 21)
  # "keep" retains it in an explicit NA row, conserving the total
  kept <- recast_scale(d, s,
    source = "unit", target = "sector", rule = "sum",
    na_action = "keep"
  )
  expect_true(anyNA(kept$sector))
  expect_equal(sum(kept$value, na.rm = TRUE), 121)
  # "error" refuses
  expect_error(
    recast_scale(d, s,
      source = "unit", target = "sector", rule = "sum",
      na_action = "error"
    ),
    "no code at"
  )
})

test_that("per-column rules and weights are honoured", {
  s <- scale_example()
  d <- data.frame(
    unit = c("U1", "U2"), cap = c(1, 2), eff = c(0.4, 0.6),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class",
      rule = c(cap = "sum", eff = "weighted_mean"),
      weight = c(cap = "size", eff = "size")
    )
  )
  expect_equal(out$cap[out$class == "G1"], 3)
  expect_equal(out$eff[out$class == "G1"], (0.4 * 100 + 0.6 * 200) / 300)
})

test_that("a value column with no rule is an error, never a guess", {
  s <- scale_example()
  expect_error(
    recast_scale(.d6(), s, source = "unit", target = "sector"),
    "no aggregation rule for value column"
  )
})

test_that("the rule registry supplies the default", {
  s <- scale_example()
  withr::defer(clear_scale_rules("value"))
  register_scale_rule("value", "sum")
  out <- recast_scale(.d6(), s, source = "unit", target = "sector")
  expect_equal(out$value[out$sector == "P"], 10)
})

test_that("unknown source codes warn and are dropped", {
  s <- scale_example()
  d <- rbind(.d6(), data.frame(unit = "NOPE", value = 99))
  expect_warning(
    recast_scale(d, s, source = "unit", target = "sector", rule = "sum"),
    "not present at"
  )
})

test_that("no matching source code at all is an error", {
  s <- scale_example()
  d <- data.frame(
    unit = c("X", "Y"), value = c(1, 2),
    stringsAsFactors = FALSE
  )
  expect_error(
    suppressWarnings(
      recast_scale(d, s, source = "unit", target = "sector", rule = "sum")
    ),
    "no rows matched"
  )
})

test_that("reserved working-column names are rejected", {
  s <- scale_example()
  d <- .d6()
  d$.ms_f <- 1
  expect_error(
    recast_scale(d, s, source = "unit", target = "sector", rule = "sum"),
    "reserved column name"
  )
})

test_that("`from` is inferred from the data's columns", {
  s <- scale_example()
  out <- recast_scale(.d6(), s, target = "sector", rule = "sum")
  expect_equal(out$value[out$sector == "P"], 10)
})

test_that("a registered crosswalk short-circuits the derivation", {
  s <- scale_example()
  withr::defer(clear_scale_maps())
  fake <- data.frame(
    unit = c("U1", "U2"), sector = c("P", "P"),
    n_from = 1L, n_overlap = 1L, w = 1, w_from = 1,
    stringsAsFactors = FALSE
  )
  register_scale_map(s, "unit", "sector", fake)
  out <- suppressWarnings(
    recast_scale(.d6(), s, source = "unit", target = "sector", rule = "sum")
  )
  # only U1 and U2 exist in the registered map
  expect_equal(out$value[out$sector == "P"], 3)
})

test_that("recast() dispatches to recast_scale()", {
  s <- scale_example()
  expect_equal(
    recast(.d6(), s, target = "sector", rule = "sum"),
    recast_scale(.d6(), s, target = "sector", rule = "sum")
  )
})
