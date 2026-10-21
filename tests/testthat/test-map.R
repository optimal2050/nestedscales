# =========================================================================== #
# scale_map(): the crosswalk, its schema, and the registry.
# =========================================================================== #

test_that("the map has the documented schema", {
  s <- scale_example()
  m <- scale_map(s, "class", "group")
  expect_named(m, c("class", "group", "n_from", "n_overlap", "w", "w_from"))
  expect_true(is.numeric(m$w))
  expect_true(is.integer(m$n_overlap))
})

test_that("n_from is the source unit's full atom count", {
  s <- scale_example()
  m <- scale_map(s, "class", "unit")
  # class G1 holds U1 and U2
  expect_equal(unique(m$n_from[m$class == "G1"]), 2L)
  expect_true(all(m$n_overlap == 1L))
})

test_that("w_from is the source unit's full weight", {
  s <- scale_example()
  m <- scale_map(s, "class", "unit", weight = "size")
  expect_equal(unique(m$w_from[m$class == "G1"]), 300)
  expect_equal(sum(m$w[m$class == "G1"]), 300)
})

test_that("uncovered atoms appear with an NA target", {
  s <- scale_example()
  m <- scale_map(s, "unit", "sector")
  expect_true(any(is.na(m$sector)))
  expect_identical(m$unit[is.na(m$sector)], "OTH")
})

test_that("the split factor is well defined when no weight is declared", {
  df <- data.frame(
    grp = c("A", "A", "B"), unit = c("u1", "u2", "u3"),
    stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(df, frames = c("grp", "unit"), name = "noweights")
  m <- scale_map(s, "grp", "unit")
  # every atom weighs 1, so w/w_from == n_overlap/n_from
  expect_equal(m$w / m$w_from, m$n_overlap / m$n_from)
})

test_that("scale_map() rejects a same-frame pair and NestedScale arguments", {
  s <- scale_example()
  expect_error(scale_map(s, "class", "class"), "the same frame")
  expect_error(scale_map(s, s, "group"), "scale_map_between")
  expect_error(scale_map(s, "nope", "group"), "is not a frame")
})

test_that("cross-object maps match on shared atom keys", {
  a <- scale_example()
  df <- data.frame(
    big = c("X", "X", "Y", "Y", "Y", "Y", "Z"),
    unit = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH"),
    size = c(1, 1, 1, 1, 1, 1, 1),
    stringsAsFactors = FALSE
  )
  b <- scale_from_leaftable(df, frames = c("big", "unit"), name = "other")
  m <- scale_map_between(a, b)
  expect_named(m, c("example", "other", "n_from", "n_overlap", "w", "w_from"))
  expect_identical(nrow(m), 7L)
})

test_that("cross-object maps need distinct names and shared keys", {
  a <- scale_example()
  expect_error(scale_map_between(a, a), "same name")

  df <- data.frame(
    grp = c("A", "B"), unit = c("z1", "z2"),
    stringsAsFactors = FALSE
  )
  b <- scale_from_leaftable(df, frames = c("grp", "unit"), name = "disjoint")
  expect_error(scale_map_between(a, b), "share no `unit` keys")
})

test_that("scale_atom_pairs() is the documented seam", {
  s <- scale_example()
  d <- scale_atom_pairs(s, "class", "group")
  expect_named(d, c("source", "target", "w"))
  expect_identical(nrow(d), 7L)
})

test_that("extra map columns are carried through `by`", {
  s <- scale_example()
  d <- scale_atom_pairs(s, "class", "group")
  d2 <- rbind(cbind(d, year = 2020), cbind(d, year = 2021))
  m <- nestedscales:::.finish_map(d2, "class", "group", by = "year")
  expect_true("year" %in% names(m))
  # the counts are per year, not doubled
  expect_equal(unique(m$n_from[m$class == "G1"]), 2L)
})

# Registry -------------------------------------------------------------------

test_that("a registered map is returned as-is", {
  s <- scale_example()
  withr::defer(clear_scale_maps())
  fake <- data.frame(
    class = "G1", group = "GC", n_from = 1L, n_overlap = 1L,
    w = 1, w_from = 1, stringsAsFactors = FALSE
  )
  register_scale_map(s, "class", "group", fake)
  expect_equal(scale_map(s, "class", "group"), fake)
  expect_equal(get_scale_map(s, "class", "group"), fake)
})

test_that("registered maps are scoped to the object", {
  s <- scale_example()
  withr::defer(clear_scale_maps())
  fake <- data.frame(
    class = "G1", group = "GC", n_from = 1L, n_overlap = 1L,
    w = 1, w_from = 1, stringsAsFactors = FALSE
  )
  register_scale_map(s, "class", "group", fake)
  # a different object's identically-named frames are unaffected
  expect_null(get_scale_map("other_scale", "class", "group"))
})

test_that("registering NULL removes the entry", {
  s <- scale_example()
  withr::defer(clear_scale_maps())
  fake <- data.frame(
    class = "G1", group = "GC", n_from = 1L, n_overlap = 1L,
    w = 1, w_from = 1, stringsAsFactors = FALSE
  )
  register_scale_map(s, "class", "group", fake)
  register_scale_map(s, "class", "group", NULL)
  expect_null(get_scale_map(s, "class", "group"))
})

test_that("a registered map must have the schema columns", {
  s <- scale_example()
  expect_error(
    register_scale_map(s, "class", "group", data.frame(a = 1)),
    "missing column"
  )
  expect_error(
    register_scale_map(s, "class", "group", "nope"),
    "must be a data.frame"
  )
})

test_that("list_scale_maps() reports the keys", {
  s <- scale_example()
  withr::defer(clear_scale_maps())
  clear_scale_maps()
  fake <- data.frame(
    class = "G1", group = "GC", n_from = 1L, n_overlap = 1L,
    w = 1, w_from = 1, stringsAsFactors = FALSE
  )
  register_scale_map(s, "class", "group", fake)
  expect_identical(list_scale_maps()$key, "example:class->group")
})
