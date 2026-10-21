# =========================================================================== #
# Shared fixtures.
#
# `scale_example()` is the package's own awkward-on-purpose hierarchy (reused
# code, cross-cutting pair, unassigned atom). These helpers add the small
# well-behaved cases that make single assertions readable.
# =========================================================================== #

# A clean 3-frame nesting hierarchy with one weight. Nothing awkward.
tidy_scale <- function(name = "tidy") {
  df <- data.frame(
    top = c("T", "T", "T", "T"),
    mid = c("M1", "M1", "M2", "M2"),
    leaf = c("L1", "L2", "L3", "L4"),
    w = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(df, frames = c("top", "mid", "leaf"), name = name)
}

# A scale whose key column is named something other than a frame.
keyed_scale <- function(key = "id") {
  df <- data.frame(
    grp = c("A", "A", "B"),
    sub = c("a1", "a2", "b1"),
    id = c("x", "y", "z"),
    w = c(1, 1, 2),
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(df, frames = c("grp", "sub"), key = key, name = "keyed")
}

# A minimal single-frame scale (the degenerate hierarchy).
flat_scale <- function() {
  scale_from_leaftable(
    data.frame(unit = c("u1", "u2"), w = c(1, 3), stringsAsFactors = FALSE),
    frames = "unit", name = "flat"
  )
}

# --- clustering fixtures (merged from clusterscales) ---

# =========================================================================== #
# Fixtures.
#
# A scale of 8 units whose profiles fall into THREE obvious groups: flat-ish,
# rising, and a sharp spike. Any sensible clustering at k = 3 must recover
# them, so the tests can assert on structure rather than on numbers that would
# change with an algorithm's tie-breaking.
# =========================================================================== #

three_group_scale <- function() {
  scale_from_leaftable(
    data.frame(
      top = "T",
      unit = sprintf("u%d", 1:8),
      w = c(1, 1, 1, 2, 2, 2, 3, 3),
      stringsAsFactors = FALSE
    ),
    frames = c("top", "unit"), key = "unit", weights = "w",
    name = "fixture"
  )
}

# group A: u1..u3 flat; B: u4..u6 rising; C: u7..u8 spiked
three_group_data <- function(noise = 0.01, seed = 42) {
  set.seed(seed)
  t <- sprintf("t%d", 1:6) # the feature LABEL, deliberately not numeric
  ramp <- as.numeric(1:6) # the rising group's actual values
  shape <- list(
    u1 = rep(1, 6), u2 = rep(1, 6), u3 = rep(1, 6),
    u4 = ramp, u5 = ramp, u6 = ramp,
    u7 = c(0, 0, 10, 0, 0, 0), u8 = c(0, 0, 10, 0, 0, 0)
  )
  d <- do.call(rbind, lapply(names(shape), function(u) {
    data.frame(
      unit = u, t = t,
      v = shape[[u]] + stats::rnorm(6, sd = noise),
      stringsAsFactors = FALSE
    )
  }))
  d
}

# The truth the tests compare against.
three_group_truth <- function() {
  list(A = c("u1", "u2", "u3"), B = c("u4", "u5", "u6"), C = c("u7", "u8"))
}

# TRUE when `assignment` (named by unit) recovers the three groups, whatever
# the cluster codes happen to be called.
recovers_groups <- function(tab, unit_col, cluster_col,
                            truth = three_group_truth()) {
  g <- stats::setNames(tab[[cluster_col]], tab[[unit_col]])
  all(vapply(truth, function(members) {
    length(unique(g[members])) == 1L
  }, logical(1))) &&
    length(unique(vapply(truth, function(m) g[[m[[1]]]], character(1)))) ==
      length(truth)
}

# An ordered scale: 12 periods forming a cycle, three contiguous regimes.
ordered_scale <- function() {
  scale_from_leaftable(
    data.frame(
      all = "A",
      period = sprintf("p%02d", 1:12),
      w = 1, stringsAsFactors = FALSE
    ),
    frames = c("all", "period"), key = "period", weights = "w",
    name = "cycle"
  )
}

ordered_data <- function() {
  lvl <- c(rep(1, 4), rep(5, 4), rep(9, 4))
  do.call(rbind, lapply(seq_len(12), function(i) {
    data.frame(
      period = sprintf("p%02d", i), t = sprintf("t%d", 1:3),
      v = lvl[[i]] + c(0, 0.1, -0.1), stringsAsFactors = FALSE
    )
  }))
}

# A small fuel hierarchy with attributes at three levels, an alias that
# resolves to two members, and a cross-cutting `phase` frame -- the fixture
# for attributes, aliases and conversion (the energyscales example, 2026-10).
.fuels <- function() {
  lt <- data.frame(
    group   = c("Fossil", "Fossil", "Fossil", "Fossil", "Fossil",
                "Bio", "Bio", "Bio", "Power"),
    phase   = c("solid", "solid", "liquid", "liquid", "gas",
                "solid", "liquid", "gas", NA),
    carrier = c("Coal", "Coal", "Oil", "Oil", "Gas",
                "Biomass", "Biomass", "Biomass", "Electricity"),
    fuel    = c("Anthracite", "Lignite", "Diesel", "Gasoline", "NaturalGas",
                "Wood", "Biodiesel", "Biogas", "Electricity"),
    stringsAsFactors = FALSE
  )
  at <- data.frame(
    frame     = c("fuel", "fuel", "carrier", "group", "fuel", "carrier"),
    unit      = c("Anthracite", "Lignite", "Oil", "Bio", "Anthracite", "Gas"),
    attribute = c("lhv", "lhv", "lhv", "lhv", "ef_co2", "ef_co2"),
    kind      = c(rep("property", 4L), "factor", "factor"),
    value     = c(26.7, 11.9, 42.5, 15.0, 98300, 56100),
    lower     = c(21.6, 5.5, 40.0, 7.9, 94600, 54300),
    upper     = c(32.2, 21.6, 45.0, 31.0, 101000, 58300),
    unit_of_measure = c("GJ/t", "GJ/t", "GJ/t", "GJ/t", "kg/TJ", "kg/TJ"),
    source    = "example",
    stringsAsFactors = FALSE
  )
  al <- data.frame(
    frame  = c("fuel", "carrier", "fuel", "carrier", "carrier"),
    unit   = c("Anthracite", "Coal", "Electricity", "Electricity",
               "Electricity"),
    alias  = c("hard coal", "coal", "elc", "elc", "power"),
    source = "example",
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(
    lt,
    frames = c("group", "phase", "carrier", "fuel"), key = "fuel",
    attributes = at, aliases = al, name = "fuels",
    desc = "Fuels: reused code, cross-cutting phase, attributes at 3 levels"
  )
}

# The same fuels without the cross-cutting frame: a pure tree, for prune.
.fuels_tree <- function() {
  es <- .fuels()
  lt <- scale_leaftable(es)
  lt$phase <- NULL
  scale_from_leaftable(
    lt, frames = c("group", "carrier", "fuel"), key = "fuel",
    attributes = S7::prop(es, "attributes"),
    aliases = S7::prop(es, "aliases"), name = "tree"
  )
}
