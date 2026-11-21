# =========================================================================== #
# Distances and the registry.
# =========================================================================== #

test_that("scale_distance() is a dist over the frame's members, in order", {
  s <- three_group_scale()
  d <- scale_distance(three_group_data(), s)
  expect_s3_class(d, "dist")
  expect_identical(attr(d, "Size"), 8L)
  expect_identical(attr(d, "Labels"), scale_members(s))
})

test_that("level distances see magnitude and shape distances do not", {
  s <- three_group_scale()
  t <- sprintf("t%d", 1:6)
  # u1 and u2 have the SAME shape at different magnitudes; u3 differs in shape
  d <- rbind(
    data.frame(item = "u1", t = t, v = as.numeric(1:6)),
    data.frame(item = "u2", t = t, v = as.numeric(1:6) * 50),
    data.frame(item = "u3", t = t, v = as.numeric(6:1)),
    data.frame(item = "u4", t = t, v = as.numeric(6:1)),
    data.frame(item = "u5", t = t, v = as.numeric(6:1)),
    data.frame(item = "u6", t = t, v = as.numeric(6:1)),
    data.frame(item = "u7", t = t, v = as.numeric(6:1)),
    data.frame(item = "u8", t = t, v = as.numeric(6:1)),
    stringsAsFactors = FALSE
  )

  lev <- as.matrix(scale_distance(d, s, method = "euclidean"))
  shp <- as.matrix(scale_distance(d, s, method = "correlation"))

  # by level, u1 is far from its own shape-mate u2 and near the others
  expect_gt(lev["u1", "u2"], lev["u1", "u3"])
  # by shape, the opposite
  expect_lt(shp["u1", "u2"], shp["u1", "u3"])
  expect_equal(unname(shp["u1", "u2"]), 0, tolerance = 1e-8)
})

test_that("scale_members = TRUE turns a level distance into a shape one", {
  s <- three_group_scale()
  t <- sprintf("t%d", 1:6)
  d <- do.call(rbind, lapply(seq_len(8), function(i) {
    data.frame(
      item = sprintf("u%d", i), t = t,
      v = as.numeric(1:6) * i, stringsAsFactors = FALSE
    )
  }))
  raw <- as.matrix(scale_distance(d, s, method = "euclidean"))
  std <- as.matrix(scale_distance(d, s,
    method = "euclidean",
    scale_members = TRUE
  ))
  expect_gt(raw["u1", "u8"], 1)
  expect_equal(unname(std["u1", "u8"]), 0, tolerance = 1e-8)
})

test_that("a profile with no shape is maximally distant, not accidentally close", {
  s <- three_group_scale()
  t <- sprintf("t%d", 1:6)
  d <- do.call(rbind, lapply(seq_len(8), function(i) {
    v <- if (i <= 2) rep(5, 6) else as.numeric(1:6) # u1, u2 are constant
    data.frame(
      item = sprintf("u%d", i), t = t, v = v,
      stringsAsFactors = FALSE
    )
  }))
  m <- as.matrix(scale_distance(d, s, method = "correlation"))
  # two flat members are NOT treated as a matching pair
  expect_equal(unname(m["u1", "u2"]), 2)
  expect_equal(unname(m["u1", "u3"]), 2)
  # while two genuinely identical shapes are
  expect_equal(unname(m["u3", "u4"]), 0, tolerance = 1e-8)
})

test_that("every built-in distance runs and is symmetric with a zero diagonal", {
  s <- three_group_scale()
  d <- three_group_data()
  for (m in SCALE_DISTANCES) {
    mm <- as.matrix(scale_distance(d, s, method = m))
    expect_equal(mm, t(mm), label = m)
    expect_true(all(diag(mm) == 0), label = m)
    expect_false(anyNA(mm), label = m)
  }
})

test_that("an unknown distance is an error", {
  s <- three_group_scale()
  expect_error(
    scale_distance(three_group_data(), s, method = "nope"),
    "unknown distance"
  )
})

# Registry ---------------------------------------------------------------------

test_that("a registered distance is usable by name", {
  withr::defer(clear_scale_distances())
  s <- three_group_scale()
  register_scale_distance("first_diff", function(m) {
    stats::dist(t(apply(m, 1, diff)))
  })
  expect_true("first_diff" %in% list_scale_distances())
  d <- scale_distance(three_group_data(), s, method = "first_diff")
  expect_s3_class(d, "dist")
  expect_identical(attr(d, "Size"), 8L)
})

test_that("a registered distance can drive a clustering", {
  withr::defer(clear_scale_distances())
  s <- three_group_scale()
  register_scale_distance("mine", function(m) stats::dist(m))
  cl <- cluster_scale(three_group_data(), s,
    k = 3, method = "hclust",
    distance = "mine"
  )
  expect_true(recovers_groups(attr(cl, "clustering"), "item", "cluster"))
})

test_that("the registry validates and clears", {
  withr::defer(clear_scale_distances())
  expect_error(
    register_scale_distance("", function(m) m),
    "non-empty string"
  )
  expect_error(
    register_scale_distance("x", "not a function"),
    "must be a function"
  )
  register_scale_distance("tmp", function(m) stats::dist(m))
  expect_false(is.null(get_scale_distance("tmp")))
  clear_scale_distances("tmp")
  expect_null(get_scale_distance("tmp"))
  # built-ins survive clearing
  expect_true(all(SCALE_DISTANCES %in% list_scale_distances()))
})

test_that("a registered distance of the wrong size is caught", {
  withr::defer(clear_scale_distances())
  s <- three_group_scale()
  register_scale_distance("wrong", function(m) stats::dist(m[1:3, ]))
  expect_error(
    scale_distance(three_group_data(), s, method = "wrong"),
    "returned 3 rows for 8 members"
  )
})
