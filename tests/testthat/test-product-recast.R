# =========================================================================== #
# recast_product(): the separability laws.
#
# The design claim is that a product recast IS a sequence of single-axis
# recasts, in either order. These tests state that as a law and check it for
# every supported rule pair, rather than pinning numbers a refactor could
# quietly change.
# =========================================================================== #

.pp <- function() scale_product(a = scale_example(), b = scale_example2())

.pdata <- function() {
  d <- merge(
    data.frame(
      unit = c("U1", "U2", "U3", "U4", "U5", "U6"),
      stringsAsFactors = FALSE
    ),
    data.frame(
      period = c("p1", "p2", "p3", "p4"),
      stringsAsFactors = FALSE
    )
  )
  d$cap <- seq_len(nrow(d))
  d
}

# Sort rows and columns so only CONTENT is compared.
.norm <- function(d) {
  d <- as.data.frame(d)
  d <- d[, sort(names(d)), drop = FALSE]
  d <- d[do.call(order, lapply(d, as.character)), , drop = FALSE]
  rownames(d) <- NULL
  d
}

.by_hand <- function(d, order_ax, rule_a, rule_b) {
  s <- .pp()
  step <- d
  for (ax in order_ax) {
    step <- if (ax == "a") {
      recast_scale(step, scale_axes(s, "a"),
        source = "unit", target = "sector",
        key = "unit", values = "cap", rule = rule_a
      )
    } else {
      recast_scale(step, scale_axes(s, "b"),
        source = "period", target = "era",
        key = "period", values = "cap", rule = rule_b
      )
    }
  }
  step
}

test_that("a product recast equals either sequential order (commutation)", {
  p <- .pp()
  d <- .pdata()
  rules <- c("sum", "mean", "weighted_mean", "copy")
  for (ra in rules) {
    for (rb in rules) {
      dd <- if (ra == "copy" || rb == "copy") {
        # `copy` needs a value that IS constant within every target block
        transform(d, cap = 7)
      } else {
        d
      }

      ab <- suppressWarnings(.by_hand(dd, c("a", "b"), ra, rb))
      ba <- suppressWarnings(.by_hand(dd, c("b", "a"), ra, rb))
      one <- suppressWarnings(
        recast_product(dd, p,
          target = list(a = "sector", b = "era"),
          rules = list(cap = c(a = ra, b = rb))
        )
      )

      lab <- sprintf("a=%s, b=%s", ra, rb)
      expect_equal(.norm(ab), .norm(ba),
        ignore_attr = TRUE,
        label = paste("order independence:", lab)
      )
      expect_equal(.norm(one), .norm(ab),
        ignore_attr = TRUE,
        label = paste("product == sequential:", lab)
      )
    }
  }
})

test_that("sum over a product conserves the total", {
  p <- .pp()
  d <- .pdata()
  out <- suppressWarnings(
    recast_product(d, p, target = list(a = "sector", b = "era"), rules = "sum")
  )
  expect_equal(sum(out$cap, na.rm = TRUE), sum(d$cap))
})

test_that("the output is keyed by the target frames", {
  p <- .pp()
  out <- suppressWarnings(
    recast_product(.pdata(), p,
      target = list(a = "sector", b = "era"),
      rules = "sum"
    )
  )
  expect_true(all(c("sector", "era", "cap") %in% names(out)))
  expect_false(any(c("unit", "period") %in% names(out)))
})

test_that("an axis left out of `to` passes through untouched", {
  p <- .pp()
  out <- suppressWarnings(
    recast_product(.pdata(), p, target = list(a = "sector"), rules = "sum")
  )
  expect_true(all(c("sector", "period") %in% names(out)))
  expect_setequal(unique(out$period), c("p1", "p2", "p3", "p4"))
  expect_equal(sum(out$cap, na.rm = TRUE), sum(.pdata()$cap))
})

test_that("a scalar rule applies to every axis and column", {
  p <- .pp()
  d <- .pdata()
  expect_equal(
    .norm(suppressWarnings(
      recast_product(d, p,
        target = list(a = "sector", b = "era"),
        rules = "sum"
      )
    )),
    .norm(suppressWarnings(
      recast_product(d, p,
        target = list(a = "sector", b = "era"),
        rules = list(cap = c(a = "sum", b = "sum"))
      )
    ))
  )
})

