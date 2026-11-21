# =========================================================================== #
# join_scale(): attaching labels, memberships, share and weight.
# =========================================================================== #

.jd <- function() {
  data.frame(class = c("G1", "G2", "S1"), v = 1:3, stringsAsFactors = FALSE)
}

test_that("the label column is named after the scale", {
  s <- scale_example()
  out <- join_scale(.jd(), s)
  expect_true("example" %in% names(out))
  expect_identical(as.character(out$example), c("G1", "G2", "S1"))
})

test_that("coarser frames attach with the scale-name prefix", {
  s <- scale_example()
  out <- join_scale(.jd(), s, attach = TRUE)
  expect_true("example.sector" %in% names(out))
  expect_identical(as.character(out$example.sector), c("P", "P", "S"))
  # attached memberships are factors over the frame's full vocabulary
  expect_s3_class(out$example.sector, "factor")
  expect_identical(levels(out$example.sector), scale_members(s, "sector"))
})

test_that("as_factor = FALSE returns plain character", {
  s <- scale_example()
  out <- join_scale(.jd(), s, attach = TRUE, as_factor = FALSE)
  expect_type(out$example.sector, "character")
})

test_that("only coarser frames may be attached", {
  s <- scale_example()
  expect_error(join_scale(.jd(), s, attach = "item"), "must be coarser")
})

test_that("meta attaches share and weight, and share sums to 1", {
  s <- scale_example()
  out <- join_scale(.jd(), s, meta = TRUE, weight = "size")
  expect_true(all(c("example.share", "example.weight") %in% names(out)))
  # class G1 = U1 + U2 = 300 by size
  expect_equal(out$example.weight[out$class == "G1"], 300)
  # the denominator is the CODED total at that frame (the unassigned leaf
  # belongs to no class, so it cannot be part of any class's share), which
  # is what makes the shares over a frame sum to 1
  expect_equal(out$example.share[out$class == "G1"], 300 / 2100)
  expect_equal(sum(out$example.share), 1)
})

test_that("a cross-cutting parent yields NA with a warning", {
  s <- scale_example()
  d <- data.frame(
    group = c("G1", "GB", "GC"), v = 1:3,
    stringsAsFactors = FALSE
  )
  expect_warning(out <- join_scale(d, s, attach = "class"), "does not nest")
  expect_true(is.na(out$example.class[out$group == "GB"]))
})

test_that("attaching never overwrites an existing column", {
  s <- scale_example()
  d <- .jd()
  d$example <- "taken"
  expect_error(join_scale(d, s, key = "class"), "would overwrite")
})

test_that("unknown codes warn but the join proceeds", {
  s <- scale_example()
  d <- rbind(.jd(), data.frame(class = "NOPE", v = 4))
  expect_warning(out <- join_scale(d, s), "are not members at")
  expect_true(is.na(out$example[out$class == "NOPE"]))
})

test_that("no matching code at all is an error", {
  s <- scale_example()
  d <- data.frame(class = c("X", "Y"), v = 1:2, stringsAsFactors = FALSE)
  expect_error(suppressWarnings(join_scale(d, s)), "no rows of the")
})

test_that("the keyed frame is inferred, and can be given", {
  s <- scale_example()
  expect_no_error(join_scale(.jd(), s))
  d <- data.frame(code = c("G1", "G2"), v = 1:2, stringsAsFactors = FALSE)
  expect_error(join_scale(d, s), "cannot infer the code frame")
  expect_no_error(join_scale(d, s, frame = "class", key = "code"))
})

test_that("several scales live side by side on one dataset", {
  a <- scale_example()
  df <- data.frame(
    big = c("X", "X", "Y", "Y", "Y", "Y", "Z"),
    item = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH"),
    size = 1, stringsAsFactors = FALSE
  )
  b <- scale_from_leaftable(df, frames = c("big", "item"), name = "other")

  d <- data.frame(
    item = c("U1", "U3", "U5"), v = 1:3,
    stringsAsFactors = FALSE
  )
  out <- join_scale(join_scale(d, a, attach = "sector"), b,
    key = "item", frame = "item", attach = "big"
  )
  # one dataset now carries both scales' labels -- a direct crosswalk
  expect_true(all(c("example", "example.sector", "other", "other.big") %in%
    names(out)))
  expect_identical(as.character(out$example.sector), c("P", "P", "S"))
  expect_identical(as.character(out$other.big), c("X", "Y", "Y"))
})

test_that("nothing to attach returns the data unchanged", {
  s <- scale_example()
  d <- data.frame(
    example = c("G1", "G2"), v = 1:2,
    stringsAsFactors = FALSE
  )
  expect_identical(join_scale(d, s, frame = "class"), d)
})

test_that("join_scale() honours the contract on every backend", {
  s <- scale_example()
  expect_backend_contract(
    .jd(),
    function(x, collect = NULL) {
      join_scale(x, s,
        attach = TRUE,
        as_factor = FALSE,
        collect = collect
      )
    },
    key_cols = "class"
  )
  expect_backend_rejects(function(x) join_scale(x, s))
})
