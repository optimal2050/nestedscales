# =========================================================================== #
# ScaleProduct: construction, the key contract, accessors, guarded leaves.
# =========================================================================== #

.p2 <- function() scale_product(a = scale_example(), b = scale_example2())

test_that("scale_product() combines named axes", {
  p <- .p2()
  expect_s3_class(p, "nestedscales::ScaleProduct")
  expect_identical(names(p), c("a", "b"))
  expect_identical(names(scale_axes(p)), c("a", "b"))
  expect_identical(S7::prop(scale_axes(p, "a"), "meta")$name, "example")
})

test_that("axes must be named", {
  expect_error(
    scale_product(scale_example(), scale_example2()),
    "must be named"
  )
  expect_error(scale_product(), "pass the axes as named")
})

test_that("a product needs at least two axes", {
  expect_error(scale_product(a = scale_example()), "at least 2 axes")
})

test_that("axes must be named NestedScale objects", {
  expect_error(
    scale_product(a = scale_example(), b = 42),
    "is not a NestedScale object"
  )
  # a scale with no name cannot key a crosswalk or a join column
  anon <- scale_from_leaftable(
    data.frame(
      g = c("A", "A"), item = c("u1", "u2"),
      stringsAsFactors = FALSE
    ),
    frames = c("g", "item")
  )
  expect_error(scale_product(a = scale_example(), b = anon), "has no name")
})

test_that("a product may not nest another product", {
  expect_error(
    scale_product(a = .p2(), b = scale_example2()),
    "is itself a product"
  )
})

# Keys ------------------------------------------------------------------------

test_that("each axis keeps its own key column by default", {
  p <- .p2()
  expect_identical(product_keys(p), c(a = "item", b = "period"))
})

test_that("colliding keys fall back to the axis names", {
  # both example scales are keyed "member"
  p <- scale_product(first = scale_example(), second = scale_example())
  expect_identical(product_keys(p), c(first = "first", second = "second"))
})

test_that("keys= overrides per axis and is validated", {
  p <- scale_product(
    a = scale_example(), b = scale_example2(),
    keys = c(a = "code")
  )
  expect_identical(product_keys(p), c(a = "code", b = "period"))
  expect_error(
    scale_product(
      a = scale_example(), b = scale_example2(),
      keys = c(zz = "code")
    ),
    "unknown axes"
  )
  # an override that recreates a collision is still rejected
  expect_error(
    scale_product(
      a = scale_example(), b = scale_example2(),
      keys = c(a = "period")
    ),
    "same key column"
  )
})

# Accessors -------------------------------------------------------------------

test_that("the cheap accessors report the components", {
  p <- .p2()
  expect_identical(product_frames(p)$a, scale_frames(scale_example()))
  expect_identical(product_frames(p)$b, c("era", "period"))
  expect_identical(product_weights(p)$b, "span")

  sz <- product_size(p)
  expect_identical(sz$axes, c(a = 7L, b = 4L))
  expect_equal(sz$total, 28)
})

test_that("coverage is per axis, and the joint one is their product", {
  p <- scale_product(
    a = filter_scale(scale_example(), "sector", "P"),
    b = scale_example2()
  )
  cov <- product_coverage(p)
  expect_equal(unname(cov[["a"]]), 1000 / 3100)
  expect_equal(unname(cov[["b"]]), 1)
  expect_equal(prod(cov), 1000 / 3100)
})

# Leaves -----------------------------------------------------------------------

test_that("product_leaves() is the cross product of the components", {
  p <- .p2()
  at <- product_leaves(p)
  expect_identical(nrow(at), 28L)
  expect_true(all(c("item", "period") %in% names(at)))
  # each axis's frames are carried, prefixed by the axis name
  expect_true(all(c("a.sector", "a.class", "a.group", "b.era") %in%
    names(at)))
  # the leaf column is not repeated as a prefixed frame
  expect_false("a.item" %in% names(at))
  expect_setequal(unique(at$item), scale_members(scale_example()))
  expect_setequal(unique(at$period), scale_members(scale_example2()))
})

test_that("product_leaves() refuses to build more than `limit` rows", {
  p <- .p2()
  expect_error(product_leaves(p, limit = 10), "above `limit`")
  # the message reports the size so the caller can decide
  expect_error(product_leaves(p, limit = 10), "28")
  expect_no_error(product_leaves(p, limit = 28))
})

test_that("the leaftable accessor points at the product-shaped ones", {
  p <- .p2()
  expect_error(scale_leaftable(p), "scale_axes|product_leaves")
})

# Reserved joint weights -------------------------------------------------------

test_that("joint_weights is accepted and validated but not required", {
  p <- .p2()
  expect_null(S7::prop(p, "joint_weights"))

  jw <- data.frame(
    item = "U1", period = "p1", jw = 1,
    stringsAsFactors = FALSE
  )
  q <- scale_product(
    a = scale_example(), b = scale_example2(),
    joint_weights = jw
  )
  expect_s3_class(q, "nestedscales::ScaleProduct")

  expect_error(
    scale_product(
      a = scale_example(), b = scale_example2(),
      joint_weights = data.frame(item = "U1", jw = 1)
    ),
    "missing key column"
  )
  expect_error(
    scale_product(
      a = scale_example(), b = scale_example2(),
      joint_weights = data.frame(item = "U1", period = "p1")
    ),
    "no weight column"
  )
})

# Base generics ---------------------------------------------------------------

test_that("print() reports the axes and the implied size", {
  p <- .p2()
  expect_output(print(p), "ScaleProduct")
  expect_output(print(p), "7 x 4 = 28")
  expect_output(print(p), "not materialised")
  expect_output(print(p), "key: item")
})

test_that("print() reports sampling when an axis is a sample", {
  p <- scale_product(
    a = filter_scale(scale_example(), "sector", "P"),
    b = scale_example2()
  )
  expect_output(print(p), "Coverage")
})

test_that("format() is the one-line form", {
  expect_match(format(.p2()), "^<ScaleProduct\\[a x b\\] leaves=28>$")
})

test_that("summary() returns the classed view and prints it", {
  p <- .p2()
  s <- summary(p)
  expect_s3_class(s, "summary_ScaleProduct")
  expect_named(s, c(
    "name", "desc", "axes", "total", "coverage",
    "joint_coverage", "joint_weights"
  ))
  expect_identical(nrow(s$axes), 2L)
  expect_equal(s$total, 28)
  expect_output(print(s), "summary of ScaleProduct")
  expect_output(print(s), "example")
})

test_that("accessors reject a plain NestedScale", {
  expect_error(product_keys(scale_example()), "must be a ScaleProduct")
  expect_error(scale_axes(scale_example()), "must be a ScaleProduct")
})
