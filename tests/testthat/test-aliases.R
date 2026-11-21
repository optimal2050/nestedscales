# Aliases and strict matching.

test_that("exact, alias, ambiguous and none are told apart", {
  es <- .fuels()
  m <- scale_match(es, c("Lignite", "lignite", "hard coal", "elc", "nope"))
  expect_equal(m$method, c("exact", "exact", "alias", "ambiguous", "none"))
  expect_equal(m$member[1:3], c("Lignite", "Lignite", "Anthracite"))
  expect_equal(m$frame[3L], "fuel")
  expect_match(m$candidates[4L], "fuel/Electricity")
  expect_match(m$candidates[4L], "carrier/Electricity")
  expect_true(is.na(m$member[5L]))
})

test_that("a name reused at two frames is ambiguous until `frame=` is given", {
  es <- .fuels()
  expect_equal(scale_match(es, "Electricity")$method, "ambiguous")
  m2 <- scale_match(es, "Electricity", frame = "carrier")
  expect_equal(m2$method, "exact")
  expect_equal(m2$frame, "carrier")
  m3 <- scale_match(es, "elc", frame = "fuel")
  expect_equal(m3$method, "alias")
  expect_equal(m3$member, "Electricity")
  # case-insensitive exact matching also hits across frames
  s <- scale_example()
  expect_equal(scale_match(s, "g1")$method, "ambiguous")   # class and group
  expect_equal(scale_match(s, "g1", frame = "group")$member, "G1")
})

test_that("the leaf column is searched when it is the leaf level", {
  grid <- expand.grid(m = c("m1", "m2"), h = c("h1", "h2"),
                      stringsAsFactors = FALSE)
  grid$item <- paste(grid$m, grid$h, sep = "_")
  s <- scale_from_leaftable(grid, frames = c("m", "h"), leaf = "item")
  m <- scale_match(s, c("M1_H2", "h1"))
  expect_equal(m$method, c("exact", "exact"))
  expect_equal(m$frame, c("item", "h"))
})

test_that("`source=` restricts the alias stage", {
  es <- attach_aliases_scale(
    .fuels(), data.frame(frame = "carrier", member = "Gas", alias = "NG"),
    source = "commodity"
  )
  expect_equal(scale_match(es, "NG")$method, "alias")
  expect_equal(scale_match(es, "NG", source = "example")$method, "none")
  expect_equal(scale_match(es, "ng", source = "commodity")$member, "Gas")
})

test_that("scale_aliases filters by frame and source", {
  es <- .fuels()
  expect_equal(nrow(scale_aliases(es)), 5L)
  expect_equal(nrow(scale_aliases(es, frame = "carrier")), 3L)
  expect_equal(nrow(scale_aliases(es, source = "nope")), 0L)
  expect_named(scale_aliases(es), c("frame", "member", "alias", "source"))
})

test_that("attach refuses duplicates and bad tables, keeps the input", {
  es <- .fuels()
  expect_error(
    attach_aliases_scale(
      es, data.frame(frame = "fuel", member = "Anthracite", alias = "hard coal"),
      source = "example"),
    "already present"
  )
  expect_error(
    attach_aliases_scale(
      es, data.frame(frame = "zz", member = "Coal", alias = "c", source = "x")),
    "frame(s) not in the object: zz", fixed = TRUE
  )
  expect_error(
    attach_aliases_scale(
      es, data.frame(frame = "fuel", member = "Nope", alias = "c", source = "x")),
    "not members"
  )
  es2 <- attach_aliases_scale(
    es, data.frame(frame = "fuel", member = "Anthracite", alias = "anth",
                   source = "x"))
  expect_equal(nrow(scale_aliases(es2)), 6L)
  expect_equal(nrow(scale_aliases(es)), 5L)
})
