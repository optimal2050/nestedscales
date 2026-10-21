# =========================================================================== #
# DIFFERENTIAL HARNESS: the neutral engine vs the dimension it will replace.
#
# This is the numeric safety net for the rebase. `geoscales` is the package
# whose model `NestedScale` generalises, so the strongest possible check is to give
# BOTH engines literally the same data and demand the same answers -- no
# hand-written expected values, no translation table that could itself be
# wrong.
#
# The NestedScale is built FROM `geoscale_example()`'s own leaftable, keeping its
# frame names, codes, weights and key, so every call below is the same
# question asked twice. Any divergence here is a real behavioural difference
# and must be resolved BEFORE `Geoscale` becomes a `NestedScale` subclass.
# =========================================================================== #

skip_if_not_installed("geoscales")

.gs <- function() geoscales::geoscale_example()

# The same hierarchy, expressed as a neutral NestedScale.
.ms <- function() {
  gs <- .gs()
  scale_from_leaftable(
    geoscales::geoscale_leaftable(gs),
    frames = geoscales::geoscale_geoframes(gs),
    key = "region",
    weights = geoscales::geoscale_weights(gs),
    default_weight = S7::prop(gs, "meta")$default_weight,
    name = "example"
  )
}

.same <- function(a, b, label) {
  a <- as.data.frame(a)
  b <- as.data.frame(b)
  rownames(a) <- NULL
  rownames(b) <- NULL
  expect_equal(a, b, ignore_attr = TRUE, label = label)
}

test_that("the two objects really do hold the same data", {
  gs <- .gs()
  ms <- .ms()
  expect_identical(scale_frames(ms), geoscales::geoscale_geoframes(gs))
  expect_identical(scale_weights(ms), geoscales::geoscale_weights(gs))
  .same(scale_leaftable(ms), geoscales::geoscale_leaftable(gs), "leaftable")
  for (f in scale_frames(ms)) {
    expect_identical(scale_units(ms, f), geoscales::geoscale_regions(gs, f),
      label = paste("members at", f)
    )
  }
})

# Conversion ------------------------------------------------------------------

.cases <- list(
  list(
    nm = "atom->country sum",
    args = list(source = "atom", target = "country", rule = "sum")
  ),
  list(
    nm = "atom->country weighted_mean",
    args = list(
      source = "atom", target = "country", rule = "weighted_mean",
      weight = "km2"
    )
  ),
  list(
    nm = "atom->state mean",
    args = list(source = "atom", target = "state", rule = "mean")
  ),
  list(
    nm = "atom->country sd",
    args = list(source = "atom", target = "country", rule = "sd")
  ),
  list(
    nm = "atom->state pop-weighted",
    args = list(
      source = "atom", target = "state", rule = "weighted_mean",
      weight = "pop"
    )
  ),
  list(
    nm = "state->zone cross-cutting",
    data = data.frame(
      region = c("N1", "N2", "S1"), v = c(10, 20, 30),
      stringsAsFactors = FALSE
    ),
    args = list(
      source = "state", target = "zone", rule = "sum",
      weight = "km2"
    )
  ),
  list(
    nm = "atom->country keep NA",
    args = list(
      source = "atom", target = "country", rule = "sum",
      na_action = "keep"
    )
  )
)

test_that("recast agrees with geoscales on every rule and direction", {
  gs <- .gs()
  ms <- .ms()
  atoms <- data.frame(
    region = c("A1", "A2", "A3", "A4", "A5", "A6"),
    v = c(1, 2, 3, 4, 5, 6), stringsAsFactors = FALSE
  )
  for (cs in .cases) {
    d <- cs$data %||% atoms
    a <- suppressWarnings(
      do.call(
        geoscales::recast_geoscale,
        c(list(x = d, gs = gs, key = "region"), cs$args)
      )
    )
    b <- suppressWarnings(
      do.call(
        recast_scale,
        c(list(data = d, x = ms, key = "region"), cs$args)
      )
    )
    .same(a, b, cs$nm)
  }
})

