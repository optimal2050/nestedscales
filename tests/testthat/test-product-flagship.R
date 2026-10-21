# =========================================================================== #
# The motivating case, end to end.
#
# Hourly x regional load, aggregated to months x countries with DIFFERENT
# rules per axis: time is intensive (a duration-weighted mean power) and space
# is extensive (regional loads add up). That asymmetry is the whole reason the
# rules are per (value, axis), and it is exactly the split energyRt's own
# bridge files record between timeslice and region aggregation.
#
# Built from two synthetic scales so it depends on neither twin.
# =========================================================================== #

# 24 hours x 3 days -> days -> the whole span.
.clock <- function() {
  df <- expand.grid(
    hour = sprintf("h%02d", 1:24),
    day = c("d1", "d2", "d3"),
    stringsAsFactors = FALSE
  )
  df$slice <- paste(df$day, df$hour, sep = "_")
  df$span <- 1 # every hour is one hour long
  df$season <- ifelse(df$day == "d3", "warm", "cold")
  scale_from_leaftable(
    df[, c("season", "day", "slice", "span")],
    frames = c("season", "day", "slice"), key = "slice",
    weights = "span", name = "clock"
  )
}

# 6 zones -> 3 countries -> 1 market.
.grid <- function() {
  df <- data.frame(
    market = "EU",
    country = c("A", "A", "B", "B", "C", "C"),
    zone = c("A1", "A2", "B1", "B2", "C1", "C2"),
    pop = c(10, 30, 20, 20, 5, 15),
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(df,
    frames = c("market", "country", "zone"),
    key = "zone", weights = "pop", name = "grid"
  )
}

.load <- function(seed = 1) {
  cl <- .clock()
  gr <- .grid()
  d <- merge(
    data.frame(slice = scale_units(cl), stringsAsFactors = FALSE),
    data.frame(zone = scale_units(gr), stringsAsFactors = FALSE)
  )
  set.seed(seed)
  d$load_mw <- round(runif(nrow(d), 50, 150), 3)
  d
}

test_that("the flagship recast runs and is keyed by both targets", {
  p <- scale_product(time = .clock(), space = .grid())
  d <- .load()
  expect_identical(nrow(d), 24L * 3L * 6L)

  out <- recast_product(
    d, p,
    target = list(time = "day", space = "country"),
    rules = list(load_mw = c(time = "weighted_mean", space = "sum"))
  )

  expect_true(all(c("day", "country", "load_mw") %in% names(out)))
  expect_identical(nrow(out), 3L * 3L) # 3 days x 3 countries
  expect_false(anyNA(out$load_mw))
})

test_that("the two axes really do apply different arithmetic", {
  p <- scale_product(time = .clock(), space = .grid())
  d <- .load()
  out <- recast_product(
    d, p,
    target = list(time = "day", space = "country"),
    rules = list(load_mw = c(time = "weighted_mean", space = "sum"))
  )

  # country A, day d1: mean power over the day per zone, then zones summed
  ref <- d[d$zone %in% c("A1", "A2") & startsWith(d$slice, "d1_"), ]
  by_zone <- tapply(ref$load_mw, ref$zone, mean) # every hour weighs 1
  expect_equal(
    out$load_mw[out$country == "A" & out$day == "d1"],
    sum(by_zone)
  )
})

test_that("swapping the pass order changes nothing", {
  cl <- .clock()
  gr <- .grid()
  p <- scale_product(time = cl, space = gr)
  d <- .load()

  time_first <- recast_scale(d, cl,
    source = "slice", target = "day", key = "slice",
    values = "load_mw", rule = "weighted_mean"
  ) |>
    recast_scale(gr,
      source = "zone", target = "country", key = "zone",
      values = "load_mw", rule = "sum"
    )
  space_first <- recast_scale(d, gr,
    source = "zone", target = "country",
    key = "zone", values = "load_mw",
    rule = "sum"
  ) |>
    recast_scale(cl,
      source = "slice", target = "day", key = "slice",
      values = "load_mw", rule = "weighted_mean"
    )
  one_call <- recast_product(
    d, p,
    target = list(time = "day", space = "country"),
    rules = list(load_mw = c(time = "weighted_mean", space = "sum"))
  )

  key <- function(z) {
    z <- as.data.frame(z)
    z <- z[order(z$country, z$day), c("day", "country", "load_mw")]
    rownames(z) <- NULL
    z
  }
  expect_equal(key(time_first), key(space_first))
  expect_equal(key(one_call), key(time_first))
})

test_that("energy is conserved when time is treated as extensive", {
  p <- scale_product(time = .clock(), space = .grid())
  d <- .load()
  # summing on BOTH axes is total energy: it must survive aggregation
  out <- recast_product(d, p,
    target = list(time = "season", space = "market"),
    rules = "sum"
  )
  expect_equal(sum(out$load_mw), sum(d$load_mw))
})

test_that("a coarse bound broadcasts down to every product cell", {
  p <- scale_product(time = .clock(), space = .grid())
  cap <- merge(
    data.frame(
      season = c("cold", "warm"),
      stringsAsFactors = FALSE
    ),
    data.frame(
      country = c("A", "B", "C"),
      stringsAsFactors = FALSE
    )
  )
  cap$max_cf <- 0.8

  fine <- recast_product(cap, p,
    target = list(time = "slice", space = "zone"),
    rules = list(max_cf = "copy")
  )
  expect_identical(nrow(fine), 24L * 3L * 6L)
  expect_true(all(fine$max_cf == 0.8))
})

test_that("per-axis weights change the spatial split going down", {
  p <- scale_product(time = .clock(), space = .grid())
  nat <- merge(
    data.frame(
      day = c("d1", "d2", "d3"),
      stringsAsFactors = FALSE
    ),
    data.frame(
      country = c("A", "B", "C"),
      stringsAsFactors = FALSE
    )
  )
  nat$load_mw <- 100

  out <- recast_product(nat, p,
    target = list(space = "zone"),
    rules = list(load_mw = c(space = "sum")),
    weights = c(space = "pop")
  )
  # country A splits 100 between A1 (pop 10) and A2 (pop 30)
  a1 <- out$load_mw[out$zone == "A1" & out$day == "d1"]
  a2 <- out$load_mw[out$zone == "A2" & out$day == "d1"]
  expect_equal(a1, 25)
  expect_equal(a2, 75)
  expect_equal(sum(out$load_mw), 3 * 300)
})

test_that("the flagship runs lazily on arrow without materialising", {
  skip_if_tier_below("full")
  skip_if_not_installed("arrow")
  p <- scale_product(time = .clock(), space = .grid())
  d <- .load()

  lazy <- recast_product(
    arrow::arrow_table(d), p,
    target = list(time = "day", space = "country"),
    rules = list(load_mw = c(time = "weighted_mean", space = "sum"))
  )
  expect_false(is.data.frame(lazy)) # still a query

  got <- as.data.frame(dplyr::collect(lazy))
  ref <- recast_product(
    d, p,
    target = list(time = "day", space = "country"),
    rules = list(load_mw = c(time = "weighted_mean", space = "sum"))
  )
  got <- got[order(got$country, got$day), ]
  ref <- ref[order(ref$country, ref$day), ]
  expect_equal(got$load_mw, ref$load_mw)
})

test_that("the product never materialises its atoms to do any of this", {
  p <- scale_product(time = .clock(), space = .grid())
  # 72 x 6 = 432 atoms exist only implicitly; the guard proves nothing built
  # them, since a limit below that size would have errored
  expect_equal(product_size(p)$total, 432)
  expect_error(product_atoms(p, limit = 10), "above `limit`")
  expect_no_error(
    recast_product(.load(), p,
      target = list(time = "day", space = "country"),
      rules = list(load_mw = c(
        time = "weighted_mean",
        space = "sum"
      ))
    )
  )
})
