# =============================================================================
# Recasting across a product of scales
# =============================================================================
# The whole design rests on one result. For a rule that is LINEAR in the data
# with coefficients depending only on its own axis -- sum, mean,
# weighted_mean, copy -- recasting along axis A is
#
#     y[T, a] = sum_i c_A(i, T) . x[i, a]
#
# and the coefficients never mix axes: `mean`'s denominator depends on the
# target block of its own axis alone, and a product weight w_A . w_B
# factorises, so `weighted_mean` needs no authored joint weight. Composing two
# such operators is a Kronecker product, and Kronecker factors COMMUTE:
#
#     recast A then B  ==  recast B then A  ==  the joint recast
#
# So a separable product recast is executed as a SEQUENCE of ordinary
# single-axis recasts. Nothing new computes the numbers; the Stage-1 engine
# does, once per axis, and the identifier-column contract carries each axis's
# key through the other axis's pass. The 12.9M-row joint crosswalk is never
# built.
#
# `sd` is the exception, because it is not linear. Per-axis `sd` is genuinely
# order-dependent -- the sd of spatial totals is a different quantity from the
# total of per-region sds -- so it is refused rather than silently resolved.
# A scalar `"sd"` means the POOLED sd over all product atoms in a block, which
# IS well defined; its sufficient statistics (sum n, sum n.x, sum n.x^2) each
# factorise, so it is computed by chaining the small per-axis map joins rather
# than by materialising the product.
# =============================================================================

#' @include product-class.R
#' @include recast.R
NULL

#' Rules that compose across axes without regard to order
#' @noRd
.SEPARABLE_RULES <- c("sum", "mean", "weighted_mean", "copy")

#' Resolve the per-(value, axis) rule table for a product recast
#'
#' `rules` may be a scalar (every value, every axis), a named list of scalars
#' or per-axis vectors, or `NULL` (each axis resolves each value through its
#' own registry scope).
#' @noRd
.product_rules <- function(values, axes, rules = NULL, weights = NULL) {
  ax <- names(axes)

  spec_for <- function(v) {
    if (is.null(rules)) {
      return(stats::setNames(vector("list", length(ax)), ax))
    }
    r <- if (is.list(rules)) {
      if (is.null(names(rules))) {
        .stop("`rules` must be a named list, one entry per value column")
      }
      unknown <- setdiff(names(rules), values)
      if (length(unknown) > 0L) {
        .stop(
          "`rules` names columns that are not value columns: %s",
          .preview(unknown)
        )
      }
      rules[[v]]
    } else {
      rules
    }
    if (is.null(r)) {
      return(stats::setNames(vector("list", length(ax)), ax))
    }
    if (length(r) == 1L && is.null(names(r))) {
      return(stats::setNames(rep(list(unname(r)), length(ax)), ax))
    }
    if (is.null(names(r))) {
      .stop(paste0(
        "the rule for `%s` must be a single value or a vector ",
        "NAMED by axis (%s)"
      ), v, paste(ax, collapse = ", "))
    }
    bad <- setdiff(names(r), ax)
    if (length(bad) > 0L) {
      .stop("the rule for `%s` names unknown axes: %s", v, .preview(bad))
    }
    out <- stats::setNames(vector("list", length(ax)), ax)
    for (a in names(r)) out[[a]] <- unname(r[[a]])
    out
  }

  wt_for <- function(a) {
    if (is.null(weights)) {
      return(NULL)
    }
    if (is.null(names(weights))) {
      if (length(weights) != 1L) {
        .stop("`weights` must be a single value or a vector NAMED by axis")
      }
      return(unname(weights[[1L]]))
    }
    bad <- setdiff(names(weights), ax)
    if (length(bad) > 0L) {
      .stop("`weights` names unknown axes: %s", .preview(bad))
    }
    if (!a %in% names(weights)) {
      return(NULL)
    }
    unname(weights[[a]])
  }

  out <- list()
  for (a in ax) {
    per_value <- list()
    for (v in values) {
      r <- spec_for(v)[[a]]
      if (is.null(r)) {
        entry <- get_scale_rule(v, scope = .scale_scope(axes[[a]]))
        if (is.null(entry)) {
          .stop(paste0(
            "no aggregation rule for value column `%s` on axis `%s`. Pass ",
            "`rules = list(%s = c(%s = \"...\"))` or register one ",
            "with `register_scale_rule()`."
          ), v, a, v, a)
        }
        r <- entry$rule
      }
      per_value[[v]] <- match.arg(r, SCALE_RULES)
    }
    out[[a]] <- list(rules = per_value, weight = wt_for(a))
  }
  out
}

