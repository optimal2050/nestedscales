# =========================================================================== #
# cluster_scale(): a clustering IS a new frame on the scale.
# =========================================================================== #

test_that("the result is the scale with a new frame above the clustered one", {
  s <- three_group_scale()
  cl <- cluster_scale(three_group_data(), s, k = 3)

  # Not expect_s3_class("NestedScale"): the class is spelled "NestedScale" or
  # "nestedscales::NestedScale" depending on how the package was loaded.
  expect_true(scale_is(cl))
  expect_identical(
    scale_frames(cl),
    c("top", "cluster", "unit")
  )
  expect_identical(scale_key(cl), "unit")
  expect_length(scale_units(cl, "cluster"), 3L)
  # the atoms and their weights are untouched
  expect_identical(scale_units(cl), scale_units(s))
  expect_identical(
    scale_weights(cl),
    scale_weights(s)
  )
})

test_that("every method recovers three obvious groups", {
  s <- three_group_scale()
  d <- three_group_data()
  for (m in c("pam", "hclust", "kmeans")) {
    if (m == "pam") skip_if_not_installed("cluster")
    cl <- cluster_scale(d, s, k = 3, method = m, seed = 1)
    tab <- attr(cl, "clustering")
    expect_true(recovers_groups(tab, "unit", "cluster"),
      label = sprintf("method %s recovers the groups", m)
    )
  }
})

test_that("a shape distance groups by profile, not by level", {
  s <- three_group_scale()
  # Three distinct SHAPES -- rising, falling, spiked -- at wildly different
  # magnitudes. A level distance would group by magnitude; correlation must
  # group by shape. (A flat profile is deliberately not used here: it has no
  # shape for a correlation to match, and the package treats it as maximally
  # distant rather than pretending otherwise -- see the distance tests.)
  t <- sprintf("t%d", 1:6)
  shape <- list(
    u1 = 1:6, u2 = 1:6, u3 = 1:6,
    u4 = 6:1, u5 = 6:1, u6 = 6:1,
    u7 = c(1, 1, 9, 1, 1, 1), u8 = c(1, 1, 9, 1, 1, 1)
  )
  mag <- c(
    u1 = 100, u2 = 1, u3 = 0.01, u4 = 100, u5 = 1, u6 = 0.01,
    u7 = 100, u8 = 0.01
  )
  d <- do.call(rbind, lapply(names(shape), function(u) {
    data.frame(
      unit = u, t = t, v = as.numeric(shape[[u]]) * mag[[u]],
      stringsAsFactors = FALSE
    )
  }))

  by_shape <- cluster_scale(d, s,
    k = 3, method = "hclust",
    distance = "correlation"
  )
  expect_true(recovers_groups(
    attr(by_shape, "clustering"), "unit",
    "cluster"
  ))

  # and a level distance does NOT -- it groups the big ones together
  by_level <- cluster_scale(d, s,
    k = 3, method = "hclust",
    distance = "euclidean"
  )
  expect_false(recovers_groups(
    attr(by_level, "clustering"), "unit",
    "cluster"
  ))
})

test_that("the clustering table reports the assignment and the medoids", {
  skip_if_not_installed("cluster")
  s <- three_group_scale()
  tab <- attr(cluster_scale(three_group_data(), s, k = 3), "clustering")
  expect_named(tab, c("unit", "cluster", "medoid"))
  expect_identical(nrow(tab), 8L)
  expect_identical(sum(tab$medoid), 3L) # one representative per cluster
})

test_that("cluster_medoids() names a real unit per cluster", {
  skip_if_not_installed("cluster")
  s <- three_group_scale()
  med <- cluster_medoids(cluster_scale(three_group_data(), s, k = 3))
  expect_named(med, c("cluster", "representative"))
  expect_identical(nrow(med), 3L)
  expect_true(all(med$representative %in% scale_units(s)))
})

test_that("cluster_medoids() refuses a scale that carries no clustering", {
  expect_error(cluster_medoids(three_group_scale()), "carries no clustering")
})

test_that("labels = medoid names clusters after their representative", {
  skip_if_not_installed("cluster")
  s <- three_group_scale()
  cl <- cluster_scale(three_group_data(), s, k = 3, labels = "medoid")
  codes <- scale_units(cl, "cluster")
  expect_true(all(codes %in% scale_units(s)))
})

test_that("the cluster frame works with the rest of nestedscales", {
  s <- three_group_scale()
  cl <- cluster_scale(three_group_data(), s, k = 3, method = "hclust")

  # recasting to the clusters is now an ordinary recast
  d <- data.frame(
    unit = scale_units(s), cap = 1:8,
    stringsAsFactors = FALSE
  )
  out <- recast_scale(d, cl,
    source = "unit", target = "cluster",
    rule = "sum"
  )
  expect_equal(sum(out$cap), sum(d$cap))
  expect_identical(nrow(out), 3L)

  # and so is asking what is inside a cluster
  first <- scale_units(cl, "cluster")[[1L]]
  expect_gt(length(scale_children(cl, "cluster", first)), 0)
})

test_that("k is validated against the units available", {
  s <- three_group_scale()
  d <- three_group_data()
  expect_error(cluster_scale(d, s, k = 99), "more than the 8 unit")
  expect_error(cluster_scale(d, s, k = 0), "single positive number")
})

test_that("the new frame may not collide with an existing one", {
  s <- three_group_scale()
  expect_error(
    cluster_scale(three_group_data(), s,
      k = 3,
      new_frame = "top"
    ),
    "already a frame"
  )
})

test_that("a unit missing observations is an error, not a hole", {
  s <- three_group_scale()
  d <- three_group_data()
  d <- d[!(d$unit == "u1" & d$t == "t3"), ]
  expect_error(cluster_scale(d, s, k = 3), "not observed over every")
})

test_that("data with no feature column is refused", {
  s <- three_group_scale()
  d <- data.frame(
    unit = scale_units(s), v = 1:8,
    stringsAsFactors = FALSE
  )
  expect_error(cluster_scale(d, s, k = 2), "no identifier column")
})

test_that("kmeans is reproducible through seed", {
  s <- three_group_scale()
  d <- three_group_data()
  a <- attr(
    cluster_scale(d, s, k = 3, method = "kmeans", seed = 7),
    "clustering"
  )
  b <- attr(
    cluster_scale(d, s, k = 3, method = "kmeans", seed = 7),
    "clustering"
  )
  expect_equal(a, b)
})

test_that("clustering keeps the concrete class and its member tables", {
  s <- attach_attributes_scale(
    three_group_scale(),
    data.frame(frame = "top", unit = scale_units(three_group_scale(), "top")[1],
               attribute = "density", value = 1, unit_of_measure = "t/m3"),
    source = "t", kind = "property"
  )
  cl <- cluster_scale(three_group_data(), s, k = 3)
  expect_identical(nrow(scale_attributes(cl)), 1L)
  expect_identical(S7::prop(cl, "meta")[["name"]],
                   S7::prop(s, "meta")[["name"]])
  # a subclass comes back as itself
  Tagged <- S7::new_class("Tagged", parent = scale_class(),
                          properties = list(tag = S7::class_character))
  t <- Tagged(leaftable = scale_leaftable(s), frames = scale_frames(s),
              members = S7::prop(s, "members"), key = scale_key(s),
              meta = S7::prop(s, "meta"), tag = "keep me")
  clt <- cluster_scale(three_group_data(), t, k = 3)
  expect_true(S7::S7_inherits(clt, Tagged))
  expect_identical(clt@tag, "keep me")
  expect_identical(scale_frames(clt), c("top", "cluster", "unit"))
})
