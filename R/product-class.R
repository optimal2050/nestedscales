# =============================================================================
# ScaleProduct -- several scales combined into one multi-index
# =============================================================================
# A product of an hourly calendar (8,760 atoms) and a NUTS3 geoscale (1,477)
# has ~12.9M atoms. A `NestedScale`'s contract is "leaftable = one row per atom", so
# a product CANNOT be a NestedScale subclass without either lying about that
# contract or materialising something nobody asked for. It is a sibling class
# that HOLDS scales instead, and its atoms are never built unless asked for
# explicitly.
#
# Data on a product carries ONE KEY COLUMN PER AXIS -- never a pasted
# composite. That is not a style choice: during a recast along one axis, the
# other axes' key columns are ordinary identifier columns, and the engine's
# identifier-column contract carries them through untouched. That contract is
# the whole reason a product recast can be executed as a sequence of
# single-axis recasts.
# =============================================================================

#' @include scale-class.R
NULL

#' A product of several scales (S7 class)
#'
#' Combines two or more [`NestedScale`] objects into one multi-dimensional index --
#' time x space, time x space x industry, and so on. The atoms of the product
#' are tuples of the component atoms, and they stay LAZY: nothing is
#' materialised at construction, and [`product_atoms()`] is the guarded way to
#' realise them.
#'
#' Construct with [`scale_product()`].
#'
#' @param axes Named list of [`NestedScale`] objects; the names are the axis names.
#' @param keys Named character vector, one entry per axis, giving the data
#'   column that carries that axis's unit codes.
#' @param joint_weights Reserved for a weight that varies jointly across axes
#'   (an hourly profile used as a spatial split weight). `NULL` in this
#'   version; a supplied table is validated but not yet consumed.
#' @param meta Named list of attributes (`name`, `desc`).
#'
#' @return A `ScaleProduct` object.
#'
#' @seealso [`scale_product()`], [`product_atoms()`], [`product_size()`]
#' @examples
#' scale_product(a = scale_example(), b = scale_example2())
#' @export
ScaleProduct <- S7::new_class(
  "ScaleProduct",
  package = "nestedscales",
  properties = list(
    axes          = S7::new_property(S7::class_list),
    keys          = S7::new_property(S7::class_character),
    joint_weights = S7::new_property(S7::class_any, default = NULL),
    meta          = S7::new_property(S7::class_list, default = quote(list()))
  ),
  constructor = function(axes, keys, joint_weights = NULL, meta = list()) {
    S7::new_object(
      S7::S7_object(),
      axes = axes, keys = keys, joint_weights = joint_weights, meta = meta
    )
  },
  validator = function(self) {
    errs <- character()

    axes <- S7::prop(self, "axes")
    keys <- S7::prop(self, "keys")
    jw <- S7::prop(self, "joint_weights")

    # axes --------------------------------------------------------------------
    if (!is.list(axes)) {
      return("`axes` must be a list of NestedScale objects")
    }
    if (length(axes) < 2L) {
      errs <- c(errs, "a product needs at least 2 axes")
    }
    nms <- names(axes)
    if (is.null(nms) || anyNA(nms) || any(!nzchar(nms))) {
      errs <- c(errs, "every axis must be named")
    } else if (anyDuplicated(nms)) {
      errs <- c(errs, sprintf(
        "axis names must be unique; duplicated: %s",
        .preview(unique(nms[duplicated(nms)]))
      ))
    }
    for (i in seq_along(axes)) {
      a <- axes[[i]]
      nm <- if (is.null(nms)) as.character(i) else nms[[i]]
      if (S7::S7_inherits(a, ScaleProduct)) {
        errs <- c(errs, sprintf(
          paste0(
            "axis `%s` is itself a product; pass its axes directly ",
            "instead of nesting"
          ), nm
        ))
        next
      }
      if (!S7::S7_inherits(a, NestedScale)) {
        errs <- c(errs, sprintf("axis `%s` is not a NestedScale object", nm))
        next
      }
      # the crosswalk and join machinery is keyed by the object's name
      anm <- S7::prop(a, "meta")[["name"]] %||% ""
      if (!nzchar(anm)) {
        errs <- c(errs, sprintf(
          paste0(
            "axis `%s` has no name; a product's axes must be named ",
            "scales (set meta$name)"
          ), nm
        ))
      }
    }

    # keys --------------------------------------------------------------------
    if (!is.character(keys) || is.null(names(keys))) {
      errs <- c(errs, "`keys` must be a named character vector")
    } else if (length(errs) == 0L) {
      if (!setequal(names(keys), nms)) {
        errs <- c(errs, "`keys` must have exactly one entry per axis")
      } else if (anyDuplicated(keys)) {
        dup <- unique(keys[duplicated(keys)])
        errs <- c(errs, sprintf(
          paste0(
            "axes resolve to the same key column: %s. Data on a product ",
            "carries one column per axis, so the columns must differ -- ",
            "pass `keys=` to name them."
          ), .preview(dup)
        ))
      }
    }

    # joint_weights (reserved) -----------------------------------------------
    if (!is.null(jw)) {
      if (!is.data.frame(jw)) {
        errs <- c(errs, "`joint_weights` must be a data.frame or NULL")
      } else if (length(errs) == 0L) {
        missing_keys <- setdiff(unname(keys), names(jw))
        if (length(missing_keys) > 0L) {
          errs <- c(errs, sprintf(
            "`joint_weights` is missing key column(s): %s",
            .preview(missing_keys)
          ))
        }
        wcols <- setdiff(names(jw), unname(keys))
        if (length(wcols) == 0L) {
          errs <- c(errs, "`joint_weights` has no weight column")
        }
      }
    }

    if (length(errs) == 0L) NULL else errs
  }
)

