# scale_tree(): the parts of a scale and their marks. The marks are claims
# about scale_id(), so they are checked against it.

test_that("the tree lists every property and every leaftable column", {
  s <- scale_example()
  tr <- scale_tree(s)
  expect_s3_class(tr, "scale_tree")
  expect_named(tr, c("part", "parent", "kind", "shape", "mark", "verb", "note"))
  expect_setequal(tr$part[tr$parent == ""], S7::prop_names(s))
  expect_setequal(tr$part[tr$parent == "leaftable"], names(scale_leaftable(s)))
  expect_true(all(tr$mark %in% c("", "fixed", "derived", "mutable")))
})

test_that("the marks follow the identity", {
  s <- scale_example()
  tr <- scale_tree(s)
  mark <- function(part) tr$mark[tr$part == part]
  expect_identical(mark("frames"), "fixed")
  expect_identical(mark("key"), "fixed")
  expect_identical(mark("members"), "derived")
  cols <- tr[tr$parent == "leaftable", ]
  expect_identical(
    cols$mark[cols$kind %in% c("key", "frame")],
    rep("fixed", length(scale_frames(s)))
  )
  expect_true(all(cols$mark[cols$kind == "weight"] == "mutable"))
  expect_setequal(cols$part[cols$kind == "weight"], scale_weights(s))
})

test_that("changing a mutable part keeps the identity", {
  s <- scale_example()
  id <- scale_id(s)
  hash <- function(x) sub("^.*@", "", scale_id(x))
  lab <- attach_labels_scale(s, data.frame(
    frame = "sector", unit = scale_units(s, "sector")[[1L]], label = "First"
  ))
  expect_identical(scale_id(lab), id)
  al <- attach_aliases_scale(s, data.frame(
    frame = "sector", unit = scale_units(s, "sector")[[1L]], alias = "one"
  ), source = "t")
  expect_identical(scale_id(al), id)
  at <- attach_attributes_scale(
    s, data.frame(
      frame = "sector", unit = scale_units(s, "sector")[[1L]],
      attribute = "density", value = 1, unit_of_measure = "t/m3"
    ),
    source = "t", kind = "property"
  )
  expect_identical(scale_id(at), id)
  w <- s
  lt <- scale_leaftable(w)
  lt[[scale_weights(w)[[1L]]]] <- lt[[scale_weights(w)[[1L]]]] * 2
  S7::prop(w, "leaftable") <- lt
  expect_identical(scale_id(w), id)
  m <- s
  meta <- S7::prop(m, "meta")
  meta$desc <- "another description"
  S7::prop(m, "meta") <- meta
  expect_identical(hash(m), hash(s))
})

test_that("changing a fixed part gives another scale", {
  s <- scale_example()
  lt <- scale_leaftable(s)
  fr <- scale_frames(s)
  lt[[fr[[1L]]]] <- paste0(lt[[fr[[1L]]]], "x")
  other <- scale_from_leaftable(lt, frames = fr, key = scale_key(s),
                                weights = scale_weights(s), name = "example")
  expect_false(identical(scale_id(other), scale_id(s)))
})

test_that("a product has its own tree", {
  p <- scale_product(a = scale_example(), b = scale_example2())
  tr <- scale_tree(p)
  expect_setequal(tr$part[tr$parent == ""],
                  c("axes", "keys", "joint_weights", "meta"))
  expect_identical(tr$part[tr$parent == "axes"], c("a", "b"))
  expect_identical(tr$note[tr$part == "a"], scale_id(scale_example()))
})

test_that("the drawing has one line per part, in either character set", {
  tr <- scale_tree(scale_example())
  a <- utils::capture.output(print(tr, ascii = TRUE))
  u <- utils::capture.output(print(tr, ascii = FALSE))
  expect_length(a, nrow(tr) + 1L)
  expect_length(u, nrow(tr) + 1L)
  expect_match(a[[1L]], "^<NestedScale> example@")
  expect_false(any(grepl("[^ -~]", a)))
  expect_true(all(grepl("^(\\+- |\\|  \\+- |   \\+- )", a[-1L])))
  expect_true(any(grepl("├", u)))
  expect_output(print(tr, ascii = TRUE), "attach_labels_scale()", fixed = TRUE)
  expect_output(str(scale_example()), "leaftable")
})

test_that("a subclass describes the parts it adds", {
  Sub <- S7::new_class("Sub",
    parent = scale_class(),
    properties = list(payload = S7::class_any, plain = S7::class_any)
  )
  S7::method(scale_payload_parts, Sub) <- function(x, ...) {
    data.frame(
      part = c("payload", "labels", "extra"),
      parent = c("", "", "leaftable"),
      mark = c("mutable", NA, "derived"),
      verb = c("set_payload()", "attach_labels_sub()", NA)
    )
  }
  s <- scale_example()
  x <- Sub(
    leaftable = scale_leaftable(s), frames = scale_frames(s),
    members = S7::prop(s, "members"), key = scale_key(s),
    meta = S7::prop(s, "meta"), payload = 1:3, plain = NULL
  )
  tr <- scale_tree(x)
  expect_identical(tr$mark[tr$part == "payload"], "mutable")
  expect_identical(tr$verb[tr$part == "labels"], "attach_labels_sub()")
  expect_identical(tr$mark[tr$part == "labels"], "mutable")
  expect_identical(tr$note[tr$part == "plain"], "added by the subclass")
  expect_identical(tr$mark[tr$part == "plain"], "")
  # a new child sits with the other children of its parent
  kids <- which(tr$parent == "leaftable")
  expect_identical(tr$part[max(kids)], "extra")
  expect_identical(diff(range(kids)), length(kids) - 1L)
  expect_output(print(tr, ascii = TRUE), "^<Sub> ")
})
