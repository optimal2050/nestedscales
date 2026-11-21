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
  d <- data.frame(item = c("U1", "U2", "U3", "U4", "U5", "U6"), v = 1:6)
  expect_no_error(recast_scale(d, old, source = "item", target = "sector",
                               rule = "sum"))
  expect_no_error(join_scale(d, old, attach = TRUE))
  expect_output(print(old), "NestedScale: example")
  expect_no_error(summary(old))
  f <- filter_scale(old, "sector", "P")
  expect_s3_class(S7::prop(f, "attributes"), "data.frame")   # healed
  p <- prune_scale(old, "class")
  expect_s3_class(S7::prop(p, "attributes"), "data.frame")
  panel <- merge(data.frame(item = scale_members(old)),
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
  expect_false("attributes" %in% names(S7::S7_class(s)@properties))
  # no message pattern: the wording is S7's and differs between its versions
  expect_error(S7::prop(s, "attributes"))
  expect_no_error(S7::validate(s))
  expect_identical(nrow(scale_attributes(s)), 0L)
  expect_identical(nrow(scale_aliases(s)), 0L)
  expect_output(print(s), "NestedScale: example")
  # the fixture's finest frame and leaf column are named `unit`
  d <- data.frame(unit = c("U1", "U2", "U3", "U4", "U5", "U6"), v = 1:6)
  expect_no_error(recast_scale(d, s, source = "unit", target = "sector",
                               rule = "sum"))
  f <- filter_scale(s, "sector", "P")
  expect_identical(scale_members(f, "sector"), "P")
  expect_true("attributes" %in% names(S7::S7_class(f)@properties))
  expect_s3_class(S7::prop(f, "attributes"), "data.frame")
  s2 <- attach_attributes_scale(
    s, data.frame(frame = "sector", member = "P", attribute = "density",
                  value = 1, unit_of_measure = "t/m3"),
    source = "t", kind = "property"
  )
  expect_identical(nrow(scale_attributes(s2)), 1L)
})

# Up to 0.2.0 the leaf column was the property `key`, and the attribute,
# alias and label tables named their code column `unit`.

# The fixture with the three tables as 0.2.0 stored them.
.keyed_old_scale <- function() {
  s <- readRDS(test_path("fixtures", "scale-0.1.1.rds"))
  attr(s, "attributes") <- data.frame(
    frame = "sector", unit = "P", attribute = "density", kind = "property",
    value = 1, lower = NA_real_, upper = NA_real_, unit_of_measure = "t/m3",
    source = "t", note = NA_character_, stringsAsFactors = FALSE
  )
  attr(s, "aliases") <- data.frame(
    frame = "sector", unit = "P", alias = "primary", source = "t",
    stringsAsFactors = FALSE
  )
  attr(s, "labels") <- data.frame(
    frame = "sector", unit = "P", variant = "label", label = "Primary",
    stringsAsFactors = FALSE
  )
  s
}

test_that("an object saved with `key` is read through the accessors", {
  s <- readRDS(test_path("fixtures", "scale-0.1.1.rds"))
  expect_identical(attr(s, "key", exact = TRUE), "unit")
  expect_null(attr(s, "leaf", exact = TRUE))
  expect_false("leaf" %in% names(S7::S7_class(s)@properties))
  expect_identical(scale_leaf_column(s), "unit")
  expect_identical(scale_leaf_frame(s), "unit")
  expect_identical(
    scale_members(s), c("U1", "U2", "U3", "U4", "U5", "U6", "OTH")
  )
  expect_identical(scale_rank(s, "unit"), 4L)
  expect_identical(scale_parents(s, "unit", "U5", target = "sector"), "S")
  tr <- scale_tree(s)
  expect_identical(tr$note[tr$part == "leaf"], "unit")
  expect_identical(tr$kind[tr$part == "unit"], "leaf column")
})

test_that("tables stored with a `unit` column are read as `member`", {
  s <- .keyed_old_scale()
  expect_no_error(S7::validate(s))
  at <- scale_attributes(s)
  expect_named(at, c("frame", "member", "attribute", "kind", "value", "lower",
                     "upper", "unit_of_measure", "source", "note"))
  expect_identical(at$member, "P")
  expect_identical(scale_aliases(s)$member, "P")
  expect_named(scale_labels(s), c("frame", "member", "variant", "label"))
  expect_identical(scale_match(s, "primary")$member, "P")
  expect_identical(scale_label(s, "P", "sector"), "Primary")
  r <- scale_attributes(s, "density", frame = "unit")
  expect_identical(r$origin_member[r$member == "U1"], "P")
  expect_true(is.na(r$value[r$member == "U5"]))
  # a validator embedded in an earlier class definition passes these tables
  # to the checks as they are stored
  v <- scale_vocab(s)
  fr <- scale_frames(s)
  mb <- S7::prop(s, "members")
  expect_identical(
    .check_attributes_table(attr(s, "attributes"), fr, mb, v), character()
  )
  expect_identical(
    .check_aliases_table(attr(s, "aliases"), fr, mb, v), character()
  )
  expect_identical(
    .check_labels_table(attr(s, "labels"), fr, mb, v), character()
  )
})