#' Combine scales into a product index
#'
#' @param ... Two or more named [`NestedScale`] objects; the argument names become
#'   the axis names.
#' @param name,desc Short name and description of the product.
#' @param keys Optional named character vector overriding the data key column
#'   per axis. By default each axis uses its scale's own key
#'   ([`scale_key()`]); if that would make two axes share a column name, the
#'   AXIS NAMES are used instead.
#' @param joint_weights Reserved; see [`ScaleProduct`].
#'
#' @return A [`ScaleProduct`].
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' p
#' product_size(p)
#' @export
scale_product <- function(..., name = "", desc = "", keys = NULL,
                          joint_weights = NULL) {
  axes <- list(...)
  if (length(axes) == 0L) {
    .stop("pass the axes as named arguments, e.g. scale_product(time = cal)")
  }
  nms <- names(axes)
  if (is.null(nms) || any(!nzchar(nms))) {
    .stop(paste0(
      "every axis must be named, e.g. ",
      "scale_product(time = cal, space = gs)"
    ))
  }

  if (is.null(keys)) {
    keys <- vapply(axes, function(a) {
      if (S7::S7_inherits(a, NestedScale)) scale_key(a) else NA_character_
    }, character(1))
    names(keys) <- nms
    # Two generic scales both keyed "unit" would collide; fall back to the
    # axis names, which are unique by construction.
    if (anyDuplicated(stats::na.omit(keys))) {
      keys <- stats::setNames(nms, nms)
    }
  } else {
    if (!is.character(keys) || is.null(names(keys))) {
      .stop("`keys` must be a named character vector, one entry per axis")
    }
    unknown <- setdiff(names(keys), nms)
    if (length(unknown) > 0L) {
      .stop("`keys` names unknown axes: %s", .preview(unknown))
    }
    full <- vapply(axes, function(a) {
      if (S7::S7_inherits(a, NestedScale)) scale_key(a) else NA_character_
    }, character(1))
    names(full) <- nms
    full[names(keys)] <- keys
    keys <- full
  }

  ScaleProduct(
    axes = axes, keys = keys, joint_weights = joint_weights,
    meta = list(name = name, desc = desc)
  )
}

