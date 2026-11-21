# =============================================================================
# Construction
# =============================================================================
# `scale_from_leaftable()` is the general escape hatch: a wide table with one
# row per leaf and one column per frame. Dimension packages add their own
# higher layers on top (a catalog lookup in `timescales`, a data provider in
# `geoscales`) and delegate here.
# =============================================================================

#' Build a NestedScale from a flat table of leaves
#'
#' The general constructor. Takes a wide `data.frame` with one row per leaf
#' (the finest member) and one column per frame, and returns a [`NestedScale`].
#'
#' Blank strings (`""`) in frame columns are normalised to `NA`, meaning "this
#' leaf has no code at this frame" -- partial coverage is normal in real
#' classification tables.
#'
#' @param leaftable `data.frame` with one row per leaf, one column per name in
#'   `frames`, and optionally numeric weight columns.
#' @param frames Ordered character vector of frame names, **coarsest first**.
#'   Each must be a column of `leaftable`.
#' @param leaf Name of the leaf column: the column that identifies the
#'   leaves, one unique code per row. Defaults to a column called `"leaf"`
#'   if present, otherwise to the finest frame (the last entry of `frames`).
#' @param weights Character vector naming the weight columns. Defaults to all
#'   numeric columns that are neither frames nor reserved names.
#' @param default_weight The weight used when a caller does not name one.
#'   Defaults to the first entry of `weights`.
#' @param members Optional named list giving the ordered code vocabulary per
#'   frame. Derived from `leaftable` when `NULL` (first-appearance order).
#' @param name,desc Short name and description.
#' @param attributes Optional table of per-member physical attributes keyed
#'   by `(frame, member)`; see [`attach_attributes_scale()`] for the columns.
#' @param aliases Optional table of alternative labels keyed by
#'   `(frame, member)`; see [`attach_aliases_scale()`] for the columns.
#' @param labels Optional table of display names keyed by
#'   `(frame, member, variant)`; see [`attach_labels_scale()`] for the
#'   columns.
#' @param ... Further named entries merged into `meta` (e.g. `source`).
#'
#' @return A [`NestedScale`].
#'
#' @examples
#' df <- data.frame(
#'   section = c("A", "A", "A", "B"),
#'   group   = c("A1", "A1", "A2", "B1"),
#'   item    = c("A11", "A12", "A21", "B11"),
#'   gva     = c(100, 200, 300, 400)
#' )
#' scale_from_leaftable(df, frames = c("section", "group", "item"))
#' @export
scale_from_leaftable <- function(leaftable,
                                 frames,
                                 leaf = NULL,
                                 weights = NULL,
                                 default_weight = NULL,
                                 members = NULL,
                                 name = "",
                                 desc = "",
                                 attributes = NULL,
                                 aliases = NULL,
                                 labels = NULL,
                                 ...) {
  if (!is.data.frame(leaftable)) {
    .stop("`leaftable` must be a data.frame")
  }
  leaftable <- as.data.frame(leaftable, stringsAsFactors = FALSE)

  if (!is.character(frames) || length(frames) == 0L) {
    .stop("`frames` must be a non-empty character vector")
  }
  missing_cols <- setdiff(frames, names(leaftable))
  if (length(missing_cols) > 0L) {
    .stop("`leaftable` is missing frame column(s): %s", .preview(missing_cols))
  }

  # Normalise frame columns to character, blanks -> NA ------------------------
  for (f in frames) {
    leaftable[[f]] <- .blank_to_na(leaftable[[f]])
  }

  # Leaf column ---------------------------------------------------------------
  if (is.null(leaf)) {
    leaf <- if ("leaf" %in% names(leaftable)) "leaf" else frames[length(frames)]
  }
  if (length(leaf) != 1L || is.na(leaf) || !nzchar(leaf)) {
    .stop("`leaf` must be a single non-empty string")
  }
  if (!leaf %in% names(leaftable)) {
    .stop("`leaf` column \"%s\" not found in `leaftable`", leaf)
  }
  leaftable[[leaf]] <- as.character(leaftable[[leaf]])
  if (anyNA(leaftable[[leaf]]) || any(!nzchar(leaftable[[leaf]]))) {
    .stop(paste0(
      "the leaf column \"%s\" has missing or empty values; ",
      "every leaf needs an identifier"
    ), leaf)
  }

  # Weights -------------------------------------------------------------------
  if (is.null(weights)) {
    cand <- setdiff(names(leaftable), c(frames, .RESERVED_COLS, leaf))
    weights <- cand[vapply(leaftable[cand], is.numeric, logical(1))]
  }
  weights <- as.character(weights)
  bad_w <- setdiff(weights, names(leaftable))
  if (length(bad_w) > 0L) {
    .stop("weight column(s) not found in `leaftable`: %s", .preview(bad_w))
  }
  if (is.null(default_weight) && length(weights) > 0L) {
    default_weight <- weights[[1L]]
  }

  # Members -------------------------------------------------------------------
  if (is.null(members)) {
    members <- lapply(frames, function(f) {
      unique(stats::na.omit(as.character(leaftable[[f]])))
    })
    names(members) <- frames
  }

  empty <- frames[vapply(members[frames], length, integer(1)) == 0L]
  if (length(empty) > 0L) {
    .stop("frame(s) with no codes at all: %s", .preview(empty))
  }

  # Coarse-to-fine ordering sanity check --------------------------------------
  # Tests CONTAINMENT, not code counts. Counts are a proxy for granularity and
  # a wrong one: `m12_md365` has 12 MONTH codes and 31 MDAY codes with the
  # nesting the right way round, and cross-cutting frames (YDAY x HOUR) nest
  # in neither direction, which is legal here. Only the REVERSE containment --
  # each coarse code sitting inside one fine code -- means the list is
  # actually upside down.
  .nests_in <- function(fine, coarse) {
    if (anyNA(leaftable[[fine]]) || anyNA(leaftable[[coarse]])) {
      return(FALSE)
    }
    all(tapply(
      as.character(leaftable[[coarse]]),
      as.character(leaftable[[fine]]),
      function(z) length(unique(z))
    ) == 1L)
  }
  if (length(frames) > 1L) {
    inverted <- character()
    for (i in seq_len(length(frames) - 1L)) {
      a <- frames[i]
      b <- frames[i + 1L]
      if (.nests_in(a, b) && !.nests_in(b, a)) inverted <- c(inverted, b)
    }
    if (length(inverted) > 0L) {
      .warn(
        paste0(
          "`frames` should be ordered coarsest first, but %s ",
          "CONTAINS the frame before it. Aggregation direction is ",
          "taken from this order."
        ),
        .preview(inverted)
      )
    }
  }

  meta <- c(
    list(
      name           = name,
      desc           = desc,
      weights        = weights,
      default_weight = default_weight
    ),
    list(...)
  )

  NestedScale(
    leaftable  = leaftable,
    frames     = frames,
    members    = members,
    leaf       = leaf,
    meta       = meta,
    attributes = .as_attributes(attributes),
    aliases    = .as_aliases(aliases),
    labels     = .as_labels(labels)
  )
}