test_that("disaggregation agrees", {
  gs <- .gs()
  ms <- .ms()
  d <- data.frame(
    country = c("N", "S"), v = c(10, 20),
    stringsAsFactors = FALSE
  )
  for (w in c("km2", "pop")) {
    a <- suppressWarnings(
      geoscales::recast_geoscale(d, gs,
        source = "country", target = "state",
        rule = "sum", weight = w
      )
    )
    b <- suppressWarnings(
      recast_scale(d, ms,
        source = "country", target = "state", rule = "sum",
        weight = w
      )
    )
    .same(a, b, paste("country->state split by", w))
  }
})

test_that("the copy rule agrees, including its refusal", {
  gs <- .gs()
  ms <- .ms()
  ok <- data.frame(
    region = c("A1", "A2"), v = c(0.5, 0.5),
    stringsAsFactors = FALSE
  )
  .same(
    suppressWarnings(
      geoscales::recast_geoscale(ok, gs,
        source = "atom", target = "state",
        rule = "copy", key = "region"
      )
    ),
    suppressWarnings(
      recast_scale(ok, ms,
        source = "atom", target = "state", rule = "copy",
        key = "region"
      )
    ),
    "copy"
  )

  bad <- data.frame(
    region = c("A1", "A2"), v = c(0.5, 0.9),
    stringsAsFactors = FALSE
  )
  expect_error(suppressWarnings(
    geoscales::recast_geoscale(bad, gs,
      source = "atom", target = "state",
      rule = "copy", key = "region"
    )
  ))
  expect_error(suppressWarnings(
    recast_scale(bad, ms,
      source = "atom", target = "state", rule = "copy",
      key = "region"
    )
  ))
})

test_that("share agrees", {
  gs <- .gs()
  ms <- .ms()
  d <- data.frame(
    region = c("A1", "A2", "A3", "A4", "A5", "A6"),
    v = c(1, 2, 3, 4, 5, 6), stringsAsFactors = FALSE
  )
  .same(
    suppressWarnings(
      geoscales::recast_geoscale(d, gs,
        source = "atom", target = "country",
        rule = "share", key = "region"
      )
    ),
    suppressWarnings(
      recast_scale(d, ms,
        source = "atom", target = "country", rule = "share",
        key = "region"
      )
    ),
    "share within country"
  )
})

test_that("identifier columns are carried the same way", {
  gs <- .gs()
  ms <- .ms()
  d <- data.frame(
    region = rep(c("A1", "A2", "A3", "A4", "A5", "A6"), 2),
    year = rep(c(2020, 2021), each = 6),
    v = c(1, 2, 3, 4, 5, 6, 2, 4, 6, 8, 10, 12),
    stringsAsFactors = FALSE
  )
  .same(
    suppressWarnings(
      geoscales::recast_geoscale(d, gs,
        source = "atom", target = "country",
        rule = "sum", key = "region",
        values = "v"
      )
    ),
    suppressWarnings(
      recast_scale(d, ms,
        source = "atom", target = "country", rule = "sum",
        key = "region", values = "v"
      )
    ),
    "panel recast"
  )
})

test_that("the route halves agree", {
  gs <- .gs()
  ms <- .ms()
  d <- data.frame(
    country = c("N", "S"), v = c(10, 20),
    stringsAsFactors = FALSE
  )
  a_down <- suppressWarnings(
    geoscales::recast_to_geoatoms(d, gs,
      source = "country", rule = "sum",
      weight = "km2"
    )
  )
  b_down <- suppressWarnings(
    recast_to_atoms(d, ms, source = "country", rule = "sum", weight = "km2")
  )
  .same(a_down, b_down, "to atoms")

  a_up <- suppressWarnings(
    geoscales::recast_from_geoatoms(a_down, gs, target = "state", rule = "sum")
  )
  b_up <- suppressWarnings(
    recast_from_atoms(b_down, ms, target = "state", rule = "sum")
  )
  .same(a_up, b_up, "from atoms")
})

test_that("the crosswalk itself agrees", {
  gs <- .gs()
  ms <- .ms()
  for (pair in list(
    c("atom", "country"), c("state", "zone"),
    c("country", "atom")
  )) {
    .same(
      geoscales::geoscale_map(pair[1], pair[2], gs = gs, weight = "km2"),
      scale_map(ms, pair[1], pair[2], weight = "km2"),
      paste(pair, collapse = "->")
    )
  }
})

