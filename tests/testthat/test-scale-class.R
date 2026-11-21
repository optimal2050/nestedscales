# =========================================================================== #
# The NestedScale class: properties, validator invariants, accessors, base generics.
# =========================================================================== #

test_that("scale_example() has the documented shape", {
  s <- scale_example()
  expect_s3_class(s, "nestedscales::NestedScale")
  expect_identical(scale_frames(s), c("sector", "class", "group", "item"))
  expect_identical(scale_frames(s, finest = TRUE), "item")
  expect_identical(scale_leaf_column(s), "item")
  expect_identical(nrow(scale_leaftable(s)), 7L)
  expect_identical(scale_weights(s), c("size", "count"))
  # the unassigned leaf is NA at every coarser frame
  lt <- scale_leaftable(s)
  expect_true(is.na(lt$sector[lt$item == "OTH"]))
})

test_that("accessors agree with the properties", {
  s <- tidy_scale()
  expect_identical(scale_frames(s), S7::prop(s, "frames"))
  expect_identical(scale_members(s), c("L1", "L2", "L3", "L4"))
  expect_identical(scale_members(s, "mid"), c("M1", "M2"))
  expect_identical(
    scale_rank(s, c("mid", "leaf", "nope")),
    c(2L, 3L, NA_integer_)
  )
  expect_identical(names(s), scale_frames(s))
  expect_identical(as.data.frame(s), scale_leaftable(s))
})

test_that("scale_members() defaults to the leaf frame and checks its argument", {
  s <- tidy_scale()
  expect_identical(scale_members(s), scale_members(s, "leaf"))
  expect_error(scale_members(s, "nope"), "is not a frame")
  expect_error(scale_members(s, c("mid", "leaf")), "single frame name")
})

test_that("the leaf column may be named independently of the frames", {
  s <- keyed_scale()
  expect_identical(scale_leaf_column(s), "id")
  expect_identical(scale_frames(s), c("grp", "sub"))
  expect_true("id" %in% names(scale_leaftable(s)))
})

test_that("a single-frame scale is legal", {
  s <- flat_scale()
  expect_identical(scale_frames(s), "item")
  expect_identical(scale_members(s), c("u1", "u2"))
  # no adjacent pair, so no nesting table
  expect_null(summary(s)$nesting)
})

# Validator ------------------------------------------------------------------

test_that("the validator rejects a leaftable without the leaf column", {
  expect_error(
    NestedScale(
      leaftable = data.frame(a = "x", stringsAsFactors = FALSE),
      frames = "a", members = list(a = "x"), leaf = "item"
    ),
    "must have a `item` column"
  )
})

test_that("the validator rejects duplicate leaf keys", {
  df <- data.frame(
    grp = c("A", "A"), item = c("u1", "u1"),
    stringsAsFactors = FALSE
  )
  expect_error(
    NestedScale(
      leaftable = df, frames = c("grp", "item"),
      members = list(grp = "A", item = "u1"), leaf = "item"
    ),
    "must be unique"
  )
})

test_that("the validator rejects an empty leaftable", {
  df <- data.frame(
    grp = character(), item = character(),
    stringsAsFactors = FALSE
  )
  expect_error(
    NestedScale(
      leaftable = df, frames = c("grp", "item"),
      members = list(grp = "A", item = "u1"), leaf = "item"
    ),
    "at least one row"
  )
})

