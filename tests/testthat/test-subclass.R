# =========================================================================== #
# The subclass contract.
#
# `timescales::Calendar` and `geoscales::Geoscale` become S7 subclasses of
# `NestedScale`. Everything those rebases depend on is asserted here against a
# synthetic subclass, so the engine can never quietly break the arrangement:
#
#   * the parent validator runs, and the child's own checks run after it
#   * an ALIAS property (`timeframes` -> `frames`) reads AND writes
#   * `class()` keeps the child first and gains NestedScale at the TAIL, so the
#     twins' existing S3 registrations still win
#   * every engine accessor works on the subclass unchanged
#   * `scale_vocab()` can be overridden, which is what keeps the twins'
#     error messages in their own dimension's words
# =========================================================================== #

# A stand-in for Calendar: fixes the key, adds a prop, aliases `frames`,
# and adds one invariant of its own.
Widget <- S7::new_class(
  "Widget",
  parent = NestedScale,
  properties = list(
    payload = S7::new_property(S7::class_any, default = NULL),
    slots = scale_alias_property("frames")
  ),
  validator = function(self) {
    if (!identical(S7::prop(self, "key"), "widget")) {
      return("`key` must be \"widget\"")
    }
    NULL
  }
)

.widget <- function(...) {
  df <- data.frame(
    grp = c("A", "A", "B"),
    widget = c("w1", "w2", "w3"),
    w = c(1, 2, 3), stringsAsFactors = FALSE
  )
  Widget(
    leaftable = df, frames = c("grp", "widget"),
    members = list(grp = c("A", "B"), widget = c("w1", "w2", "w3")),
    key = "widget", meta = list(
      name = "wx", weights = "w",
      default_weight = "w"
    ), ...
  )
}

test_that("a subclass inherits the parent validator", {
  # the PARENT's rule (members must match the leaftable) still bites
  df <- data.frame(
    grp = c("A", "A"), widget = c("w1", "w2"),
    stringsAsFactors = FALSE
  )
  expect_error(
    Widget(
      leaftable = df, frames = c("grp", "widget"),
      members = list(
        grp = c("A", "GHOST"),
        widget = c("w1", "w2")
      ),
      key = "widget"
    ),
    "exactly the non-NA"
  )
})

test_that("a subclass adds its own invariants on top", {
  df <- data.frame(
    grp = c("A", "A"), unit = c("w1", "w2"),
    stringsAsFactors = FALSE
  )
  expect_error(
    Widget(
      leaftable = df, frames = c("grp", "unit"),
      members = list(grp = "A", unit = c("w1", "w2")),
      key = "unit"
    ),
    "must be \"widget\""
  )
})

test_that("class() puts the child first and NestedScale at the tail", {
  w <- .widget()
  cl <- class(w)
  # The "pkg::Child" spelling leads when the class is defined in a package --
  # which is why the twins keep their `print.geoscales::Geoscale`
  # registrations. Whether this test-local class gets that prefix depends on
  # how the suite runs (R CMD check does, load_all() does not), so assert the
  # invariant that actually matters: the CHILD precedes NestedScale.
  child <- which(cl %in% c("Widget", "nestedscales::Widget"))
  expect_gt(length(child), 0L)
  expect_true("nestedscales::NestedScale" %in% cl)
  expect_true(S7::S7_inherits(w, NestedScale))
  # this ordering is what lets a child's S3 method win over NestedScale's
  expect_lt(min(child), match("nestedscales::NestedScale", cl))
  expect_identical(cl[[length(cl)]], "S7_object")
})

test_that("an alias property reads and writes the inherited prop", {
  w <- .widget()
  expect_identical(w@slots, scale_frames(w))
  expect_identical(S7::prop(w, "slots"), c("grp", "widget"))

  w@slots <- c("grp", "widget")
  expect_identical(S7::prop(w, "frames"), c("grp", "widget"))
  # an invalid write is caught by the PARENT validator, which proves the
  # setter really writes `frames` rather than storing a private copy
  expect_error(
    {
      w@slots <- c("grp", "nope")
    },
    "missing frame columns"
  )
})

