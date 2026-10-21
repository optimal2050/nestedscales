# The catalogue of shipped definitions and id resolution.

.catalog_dir <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  write_scale(scale_example(), file.path(d, "example.json"))
  write_scale(.fuels(), file.path(d, "fuels.scale"), tables = "csv")
  writeLines("not a scale", file.path(d, "README.md"))
  d
}

test_that("a registered directory is listed with its definitions", {
  withr::defer(clear_scale_dirs())
  clear_scale_dirs()
  d <- .catalog_dir()
  register_scale_dir(d, package = "testpkg")
  dirs <- list_scale_dirs()
  expect_identical(dirs$package, "testpkg")
  cat <- scale_catalog()
  expect_named(cat, c("id", "name", "kind", "key", "frames", "n_atoms",
                      "package", "path"))
  expect_setequal(cat$id, c("example", "fuels"))
  ex <- cat[cat$id == "example", ]
  expect_identical(ex$kind, "NestedScale")
  expect_identical(ex$key, "unit")
  expect_identical(ex$frames, "sector/class/group/unit")
  expect_identical(ex$n_atoms, 7L)
  fu <- cat[cat$id == "fuels", ]
  expect_identical(fu$n_atoms, 9L)
  expect_identical(fu$name, "fuels")
})

test_that("read_scale() resolves an id, and ambiguity needs `package=`", {
  withr::defer(clear_scale_dirs())
  clear_scale_dirs()
  d1 <- .catalog_dir()
  register_scale_dir(d1, package = "one")
  s <- read_scale("fuels")
  expect_identical(scale_units(s), scale_units(.fuels()))
  expect_error(read_scale("nope"), "neither a file nor a definition")

  d2 <- withr::local_tempdir()
  write_scale(scale_example2(), file.path(d2, "fuels.json"))
  register_scale_dir(d2, package = "two")
  expect_error(read_scale("fuels"), "several packages")
  expect_identical(scale_frames(read_scale("fuels", package = "two")),
                   scale_frames(scale_example2()))
  # a hand-registered directory has no package
  register_scale_dir(withr::local_tempdir())
  expect_true(anyNA(list_scale_dirs()$package))
  expect_error(register_scale_dir("/no/such/dir"), "not a directory")
})
