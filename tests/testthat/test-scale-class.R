# =========================================================================== #
# The NestedScale class: properties, validator invariants, accessors, base generics.
# =========================================================================== #

test_that("scale_example() has the documented shape", {
  s <- scale_example()
  expect_s3_class(s, "nestedscales::NestedScale")
  expect_identical(scale_frames(s), c("sector", "class", "group", "unit"))
  expect_identical(scale_frames(s, finest = TRUE), "unit")
  expect_identical(scale_key(s), "unit")
  expect_identical(nrow(scale_leaftable(s)), 7L)
  expect_identical(scale_weights(s), c("size", "count"))
  # the unassigned atom is NA at every coarser frame
  lt <- scale_leaftable(s)
  expect_true(is.na(lt$sector[lt$unit == "OTH"]))
})

test_that("accessors agree with the properties", {
  s <- tidy_scale()
  expect_identical(scale_frames(s), S7::prop(s, "frames"))
  expect_identical(scale_units(s), c("L1", "L2", "L3", "L4"))
  expect_identical(scale_units(s, "mid"), c("M1", "M2"))
  expect_identical(
    scale_rank(s, c("mid", "leaf", "nope")),
    c(2L, 3L, NA_integer_)
  )
  expect_identical(names(s), scale_frames(s))
  expect_identical(as.data.frame(s), scale_leaftable(s))
})

test_that("scale_units() defaults to the atom frame and checks its argument", {
  s <- tidy_scale()
  expect_identical(scale_units(s), scale_units(s, "leaf"))
  expect_error(scale_units(s, "nope"), "is not a frame")
  expect_error(scale_units(s, c("mid", "leaf")), "single frame name")
})

test_that("the key column may be named independently of the frames", {
  s <- keyed_scale()
  expect_identical(scale_key(s), "id")
  expect_identical(scale_frames(s), c("grp", "sub"))
  expect_true("id" %in% names(scale_leaftable(s)))
})

test_that("a single-frame scale is legal", {
  s <- flat_scale()
  expect_identical(scale_frames(s), "unit")
  expect_identical(scale_units(s), c("u1", "u2"))
  # no adjacent pair, so no nesting table
  expect_null(summary(s)$nesting)
})

# Validator ------------------------------------------------------------------

test_that("the validator rejects a leaftable without the key column", {
  expect_error(
    NestedScale(
      leaftable = data.frame(a = "x", stringsAsFactors = FALSE),
      frames = "a", members = list(a = "x"), key = "unit"
    ),
    "must have a `unit` column"
  )
})

test_that("the validator rejects duplicate atom keys", {
  df <- data.frame(
    grp = c("A", "A"), unit = c("u1", "u1"),
    stringsAsFactors = FALSE
  )
  expect_error(
    NestedScale(
      leaftable = df, frames = c("grp", "unit"),
      members = list(grp = "A", unit = "u1")
    ),
    "must be unique"
  )
})

test_that("the validator rejects an empty leaftable", {
  df <- data.frame(
    grp = character(), unit = character(),
    stringsAsFactors = FALSE
  )
  expect_error(
    NestedScale(
      leaftable = df, frames = c("grp", "unit"),
      members = list(grp = "A", unit = "u1")
    ),
    "at least one row"
  )
})

