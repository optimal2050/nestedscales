# =========================================================================== #
# Structure queries: family, nests, coverage.
# =========================================================================== #

test_that("scale_family() returns the adjacent pairs by default", {
  s <- tidy_scale()
  fam <- scale_family(s)
  expect_named(fam, c("parent_frame", "parent", "child_frame", "child"))
  expect_setequal(unique(fam$parent_frame), c("top", "mid"))
  # one row per (parent, child) pair actually present
  expect_identical(nrow(scale_family(s, "top", "mid")), 2L)
  expect_identical(nrow(scale_family(s, "mid", "leaf")), 4L)
})

test_that("scale_family() omits leaves unassigned at either frame", {
  s <- scale_example()
  fam <- scale_family(s, "sector", "class")
  expect_false(anyNA(fam$parent))
  expect_false(anyNA(fam$child))
  # "OTH" is NA at both, so it contributes nothing
  expect_false("OTH" %in% fam$child)
})

test_that("scale_family() checks its frame arguments", {
  s <- tidy_scale()
  expect_error(scale_family(s, "nope", "mid"), "is not a frame")
  expect_error(scale_family(s, "top", "nope"), "is not a frame")
})

test_that("a single-frame scale has an empty family", {
  fam <- scale_family(flat_scale())
  expect_identical(nrow(fam), 0L)
  expect_named(fam, c("parent_frame", "parent", "child_frame", "child"))
})

test_that("scale_nests() detects a clean hierarchy", {
  s <- tidy_scale()
  expect_true(scale_nests(s, "top", "mid"))
  expect_true(scale_nests(s, "mid", "leaf"))
})

test_that("scale_nests() reports cross-cutting frames and their offenders", {
  s <- scale_example()
  ok <- scale_nests(s, "class", "group")
  expect_false(ok)
  expect_true("GB" %in% attr(ok, "offenders"))
})

test_that("scale_coverage() is 1 for a scale that was never subset", {
  s <- scale_example()
  expect_equal(scale_coverage(s), c(size = 1, count = 1))
  expect_equal(scale_coverage(s, "size"), 1)
  expect_error(scale_coverage(s, "nope"), "unknown weight")
})

test_that("scale_coverage() reads the bookkeeping when present", {
  s <- tidy_scale()
  sampled <- NestedScale(
    leaftable = scale_leaftable(s), frames = scale_frames(s),
    members = S7::prop(s, "members"), leaf = "leaf",
    meta = list(
      name = "part", weights = "w", default_weight = "w",
      coverage = c(w = 0.5), parent_totals = list(w = 20),
      parent_name = "tidy"
    )
  )
  expect_equal(scale_coverage(sampled), c(w = 0.5))
  expect_true(summary(sampled)$sampled)
  expect_output(print(summary(sampled)), "SAMPLED")
  expect_output(print(summary(sampled)), "of 'tidy'")
})

# scale_crosses() / scale_is_uniform(): structure a frame pair actually has --

test_that("scale_crosses() tells a product apart from a tree", {
  s <- scale_example()
  expect_true(scale_nests(s, "sector", "class"))
  expect_false(scale_crosses(s, "sector", "class"))
  expect_false(scale_nests(s, "class", "group"))  # GB sits under G2 and S1
  no <- scale_crosses(s, "class", "group")
  expect_false(no)
  expect_true(length(attr(no, "offenders")) > 0)

  grid <- expand.grid(m = c("m1", "m2"), h = c("h1", "h2", "h3"),
                      stringsAsFactors = FALSE)
  grid$item <- paste(grid$m, grid$h, sep = "_")
  mh <- scale_from_leaftable(grid, frames = c("m", "h"), leaf = "item")
  expect_true(scale_crosses(mh, "m", "h"))
  expect_true(scale_crosses(mh, "h", "m"))
  expect_false(scale_nests(mh, "m", "h"))
  expect_identical(scale_leaf_frame(mh), "item")

  grid2 <- grid[-1, ]                      # drop m1_h1: no longer a product
  mh2 <- scale_from_leaftable(grid2, frames = c("m", "h"), leaf = "item")
  expect_false(scale_crosses(mh2, "m", "h"))
})

test_that("scale_is_uniform() compares leaf counts or weight totals", {
  s <- scale_example()
  expect_true(scale_is_uniform(s, "item"))
  expect_true(scale_is_uniform(s, "class"))   # two leaves in each class
  by_size <- scale_is_uniform(s, "class", weight = "size")
  expect_false(by_size)
  expect_named(attr(by_size, "sizes"), c("G1", "G2", "S1"))
  expect_error(scale_is_uniform(s, "class", weight = "nope"), "unknown weight")
  expect_error(scale_is_uniform(s, "nope"), "frame")
})