test_that("the rule registry supplies per-axis defaults", {
  withr::defer(clear_scale_rules())
  clear_scale_rules()
  register_scale_rule("cap", "sum")
  p <- .pp()
  d <- .pdata()
  expect_equal(
    .norm(suppressWarnings(
      recast_product(d, p, target = list(a = "sector", b = "era"))
    )),
    .norm(suppressWarnings(
      recast_product(d, p,
        target = list(a = "sector", b = "era"),
        rules = "sum"
      )
    ))
  )
})

test_that("a column with no rule on some axis is an error", {
  withr::defer(clear_scale_rules())
  clear_scale_rules()
  p <- .pp()
  expect_error(
    recast_product(.pdata(), p, target = list(a = "sector", b = "era")),
    "no aggregation rule for value column"
  )
})

test_that("per-axis weights are honoured", {
  p <- .pp()
  d <- .pdata()
  a <- suppressWarnings(
    recast_product(d, p,
      target = list(a = "sector", b = "era"),
      rules = list(cap = c(a = "weighted_mean", b = "sum")),
      weights = c(a = "size")
    )
  )
  b <- suppressWarnings(
    recast_product(d, p,
      target = list(a = "sector", b = "era"),
      rules = list(cap = c(a = "weighted_mean", b = "sum")),
      weights = c(a = "count")
    )
  )
  # different weights on axis `a` give different answers
  expect_false(isTRUE(all.equal(a$cap, b$cap)))
})

# The non-separable cases ------------------------------------------------------

test_that("a per-axis sd is refused, with both alternatives named", {
  p <- .pp()
  expect_error(
    recast_product(.pdata(), p,
      target = list(a = "sector", b = "era"),
      rules = list(cap = c(a = "sd", b = "sum"))
    ),
    "order-dependent"
  )
  expect_error(
    recast_product(.pdata(), p,
      target = list(a = "sector", b = "era"),
      rules = list(cap = c(a = "sd", b = "sum"))
    ),
    "pooled sd"
  )
})

test_that("share is refused across a product", {
  p <- .pp()
  expect_error(
    recast_product(.pdata(), p,
      target = list(a = "sector", b = "era"),
      rules = "share"
    ),
    "not defined across a product"
  )
})

test_that("pooled sd equals the direct sd over the product atoms", {
  p <- .pp()
  d <- .pdata()
  out <- suppressWarnings(
    recast_product(d, p,
      target = list(a = "sector", b = "era"),
      rules = list(cap = "sd")
    )
  )

  # the data is keyed at BOTH atom frames, so every row is one product atom
  # and the pooled sd is just the sd of the values in each block
  lt_a <- scale_leaftable(scale_example())
  lt_b <- scale_leaftable(scale_example2())
  d$sector <- lt_a$sector[match(d$unit, lt_a$unit)]
  d$era <- lt_b$era[match(d$period, lt_b$period)]
  ref <- stats::aggregate(cap ~ sector + era, data = d, FUN = stats::sd)

  got <- merge(out, ref, by = c("sector", "era"), suffixes = c("", ".ref"))
  expect_equal(got$cap, got$cap.ref)
  expect_gt(nrow(got), 0)
})

test_that("pooled sd weights by the product atom counts", {
  p <- .pp()
  # keyed at a COARSER frame on axis a, so each row covers several atoms
  d <- merge(
    data.frame(class = c("G1", "G2", "S1"), stringsAsFactors = FALSE),
    data.frame(period = c("p1", "p2"), stringsAsFactors = FALSE)
  )
  d$v <- c(1, 2, 3, 4, 5, 6)
  out <- suppressWarnings(
    recast_product(d, p,
      target = list(a = "sector", b = "era"),
      rules = list(v = "sd")
    )
  )
  # Block (P, E1) covers classes G1 and G2 across periods p1 and p2: four
  # rows, each standing for 2 atoms (G1 and G2 hold 2 units each; p1 and p2
  # are single atoms). The pooled sd weights each value by that atom count.
  vals <- d$v[d$class %in% c("G1", "G2") & d$period %in% c("p1", "p2")]
  n <- rep(2, length(vals))
  nn <- sum(n)
  expect_equal(
    out$v[out$sector == "P" & out$era == "E1"],
    sqrt((sum(n * vals^2) - sum(n * vals)^2 / nn) / (nn - 1))
  )
})