test_that("the write paths bring an old object to the current form", {
  s <- .keyed_old_scale()
  f <- filter_scale(s, "sector", "P")
  expect_true("leaf" %in% names(S7::S7_class(f)@properties))
  expect_identical(S7::prop(f, "leaf"), "unit")
  expect_null(attr(f, "key", exact = TRUE))
  expect_identical(S7::prop(f, "attributes")$member, "P")
  expect_identical(S7::prop(f, "aliases")$member, "P")
  expect_identical(S7::prop(f, "labels")$member, "P")
  expect_false("unit" %in% names(S7::prop(f, "attributes")))
  expect_no_error(S7::validate(f))

  s2 <- attach_aliases_scale(
    s, data.frame(frame = "sector", member = "S", alias = "secondary"),
    source = "t"
  )
  expect_identical(S7::prop(s2, "leaf"), "unit")
  expect_setequal(scale_aliases(s2)$member, c("P", "S"))

  path <- withr::local_tempfile(fileext = ".json")
  write_scale(s, path)
  h <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_identical(h$leaf, "unit")
  expect_true("member" %in% names(h$tables$attributes$inline$columns))
  back <- read_scale(path)
  expect_identical(scale_id(back), scale_id(s))
  expect_identical(scale_attributes(back)$member, "P")
})

test_that("scale_id() of an unchanged structure is what it was before 0.3.0", {
  # scale_example() as it was up to 0.2.0, with the finest frame `unit`
  df <- data.frame(
    sector = c("P", "P", "P", "P", "S", "S", NA),
    class = c("G1", "G1", "G2", "G2", "S1", "S1", NA),
    group = c("G1", "G1", "GB", "GB", "GB", "GC", NA),
    unit = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH"),
    size = c(100, 200, 300, 400, 500, 600, 1000),
    count = c(10, 90, 30, 70, 50, 50, 0),
    stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(
    df, frames = c("sector", "class", "group", "unit"), name = "example"
  )
  expect_identical(scale_leaf_column(s), "unit")
  # the values below were computed with 0.2.0, before the renaming
  expect_identical(scale_id(s), "example@491e9cf6")
  old <- readRDS(test_path("fixtures", "scale-0.1.1.rds"))
  expect_identical(scale_id(old), "example@491e9cf6")
  expect_identical(scale_id(scale_example2()), "example2@f6854959")
  expect_identical(scale_id(tidy_scale()), "tidy@dd57124b")
  expect_identical(scale_id(keyed_scale()), "keyed@7aab83c6")
})

test_that("a schema 1 definition is read into the current form", {
  s <- attach_labels_scale(
    .fuels(), data.frame(frame = "carrier", member = "Coal", label = "Coal")
  )
  path <- withr::local_tempfile(fileext = ".json")
  write_scale(s, path)
  txt <- readLines(path)
  expect_true(any(grepl("\"schema_version\": 2", txt, fixed = TRUE)))
  # the same definition as schema 1 named its fields
  txt <- sub("\"schema_version\": 2", "\"schema_version\": 1", txt,
             fixed = TRUE)
  txt <- sub("\"leaf\":", "\"key\":", txt, fixed = TRUE)
  txt <- gsub("\"member\":", "\"unit\":", txt, fixed = TRUE)
  expect_false(any(grepl("\"member\":|\"leaf\":", txt)))
  dir <- withr::local_tempdir()
  old <- file.path(dir, "fuels.json")
  writeLines(txt, old)

  back <- read_scale(old)
  expect_identical(scale_leaf_column(back), "fuel")
  expect_identical(scale_id(back), scale_id(s))
  expect_equal(scale_attributes(back), scale_attributes(s))
  expect_equal(scale_aliases(back), scale_aliases(s))
  expect_equal(scale_labels(back), scale_labels(s))

  withr::defer(clear_scale_dirs())
  clear_scale_dirs()
  register_scale_dir(dir, package = "testpkg")
  cat <- scale_catalog()
  expect_identical(cat$leaf[cat$id == "fuels"], "fuel")
})

test_that("the schema 1 goldens are still read", {
  dir <- test_path("..", "..", "specs", "goldens", "definitions")
  skip_if_not(dir.exists(dir), "the goldens are not in a built package")
  ex <- read_scale(file.path(dir, "example.json"))
  expect_identical(scale_leaf_column(ex), "unit")
  expect_identical(scale_id(ex), "example@491e9cf6")
  fu <- read_scale(file.path(dir, "fuels.json"))
  expect_identical(scale_leaf_column(fu), "fuel")
  expect_identical(nrow(scale_attributes(fu)), 6L)
  expect_true("member" %in% names(scale_attributes(fu)))
  expect_identical(nrow(scale_aliases(fu)), 5L)
  expect_true("member" %in% names(scale_aliases(fu)))
  skip_if_not_installed("arrow")
  suppressWarnings({
    tree <- read_scale(file.path(dir, "tree.scale"), class = "core")
    grid <- read_scale(file.path(dir, "grid.scale"), class = "core")
  })
  expect_identical(scale_attributes(tree)$member, scale_attributes(fu)$member)
  expect_identical(scale_leaf_column(grid), "unit")
})

test_that("a store written by 0.1.1 still opens", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("yaml")
  suppressWarnings(
    ds <- open_scale_dataset(test_path("fixtures", "legacy-store"))
  )
  expect_identical(scale_leaf_column(ds$scale), "unit")
  expect_identical(scale_id(ds$scale), "example@491e9cf6")
  expect_identical(scale_link(ds)$column, "unit")
  expect_identical(nrow(dplyr::collect(ds$data)), 7L)
})
