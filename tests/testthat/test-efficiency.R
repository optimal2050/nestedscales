# =========================================================================== #
# Large-data behaviour: diagnostics policy, missing_sources, batching.
#
# The engine is expected to run over arrow/on-disk data that does not fit in
# memory, so "lazy in, lazy out" has to mean NO work at all -- not "the cheap
# work". These tests state that, and pin the two escape hatches that trade it
# away deliberately.
# =========================================================================== #

.ed <- function(n_year = 4) {
  d <- merge(
    data.frame(
      unit = c("U1", "U2", "U3", "U4", "U5", "U6"),
      stringsAsFactors = FALSE
    ),
    data.frame(year = seq_len(n_year), stringsAsFactors = FALSE)
  )
  d$value <- seq_len(nrow(d))
  d
}

# Diagnostics ------------------------------------------------------------------

test_that("an eager input still gets its diagnostics", {
  s <- scale_example()
  d <- rbind(.ed(1), data.frame(unit = "NOPE", year = 1, value = 99))
  expect_warning(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value"
    ),
    "not present at"
  )
})

test_that("a lazy input gets none, and forcing them back on works", {
  skip_if_tier_below("full")
  skip_if_not_installed("arrow")
  s <- scale_example()
  d <- rbind(.ed(1), data.frame(unit = "NOPE", year = 1, value = 99))
  at <- arrow::arrow_table(d)

  expect_no_warning(
    recast_scale(at, s,
      source = "unit", target = "class", rule = "sum",
      values = "value"
    )
  )
  expect_warning(
    recast_scale(at, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", diagnostics = "on"
    ),
    "not present at"
  )
})

test_that("diagnostics = off silences an eager input too", {
  s <- scale_example()
  d <- rbind(.ed(1), data.frame(unit = "NOPE", year = 1, value = 99))
  expect_no_warning(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", diagnostics = "off"
    )
  )
})

test_that("errors that do not depend on the data fire whatever diagnostics says", {
  s <- scale_example()
  d <- .ed(1)
  for (dg in c("auto", "on", "off")) {
    expect_error(
      recast_scale(d, s,
        source = "unit", target = "nope", rule = "sum",
        values = "value", diagnostics = dg
      ),
      "is not a frame",
      label = dg
    )
    bad <- d
    bad$.ms_f <- 1
    expect_error(
      recast_scale(bad, s,
        source = "unit", target = "class", rule = "sum",
        values = "value", diagnostics = dg
      ),
      "reserved column name",
      label = dg
    )
  }
})

test_that("diagnostics never change the numbers", {
  s <- scale_example()
  d <- .ed()
  a <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", diagnostics = "on"
    )
  )
  b <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", diagnostics = "off"
    )
  )
  expect_equal(a, b)
})

test_that("join_scale() is zero-scan on a lazy input but still checks eagerly", {
  skip_if_tier_below("full")
  skip_if_not_installed("arrow")
  s <- scale_example()
  d <- data.frame(class = c("G1", "NOPE"), v = 1:2, stringsAsFactors = FALSE)
  expect_warning(join_scale(d, s), "are not units at")
  expect_no_warning(join_scale(arrow::arrow_table(d), s))
})

# missing_sources --------------------------------------------------------------

test_that("missing_sources = ignore aggregates what is present", {
  s <- scale_example()
  partial <- data.frame(unit = "U1", value = 5, stringsAsFactors = FALSE)
  poisoned <- suppressWarnings(
    recast_scale(partial, s, source = "unit", target = "class", rule = "sum")
  )
  ignored <- suppressWarnings(
    recast_scale(partial, s,
      source = "unit", target = "class", rule = "sum",
      missing_sources = "ignore"
    )
  )
  expect_true(is.na(poisoned$value[poisoned$class == "G1"]))
  expect_equal(ignored$value[ignored$class == "G1"], 5)
})

test_that("missing_sources makes no difference when the data is complete", {
  s <- scale_example()
  d <- .ed()
  a <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value"
    )
  )
  b <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", missing_sources = "ignore"
    )
  )
  expect_equal(a, b)
})

# Batching ---------------------------------------------------------------------

test_that("batching gives exactly the unbatched result, in the same order", {
  s <- scale_example()
  d <- .ed(6)
  ref <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value"
    )
  )
  for (k in c(1, 2, 6, 7)) {
    got <- suppressWarnings(
      recast_scale(d, s,
        source = "unit", target = "class", rule = "sum",
        values = "value", batch = k, batch_by = "year"
      )
    )
    expect_equal(got, ref,
      ignore_attr = TRUE,
      label = sprintf("batch = %d", k)
    )
  }
})

test_that("batching holds for every rule", {
  s <- scale_example()
  d <- .ed(4)
  for (r in c("sum", "mean", "weighted_mean", "sd")) {
    ref <- suppressWarnings(
      recast_scale(d, s,
        source = "unit", target = "class", rule = r,
        values = "value",
        weight = if (r == "weighted_mean") "size" else NULL
      )
    )
    got <- suppressWarnings(
      recast_scale(d, s,
        source = "unit", target = "class", rule = r,
        values = "value", batch = 2, batch_by = "year",
        weight = if (r == "weighted_mean") "size" else NULL
      )
    )
    expect_equal(got, ref, ignore_attr = TRUE, label = r)
  }
})