#' @noRd
.check_product <- function(x, arg = "x") {
  if (!S7::S7_inherits(x, ScaleProduct)) {
    .stop("`%s` must be a ScaleProduct object", arg)
  }
  invisible(TRUE)
}

#' Resolve an axis name against a product
#' @noRd
.check_axis <- function(x, axis, arg = "axis") {
  ax <- names(S7::prop(x, "axes"))
  if (is.null(axis) || length(axis) != 1L || is.na(axis)) {
    .stop(
      "`%s` must be a single axis name; one of: %s", arg,
      paste(ax, collapse = ", ")
    )
  }
  if (!axis %in% ax) {
    .stop(
      "`%s` = \"%s\" is not an axis of this product; one of: %s",
      arg, axis, paste(ax, collapse = ", ")
    )
  }
  invisible(axis)
}

# Accessors --------------------------------------------------------------------

#' Axes of a product
#'
#' @param x A [`ScaleProduct`].
#' @param axis Optional single axis name, to get just that [`NestedScale`].
#'
#' @return A named list of [`NestedScale`] objects, or one NestedScale when `axis` is
#'   given.
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' names(scale_axes(p))
#' scale_axes(p, "a")
#' @export
scale_axes <- function(x, axis = NULL) {
  .check_product(x)
  axes <- S7::prop(x, "axes")
  if (is.null(axis)) {
    return(axes)
  }
  .check_axis(x, axis)
  axes[[axis]]
}

#' The data key column of each axis
#'
#' Data on a product carries one of these columns per axis.
#'
#' @param x A [`ScaleProduct`].
#' @return A named character vector, axis -> column name.
#' @examples
#' product_keys(scale_product(a = scale_example(), b = scale_example2()))
#' @export
product_keys <- function(x) {
  .check_product(x)
  S7::prop(x, "keys")
}

#' Frames of each axis
#'
#' @param x A [`ScaleProduct`].
#' @return A named list of character vectors, each coarsest-first.
#' @examples
#' product_frames(scale_product(a = scale_example(), b = scale_example2()))
#' @export
product_frames <- function(x) {
  .check_product(x)
  lapply(S7::prop(x, "axes"), scale_frames)
}

#' Size of a product
#'
#' The per-axis atom counts and their product -- the number of rows a fully
#' dense realisation would have.
#'
#' @param x A [`ScaleProduct`].
#' @return A list with `axes` (named integer, atoms per axis) and `total`
#'   (double, their product).
#' @examples
#' product_size(scale_product(a = scale_example(), b = scale_example2()))
#' @export
product_size <- function(x) {
  .check_product(x)
  n <- vapply(
    S7::prop(x, "axes"),
    function(a) nrow(S7::prop(a, "leaftable")), integer(1)
  )
  list(axes = n, total = prod(as.numeric(n)))
}

#' Weight columns of each axis
#'
#' A product has no weights of its own: the weight of a product atom is the
#' product of its components' weights, which is derived when needed and never
#' stored.
#'
#' @param x A [`ScaleProduct`].
#' @return A named list of character vectors.
#' @examples
#' product_weights(scale_product(a = scale_example(), b = scale_example2()))
#' @export
product_weights <- function(x) {
  .check_product(x)
  lapply(S7::prop(x, "axes"), scale_weights)
}

#' Coverage of each axis
#'
#' Sampling is per-axis and independent, so the coverage of the product is the
#' product of its axes' coverages -- `prod(product_coverage(p))`.
#'
#' @param x A [`ScaleProduct`].
#' @param weight Optional weight name, applied to every axis. `NULL` uses each
#'   axis's own default weight.
#'
#' @return A named numeric, one entry per axis.
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' product_coverage(p)
#' prod(product_coverage(p))
#' @export
product_coverage <- function(x, weight = NULL) {
  .check_product(x)
  vapply(S7::prop(x, "axes"), function(a) {
    w <- weight %||% (S7::prop(a, "meta")[["default_weight"]] %||%
      (if (length(scale_weights(a))) {
        scale_weights(a)[[1L]]
      } else {
        NULL
      }))
    if (is.null(w)) {
      return(1)
    }
    scale_coverage(a, w)
  }, numeric(1))
}

