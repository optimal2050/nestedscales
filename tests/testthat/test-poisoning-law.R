# =========================================================================== #
# THE PARTIAL-SOURCE POISONING LAW.
#
# When a target unit's sources are only PARTIALLY present in the data, the
# result for that unit is NA -- not a partial answer. The engine gets this
# from a right join against the crosswalk, which injects an NA row for every
# (identifier, source) pair the data does not carry.
#
# This is stated here on its own because it is the semantics most at risk from
# any performance rewrite of `.recast_pipeline()`: switching the right join to
# an inner join would turn every case below into a plausible-looking partial
# number, and no other test in the suite would notice. A wholly-missing group
# is NOT sufficient evidence -- `.recast_complete()` fills those with NA under
# either join type, so a test using one would pass either way.
# =========================================================================== #

# class G1 holds exactly U1 and U2. Supplying only U1 makes G1 PARTIAL, while
# G2 (U3, U4) and S1 (U5, U6) are wholly absent -- the two cases must be
# distinguished, so both appear here.
.partial <- function(v = 1) {
  data.frame(unit = "U1", value = v, stringsAsFactors = FALSE)
}

test_that("a partially-supplied target is NA for every rule", {
  s <- scale_example()
  for (r in c("sum", "mean", "weighted_mean", "copy", "sd")) {
    out <- suppressWarnings(
      recast_scale(.partial(), s,
        source = "unit", target = "class", rule = r,
        weight = if (r == "weighted_mean") "size" else NULL
      )
    )
    got <- out$value[out$class == "G1"]
    expect_identical(length(got), 1L, label = sprintf("one G1 row (%s)", r))
    expect_true(is.na(got),
      label = sprintf(
        "G1 is NA under rule \"%s\" (partial source)",
        r
      )
    )
  }
})

test_that("the poisoning is partiality, not absence", {
  s <- scale_example()
  # Both are NA, but for DIFFERENT reasons, and only the first is the law
  # under test: G1 is poisoned by its missing sibling U2, while G2 is simply
  # absent and gets its NA from vocabulary completion.
  out <- suppressWarnings(
    recast_scale(.partial(), s, source = "unit", target = "class", rule = "sum")
  )
  expect_true(is.na(out$value[out$class == "G1"]))
  expect_true(is.na(out$value[out$class == "G2"]))
  # supplying BOTH of G1's sources gives a real answer -- so the NA above is
  # caused by the missing source, not by anything about G1 itself
  both <- suppressWarnings(
    recast_scale(
      data.frame(
        unit = c("U1", "U2"), value = c(1, 2),
        stringsAsFactors = FALSE
      ),
      s,
      source = "unit", target = "class", rule = "sum"
    )
  )
  expect_equal(both$value[both$class == "G1"], 3)
})

test_that("poisoning is per identifier group, not global", {
  s <- scale_example()
  # 2020 has both of G1's sources; 2021 has only one. The complete year must
  # keep its answer -- a poisoned group may not spread across groups.
  d <- data.frame(
    unit = c("U1", "U2", "U1"),
    year = c(2020, 2020, 2021),
    value = c(1, 2, 5),
    stringsAsFactors = FALSE
  )
  out <- suppressWarnings(
    recast_scale(d, s,
      source = "unit", target = "class", rule = "sum",
      values = "value"
    )
  )
  expect_equal(out$value[out$class == "G1" & out$year == 2020], 3)
  expect_true(is.na(out$value[out$class == "G1" & out$year == 2021]))
})

test_that("a partial source poisons through the atom halves too", {
  s <- scale_example()
  up <- suppressWarnings(
    recast_from_atoms(.partial(), s, target = "class", rule = "sum")
  )
  # recast_from_atoms joins the data to the members, so a missing atom simply
  # does not contribute; this half does NOT poison, and that asymmetry is
  # deliberate -- pin it so a "consistency" refactor cannot quietly change it
  expect_equal(up$value[up$class == "G1"], 1)
})

test_that("poisoning survives on every backend", {
  s <- scale_example()
  for (bk in test_backends()) {
    x <- as_backend(.partial(), bk)
    out <- suppressWarnings(
      recast_scale(x, s,
        source = "unit", target = "class", rule = "sum",
        collect = TRUE
      )
    )
    out <- as.data.frame(out)
    expect_true(is.na(out$value[out$class == "G1"]),
      label = sprintf("[%s] partial source poisons", bk)
    )
  }
})

test_that("the crosswalk is what defines the expected source set", {
  s <- scale_example()
  withr::defer(clear_scale_maps())
  # Registering a crosswalk in which G1 has ONLY U1 makes the same data
  # complete -- so the law is "every source the CROSSWALK expects", not
  # "every unit that happens to exist".
  one <- data.frame(
    unit = "U1", class = "G1", n_from = 1L, n_overlap = 1L,
    w = 1, w_from = 1, stringsAsFactors = FALSE
  )
  register_scale_map(s, "unit", "class", one)
  out <- suppressWarnings(
    recast_scale(.partial(), s, source = "unit", target = "class", rule = "sum")
  )
  expect_equal(out$value[out$class == "G1"], 1)
})