#' A second small example NestedScale
#'
#' A different dimension from [`scale_example()`], for the examples that need
#' two axes. Two frames, four leaves, its own leaf column (`period`) and a
#' weight -- deliberately well behaved, so the awkwardness in an example stays
#' on the other axis.
#'
#' @return A [`NestedScale`] with 4 leaves and frames `era`/`period`.
#'
#' @examples
#' scale_example2()
#' scale_product(a = scale_example(), b = scale_example2())
#' @export
scale_example2 <- function() {
  df <- data.frame(
    era = c("E1", "E1", "E2", "E2"),
    period = c("p1", "p2", "p3", "p4"),
    span = c(1, 3, 2, 4),
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(
    df,
    frames = c("era", "period"), name = "example2",
    desc = "Synthetic second dimension, for product examples"
  )
}

#' A small example NestedScale
#'
#' A synthetic 3-frame hierarchy used in examples and tests. It deliberately
#' reproduces three awkward features of real classification tables:
#'
#' * a code (`"G1"`) reused at more than one frame, so bare codes are ambiguous
#'   and every lookup must name its frame;
#' * a non-nesting pair of frames -- group `"GB"` draws members from two
#'   different classes, so `class` and `group` do not form a tree;
#' * a member (`"OTH"`) with no code at any coarser frame (partial coverage).
#'
#' @return A [`NestedScale`] with 7 leaves and frames
#'   `sector`/`class`/`group`/`item`.
#'
#' @examples
#' s <- scale_example()
#' s
#' scale_nests(s, "class", "group") # FALSE - they cross-cut
#' @export
scale_example <- function() {
  df <- data.frame(
    sector = c("P", "P", "P", "P", "S", "S", NA),
    class = c("G1", "G1", "G2", "G2", "S1", "S1", NA),
    group = c("G1", "G1", "GB", "GB", "GB", "GC", NA),
    item = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH"),
    size = c(100, 200, 300, 400, 500, 600, 1000),
    count = c(10, 90, 30, 70, 50, 50, 0),
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(
    df,
    frames = c("sector", "class", "group", "item"),
    name = "example",
    desc = paste(
      "Synthetic example: reused code, non-nesting frame pair,",
      "and an unassigned leaf"
    )
  )
}