#' Realise the atoms of a product
#'
#' The cross product of the component leaftables: one row per tuple of
#' component atoms, with each axis's key column named by [`product_keys()`]
#' and its frame columns prefixed `"<axis>."`.
#'
#' This is guarded on purpose. An hourly calendar crossed with NUTS3 is
#' ~12.9M rows; the whole point of a product is that its atoms exist
#' implicitly, and conversion never needs them realised (see
#' [`recast_scale()`]). Ask for them only when you actually want the grid.
#'
#' @param x A [`ScaleProduct`].
#' @param limit Maximum number of rows to build. Exceeding it is an error that
#'   reports the size, rather than a very long wait.
#'
#' @return A `data.frame` with `product_size(x)$total` rows.
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' head(product_atoms(p))
#' @export
product_atoms <- function(x, limit = 1e6) {
  .check_product(x)
  sz <- product_size(x)
  if (sz$total > limit) {
    .stop(
      paste0(
        "this product has %s atoms (%s), above `limit` = %s. Pass a ",
        "larger `limit=` to build it anyway -- but conversion never ",
        "needs the atoms realised."
      ),
      format(sz$total, big.mark = ",", scientific = FALSE),
      paste(sprintf("%s: %d", names(sz$axes), sz$axes), collapse = " x "),
      format(limit, big.mark = ",", scientific = FALSE)
    )
  }
  keys <- product_keys(x)
  parts <- lapply(names(S7::prop(x, "axes")), function(ax) {
    a <- scale_axes(x, ax)
    lt <- scale_leaftable(a)
    # the finest frame is often the key column itself; carrying it twice
    # (once as the key, once prefixed) is pure noise
    fr <- setdiff(scale_frames(a), scale_key(a))
    out <- lt[, fr, drop = FALSE]
    names(out) <- paste0(ax, ".", fr)
    out[[keys[[ax]]]] <- as.character(lt[[scale_key(a)]])
    out[, c(keys[[ax]], setdiff(names(out), keys[[ax]])), drop = FALSE]
  })
  out <- Reduce(function(a, b) merge(a, b, by = NULL), parts)
  rownames(out) <- NULL
  out
}

# Format / print ---------------------------------------------------------------

S7::method(format, ScaleProduct) <- function(x, ...) {
  sz <- product_size(x)
  sprintf(
    "<ScaleProduct[%s] atoms=%s>",
    paste(names(S7::prop(x, "axes")), collapse = " x "),
    format(sz$total, big.mark = ",", scientific = FALSE)
  )
}

#' @method print ScaleProduct
print.ScaleProduct <- function(x, ...) {
  axes <- S7::prop(x, "axes")
  keys <- product_keys(x)
  sz <- product_size(x)
  meta <- S7::prop(x, "meta")

  nm <- meta[["name"]] %||% ""
  cat("ScaleProduct:", if (nzchar(nm)) nm else "<unnamed>", "\n")
  if (!is.null(meta[["desc"]]) && nzchar(meta[["desc"]])) {
    cat("Description:", meta[["desc"]], "\n")
  }
  cat("Axes (", length(axes), "):\n", sep = "")
  w <- max(nchar(names(axes)))
  for (ax in names(axes)) {
    a <- axes[[ax]]
    v <- scale_vocab(a)
    cat("  ", format(ax, width = w), " : ", v$object, " '",
      S7::prop(a, "meta")[["name"]] %||% "", "'  ",
      paste(scale_frames(a), collapse = "/"),
      "  atoms ", format(sz$axes[[ax]], big.mark = ","),
      "  key: ", keys[[ax]], "\n",
      sep = ""
    )
  }
  cat("Atoms: ",
    paste(format(sz$axes, big.mark = ","), collapse = " x "),
    " = ", format(sz$total, big.mark = ",", scientific = FALSE),
    "  (not materialised)\n",
    sep = ""
  )
  cov <- product_coverage(x)
  if (any(cov < 1)) {
    cat("Coverage: ",
      paste(sprintf("%s %.1f%%", names(cov), 100 * cov), collapse = " x "),
      " = ", sprintf("%.1f%%", 100 * prod(cov)), "\n",
      sep = ""
    )
  }
  if (!is.null(S7::prop(x, "joint_weights"))) {
    cat("Joint weights: attached\n")
  }
  invisible(x)
}