test_that("members must match the non-NA codes present in the leaftable", {
  df <- data.frame(
    grp = c("A", "B"), item = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  expect_error(
    NestedScale(
      leaftable = df, frames = c("grp", "item"),
      members = list(
        grp = c("A", "B", "GHOST"),
        item = c("u1", "u2")
      ),
      leaf = "item"
    ),
    "exactly the non-NA"
  )
  # ... and NA memberships are legal (partial coverage)
  df2 <- data.frame(
    grp = c("A", NA), item = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  expect_s3_class(
    NestedScale(
      leaftable = df2, frames = c("grp", "item"),
      members = list(grp = "A", item = c("u1", "u2")), leaf = "item"
    ),
    "nestedscales::NestedScale"
  )
})

test_that("the leaf column name is a frame only as the finest frame", {
  # legal: the finest frame IS the leaf column
  df <- data.frame(
    grp = c("A", "A"), item = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  expect_s3_class(
    scale_from_leaftable(df, frames = c("grp", "item")), "nestedscales::NestedScale"
  )
  # illegal: the name of the leaf column used as a coarser frame
  df2 <- data.frame(
    item = c("A", "A"), leaf = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  df2$unit_key <- df2$leaf
  expect_error(
    NestedScale(
      leaftable = df2, frames = c("item", "leaf"),
      members = list(item = "A", leaf = c("u1", "u2")), leaf = "item"
    ),
    "reserved names"
  )
})

test_that("frame names must be syntactically valid and unique", {
  df <- data.frame(a = "A", item = "u1", stringsAsFactors = FALSE)
  expect_error(
    NestedScale(
      leaftable = df, frames = c("a", "a"),
      members = list(a = "A"), leaf = "item"
    ), "must be unique"
  )
  expect_false(is_valid_frame("2bad"))
  expect_true(is_valid_frame("reg32"))
})

test_that("weight columns must be numeric, non-negative and not all zero", {
  df <- data.frame(
    grp = c("A", "A"), item = c("u1", "u2"),
    w = c(-1, 2), stringsAsFactors = FALSE
  )
  expect_error(
    scale_from_leaftable(df, frames = c("grp", "item"), weights = "w"),
    ">= 0"
  )
  df$w <- c(0, 0)
  expect_error(
    scale_from_leaftable(df, frames = c("grp", "item"), weights = "w"),
    "sums to zero"
  )
  df$w <- c("a", "b")
  expect_error(
    scale_from_leaftable(df, frames = c("grp", "item"), weights = "w"),
    "must be numeric"
  )
})

test_that("default_weight must name a declared weight", {
  df <- data.frame(
    grp = c("A", "A"), item = c("u1", "u2"),
    w = c(1, 2), stringsAsFactors = FALSE
  )
  expect_error(
    scale_from_leaftable(df,
      frames = c("grp", "item"), weights = "w",
      default_weight = "nope"
    ),
    "must be one of"
  )
})

test_that("coverage bookkeeping is validated against the leaftable", {
  s <- tidy_scale()
  lt <- scale_leaftable(s)
  # a coverage that does not match the leaftable is rejected
  expect_error(
    NestedScale(
      leaftable = lt, frames = scale_frames(s),
      members = S7::prop(s, "members"), leaf = "leaf",
      meta = list(
        weights = "w", coverage = c(w = 0.5),
        parent_totals = list(w = 10)
      )
    ),
    "does not match the leaftable"
  )
  # ... and the consistent one is accepted (10 of 20 = 0.5)
  expect_s3_class(
    NestedScale(
      leaftable = lt, frames = scale_frames(s),
      members = S7::prop(s, "members"), leaf = "leaf",
      meta = list(
        weights = "w", coverage = c(w = 0.5),
        parent_totals = list(w = 20)
      )
    ),
    "nestedscales::NestedScale"
  )
})

test_that("coverage must lie in (0, 1] over declared weights", {
  s <- tidy_scale()
  expect_error(
    NestedScale(
      leaftable = scale_leaftable(s), frames = scale_frames(s),
      members = S7::prop(s, "members"), leaf = "leaf",
      meta = list(weights = "w", coverage = c(w = 1.5))
    ),
    "must lie in"
  )
  expect_error(
    NestedScale(
      leaftable = scale_leaftable(s), frames = scale_frames(s),
      members = S7::prop(s, "members"), leaf = "leaf",
      meta = list(weights = "w", coverage = c(nope = 1))
    ),
    "over declared weights"
  )
})

# Base generics --------------------------------------------------------------

test_that("print() shows the hierarchy and weights", {
  expect_output(print(scale_example()), "NestedScale: example")
  expect_output(print(scale_example()), "sector \\(2\\)")
  expect_output(print(scale_example()), "Leaves: 7")
  expect_output(print(scale_example()), "Weights: size, count")
  # the unassigned leaf is reported
  expect_output(print(scale_example()), "1 member unassigned")
})

test_that("format() is the one-line form", {
  expect_match(format(tidy_scale()), "^<NestedScale\\[top/mid/leaf\\] leaves=4>$")
})

test_that("summary() returns the classed quantitative view", {
  s <- scale_example()
  sm <- summary(s)
  expect_s3_class(sm, "summary_Scale")
  expect_named(sm, c(
    "name", "desc", "frames", "unassigned", "n_leaves",
    "weights", "weight_totals", "default_weight",
    "coverage", "sampled", "parent_name", "nesting",
    "attributes", "aliases", "labels", "source", "vocab"
  ))
  expect_identical(sm$n_leaves, 7L)
  expect_false(sm$sampled)
  expect_equal(sm$weight_totals[["size"]], 3100)
  # the cross-cutting class/group pair is flagged with its offenders
  row <- sm$nesting[sm$nesting$parent == "class" &
    sm$nesting$child == "group", ]
  expect_identical(nrow(row), 1L)
  expect_false(row$nests)
  expect_gt(row$n_offenders, 0)
})

test_that("summary() prints its formatted view, not a list dump", {
  sm <- summary(scale_example())
  expect_output(print(sm), "summary of NestedScale 'example'")
  expect_output(print(sm), "CROSS-CUTTING")
  expect_output(print(sm), "leaves:")
})

test_that("scale_vocab() gives the neutral words by default", {
  v <- scale_vocab(scale_example())
  expect_identical(v$object, "NestedScale")
  expect_identical(v$frame, "frame")
  expect_identical(v$member, "member")
})

test_that("accessors reject non-NestedScale input", {
  expect_error(scale_frames(42), "must be a NestedScale object")
  expect_error(scale_leaftable("x"), "must be a NestedScale object")
})