#' Reject the rule combinations that do not compose
#'
#' Order-dependence is a property of the RULE, not of the data, so it is
#' caught before anything is computed.
#' @noRd
.check_product_rules <- function(spec, values, ax) {
  for (v in values) {
    rr <- vapply(ax, function(a) spec[[a]]$rules[[v]], character(1))
    is_sd <- rr == "sd"
    if (any(is_sd) && !all(is_sd)) {
      .stop(
        paste0(
          "rule \"sd\" for `%s` is order-dependent across axes, so it has no ",
          "single answer here: the sd of the `%s`-aggregated totals and the ",
          "total of the per-`%s` sds are different quantities.\n",
          "  * for one of those, recast the axes in two explicit calls;\n",
          "  * for the pooled sd over all product atoms in a block, pass ",
          "rules = list(%s = \"sd\")."
        ),
        v, ax[!is_sd][[1L]], ax[!is_sd][[1L]], v
      )
    }
    if (any(rr %in% .SHARE_RULES)) {
      .stop(paste0(
        "rule \"share\" changes which axis the output is keyed ",
        "by, so it is not defined across a product; recast the ",
        "one axis with `recast_scale()` on that axis's scale"
      ))
    }
    bad <- setdiff(rr, c(.SEPARABLE_RULES, "sd"))
    if (length(bad) > 0L) {
      .stop("unsupported rule for `%s` on a product: %s", v, .preview(bad))
    }
  }
  invisible(TRUE)
}

#' Which column of the data carries this axis's codes?
#'
#' The product's declared key when present; otherwise the single frame of that
#' axis appearing among the columns, which is how data keyed at a coarser
#' frame is recognised.
#' @noRd
.resolve_axis_key <- function(s, declared, schema, axis) {
  if (declared %in% names(schema)) {
    return(declared)
  }
  hit <- intersect(S7::prop(s, "frames"), names(schema))
  if (length(hit) == 1L) {
    return(hit)
  }
  .stop(
    paste0(
      "the data has no `%s` column for axis `%s`, and its frame ",
      "columns present are %s. Data on a product carries one key ",
      "column per axis (see `product_keys()`); pass `keys=` to name ",
      "a different one."
    ),
    declared, axis,
    if (length(hit) == 0L) "none" else .preview(hit)
  )
}

#' Order the axis passes so the biggest reduction happens first
#'
#' Each pass after the first then works on a smaller table: an hourly axis
#' collapsing 730x should run before a spatial one collapsing 41x.
#' @noRd
.pass_order <- function(axes, targets) {
  ratio <- vapply(names(targets), function(a) {
    s <- axes[[a]]
    target <- targets[[a]]
    n_from <- nrow(S7::prop(s, "leaftable"))
    n_to <- if (S7::S7_inherits(target, NestedScale)) {
      nrow(S7::prop(target, "leaftable"))
    } else {
      length(S7::prop(s, "members")[[target]])
    }
    if (n_to <= 0) Inf else n_from / n_to
  }, numeric(1))
  names(targets)[order(ratio, decreasing = TRUE)]
}