S7::method(print, ScaleProduct) <- print.ScaleProduct

#' @export
`print.nestedscales::ScaleProduct` <- print.ScaleProduct

#' @method names ScaleProduct
names.ScaleProduct <- function(x) names(S7::prop(x, "axes"))

S7::method(names, ScaleProduct) <- names.ScaleProduct

#' @export
`names.nestedscales::ScaleProduct` <- names.ScaleProduct

# Summary ----------------------------------------------------------------------

#' Summarize a product
#'
#' @param object A [`ScaleProduct`].
#' @param x A `"summary_ScaleProduct"` object (the print method's argument).
#' @param ... Ignored.
#' @return A list of class `"summary_ScaleProduct"`: `name`, `desc`, `axes`
#'   (per-axis summary rows), `total`, `coverage`, `joint_coverage`,
#'   `joint_weights`.
#' @examples
#' summary(scale_product(a = scale_example(), b = scale_example2()))
#' @method summary ScaleProduct
summary.ScaleProduct <- function(object, ...) {
  axes <- S7::prop(object, "axes")
  sz <- product_size(object)
  keys <- product_keys(object)
  cov <- product_coverage(object)
  meta <- S7::prop(object, "meta")

  rows <- data.frame(
    axis = names(axes),
    scale = vapply(
      axes, function(a) S7::prop(a, "meta")[["name"]] %||% "",
      character(1)
    ),
    frames = vapply(axes, function(a) length(scale_frames(a)), integer(1)),
    atoms = sz$axes,
    key = unname(keys[names(axes)]),
    coverage = unname(cov[names(axes)]),
    stringsAsFactors = FALSE, row.names = NULL
  )

  out <- list(
    name = meta[["name"]] %||% "",
    desc = meta[["desc"]] %||% "",
    axes = rows,
    total = sz$total,
    coverage = cov,
    joint_coverage = prod(cov),
    joint_weights = !is.null(S7::prop(object, "joint_weights"))
  )
  class(out) <- "summary_ScaleProduct"
  out
}

S7::method(summary, ScaleProduct) <- summary.ScaleProduct

#' @rdname summary.ScaleProduct
#' @export
`summary.nestedscales::ScaleProduct` <- summary.ScaleProduct

#' @rdname summary.ScaleProduct
#' @export
#' @method print summary_ScaleProduct
print.summary_ScaleProduct <- function(x, ...) {
  cat("<summary of ScaleProduct",
    if (nzchar(x$name)) paste0(" '", x$name, "'"), ">\n",
    sep = ""
  )
  if (nzchar(x$desc)) cat("  desc:           ", x$desc, "\n", sep = "")
  cat("  axes:           ", nrow(x$axes), "\n", sep = "")
  for (i in seq_len(nrow(x$axes))) {
    r <- x$axes[i, ]
    cat("    ", r$axis, " -> '", r$scale, "'  ", r$frames, " frames, ",
      format(r$atoms, big.mark = ","), " atoms, key `", r$key, "`",
      if (r$coverage < 1) sprintf("  [%.1f%% covered]", 100 * r$coverage),
      "\n",
      sep = ""
    )
  }
  cat("  atoms:          ",
    format(x$total, big.mark = ",", scientific = FALSE), "\n",
    sep = ""
  )
  if (x$joint_coverage < 1) {
    cat("  joint coverage: ", sprintf("%.1f%%", 100 * x$joint_coverage),
      "\n",
      sep = ""
    )
  }
  if (isTRUE(x$joint_weights)) cat("  joint weights:  attached\n")
  invisible(x)
}
