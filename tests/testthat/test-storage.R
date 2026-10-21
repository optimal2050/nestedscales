# =========================================================================== #
# Array views and the scale-aware dataset store.
# =========================================================================== #

.sp <- function() scale_product(a = scale_example(), b = scale_example2())

.sd <- function() {
  d <- merge(
    data.frame(unit = c("U1", "U2", "U3"), stringsAsFactors = FALSE),
    data.frame(period = c("p1", "p2"), stringsAsFactors = FALSE)
  )
  d$v <- seq_len(nrow(d))
  d
}

# Arrays -----------------------------------------------------------------------

test_that("as_scale_array() shapes the table by the axes", {
  p <- .sp()
  a <- as_scale_array(.sd(), p, value = "v")
  expect_identical(dim(a), c(7L, 4L)) # 7 units x 4 periods
  expect_identical(dimnames(a)[[1]], scale_units(scale_example()))
  expect_identical(dimnames(a)[[2]], scale_units(scale_example2()))
  # supplied cells carry their value, the rest are the fill
  d <- .sd()
  expect_equal(a["U1", "p1"], d$v[d$unit == "U1" & d$period == "p1"])
  expect_true(is.na(a["U6", "p4"]))
})

test_that("the array round-trips back to the long table", {
  p <- .sp()
  d <- .sd()
  back <- as_scale_table(as_scale_array(d, p, value = "v"), p, value = "v")
  key <- function(z) paste(z$unit, z$period)
  expect_setequal(key(back), key(d))
  expect_equal(back$v[match(key(d), key(back))], d$v)
})

test_that("as_scale_table() can keep the uncovered cells", {
  p <- .sp()
  full <- as_scale_table(as_scale_array(.sd(), p, value = "v"), p,
    value = "v", drop_na = FALSE
  )
  expect_identical(nrow(full), 28L)
  expect_true(anyNA(full$v))
})

test_that("a fill value other than NA is honoured", {
  p <- .sp()
  a <- as_scale_array(.sd(), p, value = "v", fill = 0)
  expect_equal(a["U6", "p4"], 0)
  expect_false(anyNA(a))
})

test_that("a one-dimensional NestedScale also works", {
  s <- scale_example()
  d <- data.frame(unit = c("U1", "U2"), v = c(5, 6), stringsAsFactors = FALSE)
  a <- as_scale_array(d, s, value = "v")
  expect_identical(dim(a), 7L)
  expect_equal(a[["U1"]], 5)
})

test_that("an oversized array is refused rather than allocated", {
  p <- .sp()
  expect_error(
    as_scale_array(.sd(), p, value = "v", limit = 10),
    "above `limit`"
  )
})

test_that("codes that are not units are an error, never silently dropped", {
  p <- .sp()
  d <- .sd()
  d$unit[1] <- "NOPE"
  expect_error(as_scale_array(d, p, value = "v"), "not units of axis")
})

test_that("the value column is inferred, and ambiguity is reported", {
  p <- .sp()
  expect_no_error(as_scale_array(.sd(), p))
  d <- .sd()
  d$w <- 1
  expect_error(as_scale_array(d, p), "cannot infer the value column")
})

test_that("a missing key column is named", {
  p <- .sp()
  d <- .sd()
  d$period <- NULL
  expect_error(as_scale_array(d, p, value = "v"), "one key column per axis")
})

test_that("as_scale_table() checks the array's shape", {
  p <- .sp()
  expect_error(
    as_scale_table(array(1, c(2, 2)), p),
    "but this scale describes"
  )
})

# The store --------------------------------------------------------------------

test_that("a product dataset round-trips through the store", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  p <- .sp()
  d <- .sd()
  dir <- withr::local_tempdir()
  path <- file.path(dir, "store")

  write_scale_dataset(d, p, path)
  ds <- open_scale_dataset(path)

  expect_s3_class(ds, "scale_dataset")
  expect_s3_class(ds$scale, "nestedscales::ScaleProduct")
  expect_identical(names(scale_axes(ds$scale)), c("a", "b"))
  expect_identical(product_keys(ds$scale), product_keys(p))

  got <- as.data.frame(dplyr::collect(ds$data))
  expect_setequal(paste(got$unit, got$period), paste(d$unit, d$period))
})

test_that("an unavailable codec falls back to uncompressed IPC", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "store")

  expect_warning(
    write_scale_dataset(.sd(), .sp(), path, compression = "not-a-codec"),
    "unavailable; writing uncompressed"
  )
  got <- as.data.frame(dplyr::collect(open_scale_dataset(path)$data))
  expect_equal(nrow(got), nrow(.sd()))
})