test_that("a mixed call splits into the sequential and joint paths", {
  p <- .pp()
  d <- .pdata()
  d$other <- d$cap * 2
  out <- suppressWarnings(
    recast_product(d, p,
      target = list(a = "sector", b = "era"),
      rules = list(cap = "sum", other = "sd")
    )
  )
  expect_true(all(c("sector", "era", "cap", "other") %in% names(out)))
  expect_equal(sum(out$cap, na.rm = TRUE), sum(d$cap))
  expect_false(anyNA(out$other))
})

# Argument handling ------------------------------------------------------------

test_that("`to` must name known axes", {
  p <- .pp()
  expect_error(
    recast_product(.pdata(), p, target = list(zz = "sector")),
    "unknown axes"
  )
  expect_error(
    recast_product(.pdata(), p, target = list()),
    "at least one axis"
  )
  expect_error(
    recast_product(.pdata(), p, target = list("sector")),
    "must be named by axis"
  )
  expect_error(
    recast_product(.pdata(), p, target = list(a = "nope")),
    "is not a frame"
  )
})

test_that("a missing key column is reported as such", {
  p <- .pp()
  d <- .pdata()
  d$period <- NULL
  expect_error(
    recast_product(d, p, target = list(b = "era"), rules = "sum"),
    "one key column per axis"
  )
})

test_that("a target colliding with another axis's frame is refused", {
  # `era` is a frame of axis b; make axis a able to target that name too
  df <- data.frame(
    era = c("X", "X", "Y"), unit = c("u1", "u2", "u3"),
    w = c(1, 1, 1), stringsAsFactors = FALSE
  )
  odd <- scale_from_leaftable(df, frames = c("era", "unit"), name = "odd")
  p <- scale_product(a = odd, b = scale_example2())
  d <- merge(
    data.frame(
      unit = c("u1", "u2", "u3"),
      stringsAsFactors = FALSE
    ),
    data.frame(period = c("p1", "p2"), stringsAsFactors = FALSE)
  )
  d$v <- 1
  expect_error(
    recast_product(d, p, target = list(a = "era"), rules = "sum"),
    "would be dropped"
  )
})

test_that("recast() dispatches on a product", {
  p <- .pp()
  d <- .pdata()
  expect_equal(
    suppressWarnings(recast(d, p, target = list(a = "sector"), rules = "sum")),
    suppressWarnings(recast_product(d, p,
      target = list(a = "sector"),
      rules = "sum"
    ))
  )
})

# Backends ---------------------------------------------------------------------

test_that("a product recast honours the backend contract", {
  p <- .pp()
  expect_backend_contract(
    .pdata(),
    function(x, collect = NULL) {
      suppressWarnings(
        recast_product(x, p,
          target = list(a = "sector", b = "era"),
          rules = "sum", collect = collect
        )
      )
    },
    key_cols = c("sector", "era"),
    value_cols = "cap"
  )
})

test_that("the joint sd path also honours the backend contract", {
  p <- .pp()
  expect_backend_contract(
    .pdata(),
    function(x, collect = NULL) {
      suppressWarnings(
        recast_product(x, p,
          target = list(a = "sector", b = "era"),
          rules = list(cap = "sd"), collect = collect
        )
      )
    },
    key_cols = c("sector", "era")
  )
})

# Componentwise verbs ----------------------------------------------------------

test_that("filter_product() subsets one axis and keeps a product", {
  p <- .pp()
  q <- filter_product(p, "a", "sector", "P")
  expect_s3_class(q, "nestedscales::ScaleProduct")
  expect_identical(product_size(q)$axes[["a"]], 4L)
  expect_identical(product_size(q)$axes[["b"]], 4L)
  expect_equal(unname(product_coverage(q)[["a"]]), 1000 / 3100)
  expect_error(filter_product(p, "zz", "sector", "P"), "is not an axis")
})

test_that("join_product() attaches every axis's labels", {
  p <- .pp()
  d <- data.frame(
    unit = c("U1", "U3"), period = c("p1", "p2"),
    v = 1:2, stringsAsFactors = FALSE
  )
  out <- join_product(d, p, attach = TRUE)
  expect_true(all(c("example", "example2") %in% names(out)))
  expect_true("example.sector" %in% names(out))
  expect_true("example2.era" %in% names(out))
})
