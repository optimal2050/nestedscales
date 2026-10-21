# Objects saved before the attribute and alias tables existed (0.1.1) read
# them as NULL. They must still validate and flow through every verb, and
# come out of a rebuild carrying real tables.

.old_scale <- function() {
  s <- scale_example()
  attr(s, "attributes") <- NULL
  attr(s, "aliases") <- NULL
  s
}

test_that("a scale without the new properties validates and reads as empty", {
  old <- .old_scale()
  expect_null(S7::prop(old, "attributes"))
  expect_no_error(S7::validate(old))
  expect_identical(nrow(scale_attributes(old)), 0L)
  expect_identical(nrow(scale_aliases(old)), 0L)
  expect_equal(scale_match(old, "P")$method, "exact")
})

test_that("every verb runs on an old object", {
  old <- .old_scale()
  d <- data.frame(unit = c("U1", "U2", "U3", "U4", "U5", "U6"), v = 1:6)
  expect_no_error(recast_scale(d, old, source = "unit", target = "sector",
                               rule = "sum"))
  expect_no_error(join_scale(d, old, attach = TRUE))
  expect_output(print(old), "NestedScale: example")
  expect_no_error(summary(old))
  f <- filter_scale(old, "sector", "P")
  expect_s3_class(S7::prop(f, "attributes"), "data.frame")   # healed
  p <- prune_scale(old, "class")
  expect_s3_class(S7::prop(p, "attributes"), "data.frame")
  panel <- merge(data.frame(unit = scale_units(old)),
                 data.frame(t = c("t1", "t2", "t3")))
  panel$v <- seq_len(nrow(panel))
  expect_no_error(cluster_scale(panel, old, k = 2))
})

test_that("the 0.1.1 fixture still loads and behaves", {
  # A saved S7 object embeds its class: this one's knows nothing of the
  # attribute and alias properties, so S7 itself refuses prop() on them.
  # The accessors read around that, and the write paths refresh the class.
  path <- test_path("fixtures", "scale-0.1.1.rds")
  skip_if_not(file.exists(path))
  s <- readRDS(path)
  expect_true(scale_is(s))
  expect_false("attributes" %in% names(attr(s, "S7_class")@properties))
  expect_error(S7::prop(s, "attributes"), "Can't find property")
  expect_no_error(S7::validate(s))
  expect_identical(nrow(scale_attributes(s)), 0L)
  expect_identical(nrow(scale_aliases(s)), 0L)
  expect_output(print(s), "NestedScale: example")
  d <- data.frame(unit = c("U1", "U2", "U3", "U4", "U5", "U6"), v = 1:6)
  expect_no_error(recast_scale(d, s, source = "unit", target = "sector",
                               rule = "sum"))
  f <- filter_scale(s, "sector", "P")
  expect_identical(scale_units(f, "sector"), "P")
  expect_true("attributes" %in% names(attr(f, "S7_class")@properties))
  expect_s3_class(S7::prop(f, "attributes"), "data.frame")
  s2 <- attach_attributes_scale(
    s, data.frame(frame = "sector", unit = "P", attribute = "density",
                  value = 1, unit_of_measure = "t/m3"),
    source = "t", kind = "property"
  )
  expect_identical(nrow(scale_attributes(s2)), 1L)
})
