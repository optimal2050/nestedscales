# =========================================================================== #
# reconcile_scale(): measuring, and optionally closing, a data discrepancy.
#
# The gap lives in the DATA, not on the scale: it varies by variable, by
# period and by vintage. These tests hold the scale fixed and vary the data.
# =========================================================================== #

.rc_scale <- function(residuals = TRUE) {
  lf <- data.frame(
    country = c("DE", "DE", "DE", "FR", "FR"),
    unit = c("DE1", "DE2", "DE_XR", "FR1", "FR_XR"),
    pop = c(40, 30, 0, 60, 0), stringsAsFactors = FALSE
  )
  args <- list(lf,
    frames = c("country", "unit"), key = "unit",
    weights = "pop", name = "geo"
  )
  if (isTRUE(residuals)) {
    args$residuals <- list(unit = c("DE_XR", "FR_XR"))
  }
  do.call(scale_from_leaftable, args)
}

# fine data summing to DE 700, FR 600
.fine <- function() {
  data.frame(
    unit = c("DE1", "DE2", "DE_XR", "FR1", "FR_XR"),
    gdp = c(400, 300, 0, 600, 0), stringsAsFactors = FALSE
  )
}

# published totals: DE is 100 higher than its parts, FR agrees
.published <- function(de = 800, fr = 600) {
  data.frame(
    country = c("DE", "FR"), gdp = c(de, fr),
    stringsAsFactors = FALSE
  )
}

test_that("the report names the gap and leaves everything alone", {
  s <- .rc_scale()
  g <- reconcile_scale(.fine(), s,
    source = "unit", target = "country",
    .published()
  )
  expect_named(g, c(
    "country", "value", "aggregated", "target", "gap",
    "rel_gap", "ok"
  ))
  expect_equal(g$aggregated[g$country == "DE"], 700)
  expect_equal(g$target[g$country == "DE"], 800)
  expect_equal(g$gap[g$country == "DE"], 100)
  expect_false(g$ok[g$country == "DE"])
})

test_that("a consistent group reports a zero gap and ok", {
  s <- .rc_scale()
  g <- reconcile_scale(.fine(), s,
    source = "unit", target = "country",
    .published()
  )
  expect_equal(g$gap[g$country == "FR"], 0)
  expect_true(g$ok[g$country == "FR"])
})

test_that("rounding-sized gaps are ok, and tolerance is adjustable", {
  s <- .rc_scale()
  g <- reconcile_scale(.fine(), s,
    source = "unit", target = "country",
    .published(de = 700.0000001)
  )
  expect_true(g$ok[g$country == "DE"])
  strict <- reconcile_scale(.fine(), s,
    source = "unit", target = "country",
    .published(de = 700.0000001), tolerance = 0
  )
  expect_false(strict$ok[strict$country == "DE"])
})

test_that("gaps are per identifier group", {
  s <- .rc_scale()
  d <- rbind(cbind(.fine(), year = 2020), cbind(.fine(), year = 2021))
  tot <- rbind(
    cbind(.published(de = 800), year = 2020),
    cbind(.published(de = 700), year = 2021)
  )
  g <- reconcile_scale(d, s,
    source = "unit", target = "country", tot,
    values = "gdp"
  )
  expect_equal(g$gap[g$country == "DE" & g$year == 2020], 100)
  expect_equal(g$gap[g$country == "DE" & g$year == 2021], 0)
})

test_that("several value columns each get a row", {
  s <- .rc_scale()
  d <- .fine()
  d$emp <- c(4, 3, 0, 6, 0)
  tot <- .published()
  tot$emp <- c(7, 6)
  g <- reconcile_scale(d, s, source = "unit", target = "country", tot)
  expect_setequal(g$value, c("gdp", "emp"))
  expect_equal(g$gap[g$value == "emp" & g$country == "DE"], 0)
  expect_equal(g$gap[g$value == "gdp" & g$country == "DE"], 100)
})

# Closing the gap --------------------------------------------------------------

test_that("balance = residual parks the gap and then reconciles exactly", {
  s <- .rc_scale()
  out <- reconcile_scale(.fine(), s,
    source = "unit", target = "country",
    .published(), balance = "residual"
  )
  expect_equal(out$gdp[out$unit == "DE_XR"], 100)
  expect_equal(out$gdp[out$unit == "DE1"], 400) # untouched
  # and it now adds up
  again <- reconcile_scale(out, s,
    source = "unit", target = "country",
    .published()
  )
  expect_true(all(again$ok))
})