test_that("an alias setter no-ops on NULL", {
  # S7's generated constructor writes every dynamic property once with NULL
  # before the real values land; a setter that forwarded it would make the
  # subclass impossible to construct.
  w <- .widget()
  w@slots <- NULL
  expect_identical(scale_frames(w), c("grp", "widget"))
})

test_that("engine accessors work unchanged on a subclass", {
  w <- .widget()
  expect_identical(scale_frames(w), c("grp", "widget"))
  expect_identical(scale_units(w), c("w1", "w2", "w3"))
  expect_identical(scale_key(w), "widget")
  expect_identical(scale_weights(w), "w")
  expect_identical(nrow(scale_leaftable(w)), 3L)
  expect_equal(scale_coverage(w), c(w = 1))
  expect_true(scale_nests(w, "grp", "widget"))
  expect_identical(nrow(scale_family(w, "grp", "widget")), 3L)
})

test_that("a subclass carries its own extra property", {
  w <- .widget(payload = list(1, 2, 3))
  expect_length(S7::prop(w, "payload"), 3L)
  expect_null(S7::prop(.widget(), "payload"))
})

test_that("scale_vocab() can be overridden per dimension", {
  S7::method(scale_vocab, Widget) <- function(x, ...) {
    list(
      object = "Widget", frame = "slot", frames = "slots",
      unit = "widget", units = "widgets", atoms = "widgetbase"
    )
  }
  w <- .widget()
  expect_identical(scale_vocab(w)$frame, "slot")
  # and the shared checker speaks the subclass's language
  expect_error(scale_units(w, "nope"), "is not a slot of this Widget")
})

test_that("a positional per-atom payload survives a row subset", {
  Shaped <- S7::new_class("Shaped",
    parent = scale_class(),
    properties = list(shape = S7::class_character),
    validator = function(self) {
      if (length(self@shape) != nrow(self@leaftable)) {
        "`shape` needs one entry per leaftable row"
      }
    }
  )
  S7::method(scale_payload_slice, Shaped) <- function(x, i, ...) {
    x@shape <- x@shape[i]
    x
  }
  base <- scale_example()
  lt <- scale_leaftable(base)
  s <- Shaped(
    leaftable = lt, frames = scale_frames(base),
    members = S7::prop(base, "members"), key = scale_key(base),
    meta = S7::prop(base, "meta"),
    shape = paste0("shape_", lt$unit)
  )
  p <- filter_scale(s, "sector", "P")
  expect_identical(p@shape, paste0("shape_", scale_leaftable(p)$unit))
  expect_true(S7::S7_inherits(p, Shaped))
})

test_that("a collapse keeps the concrete class and asks the payload to merge", {
  Shaped <- S7::new_class("Shaped",
    parent = scale_class(),
    properties = list(shape = S7::class_character),
    validator = function(self) {
      if (length(self@shape) != nrow(self@leaftable)) {
        "`shape` needs one entry per leaftable row"
      }
    }
  )
  base <- scale_example()
  lt <- scale_leaftable(base)
  s <- Shaped(
    leaftable = lt, frames = scale_frames(base),
    members = S7::prop(base, "members"), key = scale_key(base),
    meta = S7::prop(base, "meta"),
    shape = paste0("shape_", lt$unit)
  )
  # no collapse method: the positional payload no longer fits and the
  # subclass's own validator says so -- loud, not silently misaligned
  expect_error(prune_scale(s, "class"), "one entry per leaftable row")

  # with one: merged by `map`, one new row index per old row, NA = dropped
  S7::method(scale_payload_collapse, Shaped) <- function(x, map, ...) {
    merged <- tapply(x@shape, map, function(z) paste(z, collapse = "+"))
    x@shape <- unname(merged[as.character(seq_len(max(map, na.rm = TRUE)))])
    x
  }
  p <- prune_scale(s, "class")
  expect_true(S7::S7_inherits(p, Shaped))
  expect_identical(scale_frames(p), c("sector", "class"))
  expect_identical(length(p@shape), nrow(scale_leaftable(p)))
  expect_identical(p@shape[scale_leaftable(p)$class == "G1"], "shape_U1+shape_U2")
  # the default hook is the identity: a scale with no payload is unchanged
  expect_identical(scale_payload_collapse(base, c(1L, 1L, 2L, 2L, 3L, 3L, NA)),
                   base)
})
