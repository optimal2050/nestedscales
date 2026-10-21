# =========================================================================== #
# recast_to_atoms() / recast_from_atoms(): the two halves of the route.
#
# The law that matters: their composition IS recast_scale().
# =========================================================================== #

.tidy <- function() {
  df <- data.frame(
    top = c("T", "T", "T", "T"),
    mid = c("M1", "M1", "M2", "M2"),
    leaf = c("L1", "L2", "L3", "L4"),
    w = c(1, 3, 2, 4),
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(df, frames = c("top", "mid", "leaf"), name = "tidy")
}

test_that("to_atoms splits an extensive quantity by weight", {
  s <- .tidy()
  d <- data.frame(
    mid = c("M1", "M2"), cap = c(4, 6),
    stringsAsFactors = FALSE
  )
  out <- recast_to_atoms(d, s, source = "mid", rule = "sum")
  expect_named(out, c("leaf", "cap", "weight"))
  # M1 (w 1 + 3) splits 4 as 1 and 3
  expect_equal(out$cap[out$leaf == "L1"], 1)
  expect_equal(out$cap[out$leaf == "L2"], 3)
  expect_equal(sum(out$cap), 10)
})

test_that("to_atoms repeats an intensive quantity", {
  s <- .tidy()
  d <- data.frame(
    mid = c("M1", "M2"), eff = c(0.5, 0.8),
    stringsAsFactors = FALSE
  )
  out <- recast_to_atoms(d, s, source = "mid", rule = "weighted_mean")
  expect_equal(out$eff[out$leaf == "L1"], 0.5)
  expect_equal(out$eff[out$leaf == "L2"], 0.5)
  expect_equal(out$eff[out$leaf == "L3"], 0.8)
})

test_that("to_atoms attaches the atom weight, and can be told not to", {
  s <- .tidy()
  d <- data.frame(
    mid = c("M1", "M2"), cap = c(4, 6),
    stringsAsFactors = FALSE
  )
  expect_true("weight" %in% names(recast_to_atoms(d, s,
    source = "mid",
    rule = "sum"
  )))
  bare <- recast_to_atoms(d, s,
    source = "mid", rule = "sum",
    attach_weight = FALSE
  )
  expect_false("weight" %in% names(bare))
})

test_that("from_atoms aggregates back up", {
  s <- .tidy()
  atoms <- data.frame(
    leaf = c("L1", "L2", "L3", "L4"), cap = c(1, 3, 2, 4),
    stringsAsFactors = FALSE
  )
  out <- recast_from_atoms(atoms, s, target = "mid", rule = "sum")
  expect_named(out, c("mid", "cap"))
  expect_equal(out$cap[out$mid == "M1"], 4)
  expect_equal(out$cap[out$mid == "M2"], 6)
})

test_that("the composition of the halves equals recast_scale()", {
  s <- .tidy()
  d <- data.frame(
    mid = c("M1", "M2"), cap = c(4, 6),
    stringsAsFactors = FALSE
  )
  for (r in c("sum", "weighted_mean", "mean")) {
    direct <- recast_scale(d, s, source = "mid", target = "top", rule = r)
    halves <- recast_from_atoms(
      recast_to_atoms(d, s, source = "mid", rule = r), s,
      target = "top", rule = r
    )
    expect_equal(direct, halves,
      ignore_attr = TRUE,
      label = sprintf("rule %s", r)
    )
  }
})

test_that("the halves round-trip a value through the atom layer", {
  s <- .tidy()
  d <- data.frame(
    mid = c("M1", "M2"), cap = c(4, 6),
    stringsAsFactors = FALSE
  )
  back <- recast_from_atoms(recast_to_atoms(d, s, source = "mid", rule = "sum"),
    s,
    target = "mid", rule = "sum"
  )
  expect_equal(back$cap[back$mid == "M1"], 4)
  expect_equal(back$cap[back$mid == "M2"], 6)
})

test_that("from_atoms uses the attached weight for a weighted mean", {
  s <- .tidy()
  atoms <- data.frame(
    leaf = c("L1", "L2"), eff = c(0.2, 0.6),
    weight = c(1, 3), stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_from_atoms(atoms, s, target = "mid", rule = "weighted_mean")
  )
  expect_equal(out$eff[out$mid == "M1"], (0.2 * 1 + 0.6 * 3) / 4)
})

test_that("from_atoms honours a weight column that varies by identifier", {
  s <- .tidy()
  atoms <- data.frame(
    leaf = rep(c("L1", "L2"), 2),
    year = rep(c(2020, 2021), each = 2),
    eff = c(0.2, 0.6, 0.2, 0.6),
    cap = c(1, 3, 3, 1),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_from_atoms(atoms, s,
      target = "mid", values = "eff",
      rule = "weighted_mean", weight = "cap"
    )
  )
  expect_equal(
    out$eff[out$mid == "M1" & out$year == 2020],
    (0.2 * 1 + 0.6 * 3) / 4
  )
  expect_equal(
    out$eff[out$mid == "M1" & out$year == 2021],
    (0.2 * 3 + 0.6 * 1) / 4
  )
})

test_that("na_rm reads NA as silence rather than as an unknown", {
  s <- .tidy()
  atoms <- data.frame(
    leaf = c("L1", "L2"), cap = c(NA, 3),
    weight = c(1, 3), stringsAsFactors = FALSE
  )
  poisoned <- suppressWarnings(
    recast_from_atoms(atoms, s, target = "mid", values = "cap", rule = "sum")
  )
  expect_true(is.na(poisoned$cap[poisoned$mid == "M1"]))

  rescued <- suppressWarnings(
    recast_from_atoms(atoms, s,
      target = "mid", values = "cap", rule = "sum",
      na_rm = TRUE
    )
  )
  expect_equal(rescued$cap[rescued$mid == "M1"], 3)
})

test_that("an all-NA group stays NA even with na_rm", {
  s <- .tidy()
  atoms <- data.frame(
    leaf = c("L1", "L2"), cap = c(NA_real_, NA_real_),
    weight = c(1, 3), stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_from_atoms(atoms, s,
      target = "mid", values = "cap", rule = "sum",
      na_rm = TRUE
    )
  )
  expect_true(is.na(out$cap[out$mid == "M1"]))
})

test_that("the halves refuse rule \"share\"", {
  s <- .tidy()
  d <- data.frame(
    mid = c("M1", "M2"), cap = c(4, 6),
    stringsAsFactors = FALSE
  )
  expect_error(
    recast_to_atoms(d, s, source = "mid", rule = "share"),
    "not supported by recast_to_atoms"
  )
  atoms <- data.frame(
    leaf = c("L1", "L2"), cap = c(1, 3),
    stringsAsFactors = FALSE
  )
  expect_error(
    suppressWarnings(
      recast_from_atoms(atoms, s, target = "mid", rule = "share")
    ),
    "not supported by recast_from_atoms"
  )
})

test_that("a cross-object recast goes through the shared atom keys", {
  a <- .tidy()
  # a second scale over the same atoms, grouped differently
  df <- data.frame(
    half = c("H1", "H1", "H2", "H2"),
    leaf = c("L1", "L3", "L2", "L4"),
    w = c(1, 2, 3, 4), stringsAsFactors = FALSE
  )
  b <- scale_from_leaftable(df, frames = c("half", "leaf"), name = "halves")

  d <- data.frame(
    mid = c("M1", "M2"), cap = c(4, 6),
    stringsAsFactors = FALSE
  )
  out <- recast_scale(d, a, source = "mid", target = b, rule = "sum")
  # totals conserve across the object boundary
  expect_equal(sum(out$leaf %in% scale_units(b)), 4L)
  expect_equal(sum(out$cap, na.rm = TRUE), 10)
})
