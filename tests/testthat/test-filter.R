# =========================================================================== #
# filter_scale() / prune_scale() / scale_share() / navigation.
# =========================================================================== #

test_that("filter_scale() keeps the named units and rebuilds members", {
  s <- scale_example()
  p <- filter_scale(s, "sector", "P")
  expect_identical(nrow(scale_leaftable(p)), 4L)
  expect_identical(scale_units(p, "sector"), "P")
  expect_identical(scale_units(p, "class"), c("G1", "G2"))
  expect_identical(scale_units(p), c("U1", "U2", "U3", "U4"))
})

test_that("a filter records coverage against the ROOT parent", {
  s <- scale_example()
  p <- filter_scale(s, "sector", "P")
  # sizes 100+200+300+400 of 3100
  expect_equal(scale_coverage(p, "size"), 1000 / 3100)
  expect_identical(S7::prop(p, "meta")$parent_name, "example")
})

test_that("filters compose against the root, not the intermediate", {
  s <- scale_example()
  p <- filter_scale(s, "sector", "P")
  g <- filter_scale(p, "class", "G1")
  # G1 is 300 of the ORIGINAL 3100, not of P's 1000
  expect_equal(scale_coverage(g, "size"), 300 / 3100)
  expect_identical(S7::prop(g, "meta")$parent_name, "example")
})

test_that("a sample is renamed so it cannot impersonate its parent", {
  s <- scale_example()
  p <- filter_scale(s, "sector", "P")
  expect_identical(S7::prop(p, "meta")$name, "example[sector:P]")
  # two different single-unit samples get different names
  q <- filter_scale(s, "sector", "S")
  expect_false(identical(
    S7::prop(p, "meta")$name,
    S7::prop(q, "meta")$name
  ))
})

test_that("a filter that keeps everything is a true no-op", {
  s <- scale_example()
  all_sectors <- c(scale_units(s, "sector"))
  # every atom with a sector, plus the unassigned one, is not expressible
  # through `sector`; filter on the atom frame instead
  keep_all <- filter_scale(s, "unit", scale_units(s))
  expect_identical(S7::prop(keep_all, "meta")$name, "example")
  expect_equal(scale_coverage(keep_all), scale_coverage(s))
  expect_null(S7::prop(keep_all, "meta")$parent_name)
})

test_that("filter_scale() validates its codes", {
  s <- scale_example()
  expect_error(filter_scale(s, "sector", "NOPE"), "code\\(s\\) not found")
  expect_error(filter_scale(s, "nope", "P"), "is not a frame")
})

test_that("a frame left empty errors unless dropping is requested", {
  # a scale whose unassigned atom carries positive weight
  df <- data.frame(
    grp = c("A", "A", NA), unit = c("u1", "u2", "oth"),
    w = c(1, 2, 3), stringsAsFactors = FALSE
  )
  s <- scale_from_leaftable(df, frames = c("grp", "unit"), name = "part")
  expect_error(filter_scale(s, "unit", "oth"), "left with no codes")
  dropped <- filter_scale(s, "unit", "oth", drop_empty_frames = TRUE)
  expect_identical(scale_frames(dropped), "unit")
  expect_equal(scale_coverage(dropped, "w"), 3 / 6)
})

test_that("a subset whose weights all vanish is rejected, not silently kept", {
  # `count` is 0 for the unassigned atom, so keeping only it would leave a
  # weight column that sums to zero -- a scale that cannot weight anything.
  # The validator refuses rather than handing back a degenerate object.
  s <- scale_example()
  expect_error(
    filter_scale(s, "unit", "OTH", drop_empty_frames = TRUE),
    "sums to zero"
  )
})

test_that("`[` subsets a scale", {
  s <- scale_example()
  expect_equal(s["sector", "P"], filter_scale(s, "sector", "P"))
  expect_error(s["sector"], "subset a scale as")
})

test_that("prune_scale() makes a coarser frame the atom layer", {
  s <- scale_example()
  p <- prune_scale(s, "class")
  expect_identical(scale_frames(p), c("sector", "class"))
  expect_identical(scale_key(p), "unit")
  expect_identical(scale_units(p), c("G1", "G2", "S1"))
  # weights are summed over the collapsed atoms
  lt <- scale_leaftable(p)
  expect_equal(lt$size[lt$class == "G1"], 300)
  expect_equal(lt$size[lt$class == "S1"], 1100)
})

test_that("prune_scale() records the parent and the coverage it lost", {
  s <- scale_example()
  p <- prune_scale(s, "class")
  expect_identical(S7::prop(p, "meta")$name, "example@class")
  expect_identical(S7::prop(p, "meta")$parent_name, "example")
  # the unassigned atom (size 1000) is dropped
  expect_equal(scale_coverage(p, "size"), 2100 / 3100)
})

test_that("pruning to the atom frame keeps everything", {
  s <- scale_example()
  p <- prune_scale(s, "unit")
  expect_identical(scale_frames(p), scale_frames(s))
  expect_identical(nrow(scale_leaftable(p)), 7L)
})

