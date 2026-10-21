# =========================================================================== #
# Declared residuals: a unit that carries value but is never a destination.
#
# The fixture is the reconciliation shape this feature exists for: two German
# regions plus a non-regionalized remainder, and one French region plus its
# own. The residuals are `NA` at `nuts1`, so the regionalized vocabulary stays
# clean while the country total still reconciles.
# =========================================================================== #

.res_scale <- function(pop = c(40, 30, 0, 60, 0), residuals = TRUE) {
  lf <- data.frame(
    country = c("DE", "DE", "DE", "FR", "FR"),
    nuts1 = c("DE1", "DE2", NA, "FR1", NA),
    atom = c("DE1", "DE2", "DE_XR", "FR1", "FR_XR"),
    pop = pop, stringsAsFactors = FALSE
  )
  args <- list(lf,
    frames = c("country", "nuts1", "atom"), key = "atom",
    weights = "pop", name = "geo"
  )
  if (isTRUE(residuals)) {
    args$residuals <- list(atom = c("DE_XR", "FR_XR"))
  }
  do.call(scale_from_leaftable, args)
}

.gdp <- function() {
  data.frame(
    atom = c("DE1", "DE2", "DE_XR", "FR1", "FR_XR"),
    gdp = c(400, 300, 50, 600, 90), stringsAsFactors = FALSE
  )
}

test_that("residuals are declared per frame and read back", {
  s <- .res_scale()
  expect_identical(scale_residuals(s, "atom"), c("DE_XR", "FR_XR"))
  expect_named(scale_residuals(s), "atom")
})

test_that("a scale declaring none reports none", {
  s <- .res_scale(residuals = FALSE)
  expect_identical(scale_residuals(s), list())
  expect_identical(scale_residuals(s, "atom"), character())
})

test_that("the declaration is validated against the frames and members", {
  lf <- data.frame(
    country = c("DE", "DE"), atom = c("DE1", "DE_XR"),
    pop = c(1, 0), stringsAsFactors = FALSE
  )
  mk <- function(r) {
    scale_from_leaftable(lf,
      frames = c("country", "atom"), key = "atom",
      weights = "pop", name = "g", residuals = r
    )
  }
  expect_error(mk(list(nope = "DE_XR")), "not frames")
  expect_error(mk(list(atom = "GHOST")), "non-member")
  expect_error(mk(list("DE_XR")), "named list")
  expect_error(mk(list(atom = 42)), "character vector")
})

test_that("residuals survive the dataset store round trip", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("yaml")
  s <- .res_scale()
  dir <- withr::local_tempdir()
  write_scale_dataset(.gdp(), s, file.path(dir, "s"))
  back <- open_scale_dataset(file.path(dir, "s"))$scale
  # YAML hands a named list of vectors back as lists of strings; without the
  # flattening in .scale_from_manifest() the validator would reject this.
  expect_identical(scale_residuals(back, "atom"), c("DE_XR", "FR_XR"))
})

test_that("a residual still aggregates upward -- that is its purpose", {
  s <- .res_scale()
  out <- recast_scale(.gdp(), s, source = "atom", target = "country", rule = "sum")
  expect_equal(out$gdp[out$country == "DE"], 750)
  expect_equal(out$gdp[out$country == "FR"], 690)
  expect_equal(sum(out$gdp), sum(.gdp()$gdp))
})

test_that("declaring residuals does not change any aggregation", {
  d <- .gdp()
  a <- recast_scale(d, .res_scale(),
    source = "atom", target = "country",
    rule = "sum"
  )
  b <- recast_scale(d, .res_scale(residuals = FALSE),
    source = "atom",
    target = "country", rule = "sum"
  )
  expect_equal(a, b)
})

test_that("the unallocated part surfaces at the regionalized frame", {
  s <- .res_scale()
  out <- recast_scale(.gdp(), s,
    source = "atom", target = "nuts1", rule = "sum",
    na_action = "keep"
  )
  expect_true(anyNA(out$nuts1))
  expect_equal(out$gdp[is.na(out$nuts1)], 140)
  expect_equal(sum(out$gdp), sum(.gdp()$gdp))
})

# Disaggregation is protected --------------------------------------------------

