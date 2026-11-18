# The data link: scale identity and bound code columns.

.atoms <- function() {
  data.frame(
    unit = c("U1", "U2", "U3", "U4", "U5", "U6"),
    capacity = c(1, 2, 3, 4, 5, 6)
  )
}

test_that("scale_id() names the structure, not the weights or the order", {
  s <- scale_example()
  id <- scale_id(s)
  expect_match(id, "^.*@[0-9a-f]{8}$")
  lt <- scale_leaftable(s)
  fr <- scale_frames(s)
  # a new weight, and a different row order, are the same scale
  lt2 <- lt[rev(seq_len(nrow(lt))), ]
  lt2$extra <- seq_len(nrow(lt2))
  s2 <- scale_from_leaftable(lt2, frames = fr, key = scale_key(s),
                             name = S7::prop(s, "meta")[["name"]])
  expect_identical(scale_id(s2), id)
  # a subset, and another scale, are not
  expect_false(identical(scale_id(filter_scale(s, "sector", "P")), id))
  expect_false(identical(scale_id(scale_example2()), id))
})

test_that("bind_scale() checks the codes and records scale and frame", {
  s <- scale_example()
  d <- data.frame(class = c("G1", "G2", "S1"), v = 1:3)
  b <- bind_scale(d, s)
  ln <- scale_link(b)
  expect_equal(ln$column, "class")
  expect_equal(ln$frame, "class")
  expect_equal(ln$id, scale_id(s))
  expect_true(is.character(b$class))
  expect_equal(as.character(b$class), d$class)
  expect_equal(nrow(scale_link(d)), 0L)
  expect_identical(unbind_scale(b), d)

  bad <- data.frame(class = c("G1", "nope"), v = 1:2)
  expect_error(bind_scale(bad, s), "not .* at .* 'class'")
  expect_error(bind_scale(data.frame(a = 1), s), "no column named after")
  # a column under another name
  o <- bind_scale(data.frame(origin = c("P", "S")), s, c(origin = "sector"))
  expect_equal(scale_link(o)$frame, "sector")
})

test_that("the link survives the usual table operations", {
  s <- scale_example()
  b <- bind_scale(.atoms(), s)
  id <- scale_id(s)
  linked <- function(d) identical(scale_link(d)$id, id)

  expect_true(linked(b[b$capacity > 2, , drop = FALSE]))
  expect_true(linked(dplyr::filter(b, capacity > 2)))
  expect_true(linked(dplyr::mutate(b, twice = 2 * capacity)))
  expect_true(linked(dplyr::arrange(b, dplyr::desc(capacity))))
  expect_true(linked(dplyr::bind_rows(b, b)))
  expect_true(linked(
    dplyr::summarise(dplyr::group_by(b, unit), n = dplyr::n())
  ))
  other <- data.frame(unit = c("U1", "U2"), z = c(10, 20))
  expect_true(linked(dplyr::left_join(b, other, by = "unit")))
  expect_true(linked(dplyr::left_join(other, b, by = "unit")))
  expect_equal(sum(b$unit == "U1"), 1L)
  expect_true(all(b$unit %in% scale_units(s, "unit")))
})

test_that("codes of two scales, or two frames, do not combine", {
  s <- scale_example()
  a <- bind_scale(data.frame(class = "G1", v = 1), s)
  b <- bind_scale(data.frame(class = "P", v = 1), s, c(class = "sector"))
  expect_error(dplyr::bind_rows(a, b), "different scales or frames")
})

test_that("verbs take the source from the link and bind the result", {
  s <- scale_example()
  plain <- recast_scale(.atoms(), s, source = "unit", target = "sector",
                        rule = "sum")
  b <- bind_scale(.atoms(), s)
  out <- recast_scale(b, s, target = "sector", rule = "sum")
  expect_equal(scale_link(out)$frame, "sector")
  expect_equal(unbind_scale(out), plain)
  # unbound data gives an unbound result
  expect_equal(nrow(scale_link(plain)), 0L)

  # a column under another name is found through its link
  r <- stats::setNames(.atoms(), c("origin", "capacity"))
  r <- bind_scale(r, s, c(origin = "unit"))
  out2 <- recast_scale(r, s, target = "sector", rule = "sum")
  expect_equal(out2$capacity, plain$capacity)
  expect_error(
    recast_scale(r, s, source = "class", key = "origin", target = "sector",
                 rule = "sum"),
    "is bound to"
  )
})

