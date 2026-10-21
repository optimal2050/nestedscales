# Scales whose ATOMS are combinations of their frames, rather than the codes of
# the finest frame.
#
# `scale_example()` and `Geoscale` both have a finest frame with one code per
# leaftable row, so "finest frame" and "atom level" coincide and the
# distinction never showed. A `Calendar` breaks that: `d365_h24` has 8760
# timeslices over YDAY x HOUR, and `m12_md365` has 365 over MONTH x MDAY --
# which is not even a full product, because February has 28 days. In both the
# KEY column enumerates the atoms and no frame does.

# A product-shaped leaftable: frames cross-cut, key is the combination.
.cross_lt <- function(days = 3L, hours = 4L) {
  d <- sprintf("d%03d", seq_len(days))
  h <- sprintf("h%02d", seq_len(hours) - 1L)
  g <- expand.grid(HOUR = h, YDAY = d, stringsAsFactors = FALSE)
  data.frame(
    YDAY = g$YDAY, HOUR = g$HOUR,
    timeslice = paste0(g$YDAY, "_", g$HOUR),
    share = 1 / (days * hours), weight = 1,
    stringsAsFactors = FALSE
  )
}

# An IRREGULAR one: month x day-of-month with unequal month lengths.
.irregular_lt <- function(lens = c(3L, 2L, 4L)) {
  mm <- rep(sprintf("m%02d", seq_along(lens)), lens)
  dd <- unlist(lapply(lens, function(n) sprintf("md%02d", seq_len(n))))
  data.frame(
    MONTH = mm, MDAY = dd,
    timeslice = paste0(mm, "_", dd),
    share = 1 / sum(lens), weight = 1,
    stringsAsFactors = FALSE
  )
}

.build <- function(lt, frames) {
  scale_from_leaftable(lt,
    frames = frames, key = "timeslice",
    weights = c("share", "weight"),
    default_weight = "share", name = "fixture"
  )
}

test_that("the atoms come from the key when no frame enumerates them", {
  lt <- .cross_lt(3L, 4L)
  s <- .build(lt, c("YDAY", "HOUR"))
  # the finest frame has 4 codes; the atoms are the 12 combinations
  expect_equal(length(scale_units(s, "HOUR")), 4L)
  expect_equal(length(scale_units(s)), 12L)
  expect_equal(scale_units(s), lt$timeslice)
})

test_that("the key ranks finer than every frame", {
  s <- .build(.cross_lt(), c("YDAY", "HOUR"))
  expect_equal(scale_rank(s, "YDAY"), 1L)
  expect_equal(scale_rank(s, "HOUR"), 2L)
  expect_equal(scale_rank(s, "timeslice"), 3L)
})

test_that("data keyed by the atoms recasts up to either cross-cutting frame", {
  lt <- .cross_lt(3L, 4L)
  s <- .build(lt, c("YDAY", "HOUR"))
  d <- data.frame(timeslice = lt$timeslice, v = 1)
  up_d <- recast_scale(d, s, source = "timeslice", target = "YDAY", rule = "sum")
  up_h <- recast_scale(d, s, source = "timeslice", target = "HOUR", rule = "sum")
  expect_equal(nrow(up_d), 3L)
  expect_equal(nrow(up_h), 4L)
  # conservation: every atom counted once on either axis
  expect_equal(sum(up_d$v), 12)
  expect_equal(sum(up_h$v), 12)
})

test_that("an IRREGULAR scale aggregates by its real groupings", {
  lt <- .irregular_lt(c(3L, 2L, 4L)) # 9 atoms, months of 3, 2 and 4
  s <- .build(lt, c("MONTH", "MDAY"))
  expect_equal(length(scale_units(s)), 9L)
  # the product of the frames would be 3 x 4 = 12; the atoms are 9
  expect_equal(length(scale_units(s, "MONTH")) *
    length(scale_units(s, "MDAY")), 12L)
  d <- data.frame(timeslice = lt$timeslice, v = 1)
  up <- recast_scale(d, s, source = "timeslice", target = "MONTH", rule = "sum")
  expect_equal(nrow(up), 3L)
  # the uneven month lengths, read from the data rather than assumed
  expect_equal(sort(up$v), c(2, 3, 4))
})

test_that("cross-cutting and irregular frames raise no ordering warning", {
  # Code COUNTS are a wrong proxy for granularity: MDAY has more codes than
  # MONTH with the nesting the right way round, and YDAY/HOUR nest in neither
  # direction, which is legal.
  expect_silent(.build(.cross_lt(), c("YDAY", "HOUR")))
  expect_silent(.build(.irregular_lt(), c("MONTH", "MDAY")))
})

test_that("a genuinely inverted frame order still warns", {
  # `unit` contains `group`: the list really is upside down.
  lt <- data.frame(
    group = c("G1", "G1", "G2"),
    unit = c("U1", "U2", "U3"),
    stringsAsFactors = FALSE
  )
  # The ordering diagnostic is what is under test; this leaftable is also
  # invalid for unrelated reasons, so the construction is allowed to fail
  # after warning.
  expect_warning(
    try(scale_from_leaftable(lt, frames = c("unit", "group"), key = "unit"),
      silent = TRUE
    ),
    "CONTAINS the frame before it"
  )
})

test_that("navigation treats a key-level atom as the finest level", {
  s <- .build(.irregular_lt(c(3L, 2L, 4L)), c("MONTH", "MDAY"))
  expect_identical(scale_parents(s, "timeslice", "m02_md01"), "md01")
  expect_identical(
    scale_children(s, "MONTH", "m02", target = "timeslice"),
    c("m02_md01", "m02_md02")
  )
  expect_error(scale_children(s, "timeslice", "m02_md01"), "finest")
  anc <- scale_ancestors(s, "timeslice", "m03_md04")
  expect_identical(anc$unit, c("m03", "md04"))
  desc <- scale_descendants(s, "MDAY", "md03")
  # md03 exists in month 1 (three days) and month 3 (four)
  expect_identical(desc$frame, c("timeslice", "timeslice"))
  expect_identical(desc$unit, c("m01_md03", "m03_md03"))
})

test_that("pruning at a key-level atom is a no-op", {
  s <- .build(.cross_lt(3L, 4L), c("YDAY", "HOUR"))
  expect_identical(prune_scale(s, "timeslice"), s)
})

test_that("clustering at a key-level atom adds the cluster frame last", {
  skip_if_not_installed("cluster")
  lt <- .cross_lt(2L, 3L)
  s <- .build(lt, c("YDAY", "HOUR"))
  # d001_h02 and d002_h00 are the outliers: the clusters cut across hours
  v <- c(1, 1.1, 5, 5.2, 1, 1.2)
  d <- rbind(
    data.frame(year = 2020, timeslice = lt$timeslice, v = v),
    data.frame(year = 2021, timeslice = lt$timeslice, v = v + 0.1)
  )
  cl <- expect_no_warning(
    cluster_scale(d, s,
      k = 2, frame = "timeslice", value = "v",
      method = "pam"
    )
  )
  expect_identical(scale_frames(cl), c("YDAY", "HOUR", "cluster"))
  lf <- scale_leaftable(cl)
  hi <- lf$cluster[lf$timeslice %in% c("d001_h02", "d002_h00")]
  expect_length(unique(hi), 1L)
  expect_false(hi[1] %in% lf$cluster[!lf$timeslice %in% c("d001_h02", "d002_h00")])
})