test_that("scale_share() normalises over the object or within a parent", {
  s <- scale_example()
  all <- scale_share(s, "class", weight = "size")
  expect_named(all, c("class", "size", "share"))
  expect_equal(sum(all$share), 1)
  expect_equal(all$share[all$class == "G1"], 300 / 2100)

  within <- scale_share(s, "class", weight = "size", within = "sector")
  expect_true("sector" %in% names(within))
  # within P: G1 300, G2 700
  expect_equal(within$share[within$class == "G1"], 300 / 1000)
  # each parent's shares sum to 1
  expect_equal(as.vector(tapply(within$share, within$sector, sum)), c(1, 1))
})

# Navigation ------------------------------------------------------------------

test_that("children and parents step one frame by default", {
  s <- scale_example()
  expect_identical(scale_children(s, "sector", "P"), c("G1", "G2"))
  expect_identical(scale_parents(s, "class", "G1"), "P")
  expect_identical(
    scale_children(s, "sector", "P", target = "unit"),
    c("U1", "U2", "U3", "U4")
  )
})

test_that("the ends of the hierarchy have no children or parents", {
  s <- scale_example()
  expect_error(scale_children(s, "unit", "U1"), "finest frame")
  expect_error(scale_parents(s, "sector", "P"), "coarsest frame")
})

test_that("descendants and ancestors report every finer/coarser frame", {
  s <- scale_example()
  d <- scale_descendants(s, "sector", "P")
  expect_named(d, c("frame", "unit"))
  expect_setequal(unique(d$frame), c("class", "group", "unit"))

  a <- scale_ancestors(s, "unit", "U5")
  expect_setequal(unique(a$frame), c("sector", "class", "group"))
  expect_identical(a$unit[a$frame == "sector"], "S")
})

test_that("navigation is atom-mediated, so cross-cutting is honest", {
  s <- scale_example()
  # group GB draws units from both sectors, so it has two parents
  expect_setequal(scale_parents(s, "group", "GB"), c("G2", "S1"))
})

test_that("scale_ancestry() does not manufacture false relationships", {
  s <- scale_example()
  anc <- scale_ancestry(s)
  # U5 is in sector S; a transitive closure through group GB would wrongly
  # make sector P its ancestor
  su <- anc[anc$parent_frame == "sector" & anc$child_frame == "unit", ]
  expect_identical(su$parent[su$child == "U5"], "S")
  expect_false("P" %in% su$parent[su$child == "U5"])
})

test_that("navigation validates unknown codes", {
  s <- scale_example()
  expect_error(scale_children(s, "sector", "NOPE"), "not found at frame")
})

test_that("filter keeps only the surviving members' attribute and alias rows", {
  es <- .fuels()
  fossil <- filter_scale(es, "group", "Fossil")
  at <- scale_attributes(fossil)
  expect_false("Bio" %in% at$unit)           # the group is gone
  expect_equal(nrow(at), 5L)
  al <- scale_aliases(fossil)
  expect_false("Electricity" %in% al$unit)
  expect_equal(nrow(al), 2L)
  expect_identical(es["group", "Bio"], filter_scale(es, "group", "Bio"))
  # a frame dropped entirely takes its rows with it
  es2 <- attach_attributes_scale(
    es, data.frame(frame = "phase", unit = "gas", attribute = "lhv",
                   value = 48, unit_of_measure = "GJ/t"),
    source = "x", kind = "property")
  expect_error(filter_scale(es2, "group", "Power"), "drop_empty_frames")
  p <- filter_scale(es2, "group", "Power", drop_empty_frames = TRUE)
  expect_identical(scale_frames(p), c("group", "carrier", "fuel"))
  expect_false("phase" %in% scale_attributes(p)$frame)
})

test_that("prune keeps coarser attribute rows, drops finer ones, resolves", {
  es <- .fuels_tree()
  p <- prune_scale(es, "carrier")
  expect_true(scale_is(p))
  expect_identical(scale_frames(p), c("group", "carrier"))
  expect_setequal(scale_leaftable(p)$fuel, scale_units(es, "carrier"))
  at <- scale_attributes(p)
  expect_false("fuel" %in% at$frame)
  expect_setequal(at$unit, c("Oil", "Bio", "Gas"))
  expect_setequal(scale_aliases(p)$unit, c("Coal", "Electricity"))
  r <- scale_attributes(p, "lhv", frame = "carrier")
  expect_equal(r$value[r$unit == "Biomass"], 15.0)   # still inherited
  expect_identical(S7::prop(p, "meta")[["name"]], "tree@carrier")
  expect_identical(S7::prop(p, "meta")[["parent_name"]], "tree")
  # a cross-cutting frame between group and carrier makes Biomass three
  # atoms, which the key uniqueness rule refuses
  expect_error(prune_scale(.fuels(), "carrier"), "must be unique")
})