test_that("balance = proportional scales the children and then reconciles", {
  s <- .rc_scale()
  out <- reconcile_scale(.fine(), s,
    source = "unit", target = "country",
    .published(), balance = "proportional"
  )
  expect_equal(out$gdp[out$unit == "DE1"], 400 * 800 / 700)
  expect_equal(out$gdp[out$unit == "DE2"], 300 * 800 / 700)
  expect_equal(out$gdp[out$unit == "FR1"], 600) # already agreed
  again <- reconcile_scale(out, s,
    source = "unit", target = "country",
    .published()
  )
  expect_true(all(again$ok))
})

test_that("a balanced result carries the gap table as provenance", {
  s <- .rc_scale()
  out <- reconcile_scale(.fine(), s,
    source = "unit", target = "country",
    .published(), balance = "residual"
  )
  rec <- attr(out, "reconciliation")
  expect_false(is.null(rec))
  expect_equal(rec$gap[rec$country == "DE"], 100)
})

test_that("the report path mutates nothing", {
  s <- .rc_scale()
  d <- .fine()
  invisible(reconcile_scale(d, s,
    source = "unit", target = "country",
    .published()
  ))
  expect_equal(d, .fine())
})

test_that("parking needs a declared residual", {
  s <- .rc_scale(residuals = FALSE)
  expect_error(
    reconcile_scale(.fine(), s,
      source = "unit", target = "country", .published(),
      balance = "residual"
    ),
    "no residual is declared"
  )
})

test_that("parking a gap between means is refused, not computed", {
  s <- .rc_scale()
  expect_error(
    reconcile_scale(.fine(), s,
      source = "unit", target = "country", .published(),
      rule = "weighted_mean", weight = "pop",
      balance = "residual"
    ),
    "needs `rule = \"sum\"`"
  )
})

test_that("more than one residual per group has no single home", {
  lf <- data.frame(
    country = rep("DE", 3),
    unit = c("DE1", "DE_XA", "DE_XB"),
    pop = c(10, 0, 0), stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(lf,
    frames = c("country", "unit"), key = "unit",
    weights = "pop", name = "g",
    residuals = list(unit = c("DE_XA", "DE_XB"))
  )
  d <- data.frame(
    unit = c("DE1", "DE_XA", "DE_XB"), gdp = c(100, 0, 0),
    stringsAsFactors = FALSE
  )
  expect_error(
    reconcile_scale(d, s,
      source = "unit", target = "country",
      data.frame(country = "DE", gdp = 150),
      balance = "residual"
    ),
    "no single home"
  )
})

test_that("a group aggregating to zero cannot be scaled proportionally", {
  s <- .rc_scale()
  d <- .fine()
  d$gdp[d$unit %in% c("DE1", "DE2")] <- 0
  expect_error(
    reconcile_scale(d, s,
      source = "unit", target = "country", .published(de = 50),
      balance = "proportional"
    ),
    "aggregates to 0"
  )
})

test_that("`to` must be coarser than `from`", {
  s <- .rc_scale()
  expect_error(
    reconcile_scale(.fine(), s,
      source = "country", target = "unit",
      data.frame(unit = "DE1", gdp = 1)
    ),
    "must be coarser"
  )
})

test_that("the arguments it needs are checked", {
  s <- .rc_scale()
  expect_error(
    reconcile_scale(.fine(), s,
      source = "unit", target = "country",
      data.frame(nope = "DE", gdp = 1)
    ),
    "no `country` column"
  )
  expect_error(
    reconcile_scale(.fine(), s,
      source = "unit", target = "country",
      data.frame(country = "DE", other = 1)
    ),
    "no numeric column is common"
  )
})

test_that("an intensive quantity reconciles as a weighted mean", {
  s <- .rc_scale()
  d <- data.frame(
    unit = c("DE1", "DE2", "DE_XR", "FR1", "FR_XR"),
    eff = c(0.5, 0.8, 0, 0.6, 0), stringsAsFactors = FALSE
  )
  tot <- data.frame(
    country = c("DE", "FR"), eff = c(0.62857142857, 0.6),
    stringsAsFactors = FALSE
  )
  g <- reconcile_scale(d, s,
    source = "unit", target = "country", tot,
    rule = "weighted_mean", weight = "pop",
    tolerance = 1e-6
  )
  expect_true(all(g$ok))
})
