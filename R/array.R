# =============================================================================
# Long table <-> dense array
# =============================================================================
# The long table is canonical: it is what the engine computes on, what an
# Arrow dataset holds, and the only form that stays honest when the data is
# sparse. The array is a VIEW -- the shape optimisation models think in, where
# a value is addressed by position along each dimension.
#
# Converting is only sensible when the data is reasonably dense, so the size
# is checked before anything is allocated: a product of an hourly calendar and
# a NUTS3 geoscale is ~12.9M cells, and silently allocating that is not a
# service to anybody.
# =============================================================================

#' @include product-class.R
NULL

#' Axis specification shared by the array converters
#'
#' Normalises a `NestedScale` or `ScaleProduct` into a list of (key column, units)
#' pairs, so both cases go through one code path.
#' @noRd
.array_axes <- function(x, frames = NULL, cols = NULL) {
  one <- function(s, fr) {
    # The column holding codes at frame F is named F -- that is what every
    # recast emits. At the atom frame the scale's own key is equally valid, so
    # when the data is in hand, accept whichever of the two it actually has.
    cand <- if (is.null(fr)) scale_key(s) else fr
    if (!is.null(cols) && !(cand %in% cols) && scale_key(s) %in% cols) {
      cand <- scale_key(s)
    }
    list(
      key = cand,
      units = if (is.null(fr)) scale_units(s) else scale_units(s, fr)
    )
  }
  if (S7::S7_inherits(x, ScaleProduct)) {
    ax <- names(S7::prop(x, "axes"))
    out <- lapply(ax, function(a) {
      one(
        scale_axes(x, a),
        if (is.null(frames)) NULL else frames[[a]]
      )
    })
    names(out) <- ax
    return(out)
  }
  .check_scale(x)
  fr <- if (is.null(frames)) NULL else frames[[1L]]
  z <- one(x, fr)
  stats::setNames(list(z), z$key)
}

#' Data on scales as a dense array
#'
#' Reshapes a long table into an array whose dimensions are the scale's axes,
#' in the order the product declares them, with the units as `dimnames`.
#'
#' @param data A long table with one column per axis key plus the value
#'   column. Lazy inputs are materialised -- an array is a dense in-memory
#'   object by definition.
#' @param x A [`NestedScale`] or [`ScaleProduct`].
#' @param value Name of the value column. Defaults to the single numeric
#'   column that is not a key.
#' @param frames Optional named list giving the frame each axis is keyed at;
#'   defaults to each axis's atom frame.
#' @param fill Value for cells the data does not cover.
#' @param limit Refuse to allocate more than this many cells.
#'
#' @return An array with one dimension per axis.
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' d <- merge(
#'   data.frame(unit = c("U1", "U2")),
#'   data.frame(period = c("p1", "p2"))
#' )
#' d$v <- 1:4
#' as_scale_array(d, p, value = "v")
#' @export
as_scale_array <- function(data, x, value = NULL, frames = NULL, fill = NA,
                           limit = 1e7) {
  backend <- backend_of(data, "data")
  schema <- backend_schema(data)
  axes <- .array_axes(x, frames, cols = names(schema))
  keys <- vapply(axes, function(a) a$key, character(1))
  dims <- vapply(axes, function(a) length(a$units), integer(1))

  n_cells <- prod(as.numeric(dims))
  if (n_cells > limit) {
    .stop(
      paste0(
        "a dense array of this shape needs %s cells (%s), above ",
        "`limit`. The long table is the form that stays workable at ",
        "this size."
      ),
      format(n_cells, big.mark = ",", scientific = FALSE),
      paste(sprintf("%s: %d", names(dims), dims), collapse = " x ")
    )
  }

  d <- as.data.frame(dplyr::collect(backend_lazy(data, backend)))

  missing_keys <- setdiff(unname(keys), names(d))
  if (length(missing_keys) > 0L) {
    .stop(
      "the data has no column(s) %s (one key column per axis)",
      .preview(missing_keys)
    )
  }
  if (is.null(value)) {
    cand <- setdiff(names(d), unname(keys))
    cand <- cand[vapply(d[cand], is.numeric, logical(1))]
    if (length(cand) != 1L) {
      .stop(
        paste0(
          "cannot infer the value column (found: %s); pass ",
          "`value=`"
        ),
        if (length(cand) == 0L) "none" else .preview(cand)
      )
    }
    value <- cand
  }
  if (!value %in% names(d)) {
    .stop(
      "`value` column `%s` is not in the data",
      value
    )
  }

  # Every key must be a unit of its axis: an unrecognised code has no cell to
  # go in, and silently dropping it would lose data without saying so.
  idx <- vector("list", length(axes))
  for (i in seq_along(axes)) {
    codes <- as.character(d[[keys[[i]]]])
    pos <- match(codes, axes[[i]]$units)
    bad <- unique(codes[is.na(pos)])
    if (length(bad) > 0L) {
      .stop(
        "column `%s` holds code(s) that are not units of axis `%s`: %s",
        keys[[i]], names(axes)[[i]], .preview(bad)
      )
    }
    idx[[i]] <- pos
  }

  a <- array(fill,
    dim = unname(dims),
    dimnames = lapply(axes, function(z) z$units)
  )
  a[do.call(cbind, idx)] <- d[[value]]
  a
}

#' @rdname as_scale_array
#'
#' @param a An array produced by [`as_scale_array()`] (or shaped like one).
#' @param drop_na Omit cells the array does not cover, rather than emitting
#'   them as rows with `NA` values.
#'
#' @return `as_scale_table()` returns a `data.frame`: one column per axis key,
#'   plus the value column.
#'
#' @examples
#' as_scale_table(as_scale_array(d, p, value = "v"), p, value = "v")
#' @export
as_scale_table <- function(a, x, value = "value", frames = NULL,
                           drop_na = TRUE) {
  axes <- .array_axes(x, frames)
  keys <- vapply(axes, function(z) z$key, character(1))
  dims <- vapply(axes, function(z) length(z$units), integer(1))

  if (length(dim(a)) != length(axes) || !identical(
    unname(dim(a)),
    unname(dims)
  )) {
    .stop(
      "the array is %s but this scale describes %s",
      paste(dim(a), collapse = " x "), paste(dims, collapse = " x ")
    )
  }

  grid <- expand.grid(lapply(axes, function(z) z$units),
    stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE
  )
  names(grid) <- unname(keys)
  grid[[value]] <- as.vector(a)
  if (isTRUE(drop_na)) {
    grid <- grid[!is.na(grid[[value]]), , drop = FALSE]
  }
  rownames(grid) <- NULL
  grid
}
