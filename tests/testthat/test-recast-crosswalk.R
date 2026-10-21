# recast_crosswalk(): the recast engine over a crosswalk built elsewhere.

.xw <- function() {
  data.frame(
    month = c("m01", "m02", "m03", "m04"),
    quarter = c("Q1", "Q1", "Q1", "Q2"),
    n_from = c(31, 28, 31, 30), n_overlap = c(31, 28, 31, 30)
  )
}
.xd <- function() {
  data.frame(
    month = c("m01", "m02", "m03", "m04"),
    energy = c(31, 28, 31, 30), price = c(10, 20, 30, 40)
  )
}

test_that("sum and weighted_mean aggregate through the crosswalk", {
  out <- recast_crosswalk(.xd(), .xw(),
    source = "month", target = "quarter",
    rule = c(energy = "sum", price = "weighted_mean")
  )
  expect_named(out, c("quarter", "energy", "price"))
  expect_equal(out$energy[out$quarter == "Q1"], 90)
  # w defaults to n_overlap: a day-weighted mean
  expect_equal(
    out$price[out$quarter == "Q1"],
    (10 * 31 + 20 * 28 + 30 * 31) / 90
  )
})

test_that("sum splits by n_overlap / n_from, or by w / w_from when given", {
  # one source straddling two targets: 10 grid points, 4 and 6
  map <- data.frame(
    src = "A", tgt = c("x", "y"), n_from = 10,
    n_overlap = c(4, 6)
  )
  d <- data.frame(src = "A", v = 100)
  out <- recast_crosswalk(d, map, source = "src", target = "tgt", rule = "sum")
  expect_equal(out$v, c(40, 60))

  map$w <- c(1, 3)
  map$w_from <- 4
  out <- recast_crosswalk(d, map, source = "src", target = "tgt", rule = "sum")
  expect_equal(out$v, c(25, 75))

  # w_from without w: the count split applies, and `w` must not be read as
  # `w_from` by partial matching (which gave a factor of 1 for every pair)
  map$w <- NULL
  expect_no_warning(
    out <- recast_crosswalk(d, map, source = "src", target = "tgt", rule = "sum")
  )
  expect_equal(out$v, c(40, 60))
})

test_that("identifiers are kept as groups and `by` matches crosswalk columns", {
  d <- rbind(transform(.xd(), year = 2020L), transform(.xd(), year = 2021L))
  map <- rbind(
    transform(.xw(), year = 2020L),
    transform(.xw(),
      year = 2021L,
      quarter = c("Q1", "Q1", "Q2", "Q2")
    )
  )
  out <- recast_crosswalk(d, map,
    source = "month", target = "quarter",
    values = "energy", rule = "sum", ids = "year",
    by = "year"
  )
  q1 <- out$energy[out$quarter == "Q1"]
  expect_equal(sort(q1), c(59, 90))
  expect_error(
    recast_crosswalk(.xd(), map,
      source = "month", target = "quarter",
      rule = "sum", by = "year"
    ),
    "not identifier columns"
  )
})

test_that("targets completes the result to the full vocabulary", {
  out <- recast_crosswalk(.xd(), .xw(),
    source = "month", target = "quarter",
    values = "energy", rule = "sum", ids = character(),
    targets = c("Q1", "Q2", "Q3", "Q4", NA)
  )
  expect_identical(out$quarter, c("Q1", "Q2", "Q3", "Q4", NA))
  expect_true(all(is.na(out$energy[3:5])))
})

test_that("a partly supplied target is NA unless missing sources are ignored", {
  d <- .xd()[-2, ]
  out <- recast_crosswalk(d, .xw(),
    source = "month", target = "quarter",
    values = "energy", rule = "sum", ids = character()
  )
  expect_true(is.na(out$energy[out$quarter == "Q1"]))
  out <- recast_crosswalk(d, .xw(),
    source = "month", target = "quarter",
    values = "energy", rule = "sum", ids = character(),
    missing_sources = "ignore"
  )
  expect_equal(out$energy[out$quarter == "Q1"], 62)
})

test_that("copy errors in the caller's vocabulary", {
  expect_error(
    recast_crosswalk(.xd(), .xw(),
      source = "month", target = "quarter",
      values = "price", rule = "copy",
      ids = character(),
      unit = "timeslice"
    ),
    "not constant within a target timeslice"
  )
})

test_that("share rules and malformed crosswalks are refused", {
  expect_error(recast_crosswalk(.xd(), .xw(),
    source = "month", target = "quarter",
    rule = "share"
  ), "not supported")
  expect_error(
    recast_crosswalk(.xd(), .xw()[1:3],
      source = "month",
      target = "quarter", rule = "sum"
    ),
    "missing column"
  )
})

test_that("a lazy input returns a query", {
  skip_if_not_installed("arrow")
  q <- recast_crosswalk(arrow::arrow_table(.xd()), .xw(),
    source = "month",
    target = "quarter", values = "energy", rule = "sum",
    ids = character()
  )
  expect_false(is.data.frame(q))
  out <- as.data.frame(dplyr::collect(q))
  expect_equal(sum(out$energy), 120)
})