#' Recast data indexed by a product of scales
#'
#' Converts one or more axes of a product in a single call. Axes named in `target`
#' are converted; axes left out pass through untouched.
#'
#' Execution is a sequence of ordinary single-axis [`recast_scale()`] calls --
#' see the file comment in `R/product-recast.R` for why that is exactly
#' equivalent to a joint recast for every supported rule, and why the joint
#' crosswalk is never built. The passes are ordered so the axis that reduces
#' the data most runs first.
#'
#' @param data The data, in any supported backend, carrying one key column per
#'   axis (see [`product_keys()`]) plus the value columns.
#' @param x A [`ScaleProduct`].
#' @param target Named list or character vector, one entry per axis to convert:
#'   either a frame name of that axis's scale, or another [`NestedScale`] to convert
#'   into. Axes omitted pass through unchanged.
#' @param values Value columns to convert. Default: all numeric columns that
#'   are not key columns. Numeric identifiers (a year) must be excluded
#'   explicitly.
#' @param rules Rule per value column and axis: a scalar for everything, or a
#'   named list whose entries are scalars or vectors named by axis, e.g.
#'   `list(load = c(time = "weighted_mean", space = "sum"))`. `NULL` (default)
#'   resolves each column on each axis through that dimension's own scope in
#'   the rule registry -- which is where an intensive/extensive asymmetry
#'   between dimensions belongs.
#' @param weights Weight column per axis, e.g. `c(space = "pop")`; scalar
#'   applies to every axis.
#' @param na_action Passed to each axis's pass.
#' @param collect For lazy inputs: materialise (`TRUE`) or return the query.
#'
#' @return The recast data in the input's class, keyed by the converted axes'
#'   target units.
#'
#' @details
#' A per-axis `"sd"` is refused because it is order-dependent; a scalar
#' `"sd"` means the pooled sd over all product atoms in a target block, which
#' is well defined and is computed without materialising the product.
#' `"share"` is not defined across a product, because it changes which axis
#' the result is keyed by.
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' d <- merge(
#'   data.frame(unit = c("U1", "U2", "U3", "U4", "U5", "U6")),
#'   data.frame(period = c("p1", "p2", "p3", "p4"))
#' )
#' d$cap <- seq_len(nrow(d))
#'
#' # aggregate both axes at once
#' recast_product(d, p, target = list(a = "sector", b = "era"), rules = "sum")
#'
#' # different rules per axis
#' recast_product(d, p,
#'   target = list(a = "sector", b = "era"),
#'   rules = list(cap = c(a = "sum", b = "weighted_mean"))
#' )
#' @export
recast_product <- function(data, x, target,
                           values = NULL,
                           rules = NULL,
                           weights = NULL,
                           na_action = c("drop", "error", "keep"),
                           collect = NULL) {
  na_action <- match.arg(na_action)
  .check_product(x, "x")
  backend <- backend_of(data, "data")
  schema <- backend_schema(data)
  .check_ms_cols(schema)

  axes <- S7::prop(x, "axes")
  keys <- product_keys(x)
  ax <- names(axes)

  # -- targets ---------------------------------------------------------------
  if (is.null(target) || length(target) == 0L) {
    .stop("`target` must name at least one axis to convert")
  }
  if (!is.list(target)) target <- as.list(target)
  if (is.null(names(target)) || any(!nzchar(names(target)))) {
    .stop("`target` must be named by axis; one of: %s", paste(ax, collapse = ", "))
  }
  unknown <- setdiff(names(target), ax)
  if (length(unknown) > 0L) {
    .stop("`target` names unknown axes: %s", .preview(unknown))
  }
  for (a in names(target)) {
    t <- target[[a]]
    if (!S7::S7_inherits(t, NestedScale)) .check_frame(axes[[a]], t, paste0("to$", a))
  }

  # -- resolve each axis's key column ----------------------------------------
  # The declared key when it is there, otherwise the one frame of that axis
  # present in the data -- so data keyed at a COARSER frame works here exactly
  # as it does in `recast_scale()`.
  keys[names(target)] <- vapply(names(target), function(a) {
    .resolve_axis_key(axes[[a]], keys[[a]], schema, a)
  }, character(1))

  # -- values and rules ------------------------------------------------------
  all_keys <- unname(keys)
  values <- .values_for(schema, all_keys, character(), values)
  values <- setdiff(values, all_keys)
  if (length(values) == 0L) {
    .stop("no value columns to convert; specify `values=`")
  }
  spec <- .product_rules(values, axes[names(target)], rules, weights)
  .check_product_rules(spec, values, names(target))
  .check_target_collisions(axes, target, keys)

  # -- the pooled-sd columns take the joint path -----------------------------
  sd_cols <- values[vapply(values, function(v) {
    all(vapply(
      names(target), function(a) spec[[a]]$rules[[v]] == "sd",
      logical(1)
    ))
  }, logical(1))]
  sep_cols <- setdiff(values, sd_cols)

  res <- NULL
  if (length(sep_cols) > 0L) {
    res <- .product_sequential(data, backend, x, target, sep_cols, spec,
      na_action, collect,
      keys = keys,
      all_values = values
    )
  }
  if (length(sd_cols) > 0L) {
    joint <- .product_pooled_sd(data, backend, x, target, sd_cols, spec,
      na_action, collect,
      keys = keys,
      all_values = values
    )
    res <- if (is.null(res)) {
      joint
    } else {
      out_keys <- unname(vapply(
        names(target),
        function(a) .axis_target_name(target[[a]]),
        character(1)
      ))
      id_cols <- setdiff(names(res), c(out_keys, sep_cols))
      dplyr::full_join(res, joint,
        by = c(id_cols, out_keys),
        na_matches = "na"
      )
    }
  }
  res
}