test_that("a scale of the same structure under another name is the same scale", {
  s <- scale_example()
  twin <- scale_from_leaftable(scale_leaftable(s), frames = scale_frames(s),
                               key = scale_key(s), name = "renamed")
  expect_false(identical(scale_id(s), scale_id(twin)))
  b <- bind_scale(.atoms(), s)
  out <- recast_scale(b, twin, target = "sector", rule = "sum")
  expect_equal(as.data.frame(unbind_scale(out)),
               as.data.frame(unbind_scale(
                 recast_scale(b, s, target = "sector", rule = "sum"))))
  expect_silent(vctrs::vec_c(bind_scale(.atoms(), s)[[scale_key(s)]],
                             bind_scale(.atoms(), twin)[[scale_key(s)]]))
})

test_that("data bound to another scale is refused", {
  s <- scale_example()
  lt <- scale_leaftable(s)
  # same names and codes, different grouping: only the identity tells
  lt$sector <- rev(lt$sector)
  twin <- scale_from_leaftable(lt, frames = scale_frames(s),
                               key = scale_key(s), name = "twin")
  b <- bind_scale(.atoms(), s)
  expect_error(
    recast_scale(b, twin, target = "sector", rule = "sum"),
    "is bound to .* not to 'twin'"
  )
  expect_error(join_scale(b, twin, attach = TRUE), "is bound to")
  expect_error(recast_to_atoms(b, twin, rule = "sum"), "is bound to")
})

test_that("the atom routes and join_scale() keep the link", {
  s <- scale_example()
  y <- bind_scale(data.frame(sector = c("P", "S"), capacity = c(10, 20)), s)
  at <- recast_to_atoms(y, s, rule = "sum")
  ln <- scale_link(at)
  expect_equal(ln$column, scale_key(s))
  back <- recast_from_atoms(at, s, target = "sector", values = "capacity",
                            rule = "sum")
  expect_equal(scale_link(back)$frame, "sector")
  expect_equal(back$capacity, c(10, 20))

  j <- join_scale(bind_scale(.atoms(), s), s, attach = "sector",
                  as_factor = FALSE)
  lj <- scale_link(j)
  nm <- S7::prop(s, "meta")[["name"]]
  expect_true(all(c("unit", paste0(nm, ".sector")) %in% lj$column))
  expect_equal(lj$frame[lj$column == paste0(nm, ".sector")], "sector")
})

test_that("a stored dataset records the link and holds plain strings", {
  skip_if_not_installed("arrow")
  s <- scale_example()
  dir <- withr::local_tempdir()
  store <- file.path(dir, "store")
  write_scale_dataset(bind_scale(.atoms(), s), s, store)
  ds <- open_scale_dataset(store)
  ln <- scale_link(ds)
  expect_equal(ln$column, "unit")
  expect_equal(ln$id, scale_id(s))
  back <- bind_scale(as.data.frame(dplyr::collect(ds$data)), ds$scale)
  expect_equal(scale_link(back)$id, scale_id(s))
  # data bound to another scale does not go into this store
  other <- bind_scale(data.frame(period = "p1", unit = "U1", v = 1),
                      scale_example2(), "period")
  expect_error(write_scale_dataset(other, s, file.path(dir, "bad")),
               "not a scale of this store")
})

test_that("as_scale_unit() and a data.table carry the link too", {
  s <- scale_example()
  u <- as_scale_unit(c("P", "S"), s, "sector")
  expect_true(is_scale_unit(u))
  expect_false(is_scale_unit("P"))
  expect_error(as_scale_unit("nope", s, "sector"), "not")
  skip_if_not_installed("data.table")
  dt <- data.table::as.data.table(.atoms())
  b <- bind_scale(dt, s)
  expect_s3_class(b, "data.table")
  expect_false(is_scale_unit(dt$unit))          # the input is not modified
  out <- recast_scale(b, s, target = "sector", rule = "sum")
  expect_s3_class(out, "data.table")
  expect_equal(scale_link(out)$frame, "sector")
})