test_that("batching preserves the partial-source NA law", {
  s <- scale_example()
  # year 1 complete for G1, year 2 partial -- chunks must not hide that
  d <- data.frame(
    unit = c("U1", "U2", "U1"), year = c(1, 1, 2),
    value = c(1, 2, 5), stringsAsFactors = FALSE
  )
  got <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", batch = 1, batch_by = "year"
    )
  )
  expect_equal(got$value[got$class == "G1" & got$year == 1], 3)
  expect_true(is.na(got$value[got$class == "G1" & got$year == 2]))
})

test_that("batch_by must be an identifier column", {
  s <- scale_example()
  d <- .ed()
  expect_error(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", batch = 2, batch_by = "unit"
    ),
    "must be an identifier column"
  )
  expect_error(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", batch = 2, batch_by = "value"
    ),
    "must be an identifier column"
  )
})

test_that("batching a data-less-identifier job is refused clearly", {
  s <- scale_example()
  d <- data.frame(
    unit = c("U1", "U2"), value = c(1, 2),
    stringsAsFactors = FALSE
  )
  expect_error(
    suppressWarnings(
      recast_scale(d, s,
        source = "unit", target = "class", rule = "sum",
        batch = 2
      )
    ),
    "needs an identifier column"
  )
})

test_that("batching a lazy call is refused rather than silently collecting", {
  skip_if_tier_below("full")
  skip_if_not_installed("arrow")
  s <- scale_example()
  at <- arrow::arrow_table(.ed())
  expect_error(
    recast_scale(at, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", batch = 2, batch_by = "year"
    ),
    "Pass `collect = TRUE`"
  )
  expect_no_error(
    recast_scale(at, s,
      source = "unit", target = "class", rule = "sum",
      values = "value", batch = 2, batch_by = "year",
      collect = TRUE
    )
  )
})

test_that("batching returns the input's class", {
  skip_if_not_installed("tibble")
  s <- scale_example()
  out <- suppressWarnings(
    recast_scale(tibble::as_tibble(.ed()), s,
      source = "unit", target = "class",
      rule = "sum", values = "value", batch = 2,
      batch_by = "year"
    )
  )
  expect_s3_class(out, "tbl_df")
})

# The widened crosswalk --------------------------------------------------------

test_that("several weights in one call agree with one call per weight", {
  s <- scale_example()
  d <- data.frame(
    unit = c("U1", "U2", "U3", "U4"),
    a = c(1, 2, 3, 4), b = c(0.1, 0.2, 0.3, 0.4),
    c = c(10, 20, 30, 40), stringsAsFactors = FALSE
  )
  rules <- c(a = "sum", b = "weighted_mean", c = "weighted_mean")
  wts <- c(a = "size", b = "count", c = "size")

  together <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = rules,
      weight = wts
    )
  )
  for (v in names(rules)) {
    alone <- suppressWarnings(
      recast_scale(d[, c("unit", v)], s,
        source = "unit", target = "class",
        rule = rules[[v]], weight = wts[[v]]
      )
    )
    expect_equal(together[[v]], alone[[v]],
      label = sprintf("column %s matches its own call", v)
    )
  }
})

test_that("two columns naming the same weight still fold correctly", {
  s <- scale_example()
  d <- data.frame(
    unit = c("U1", "U2"), a = c(1, 2), b = c(3, 4),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class",
      rule = c(a = "sum", b = "sum"),
      weight = c(a = "size", b = "size")
    )
  )
  expect_equal(out$a[out$class == "G1"], 3)
  expect_equal(out$b[out$class == "G1"], 7)
})

test_that("a single weight is unaffected by the folding machinery", {
  s <- scale_example()
  d <- data.frame(unit = c("U1", "U2"), v = c(1, 2), stringsAsFactors = FALSE)
  out <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "weighted_mean",
      weight = "size"
    )
  )
  expect_equal(out$v[out$class == "G1"], (1 * 100 + 2 * 200) / 300)
})

# The combine helper -----------------------------------------------------------

test_that("backend_bind_rows() agrees on both branches", {
  parts <- list(
    data.frame(a = 1:2, b = c("x", "y"), stringsAsFactors = FALSE),
    data.frame(a = 3L, b = "z", stringsAsFactors = FALSE)
  )
  base <- backend_bind_rows(parts, use_dt = FALSE)
  expect_identical(nrow(base), 3L)
  expect_identical(base$a, 1:3)

  skip_if_not_installed("data.table")
  expect_equal(backend_bind_rows(parts, use_dt = TRUE), base)
})

test_that("backend_bind_rows() drops empty parts and handles the edges", {
  expect_null(backend_bind_rows(list()))
  expect_null(backend_bind_rows(list(NULL)))
  one <- data.frame(a = 1)
  expect_equal(backend_bind_rows(list(one, one[0, , drop = FALSE])), one)
})

test_that(".backend_chunks() splits without losing or duplicating values", {
  v <- letters[1:7]
  for (k in c(1, 3, 7, 100)) {
    ch <- .backend_chunks(v, k)
    expect_setequal(unlist(ch, use.names = FALSE), v)
    expect_true(all(lengths(ch) <= k))
  }
  expect_length(.backend_chunks(character(), 3), 0L)
})
