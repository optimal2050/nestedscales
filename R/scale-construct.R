# =============================================================================
# Construction
# =============================================================================
# `scale_from_leaftable()` is the general escape hatch: a wide table with one
# row per atom and one column per frame. Dimension packages add their own
# higher layers on top (a catalog lookup in `timescales`, a data provider in
# `geoscales`) and delegate here.
# =============================================================================

#' Build a NestedScale from a flat table of atoms
#'
#' The general constructor. Takes a wide `data.frame` with one row per atom
#' (the finest unit) and one column per frame, and returns a [`NestedScale`].
#'
#' Blank strings (`""`) in frame columns are normalised to `NA`, meaning "this
#' atom has no code at this frame" -- partial coverage is normal in real
#' classification tables.
#'
#' @param leaftable `data.frame` with one row per atom, one column per name in
#'   `frames`, and optionally numeric weight columns.
#' @param frames Ordered character vector of frame names, **coarsest first**.
#'   Each must be a column of `leaftable`.
#' @param key Name of the column holding the unique atom key. Defaults to
#'   `"unit"` if present, otherwise the finest frame (the last entry of
#'   `frames`), which is copied into a `unit` column.
#' @param weights Character vector naming the weight columns. Defaults to all
#'   numeric columns that are neither frames nor reserved names.
#' @param default_weight The weight used when a caller does not name one.
#'   Defaults to the first entry of `weights`.
#' @param members Optional named list giving the ordered code vocabulary per
#'   frame. Derived from `leaftable` when `NULL` (first-appearance order).
#' @param name,desc Short name and description.
#' @param attributes Optional table of per-member physical attributes keyed
#'   by `(frame, unit)`; see [`attach_attributes_scale()`] for the columns.
#' @param aliases Optional table of alternative labels keyed by
#'   `(frame, unit)`; see [`attach_aliases_scale()`] for the columns.
#' @param ... Further named entries merged into `meta` (e.g. `source`,
#'   `labels`).
#'
#' @return A [`NestedScale`].
#'
#' @examples
#' df <- data.frame(
#'   section = c("A", "A", "A", "B"),
#'   group   = c("A1", "A1", "A2", "B1"),
#'   unit    = c("A11", "A12", "A21", "B11"),
#'   gva     = c(100, 200, 300, 400)
#' )
#' scale_from_leaftable(df, frames = c("section", "group", "unit"))
#' @export
scale_from_leaftable <- function(leaftable,
                                 frames,
                                 key = NULL,
                                 weights = NULL,
                                 default_weight = NULL,
                                 members = NULL,
                                 name = "",
                                 desc = "",
                                 attributes = NULL,
                                 aliases = NULL,
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

  # Atom key ------------------------------------------------------------------
  if (is.null(key)) {
    key <- if ("unit" %in% names(leaftable)) "unit" else frames[length(frames)]
  }
  if (length(key) != 1L || is.na(key) || !nzchar(key)) {
    .stop("`key` must be a single non-empty string")
  }
  if (!key %in% names(leaftable)) {
    .stop("`key` column \"%s\" not found in `leaftable`", key)
  }
  leaftable[[key]] <- as.character(leaftable[[key]])
  if (anyNA(leaftable[[key]]) || any(!nzchar(leaftable[[key]]))) {
    .stop(paste0(
      "the atom key column \"%s\" has missing or empty values; ",
      "every atom needs an identifier"
    ), key)
  }

  # Weights -------------------------------------------------------------------
  if (is.null(weights)) {
    cand <- setdiff(names(leaftable), c(frames, .RESERVED_COLS, key))
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
    key        = key,
    meta       = meta,
    attributes = .as_attributes(attributes),
    aliases    = .as_aliases(aliases)
  )
}

#' A second small example NestedScale
#'
#' A different dimension from [`scale_example()`], for the examples that need
#' two axes. Two frames, four atoms, its own key column (`period`) and a
#' weight -- deliberately well behaved, so the awkwardness in an example stays
#' on the other axis.
#'
#' @return A [`NestedScale`] with 4 atoms and frames `era`/`period`.
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
#' * a non-nesting pair of frames -- group `"GB"` draws units from two
#'   different classes, so `class` and `group` do not form a tree;
#' * a unit (`"OTH"`) with no code at any coarser frame (partial coverage).
#'
#' @return A [`NestedScale`] with 7 atoms and frames `sector`/`class`/`group`/`unit`.
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
    unit = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH"),
    size = c(100, 200, 300, 400, 500, 600, 1000),
    count = c(10, 90, 30, 70, 50, 50, 0),
    stringsAsFactors = FALSE
  )
  scale_from_leaftable(
    df,
    frames = c("sector", "class", "group", "unit"),
    name = "example",
    desc = paste(
      "Synthetic example: reused code, non-nesting frame pair,",
      "and an unassigned atom"
    )
  )
}
