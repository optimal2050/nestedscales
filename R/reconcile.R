# =============================================================================
# Reconciliation: does the fine data add up to the published total?
# =============================================================================
# Three different things look alike and must not be confused:
#
#   * a STRUCTURAL RESIDUAL -- a real component belonging to the parent and to
#     none of the children (non-regionalized GDP, non-allocable taxes, an
#     "n.e.c." bucket). That is a MEMBER of the scale; declare it with
#     `residuals =` and it aggregates upward on its own. See
#     `scale_residuals()`.
#   * KNOWN SUBSETTING -- the scale deliberately holds part of its parent.
#     That is `meta$coverage`, written by `filter_scale()`/`prune_scale()`.
#     Eleven months of twelve is coverage.
#   * a DATA DISCREPANCY -- every child is present and they still do not sum
#     to the published parent figure: rounding, disclosure control,
#     independent estimation, different vintages. That is what this file is
#     for, and it is deliberately NOT stored on the scale: it varies by
#     variable, by period and by vintage, so a number parked on the scale
#     would go stale without saying so.
# =============================================================================

#' @include recast.R
NULL

#' Check fine data against an independent parent total
#'
#' Aggregates `data` from `source` to `target` and compares the result with
#' `totals`, the parent figure from another source. Reports the gap by
#' default; can also close it.
#'
#' @param data The fine data, keyed at `source`.
#' @param x A [`NestedScale`].
#' @param source,target Frame names: where the data is, and the coarser frame whose
#'   totals it is checked against.
#' @param totals The independent parent figures: a table keyed at `target`
#'   carrying the same value columns as `data`, plus any identifier columns
#'   (which are matched, so a per-year total works).
#' @param key Column of `data` holding the codes at `source`; defaults as in
#'   [`recast_scale()`].
#' @param values Value columns to check. Default: the numeric columns common
#'   to `data` and `totals`.
#' @param rule How the value aggregates. `"sum"` (default) is the question
#'   "does it add up"; an intensive quantity reconciles as
#'   `"weighted_mean"` instead.
#' @param weight Weight column for `rule = "weighted_mean"`.
#' @param balance What to do about the gap:
#'   * `"none"` (default) -- report it and change nothing.
#'   * `"residual"` -- return the data with each group's gap written onto its
#'     declared residual unit at `source`. Needs exactly one residual per
#'     affected group, and `rule = "sum"`.
#'   * `"proportional"` -- return the data scaled by `target / aggregated`
#'     within each group, so every group hits its total.
#' @param tolerance Relative size below which a gap counts as rounding; sets
#'   the `ok` column, and gaps within it are left alone when balancing.
#'
#' @return With `balance = "none"`, a long gap table: the `target` column, any
#'   identifiers, `value` (which column), `aggregated`, `target`, `gap`
#'   (`target - aggregated`), `rel_gap` and `ok`. With a balancing method, the
#'   adjusted data keyed as the input was, carrying that same table as its
#'   `"reconciliation"` attribute.
#'
#' @examples
#' lf <- data.frame(
#'   country = c("DE", "DE", "DE"),
#'   unit = c("DE1", "DE2", "DE_XR"),
#'   pop = c(40, 30, 0), stringsAsFactors = FALSE
#' )
#' s <- scale_from_leaftable(lf,
#'   frames = c("country", "unit"), key = "unit",
#'   weights = "pop", name = "geo",
#'   residuals = list(unit = "DE_XR")
#' )
#' fine <- data.frame(unit = c("DE1", "DE2", "DE_XR"), gdp = c(400, 300, 0))
#' published <- data.frame(country = "DE", gdp = 750)
#'
#' reconcile_scale(fine, s, source = "unit", target = "country", published)
#'
#' reconcile_scale(fine, s,
#'   source = "unit", target = "country", published,
#'   balance = "residual"
#' )
#' @export
reconcile_scale <- function(data, x, source, target, totals,
                            key = NULL, values = NULL,
                            rule = "sum", weight = NULL,
                            balance = c("none", "residual", "proportional"),
                            tolerance = 1e-9) {
  balance <- match.arg(balance)
  .check_scale(x, "x")
  .check_frame(x, source, "source")
  .check_frame(x, target, "target")
  if (scale_rank(x, target) >= scale_rank(x, source)) {
    .stop(paste0(
      "`target` must be coarser than `source`; reconciliation compares ",
      "fine data with a parent total (got from = \"%s\", ",
      "to = \"%s\")"
    ), source, target)
  }
  if (!is.data.frame(data)) data <- as.data.frame(data)
  totals <- as.data.frame(totals)
  if (!target %in% names(totals)) {
    .stop("`totals` has no `%s` column to identify the parent groups", target)
  }

  if (is.null(key)) key <- if (source %in% names(data)) source else scale_key(x)
  if (!key %in% names(data)) {
    .stop("the data has no column named `%s`; pass `key=`", key)
  }

  if (is.null(values)) {
    num_d <- names(data)[vapply(data, is.numeric, logical(1))]
    num_t <- names(totals)[vapply(totals, is.numeric, logical(1))]
    values <- setdiff(intersect(num_d, num_t), c(key, target, scale_frames(x)))
    if (length(values) == 0L) {
      .stop(paste0(
        "no numeric column is common to the data and `totals`; ",
        "pass `values=`"
      ))
    }
  }
  missing_v <- setdiff(values, intersect(names(data), names(totals)))
  if (length(missing_v) > 0L) {
    .stop(
      "value column(s) missing from the data or `totals`: %s",
      .preview(missing_v)
    )
  }

  # Identifiers present on BOTH sides -- a per-year total matches per year.
  id_cols <- intersect(
    setdiff(names(data), c(key, values, scale_frames(x))),
    setdiff(names(totals), c(target, values))
  )

  agg <- as.data.frame(suppressWarnings(
    recast_scale(data, x,
      source = source, target = target, key = key, values = values,
      rule = rule, weight = weight, diagnostics = "off"
    )
  ))

  gap <- .reconcile_gap(agg, totals, target, id_cols, values, tolerance)
  if (identical(balance, "none")) {
    return(gap)
  }

  out <- switch(balance,
    residual = .balance_residual(data, x, source, target, key, id_cols, gap, rule),
    proportional = .balance_proportional(
      data, x, source, target, key, id_cols,
      gap
    )
  )
  attr(out, "reconciliation") <- gap
  out
}

