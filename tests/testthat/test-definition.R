# Definition files: write_scale() / read_scale(), the header and table
# codecs, bundles vs single files, the payload hooks and the class registry.

.with_meta <- function() {
  s <- .fuels()
  meta <- S7::prop(s, "meta")
  meta$labels <- data.frame(frame = "carrier", unit = "Coal",
                            label_short = "Coal", stringsAsFactors = FALSE)
  meta$tokens <- c(group = "g", carrier = "c")
  meta$year_start <- list(month = 4L, day = 1L)
  meta$flag <- TRUE
  S7::prop(s, "meta") <- meta
  s
}

test_that("a single JSON file round-trips a scale with its tables", {
  s <- .with_meta()
  f <- withr::local_tempfile(fileext = ".json")
  write_scale(s, f, overwrite = TRUE)
  expect_true(file.exists(f))
  back <- read_scale(f)
  expect_true(scale_is(back))
  expect_identical(scale_frames(back), scale_frames(s))
  expect_identical(S7::prop(back, "members"), S7::prop(s, "members"))
  expect_identical(scale_key(back), "fuel")
  expect_equal(scale_leaftable(back), scale_leaftable(s))
  expect_equal(scale_attributes(back), scale_attributes(s))
  expect_equal(scale_aliases(back), scale_aliases(s))
  m0 <- S7::prop(s, "meta")
  m1 <- S7::prop(back, "meta")
  expect_identical(m1$name, m0$name)
  expect_identical(m1$tokens, m0$tokens)            # named vector survives
  expect_identical(m1$year_start, m0$year_start)    # a list stays a list
  expect_equal(m1$labels, m0$labels)                # a data.frame too
  expect_identical(m1$flag, TRUE)
  expect_identical(m1$weights, m0$weights)
  # the whole object, up to numeric precision
  expect_equal(back, s)
})

test_that("the header is plain JSON with the documented shape", {
  f <- withr::local_tempfile(fileext = ".json")
  write_scale(.fuels(), f, overwrite = TRUE)
  h <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  expect_identical(h$schema_version, 1L)
  expect_identical(h$class, "nestedscales::NestedScale")
  expect_identical(h$key, "fuel")
  expect_identical(unlist(h$frames), c("group", "phase", "carrier", "fuel"))
  expect_named(h$tables, c("leaftable", "attributes", "aliases"))
  expect_true(!is.null(h$tables$leaftable$inline$columns$fuel))
  expect_identical(h$tables$attributes$inline$types$value, "double")
  expect_identical(h$tables$attributes$inline$types$frame, "string")
  expect_identical(h$payload, structure(list(), names = character()))
  # a missing value in a table is null, not a string
  expect_null(h$tables$leaftable$inline$columns$phase[[9]])
})

test_that("YAML is accepted in and offered out, with the same content", {
  skip_if_not_installed("yaml")
  s <- .with_meta()
  fy <- withr::local_tempfile(fileext = ".yaml")
  fj <- withr::local_tempfile(fileext = ".json")
  write_scale(s, fy, overwrite = TRUE)
  write_scale(s, fj, overwrite = TRUE)
  expect_equal(read_scale(fy), read_scale(fj))
  expect_equal(read_scale(fy), s)
  expect_error(write_scale(s, fy, format = "json", overwrite = TRUE),
               "ends in .yaml")
})

test_that("a bundle writes the tables as arrow files and reads back identical", {
  skip_if_not_installed("arrow")
  s <- .fuels()
  d <- file.path(withr::local_tempdir(), "fuels.scale")
  write_scale(s, d, tables = "arrow")
  expect_setequal(list.files(d), c("scale.json", "leaftable.arrow",
                                   "attributes.arrow", "aliases.arrow"))
  back <- read_scale(d)
  expect_identical(scale_leaftable(back), scale_leaftable(s))
  expect_identical(scale_attributes(back), scale_attributes(s))
  expect_identical(scale_aliases(back), scale_aliases(s))
  expect_identical(back, s)
  h <- jsonlite::fromJSON(file.path(d, "scale.json"), simplifyVector = FALSE)
  expect_identical(h$tables$leaftable, list(file = "leaftable.arrow",
                                            format = "arrow"))
})

test_that("csv tables carry their types and read back equal", {
  s <- .fuels()
  d <- file.path(withr::local_tempdir(), "fuels")
  write_scale(s, d, tables = "csv")
  expect_true(file.exists(file.path(d, "attributes.csv")))
  back <- read_scale(d)
  expect_equal(scale_leaftable(back), scale_leaftable(s))
  expect_equal(scale_attributes(back), scale_attributes(s))
  expect_true(is.na(scale_leaftable(back)$phase[9]))
})

