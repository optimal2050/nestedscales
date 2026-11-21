# The export surface must not collide with packages users attach alongside it.
#
# This is the test that would have caught both of the collisions this file was
# written for: `NestedScale` against ggplot2's ggproto base class, and `recast`
# against the generic timescales owns and geoscales extends. It also caught a
# third, introduced while fixing them -- ggplot2 exports `is_scale` too.

test_that("no export collides with a package users attach alongside", {
  # A shared NAME is only a collision when it means a different OBJECT. The
  # dimension packages re-export this package's `recast` generic, so the name
  # is shared on purpose and identity is what matters.
  ours <- getNamespaceExports("nestedscales")
  for (pkg in c("ggplot2", "scales", "timescales", "geoscales")) {
    skip_if_not_installed(pkg)
    shared <- intersect(ours, getNamespaceExports(pkg))
    for (nm in shared) {
      expect_identical(getExportedValue("nestedscales", nm),
        getExportedValue(pkg, nm),
        info = paste0(pkg, "::", nm)
      )
    }
  }
})

test_that("unrelated packages share no export name at all", {
  # ggplot2 and scales have no business sharing a name with this package --
  # an earlier class name and `is_scale` both did.
  ours <- getNamespaceExports("nestedscales")
  for (pkg in c("ggplot2", "scales")) {
    skip_if_not_installed(pkg)
    expect_equal(intersect(ours, getNamespaceExports(pkg)), character(),
      info = pkg
    )
  }
})

test_that("the classes are exported beside their accessors", {
  ours <- getNamespaceExports("nestedscales")
  expect_true("NestedScale" %in% ours)
  expect_true("ScaleProduct" %in% ours)
  expect_identical(nestedscales::NestedScale, scale_class())
  expect_identical(nestedscales::ScaleProduct, scale_product_class())
  expect_true("recast" %in% ours) # owned here, re-exported by the twins
  expect_true(all(c("scale_class", "scale_is", "recast_scale") %in% ours))
})

test_that("scale_is / scale_is_product answer what an object is", {
  s <- scale_example()
  p <- scale_product(a = scale_example(), b = scale_example2())
  expect_true(scale_is(s))
  expect_false(scale_is(p)) # a product holds scales but is not one
  expect_false(scale_is(data.frame(item = "U1")))
  expect_false(scale_is(NULL))
  expect_true(scale_is_product(p))
  expect_false(scale_is_product(s))
})

test_that("scale_class() is the class, so subclassing still works", {
  expect_true(S7::S7_inherits(scale_example(), scale_class()))
  expect_true(S7::S7_inherits(
    scale_product(a = scale_example(), b = scale_example2()),
    scale_product_class()
  ))
  Child <- S7::new_class("Child", parent = scale_class())
  k <- Child(
    leaftable = scale_leaftable(scale_example()),
    frames = scale_frames(scale_example()),
    members = S7::prop(scale_example(), "members"),
    leaf = scale_leaf_column(scale_example())
  )
  expect_true(scale_is(k))
})

test_that("base methods dispatch on a scale", {
  # S3method() entries are NAMESPACE directives, independent of the exports.
  s <- scale_example()
  expect_output(print(s))
  expect_type(names(s), "character")
  expect_s3_class(as.data.frame(s), "data.frame")
  f <- scale_frames(s)[1]
  expect_true(scale_is(s[f, scale_members(s, f)[1]]))
})

test_that("loading the namespace leaves ggplot2 scale objects alone", {
  # ggplot2's scales carry "Scale" in their S3 class vector; our methods are
  # registered on the qualified class only, so none of them may capture one.
  skip_if_not_installed("ggplot2")
  sc <- ggplot2::scale_x_discrete()
  expect_true("Scale" %in% class(sc))
  for (g in c("print", "summary", "names", "as.data.frame", "[")) {
    expect_null(utils::getS3method(g, "Scale", optional = TRUE), info = g)
  }
  expect_no_error(names(sc))
  expect_identical(class(sc[["name"]]), class(ggplot2::waiver()))
  expect_output(print(sc), "ggproto")
})