#' Long gap table: one row per (parent group, identifiers, value column)
#' @noRd
.reconcile_gap <- function(agg, totals, target, id_cols, values, tolerance) {
  by <- c(id_cols, target)
  parts <- lapply(values, function(v) {
    a <- agg[, c(by, v), drop = FALSE]
    names(a)[ncol(a)] <- "aggregated"
    t <- totals[, c(by, v), drop = FALSE]
    names(t)[ncol(t)] <- "target"
    m <- merge(a, t, by = by, all = TRUE)
    m$value <- v
    m
  })
  out <- do.call(rbind, parts)
  out$gap <- out$target - out$aggregated
  denom <- pmax(abs(out$target), abs(out$aggregated), na.rm = TRUE)
  out$rel_gap <- ifelse(denom > 0, out$gap / denom, 0)
  out$ok <- !is.na(out$rel_gap) & abs(out$rel_gap) <= tolerance
  out <- out[, c(
    by, "value", "aggregated", "target", "gap", "rel_gap",
    "ok"
  ), drop = FALSE]
  out <- out[order(out$value, out[[target]]), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Rows of `gap` worth acting on
#' @noRd
.gap_rows <- function(gap) {
  which(!gap$ok & !is.na(gap$gap) & gap$gap != 0)
}

#' Select the data rows belonging to one gap row
#' @noRd
.gap_select <- function(out, key, units, id_cols, g) {
  sel <- as.character(out[[key]]) %in% units
  for (idc in id_cols) sel <- sel & out[[idc]] == g[[idc]]
  sel
}

#' Write each group's gap onto its declared residual unit
#' @noRd
.balance_residual <- function(data, x, source, target, key, id_cols, gap, rule) {
  if (!identical(rule, "sum")) {
    .stop(paste0(
      "`balance = \"residual\"` needs `rule = \"sum\"`: a gap ",
      "between weighted means is not an amount that can be parked ",
      "on a member"
    ))
  }
  res <- scale_residuals(x, source)
  if (length(res) == 0L) {
    .stop(paste0(
      "no residual is declared at `%s`, so the gap has nowhere to ",
      "go. Declare one when building the scale ",
      "(`residuals = list(%s = ...)`), or use ",
      "`balance = \"proportional\"`."
    ), source, source)
  }

  # Exactly one residual per parent group, or the gap has no single home.
  fam <- scale_family(x, target, source)
  fam <- fam[fam$child %in% res, c("parent", "child"), drop = FALSE]
  dup <- unique(fam$parent[duplicated(fam$parent)])
  if (length(dup) > 0L) {
    .stop(
      paste0(
        "%s group(s) have more than one declared residual at `%s`, ",
        "so the gap has no single home: %s"
      ), target, source,
      .preview(dup)
    )
  }

  out <- data
  for (i in .gap_rows(gap)) {
    g <- gap[i, ]
    unit <- fam$child[fam$parent == g[[target]]]
    if (length(unit) != 1L) {
      .stop("no declared residual at `%s` for %s `%s`", source, target, g[[target]])
    }
    sel <- .gap_select(out, key, unit, id_cols, g)
    if (!any(sel)) {
      .stop(paste0(
        "the data has no row for residual `%s`, so the gap cannot ",
        "be written there; add a zero row for it"
      ), unit)
    }
    out[sel, g$value] <- out[sel, g$value] + g$gap
  }
  out
}

#' NestedScale each group's children so the group hits its target
#' @noRd
.balance_proportional <- function(data, x, source, target, key, id_cols, gap) {
  fam <- scale_family(x, target, source)
  out <- data
  for (i in .gap_rows(gap)) {
    g <- gap[i, ]
    if (is.na(g$aggregated) || g$aggregated == 0) {
      .stop(
        paste0(
          "%s `%s` aggregates to 0 for `%s`, so it cannot be scaled ",
          "to a target of %s. Park the gap on a residual instead, ",
          "or fix the data."
        ), target, g[[target]], g$value,
        format(g$target)
      )
    }
    kids <- fam$child[fam$parent == g[[target]]]
    sel <- .gap_select(out, key, kids, id_cols, g)
    out[sel, g$value] <- out[sel, g$value] * (g$target / g$aggregated)
  }
  out
}