#' Separable path: one ordinary recast per axis, biggest reduction first
#' @noRd
.product_sequential <- function(data, backend, x, target, values, spec,
                                na_action, collect, keys, all_values) {
  axes <- S7::prop(x, "axes")
  order_ax <- .pass_order(axes, target)

  # Value columns bound for the OTHER path must be dropped, not carried: an
  # unconverted numeric column would be read as an identifier and would then
  # split every group.
  drop_cols <- setdiff(all_values, values)
  out <- if (length(drop_cols) > 0L) {
    dplyr::select(backend_lazy(data, backend), -dplyr::all_of(drop_cols))
  } else {
    data
  }
  n <- length(order_ax)
  for (i in seq_along(order_ax)) {
    a <- order_ax[[i]]
    rules_a <- unlist(spec[[a]]$rules[values])
    # Intermediate passes stay lazy when the input is lazy; only the final
    # pass honours `collect`, so a lazy input yields a lazy result.
    out <- recast_scale(
      out, axes[[a]],
      source = NULL, target = target[[a]], key = keys[[a]],
      values = values,
      rule = rules_a,
      weight = spec[[a]]$weight,
      na_action = na_action,
      collect = if (i == n) collect else NULL
    )
  }
  out
}

#' Target column name an axis's pass will produce
#' @noRd
.axis_target_name <- function(to_a) {
  if (S7::S7_inherits(to_a, NestedScale)) .atom_level(to_a) else to_a
}

#' Guard the one way a sequence of passes can silently lose a column
#'
#' Each pass drops columns named like ITS OWN scale's frames, treating them as
#' unit attributes. So if one axis converts into a name that happens to be a
#' frame of another axis still to be processed, that freshly written column
#' would be dropped by the later pass. Caught here rather than discovered as a
#' missing column.
#' @noRd
.check_target_collisions <- function(axes, target, keys) {
  for (a in names(target)) {
    tgt <- .axis_target_name(target[[a]])
    for (b in names(axes)) {
      if (identical(a, b)) next
      if (tgt %in% S7::prop(axes[[b]], "frames")) {
        .stop(paste0(
          "axis `%s` converts to \"%s\", which is also a frame of ",
          "axis `%s` -- that column would be dropped when `%s` is ",
          "processed. Rename the frame, or convert the axes in ",
          "separate calls."
        ), a, tgt, b, b)
      }
    }
  }
  invisible(TRUE)
}