test_that("a zero-weight residual receives nothing when splitting down", {
  s <- .res_scale()
  nat <- data.frame(
    country = c("DE", "FR"), inv = c(100, 100),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(nat, s,
      source = "country", target = "atom", rule = "sum",
      weight = "pop"
    )
  )
  expect_equal(out$inv[out$atom == "DE_XR"], 0)
  expect_equal(out$inv[out$atom == "FR_XR"], 0)
  expect_equal(sum(out$inv), 200)
})

test_that("a positive-weight residual is protected AND the total is kept", {
  # The trap: zeroing the residual's share alone would lose its part of the
  # parent total, so the allocable shares have to be renormalised.
  s <- .res_scale(pop = c(40, 30, 30, 60, 40))
  nat <- data.frame(
    country = c("DE", "FR"), inv = c(100, 100),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(nat, s,
      source = "country", target = "atom", rule = "sum",
      weight = "pop"
    )
  )
  expect_equal(out$inv[out$atom == "DE_XR"], 0)
  expect_equal(out$inv[out$atom == "DE1"], 100 * 40 / 70)
  expect_equal(out$inv[out$atom == "DE2"], 100 * 30 / 70)
  expect_equal(sum(out$inv), 200)
})

test_that("a scale with NO declared weights protects residuals too", {
  # Without weights every atom weighs 1, so the residual would take an equal
  # share. This is the silent case the guard exists for.
  lf <- data.frame(
    country = c("DE", "DE", "DE"),
    atom = c("DE1", "DE2", "DE_XR"), stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(lf,
    frames = c("country", "atom"), key = "atom",
    name = "g", residuals = list(atom = "DE_XR")
  )
  nat <- data.frame(country = "DE", inv = 90, stringsAsFactors = FALSE)
  out <- suppressWarnings(
    recast_scale(nat, s, source = "country", target = "atom", rule = "sum")
  )
  expect_equal(out$inv[out$atom == "DE_XR"], 0)
  expect_equal(out$inv[out$atom == "DE1"], 45)
  expect_equal(sum(out$inv), 90)
})

test_that("undeclared residuals are NOT protected -- the guard is opt-in", {
  lf <- data.frame(
    country = c("DE", "DE", "DE"),
    atom = c("DE1", "DE2", "DE_XR"), stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(lf,
    frames = c("country", "atom"), key = "atom",
    name = "g"
  )
  nat <- data.frame(country = "DE", inv = 90, stringsAsFactors = FALSE)
  out <- suppressWarnings(
    recast_scale(nat, s, source = "country", target = "atom", rule = "sum")
  )
  expect_equal(out$inv[out$atom == "DE_XR"], 30)
})

test_that("a group that is ALL residual has nowhere allocable to go", {
  lf <- data.frame(
    country = c("DE", "XX"), atom = c("DE1", "XX_XR"),
    pop = c(10, 0), stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(lf,
    frames = c("country", "atom"), key = "atom",
    weights = "pop", name = "g",
    residuals = list(atom = "XX_XR")
  )
  nat <- data.frame(
    country = c("DE", "XX"), inv = c(10, 10),
    stringsAsFactors = FALSE
  )
  expect_error(
    suppressWarnings(recast_scale(nat, s,
      source = "country", target = "atom",
      rule = "sum", weight = "pop"
    )),
    "nowhere allocable"
  )
})

test_that("protection does not fire when aggregating INTO a coarse residual", {
  # A residual group is a legitimate destination when it is collecting its own
  # parts; the guard must only apply to disaggregation.
  lf <- data.frame(
    grp = c("REAL", "XR", "XR"),
    atom = c("a1", "x1", "x2"),
    pop = c(10, 5, 5), stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(lf,
    frames = c("grp", "atom"), key = "atom",
    weights = "pop", name = "g",
    residuals = list(grp = "XR")
  )
  d <- data.frame(
    atom = c("a1", "x1", "x2"), v = c(1, 2, 3),
    stringsAsFactors = FALSE
  )
  out <- recast_scale(d, s, source = "atom", target = "grp", rule = "sum")
  expect_equal(out$v[out$grp == "XR"], 5)
  expect_equal(sum(out$v), 6)
})
