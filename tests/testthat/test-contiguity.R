# =========================================================================== #
# Constrained clustering: order and adjacency.
# =========================================================================== #

.is_contiguous <- function(tab, units, circular = FALSE) {
  g <- tab[[2L]][match(units, tab[[1L]])]
  r <- rle(g)
  if (!circular) {
    return(!anyDuplicated(r$values))
  }
  v <- r$values
  if (length(v) > 1L && identical(v[[1L]], v[[length(v)]])) {
    v <- v[-length(v)] # the wrap-around block
  }
  !anyDuplicated(v)
}

test_that("order-constrained clusters are contiguous blocks", {
  s <- ordered_scale()
  cl <- cluster_contiguous(ordered_data(), s, k = 3)
  tab <- attr(cl, "clustering")
  expect_true(.is_contiguous(tab, scale_units(s)))
  expect_length(scale_units(cl, "cluster"), 3L)
})

test_that("it finds the three regimes the data actually has", {
  s <- ordered_scale()
  tab <- attr(cluster_contiguous(ordered_data(), s, k = 3), "clustering")
  g <- stats::setNames(tab$cluster, tab$period)
  expect_length(unique(g[sprintf("p%02d", 1:4)]), 1L)
  expect_length(unique(g[sprintf("p%02d", 5:8)]), 1L)
  expect_length(unique(g[sprintf("p%02d", 9:12)]), 1L)
  expect_length(unique(g), 3L)
})

test_that("clusters are numbered in sequence order", {
  s <- ordered_scale()
  tab <- attr(cluster_contiguous(ordered_data(), s, k = 3), "clustering")
  g <- tab$cluster[match(scale_units(s), tab$period)]
  expect_identical(unique(g), c("c01", "c02", "c03"))
})

test_that("an unconstrained clustering of the same data need not be contiguous", {
  s <- ordered_scale()
  d <- ordered_data()
  # make the first and last blocks look alike, so shape alone would join them
  d$v[d$period %in% sprintf("p%02d", 9:12)] <-
    d$v[d$period %in% sprintf("p%02d", 1:4)]

  free <- attr(cluster_scale(d, s, k = 2, method = "hclust"), "clustering")
  tied <- attr(cluster_contiguous(d, s, k = 2), "clustering")
  expect_false(.is_contiguous(free, scale_units(s)))
  expect_true(.is_contiguous(tied, scale_units(s)))
})

test_that("circular = TRUE lets the sequence wrap", {
  s <- ordered_scale()
  d <- ordered_data()
  # a regime that straddles the year end
  d$v[d$period %in% c("p01", "p02", "p11", "p12")] <- 1
  d$v[d$period %in% sprintf("p%02d", 3:6)] <- 5
  d$v[d$period %in% sprintf("p%02d", 7:10)] <- 9

  cl <- cluster_contiguous(d, s, k = 3, circular = TRUE)
  tab <- attr(cl, "clustering")
  g <- stats::setNames(tab$cluster, tab$period)
  expect_identical(unname(g[["p12"]]), unname(g[["p01"]]))
  expect_true(.is_contiguous(tab, scale_units(s),
    circular = TRUE
  ))
})

test_that("an adjacency graph constrains which units may merge", {
  s <- three_group_scale()
  units <- scale_units(s)
  # a path graph: u1-u2-...-u8, so clusters must be path segments
  adj <- data.frame(
    source = units[-8], target = units[-1],
    stringsAsFactors = FALSE
  )
  cl <- cluster_contiguous(three_group_data(), s, k = 3, adjacency = adj)
  expect_true(.is_contiguous(attr(cl, "clustering"), units))
})

test_that("a matrix adjacency works and is symmetrised", {
  s <- three_group_scale()
  units <- scale_units(s)
  m <- matrix(0, 8, 8)
  m[cbind(1:7, 2:8)] <- 1 # upper triangle only
  cl <- cluster_contiguous(three_group_data(), s, k = 3, adjacency = m)
  expect_true(.is_contiguous(attr(cl, "clustering"), units))
})

test_that("an unreachable k is refused with the component count", {
  s <- three_group_scale()
  units <- scale_units(s)
  # two components of four: {u1..u4} and {u5..u8}
  adj <- data.frame(
    source = c(units[1:3], units[5:7]),
    target = c(units[2:4], units[6:8]),
    stringsAsFactors = FALSE
  )
  expect_error(
    cluster_contiguous(three_group_data(), s, k = 1, adjacency = adj),
    "unreachable"
  )
  # k equal to the number of components is fine
  expect_no_error(
    cluster_contiguous(three_group_data(), s, k = 2, adjacency = adj)
  )
})

test_that("adjacency naming unknown units is an error", {
  s <- three_group_scale()
  adj <- data.frame(source = "nope", target = "u2", stringsAsFactors = FALSE)
  expect_error(
    cluster_contiguous(three_group_data(), s, k = 2, adjacency = adj),
    "not at this frame"
  )
})

test_that("a mis-shaped adjacency matrix is reported", {
  s <- three_group_scale()
  expect_error(
    cluster_contiguous(three_group_data(), s,
      k = 2,
      adjacency = matrix(0, 3, 3)
    ),
    "but this frame has 8 units"
  )
})

test_that("the constrained result is a scale like any other", {
  s <- ordered_scale()
  cl <- cluster_contiguous(ordered_data(), s, k = 3)
  expect_identical(
    scale_frames(cl),
    c("all", "cluster", "period")
  )
  d <- data.frame(
    period = scale_units(s),
    v = seq_len(12), stringsAsFactors = FALSE
  )
  out <- recast_scale(d, cl,
    source = "period", target = "cluster",
    rule = "sum"
  )
  expect_equal(sum(out$v), sum(d$v))
})

test_that("linkage choices all run and stay contiguous", {
  s <- ordered_scale()
  for (lk in c("average", "complete", "single")) {
    cl <- cluster_contiguous(ordered_data(), s, k = 3, linkage = lk)
    expect_true(
      .is_contiguous(
        attr(cl, "clustering"),
        scale_units(s)
      ),
      label = lk
    )
  }
})
