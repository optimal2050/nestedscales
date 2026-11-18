# Labels: display names per (frame, unit, variant).

.labelled <- function() {
  attach_labels_scale(
    scale_example(),
    data.frame(
      frame = "sector", unit = c("P", "S", NA),
      label = c("Primary", "Secondary", "Sector")
    ),
    variant = "name"
  )
}

test_that("labels are sparse: a frame without rows shows its codes", {
  s <- .labelled()
  expect_equal(scale_labels(s)$variant, rep("name", 3L))
  expect_equal(
    scale_label(s, c("S", "P", "T"), frame = "sector"),
    c("Secondary", "Primary", "T")
  )
  expect_equal(scale_label(s, c("G1", "G2"), frame = "class"), c("G1", "G2"))
  expect_equal(nrow(scale_labels(s, frame = "class")), 0L)
})

test_that("an NA unit is the label of the frame itself", {
  s <- .labelled()
  expect_equal(scale_label(s, NA, frame = "sector"), "Sector")
  expect_equal(scale_label(s, NA, frame = "class"), "class")
})

test_that("a member carries several variants and one is the default", {
  s <- attach_labels_scale(
    .labelled(),
    data.frame(frame = "sector", unit = "P", label = "Prim."),
    variant = "short"
  )
  expect_equal(scale_label(s, "P", frame = "sector"), "Primary")
  expect_equal(scale_label(s, c("P", "S"), "sector", variant = "short"),
               c("Prim.", "S"))
  s2 <- attach_labels_scale(
    s, data.frame(frame = "sector", unit = "S", label = "Sec."),
    variant = "short", default = "short"
  )
  expect_equal(scale_label(s2, c("P", "S"), "sector"), c("Prim.", "Sec."))
  expect_error(scale_label(s, "P", "sector", variant = "nope"), "variant")
})

test_that("the table is validated", {
  s <- scale_example()
  lab <- function(...) data.frame(..., stringsAsFactors = FALSE)
  expect_error(
    attach_labels_scale(s, lab(frame = "nope", unit = "P", label = "x")),
    "not in the object"
  )
  expect_error(
    attach_labels_scale(s, lab(frame = "sector", unit = "ZZ", label = "x")),
    "not members"
  )
  expect_error(
    attach_labels_scale(s, lab(frame = "sector", unit = "P", label = "")),
    "non-empty"
  )
  expect_error(
    attach_labels_scale(s, lab(frame = "sector", unit = c("P", "P"),
                               label = c("a", "b"))),
    "more than one label"
  )
  expect_error(
    attach_labels_scale(s, lab(frame = "sector", unit = "P", label = "x",
                               extra = 1)),
    "unknown column"
  )
})

test_that("a label is replaced only with overwrite = TRUE", {
  s <- .labelled()
  new <- data.frame(frame = "sector", unit = "P", label = "Primary sector")
  expect_error(attach_labels_scale(s, new, variant = "name"), "already present")
  s2 <- attach_labels_scale(s, new, variant = "name", overwrite = TRUE)
  expect_equal(scale_label(s2, "P", "sector"), "Primary sector")
  expect_equal(nrow(scale_labels(s2)), 3L)
})

test_that("scale_from_leaftable() takes labels", {
  df <- data.frame(g = c("a", "a", "b"), unit = c("u1", "u2", "u3"))
  s <- scale_from_leaftable(
    df, frames = "g",
    labels = data.frame(frame = "g", unit = "a", label = "Alpha")
  )
  expect_equal(scale_label(s, c("a", "b"), "g"), c("Alpha", "b"))
})

test_that("subsetting trims the labels to the members that remain", {
  s <- .labelled()
  f <- filter_scale(s, "sector", "P")
  expect_equal(scale_labels(f)$unit, c("P", NA))
  expect_equal(scale_label(f, "P", "sector"), "Primary")
})

test_that("print and summary report the labels", {
  s <- .labelled()
  expect_output(print(s), "Labels: sector \\[name\\] \\(default: name\\)")
  sm <- summary(s)
  expect_equal(sm$labels$n, 3L)
  expect_output(print(sm), "labels:")
})

test_that("join_scale() attaches the display names", {
  s <- .labelled()
  d <- data.frame(sector = c("S", "P"), v = 1:2)
  nm <- S7::prop(s, "meta")[["name"]]
  out <- join_scale(d, s, labels = TRUE)
  expect_equal(out[[paste0(nm, ".label")]], c("Secondary", "Primary"))
  expect_false(paste0(nm, ".label") %in% names(join_scale(d, s)))
  expect_error(join_scale(d, s, labels = "nope"), "variant")
})

test_that("labels survive a definition round trip", {
  s <- .labelled()
  f <- withr::local_tempfile(fileext = ".json")
  write_scale(s, f)
  back <- read_scale(f)
  expect_equal(scale_labels(back), scale_labels(s))
  expect_equal(scale_label(back, NA, "sector"), "Sector")
  # a scale without labels writes no labels table
  f0 <- withr::local_tempfile(fileext = ".json")
  write_scale(scale_example(), f0)
  expect_null(jsonlite::read_json(f0)$tables$labels)
})