#' Joint path: pooled sd over the product atoms of each target block
#'
#' The pooled statistics factorise, so the two SMALL per-axis crosswalks are
#' chained onto the data and one grouped summarise closes it out with
#' `n = n_a * n_b`. The product crosswalk is never formed.
#' @noRd
.product_pooled_sd <- function(data, backend, x, target, values, spec,
                               na_action, collect, keys, all_values) {
  axes <- S7::prop(x, "axes")
  ax <- names(target)

  # Identifiers are what is left once EVERY value column and key is removed --
  # the value columns handled by the separable path are not identifiers.
  id_cols <- setdiff(names(backend_schema(data)), c(unname(keys), all_values))
  q <- dplyr::select(
    backend_lazy(data, backend),
    dplyr::all_of(c(id_cols, unname(keys[ax]), values))
  )
  n_syms <- character(0)

  for (a in ax) {
    s <- axes[[a]]
    if (S7::S7_inherits(target[[a]], NestedScale)) {
      .stop(paste0(
        "pooled \"sd\" across a product needs frame targets; ",
        "axis `%s` targets another scale"
      ), a)
    }
    source <- .infer_source(s, backend_schema(data), keys[[a]])
    m <- scale_map(s, source, target[[a]], weight = spec[[a]]$weight)
    if (na_action != "keep") m <- m[!is.na(m[[target[[a]]]]), , drop = FALSE]

    jm <- m[, c(source, target[[a]], "n_overlap")]
    n_col <- paste0(".ms_n_", a)
    names(jm) <- c(keys[[a]], paste0(".ms_to_", a), n_col)
    n_syms <- c(n_syms, n_col)
    q <- dplyr::inner_join(q, jm, by = keys[[a]])
  }

  # n for a product atom is the product of the per-axis overlap counts
  n_expr <- Reduce(
    function(l, r) rlang::expr(!!l * !!r),
    lapply(n_syms, rlang::sym)
  )
  q <- dplyr::mutate(q, .ms_n_overlap = !!n_expr)

  grp_to <- paste0(".ms_to_", ax)
  grp <- c(id_cols, grp_to)

  nn <- rlang::sym(".ms_n_overlap")
  exprs <- lapply(values, function(v) {
    sym <- rlang::sym(v)
    rlang::expr(dplyr::if_else(
      sum(!!nn) > 1,
      sqrt((sum(!!nn * (!!sym)^2) - (sum(!!nn * (!!sym)))^2 / sum(!!nn)) /
        (sum(!!nn) - 1)),
      NA_real_
    ))
  })
  names(exprs) <- values

  res <- q |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grp))) |>
    dplyr::summarise(!!!exprs, .groups = "drop")

  # like every other pass, the output is keyed by the TARGET frame name
  tgts <- vapply(ax, function(a) .axis_target_name(target[[a]]), character(1))
  for (a in ax) {
    res <- dplyr::rename(
      res, !!rlang::sym(tgts[[a]]) := !!rlang::sym(paste0(".ms_to_", a))
    )
  }
  res <- dplyr::select(
    res,
    dplyr::all_of(c(unname(tgts), id_cols, values))
  )

  if (backend_is_lazy(backend) && !isTRUE(collect)) {
    return(res)
  }
  backend_restore(res, backend, collect = collect)
}

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

S7::method(recast, list(S7::class_any, ScaleProduct)) <-
  function(x, scale, target, ...) {
    recast_product(data = x, x = scale, target = target, ...)
  }

#' Attach every axis's labels to product-indexed data
#'
#' [`join_scale()`] applied to each axis in turn, keyed by that axis's column.
#' Because every attached column is named after its scale, the result carries
#' all the axes' labels side by side.
#'
#' @param data The data, carrying one key column per axis.
#' @param x A [`ScaleProduct`].
#' @param axes Axis names to attach; `NULL` (default) attaches all of them.
#' @param ... Passed to [`join_scale()`] (`attach`, `meta`, `as_factor`, ...).
#'
#' @return `data` with each axis's labels attached, in its own class.
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' d <- data.frame(unit = c("U1", "U3"), period = c("p1", "p2"), v = 1:2)
#' join_product(d, p, attach = TRUE)
#' @export
join_product <- function(data, x, axes = NULL, ...) {
  .check_product(x, "x")
  ax <- names(S7::prop(x, "axes"))
  if (is.null(axes)) axes <- ax
  bad <- setdiff(axes, ax)
  if (length(bad) > 0L) .stop("unknown axes: %s", .preview(bad))
  keys <- product_keys(x)
  out <- data
  for (a in axes) {
    out <- join_scale(out, scale_axes(x, a), key = keys[[a]], ...)
  }
  out
}

#' Subset a product componentwise
#'
#' Applies [`filter_scale()`] to one axis and returns a new product.
#'
#' @param x A [`ScaleProduct`].
#' @param axis Axis to filter.
#' @param frame,unit Passed to [`filter_scale()`].
#' @param ... Passed to [`filter_scale()`].
#'
#' @return A [`ScaleProduct`].
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' filter_product(p, "a", "sector", "P")
#' @export
filter_product <- function(x, axis, frame, unit, ...) {
  .check_product(x, "x")
  .check_axis(x, axis)
  axes <- S7::prop(x, "axes")
  axes[[axis]] <- filter_scale(axes[[axis]], frame, unit, ...)
  S7::prop(x, "axes") <- axes
  x
}