test_that("the reopened scales are the same scales", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  p <- .sp()
  dir <- withr::local_tempdir()
  write_scale_dataset(.sd(), p, file.path(dir, "s"))
  back <- open_scale_dataset(file.path(dir, "s"))$scale

  for (a in names(scale_axes(p))) {
    orig <- scale_axes(p, a)
    got <- scale_axes(back, a)
    expect_identical(scale_frames(got), scale_frames(orig), label = a)
    expect_identical(scale_key(got), scale_key(orig), label = a)
    expect_identical(scale_units(got), scale_units(orig), label = a)
    expect_identical(scale_weights(got), scale_weights(orig), label = a)
    expect_equal(as.data.frame(scale_leaftable(got)),
      as.data.frame(scale_leaftable(orig)),
      ignore_attr = TRUE,
      label = a
    )
  }
})

test_that("a stored dataset can be recast without re-declaring anything", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  p <- .sp()
  d <- .sd()
  dir <- withr::local_tempdir()
  write_scale_dataset(d, p, file.path(dir, "s"))
  ds <- open_scale_dataset(file.path(dir, "s"))

  out <- suppressWarnings(
    recast_product(ds$data, ds$scale,
      target = list(a = "sector"),
      values = "v", rules = "sum", collect = TRUE
    )
  )
  ref <- suppressWarnings(
    recast_product(d, p,
      target = list(a = "sector"), values = "v",
      rules = "sum"
    )
  )
  key <- function(z) paste(as.data.frame(z)$sector, as.data.frame(z)$period)
  got <- as.data.frame(out)[order(key(out)), ]
  ref <- as.data.frame(ref)[order(key(ref)), ]
  expect_equal(got$v, ref$v)
})

test_that("a single NestedScale round-trips too", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  s <- scale_example()
  d <- data.frame(unit = c("U1", "U2"), v = c(1, 2), stringsAsFactors = FALSE)
  dir <- withr::local_tempdir()
  write_scale_dataset(d, s, file.path(dir, "s"))
  ds <- open_scale_dataset(file.path(dir, "s"))
  expect_s3_class(ds$scale, "nestedscales::NestedScale")
  expect_identical(scale_units(ds$scale), scale_units(s))
})

test_that("partitioning writes a pruned layout", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  p <- .sp()
  d <- .sd()
  d$year <- rep(c(2020, 2021), length.out = nrow(d))
  dir <- withr::local_tempdir()
  write_scale_dataset(d, p, file.path(dir, "s"), partitioning = "year")
  # hive layout: one directory per partition value
  parts <- list.dirs(file.path(dir, "s", "data"), recursive = FALSE)
  expect_true(any(grepl("year=2020", parts)))
  expect_true(any(grepl("year=2021", parts)))

  info <- scale_dataset_info(file.path(dir, "s"))
  expect_identical(info$kind, "product")
  expect_setequal(info$axes, c("a", "b"))
  expect_gt(info$files, 1)
})

test_that("the store refuses to clobber and to write junk", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  p <- .sp()
  dir <- withr::local_tempdir()
  path <- file.path(dir, "s")
  write_scale_dataset(.sd(), p, path)
  expect_error(write_scale_dataset(.sd(), p, path), "already exists")
  expect_no_error(write_scale_dataset(.sd(), p, path, overwrite = TRUE))

  d <- .sd()
  d$period <- NULL
  expect_error(
    write_scale_dataset(d, p, file.path(dir, "t")),
    "one key column per axis"
  )
  expect_error(
    write_scale_dataset(.sd(), p, file.path(dir, "u"),
      partitioning = "nope"
    ),
    "not in the data"
  )
})

test_that("meta that cannot be written as YAML is refused up front", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  s <- scale_example()
  meta <- S7::prop(s, "meta")
  meta$callback <- function() NULL
  S7::prop(s, "meta") <- meta
  d <- data.frame(unit = "U1", v = 1, stringsAsFactors = FALSE)
  dir <- withr::local_tempdir()
  expect_error(
    write_scale_dataset(d, s, file.path(dir, "s")),
    "cannot be written"
  )
  # and nothing was left behind
  expect_false(dir.exists(file.path(dir, "s", "data")))
})

test_that("opening a folder that is not a store says so", {
  skip_if_not_installed("jsonlite")
  dir <- withr::local_tempdir()
  expect_error(open_scale_dataset(dir), "not a scale dataset")
  expect_error(scale_dataset_info(dir), "not a scale dataset")
})

test_that("print() describes the store", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")
  p <- .sp()
  dir <- withr::local_tempdir()
  write_scale_dataset(.sd(), p, file.path(dir, "s"))
  ds <- open_scale_dataset(file.path(dir, "s"))
  expect_output(print(ds), "scale_dataset")
  expect_output(print(ds), "product over a x b")
})