# Attach ----------------------------------------------------------------------

test_that("join agrees on labels, memberships and meta", {
  gs <- .gs()
  ms <- .ms()
  d <- data.frame(
    state = c("N1", "N2", "S1"), v = 1:3,
    stringsAsFactors = FALSE
  )
  .same(geoscales::join_geoscale(d, gs), join_scale(d, ms), "labels")
  .same(
    geoscales::join_geoscale(d, gs, geoframes = TRUE),
    join_scale(d, ms, attach = TRUE), "memberships"
  )
  .same(
    geoscales::join_geoscale(d, gs, meta = TRUE, weight = "km2"),
    join_scale(d, ms, meta = TRUE, weight = "km2"), "meta"
  )
})

# Structure -------------------------------------------------------------------

test_that("structure queries agree", {
  gs <- .gs()
  ms <- .ms()

  a <- geoscales::geoscale_family(gs, "state", "zone")
  b <- scale_family(ms, "state", "zone")
  names(a) <- names(b)
  .same(a, b, "family")

  expect_identical(
    geoscales::geoscale_nests(gs, "country", "state"),
    scale_nests(ms, "country", "state")
  )
  expect_identical(
    as.logical(geoscales::geoscale_nests(gs, "state", "zone")),
    as.logical(scale_nests(ms, "state", "zone"))
  )
  expect_setequal(
    attr(geoscales::geoscale_nests(gs, "state", "zone"), "offenders"),
    attr(scale_nests(ms, "state", "zone"), "offenders")
  )

  a2 <- geoscales::geoscale_ancestry(gs)
  b2 <- scale_ancestry(ms)
  names(a2) <- names(b2)
  .same(
    a2[order(a2$parent_frame, a2$parent, a2$child_frame, a2$child), ],
    b2[order(b2$parent_frame, b2$parent, b2$child_frame, b2$child), ],
    "ancestry"
  )

  expect_equal(geoscales::geoscale_coverage(gs), scale_coverage(ms))
})

test_that("navigation agrees", {
  gs <- .gs()
  ms <- .ms()
  expect_identical(
    geoscales::geoscale_children(gs, "country", "N"),
    scale_children(ms, "country", "N")
  )
  expect_identical(
    geoscales::geoscale_parents(gs, "zone", "ZB"),
    scale_parents(ms, "zone", "ZB")
  )

  a <- geoscales::geoscale_descendants(gs, "country", "N")
  b <- scale_descendants(ms, "country", "N")
  names(a) <- names(b)
  .same(a, b, "descendants")
})

test_that("shares agree", {
  gs <- .gs()
  ms <- .ms()
  .same(
    geoscales::geoscale_share(gs, "state", weight = "km2"),
    scale_share(ms, "state", weight = "km2"), "share"
  )
  .same(
    geoscales::geoscale_share(gs, "state",
      weight = "km2",
      within = "country"
    ),
    scale_share(ms, "state", weight = "km2", within = "country"),
    "share within"
  )
})

test_that("filter agrees, bookkeeping included", {
  gs <- .gs()
  ms <- .ms()
  a <- geoscales::filter_geoscale(gs, "country", "N")
  b <- filter_scale(ms, "country", "N")
  .same(geoscales::geoscale_leaftable(a), scale_leaftable(b), "leaftable")
  expect_identical(geoscales::geoscale_geoframes(a), scale_frames(b))
  expect_equal(geoscales::geoscale_coverage(a), scale_coverage(b))
  expect_identical(S7::prop(a, "meta")$name, S7::prop(b, "meta")$name)
  expect_identical(
    S7::prop(a, "meta")$parent_name,
    S7::prop(b, "meta")$parent_name
  )
})

test_that("prune agrees, bookkeeping included", {
  gs <- .gs()
  ms <- .ms()
  a <- geoscales::prune_geoscale(gs, "state")
  b <- prune_scale(ms, "state")
  .same(geoscales::geoscale_leaftable(a), scale_leaftable(b), "leaftable")
  expect_identical(geoscales::geoscale_geoframes(a), scale_frames(b))
  expect_equal(geoscales::geoscale_coverage(a), scale_coverage(b))
  expect_identical(S7::prop(a, "meta")$name, S7::prop(b, "meta")$name)
})