test_that("auto inlines small scales and files large ones", {
  s <- scale_example()
  d <- file.path(withr::local_tempdir(), "small")
  write_scale(s, d)
  expect_identical(list.files(d), "scale.json")
  big <- scale_from_leaftable(
    data.frame(top = "T", unit = sprintf("u%04d", 1:1500)),
    frames = c("top", "unit"), name = "big"
  )
  d2 <- file.path(withr::local_tempdir(), "big")
  write_scale(big, d2)
  files <- list.files(d2)
  expect_true(any(grepl("^leaftable\\.(arrow|csv)$", files)))
  expect_identical(scale_units(read_scale(d2)), scale_units(big))
})

test_that("overwrite and junk directories are handled explicitly", {
  s <- scale_example()
  f <- withr::local_tempfile(fileext = ".json")
  write_scale(s, f, overwrite = TRUE)
  expect_error(write_scale(s, f), "already exists")
  expect_error(write_scale(s, f, tables = "arrow"), "can only inline")

  d <- file.path(withr::local_tempdir(), "b")
  write_scale(s, d)
  expect_error(write_scale(s, d), "already holds a definition")
  expect_no_error(write_scale(s, d, overwrite = TRUE))

  junk <- withr::local_tempdir()
  writeLines("x", file.path(junk, "notes.txt"))
  expect_error(write_scale(s, junk), "not a scale bundle")
  expect_error(read_scale(junk), "holds no scale.json")
  expect_error(read_scale(file.path(junk, "notes.txt")), "not a .json")
})

test_that("meta that cannot be written is refused by name before any file", {
  s <- scale_example()
  meta <- S7::prop(s, "meta")
  meta$callback <- function() NULL
  S7::prop(s, "meta") <- meta
  f <- withr::local_tempfile(fileext = ".json")
  expect_error(write_scale(s, f, overwrite = TRUE), "cannot be written: callback")
  expect_false(file.exists(f))
})

test_that("a newer schema version is refused", {
  f <- withr::local_tempfile(fileext = ".json")
  write_scale(scale_example(), f, overwrite = TRUE)
  h <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  h$schema_version <- 99L
  writeLines(jsonlite::toJSON(h, auto_unbox = TRUE, null = "null"), f)
  expect_error(read_scale(f), "schema_version 99")
})

test_that("an old (0.1.1) object writes a definition", {
  path <- test_path("fixtures", "scale-0.1.1.rds")
  skip_if_not(file.exists(path))
  old <- readRDS(path)
  f <- withr::local_tempfile(fileext = ".json")
  write_scale(old, f, overwrite = TRUE)
  expect_equal(scale_leaftable(read_scale(f)), scale_leaftable(old))
})

test_that("the payload hooks carry a subclass through a bundle", {
  Shaped <- S7::new_class("Shaped",
    parent = scale_class(),
    properties = list(shape = S7::class_character),
    validator = function(self) {
      if (length(self@shape) != nrow(self@leaftable)) {
        "`shape` needs one entry per leaftable row"
      }
    }
  )
  S7::method(scale_write_payload, Shaped) <- function(x, dir, header, ...) {
    if (is.null(dir)) stop("Shaped needs a bundle", call. = FALSE)
    writeLines(x@shape, file.path(dir, "shape.txt"))
    header$payload$shape <- list(file = "shape.txt", format = "lines")
    header
  }
  S7::method(scale_read_payload, Shaped) <- function(x, dir, header, ...) {
    Shaped(
      leaftable = scale_leaftable(x), frames = scale_frames(x),
      members = S7::prop(x, "members"), key = scale_key(x),
      meta = S7::prop(x, "meta"),
      shape = readLines(file.path(dir, header$payload$shape$file))
    )
  }
  base <- scale_example()
  s <- Shaped(
    leaftable = scale_leaftable(base), frames = scale_frames(base),
    members = S7::prop(base, "members"), key = scale_key(base),
    meta = S7::prop(base, "meta"),
    shape = paste0("shape_", scale_leaftable(base)$unit)
  )
  d <- file.path(withr::local_tempdir(), "shaped.scale")
  write_scale(s, d)
  expect_true(file.exists(file.path(d, "shape.txt")))
  h <- jsonlite::fromJSON(file.path(d, "scale.json"), simplifyVector = FALSE)
  expect_identical(h$class, class(s)[[1L]])

  # unregistered: refused, or the core on request
  clear <- function() rm(list = ls(envir = nestedscales:::.SCALE_CLASSES),
                         envir = nestedscales:::.SCALE_CLASSES)
  withr::defer(clear())
  expect_error(read_scale(d), "no such class is registered")
  core <- read_scale(d, class = "core")
  expect_false(S7::S7_inherits(core, Shaped))
  expect_identical(scale_units(core), scale_units(s))

  # registered: back as itself
  key <- register_scale_class(Shaped)
  expect_true(key %in% list_scale_classes())
  back <- read_scale(d)
  expect_true(S7::S7_inherits(back, Shaped))
  expect_identical(back@shape, s@shape)
  expect_error(register_scale_class(data.frame()), "S7 class")
})
