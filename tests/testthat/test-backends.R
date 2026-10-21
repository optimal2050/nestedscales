# =========================================================================== #
# The backend quintet: detection, laziness, and class restoration.
#
# No conversion verbs exist yet, so these test the primitives directly -- the
# contract the engine will be written against.
# =========================================================================== #

.df <- function() {
  data.frame(
    unit = c("u1", "u2", "u3"), v = c(1, 2, 3),
    stringsAsFactors = FALSE
  )
}

test_that(".backend_class() names every supported input", {
  expect_identical(.backend_class(.df()), "data.frame")
  expect_identical(.backend_class(list(a = 1)), NA_character_)

  skip_if_not_installed("tibble")
  expect_identical(.backend_class(tibble::as_tibble(.df())), "tibble")
})

test_that(".backend_class() recognises the lazy engines", {
  skip_if_tier_below("full")
  skip_if_not_installed("data.table")
  skip_if_not_installed("dtplyr")
  skip_if_not_installed("arrow")

  expect_identical(
    .backend_class(data.table::as.data.table(.df())),
    "data.table"
  )
  expect_identical(
    .backend_class(dtplyr::lazy_dt(data.table::as.data.table(.df()))), "dtplyr"
  )
  expect_identical(.backend_class(arrow::arrow_table(.df())), "arrow")
})

test_that("backend_is_lazy() marks exactly the query-producing backends", {
  expect_true(backend_is_lazy("arrow"))
  expect_true(backend_is_lazy("dtplyr"))
  expect_false(backend_is_lazy("data.frame"))
  expect_false(backend_is_lazy("tibble"))
  expect_false(backend_is_lazy("data.table"))
})

test_that("backend_of() rejects unsupported input once", {
  expect_error(
    backend_of(list(a = 1)),
    "data\\.frame, tibble, data\\.table"
  )
  expect_identical(backend_of(.df()), "data.frame")
})

test_that("backend_schema() describes columns without materialising rows", {
  s <- backend_schema(.df())
  expect_identical(nrow(s), 0L)
  expect_named(s, c("unit", "v"))
})

test_that("backend_restore() round-trips every eager backend to its own class", {
  for (bk in setdiff(test_backends(), c("dtplyr", "arrow"))) {
    x <- as_backend(.df(), bk)
    out <- backend_restore(backend_lazy(x, bk), bk)
    expect_true(.bk_expect_class(out, bk),
      label = sprintf("[%s] class restored", bk)
    )
    expect_equal(.bk_sort(out, "unit")$v, c(1, 2, 3),
      label = sprintf("[%s] values", bk)
    )
  }
})

test_that("lazy inputs stay lazy unless collect = TRUE", {
  skip_if_tier_below("full")
  for (bk in intersect(test_backends(), c("dtplyr", "arrow"))) {
    x <- as_backend(.df(), bk)
    out <- backend_restore(x, bk)
    expect_true(.bk_expect_class(out, bk),
      label = sprintf("[%s] stays lazy", bk)
    )
    out2 <- backend_restore(x, bk, collect = TRUE)
    expect_true(.bk_expect_class(out2, bk, collected = TRUE),
      label = sprintf("[%s] collect = TRUE materialises", bk)
    )
    expect_equal(.bk_sort(out2, "unit")$v, c(1, 2, 3),
      label = sprintf("[%s] collected values", bk)
    )
  }
})

# The verbs ------------------------------------------------------------------

test_that("recast_scale() honours the contract on every backend", {
  s <- scale_example()
  input <- data.frame(
    unit = c("U1", "U2", "U3", "U4", "U5", "U6"),
    value = c(1, 2, 3, 4, 5, 6),
    stringsAsFactors = FALSE
  )
  expect_backend_contract(
    input,
    function(x, collect = NULL) {
      suppressWarnings(
        recast_scale(x, s,
          source = "unit", target = "sector", rule = "sum",
          collect = collect
        )
      )
    },
    key_cols = "sector",
    # a lazy result carries the observed groups only; the eager one is
    # completed to the full vocabulary and so has an extra NA row
    value_cols = "value"
  )
})

test_that("recast_scale() with identifiers holds on every backend", {
  s <- scale_example()
  input <- data.frame(
    unit = rep(c("U1", "U2", "U3", "U4", "U5", "U6"), 2),
    year = rep(c(2020, 2021), each = 6),
    value = c(1, 2, 3, 4, 5, 6, 2, 4, 6, 8, 10, 12),
    stringsAsFactors = FALSE
  )
  expect_backend_contract(
    input,
    function(x, collect = NULL) {
      suppressWarnings(
        recast_scale(x, s,
          source = "unit", target = "sector", rule = "sum",
          values = "value", collect = collect
        )
      )
    },
    key_cols = c("sector", "year"),
    value_cols = "value"
  )
})

test_that("recast_to_atoms() honours the contract on every backend", {
  s <- scale_example()
  input <- data.frame(
    sector = c("P", "S"), cap = c(10, 20),
    stringsAsFactors = FALSE
  )
  expect_backend_contract(
    input,
    function(x, collect = NULL) {
      suppressWarnings(
        recast_to_atoms(x, s,
          source = "sector", rule = "sum",
          weight = "size", collect = collect
        )
      )
    },
    key_cols = "unit"
  )
})

test_that("every entry point rejects unsupported input the same way", {
  s <- scale_example()
  expect_backend_rejects(function(x) {
    recast_scale(x, s, source = "unit", target = "sector", rule = "sum")
  })
  expect_backend_rejects(function(x) {
    recast_to_atoms(x, s, source = "sector", rule = "sum")
  })
  expect_backend_rejects(function(x) {
    recast_from_atoms(x, s, target = "sector", rule = "sum")
  })
})

test_that("backend_lazy() wraps a data.table for dtplyr translation", {
  skip_if_not_installed("data.table")
  skip_if_not_installed("dtplyr")
  x <- data.table::as.data.table(.df())
  expect_s3_class(backend_lazy(x, "data.table"), "dtplyr_step")
  # every other backend passes through untouched
  expect_identical(backend_lazy(.df(), "data.frame"), .df())
})