test_that("members must match the non-NA codes present in the leaftable", {
  df <- data.frame(
    grp = c("A", "B"), unit = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  expect_error(
    NestedScale(
      leaftable = df, frames = c("grp", "unit"),
      members = list(
        grp = c("A", "B", "GHOST"),
        unit = c("u1", "u2")
      )
    ),
    "exactly the non-NA"
  )
  # ... and NA memberships are legal (partial coverage)
  df2 <- data.frame(
    grp = c("A", NA), unit = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  expect_s3_class(
    NestedScale(
      leaftable = df2, frames = c("grp", "unit"),
      members = list(grp = "A", unit = c("u1", "u2"))
    ),
    "nestedscales::NestedScale"
  )
})

test_that("the key name is reserved as a frame except as the finest frame", {
  # legal: the finest frame IS the key column
  df <- data.frame(
    grp = c("A", "A"), unit = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  expect_s3_class(
    scale_from_leaftable(df, frames = c("grp", "unit")), "nestedscales::NestedScale"
  )
  # illegal: the key name used as a coarser frame
  df2 <- data.frame(
    unit = c("A", "A"), leaf = c("u1", "u2"),
    stringsAsFactors = FALSE
  )
  df2$unit_key <- df2$leaf
  expect_error(
    NestedScale(
      leaftable = df2, frames = c("unit", "leaf"),
      members = list(unit = "A", leaf = c("u1", "u2")), key = "unit"
    ),
    "reserved names"
  )
})

test_that("frame names must be syntactically valid and unique", {
  df <- data.frame(a = "A", unit = "u1", stringsAsFactors = FALSE)
  expect_error(
    NestedScale(
      leaftable = df, frames = c("a", "a"),
      members = list(a = "A")
    ), "must be unique"
  )
  expect_false(is_valid_frame("2bad"))
  expect_true(is_valid_frame("reg32"))
})

test_that("weight columns must be numeric, non-negative and not all zero", {
  df <- data.frame(
    grp = c("A", "A"), unit = c("u1", "u2"),
    w = c(-1, 2), stringsAsFactors = FALSE
  )
  expect_error(
    scale_from_leaftable(df, frames = c("grp", "unit"), weights = "w"),
    ">= 0"
  )
  df$w <- c(0, 0)
  expect_error(
    scale_from_leaftable(df, frames = c("grp", "unit"), weights = "w"),
    "sums to zero"
  )
  df$w <- c("a", "b")
  expect_error(
    scale_from_leaftable(df, frames = c("grp", "unit"), weights = "w"),
    "must be numeric"
  )
})

test_that("default_weight must name a declared weight", {
  df <- data.frame(
    grp = c("A", "A"), unit = c("u1", "u2"),
    w = c(1, 2), stringsAsFactors = FALSE
  )
  expect_error(
    scale_from_leaftable(df,
      frames = c("grp", "unit"), weights = "w",
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
      members = S7::prop(s, "members"), key = "leaf",
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
      members = S7::prop(s, "members"), key = "leaf",
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
      members = S7::prop(s, "members"), key = "leaf",
      meta = list(weights = "w", coverage = c(w = 1.5))
    ),
    "must lie in"
  )
  expect_error(
    NestedScale(
      leaftable = scale_leaftable(s), frames = scale_frames(s),
      members = S7::prop(s, "members"), key = "leaf",
      meta = list(weights = "w", coverage = c(nope = 1))
    ),
    "over declared weights"
  )
})

# Base generics --------------------------------------------------------------

test_that("print() shows the hierarchy and weights", {
  expect_output(print(scale_example()), "NestedScale: example")
  expect_output(print(scale_example()), "sector \\(2\\)")
  expect_output(print(scale_example()), "Atoms: 7")
  expect_output(print(scale_example()), "Weights: size, count")
  # the unassigned atom is reported
  expect_output(print(scale_example()), "1 unit unassigned")
})

test_that("format() is the one-line form", {
  expect_match(format(tidy_scale()), "^<NestedScale\\[top/mid/leaf\\] atoms=4>$")
})

test_that("summary() returns the classed quantitative view", {
  s <- scale_example()
  sm <- summary(s)
  expect_s3_class(sm, "summary_Scale")
  expect_named(sm, c(
    "name", "desc", "frames", "unassigned", "n_atoms",
    "weights", "weight_totals", "default_weight",
    "coverage", "sampled", "parent_name", "nesting",
    "attributes", "aliases", "source", "vocab"
  ))
  expect_identical(sm$n_atoms, 7L)
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
  expect_output(print(sm), "atoms:")
})

test_that("scale_vocab() gives the neutral words by default", {
  v <- scale_vocab(scale_example())
  expect_identical(v$object, "NestedScale")
  expect_identical(v$frame, "frame")
  expect_identical(v$unit, "unit")
})

test_that("accessors reject non-NestedScale input", {
  expect_error(scale_frames(42), "must be a NestedScale object")
  expect_error(scale_leaftable("x"), "must be a NestedScale object")
})
