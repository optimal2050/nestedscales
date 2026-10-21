# =============================================================================
# recast_scale() -- the central conversion verb
# =============================================================================
# Aggregation and disaggregation are ONE operation. Every conversion routes
# through the atom layer; the route is collapsed into a small crosswalk table
# by `scale_map()` (R/map.R), so the converter is a single dplyr pipeline --
# ONE right_join plus ONE grouped summarise -- that runs unchanged over
# data.frame / tibble / data.table / dtplyr / arrow inputs (R/backend.R).
#
# Direction falls out of the crosswalk automatically: coarse -> fine is the
# weight-share split doing the work, fine -> coarse is the aggregation. Frames
# that cross-cut work for free, because no step assumes they nest.
#
# The split factor is the ONE place a dimension's arithmetic could differ, and
# it is fixed here for every dimension:
#
#     f = w / w_from        when the crosswalk carries weights
#     f = n_overlap/n_from  otherwise (the equal split)
#
# A dimension whose atom layer is generated rather than enumerated (time)
# supplies extra identifier columns on the crosswalk through `scale_map(by=)`;
# from there they ride the identifier-column contract like any panel column.
# =============================================================================

#' @include scale-class.R
#' @include map.R
NULL

# Internal working columns; user columns may not collide with these
.MS_COLS <- c(
  ".ms_parent", ".ms_tot", ".ms_to", ".ms_f", ".ms_n_from",
  ".ms_n_overlap", ".ms_w", ".ms_w_from", ".ms_nsrc",
  ".ms_nexp"
)

utils::globalVariables(c(
  ".ms_to", ".ms_f", ".ms_n_from", ".ms_n_overlap",
  ".ms_w", ".ms_w_from", ".ms_parent", ".ms_nsrc",
  ".ms_nexp"
))

# -----------------------------------------------------------------------------
# shared internals
# -----------------------------------------------------------------------------

#' Auto-detect numeric value columns of `x` (given its zero-row schema)
#' @noRd
.values_for <- function(schema, key, drop_cols, values) {
  if (is.null(values)) {
    candidates <- setdiff(names(schema), c(key, drop_cols))
    values <- candidates[vapply(schema[candidates], is.numeric, logical(1))]
    if (length(values) == 0L) {
      .stop("no numeric value columns found in `x`; specify `values=`")
    }
    return(values)
  }
  if (!all(values %in% names(schema))) {
    .stop(
      "value column(s) not in `x`: %s",
      .preview(setdiff(values, names(schema)))
    )
  }
  values
}

#' Guard against user columns colliding with internal working columns
#' @noRd
.check_ms_cols <- function(schema) {
  clash <- intersect(names(schema), .MS_COLS)
  if (length(clash) > 0L) {
    .stop("`x` uses reserved column name(s): %s", .preview(clash))
  }
}

#' Build the per-value-column summarise expressions for one rule set.
#'
#' Bare symbols (never `.data[[...]]`) so the expressions translate on every
#' backend -- dtplyr and arrow both mistranslate pronoun subsetting in places
#' where plain symbols work.
#' @noRd
.rule_exprs <- function(values, rules, sfx = NULL) {
  out <- list()
  nn <- rlang::sym(".ms_n_overlap")
  for (v in values) {
    # Each value column reads the split factor and weight belonging to ITS
    # weight column. When several weights are in play the crosswalk carries
    # them side by side as `.ms_f_1`, `.ms_w_1`, ... so one join and one
    # summarise serve them all.
    sx <- if (is.null(sfx)) "" else sfx[[v]]
    f <- rlang::sym(paste0(".ms_f", sx))
    ww <- rlang::sym(paste0(".ms_w", sx))
    sym <- rlang::sym(v)
    out[[v]] <- switch(rules[[v]]$rule,
      sum = rlang::expr(sum(!!sym * !!f)),
      mean = rlang::expr(sum(!!sym * !!nn) / sum(!!nn)),
      weighted_mean = rlang::expr(
        dplyr::if_else(sum(!!ww) > 0,
          sum(!!sym * !!ww) / sum(!!ww),
          sum(!!sym * !!nn) / sum(!!nn)
        )
      ),
      copy = rlang::expr(mean(!!sym)), # constancy pre-checked eagerly
      sd = rlang::expr(
        dplyr::if_else(
          sum(!!nn) > 1,
          sqrt((sum(!!nn * (!!sym)^2) -
            (sum(!!nn * (!!sym)))^2 / sum(!!nn)) /
            (sum(!!nn) - 1)),
          NA_real_
        )
      ),
      .stop("Unknown rule: %s", rules[[v]]$rule)
    )
  }
  out
}

#' Aggregation expressions for one group of rows (the atom-layer half)
#'
#' `weighted_mean` falls back to a plain mean when the weights sum to zero,
#' which keeps a group of zero-weight members at their common value instead of
#' `NaN`.
#'
#' With `na_rm = TRUE` an `NA` is read as "this member says nothing" rather
#' than as an unknown that poisons the group: the other members decide the
#' result, and only an all-`NA` group stays `NA`. A weighted mean also drops
#' the weight of each `NA` member, so the remaining weights still sum to the
#' divisor.
#' @noRd
.group_exprs <- function(values, rules, wt_col, na_rm = FALSE) {
  exprs <- list()
  ww <- rlang::sym(wt_col)
  for (v in values) {
    sym <- rlang::sym(v)
    if (!na_rm) {
      exprs[[v]] <- switch(rules[[v]]$rule,
        sum = rlang::expr(sum(!!sym)),
        mean = rlang::expr(mean(!!sym)),
        weighted_mean = rlang::expr(dplyr::if_else(
          sum(!!ww) > 0, sum(!!sym * !!ww) / sum(!!ww), mean(!!sym)
        )),
        copy = rlang::expr(mean(!!sym)),
        sd = rlang::expr(stats::sd(!!sym)),
        .stop("Unknown rule: %s", rules[[v]]$rule)
      )
      next
    }
    n_ok <- rlang::expr(sum(as.integer(!is.na(!!sym))))
    w_ok <- rlang::expr(sum(dplyr::if_else(is.na(!!sym), 0, !!ww)))
    exprs[[v]] <- switch(rules[[v]]$rule,
      sum = rlang::expr(dplyr::if_else(
        !!n_ok > 0, sum(!!sym, na.rm = TRUE), NA_real_
      )),
      mean = rlang::expr(dplyr::if_else(
        !!n_ok > 0, mean(!!sym, na.rm = TRUE), NA_real_
      )),
      weighted_mean = rlang::expr(dplyr::if_else(
        !!n_ok == 0, NA_real_,
        dplyr::if_else(
          !!w_ok > 0,
          sum(dplyr::if_else(is.na(!!sym), 0, !!sym * !!ww),
            na.rm = TRUE
          ) / !!w_ok,
          mean(!!sym, na.rm = TRUE)
        )
      )),
      copy = rlang::expr(dplyr::if_else(
        !!n_ok > 0, mean(!!sym, na.rm = TRUE), NA_real_
      )),
      sd = rlang::expr(stats::sd(!!sym, na.rm = TRUE)),
      .stop("Unknown rule: %s", rules[[v]]$rule)
    )
  }
  exprs
}

#' Constancy guard for `copy`-rule columns
#'
#' The per-group min and max ride the main summarise (see
#' `.recast_pipeline()`), so this reads an already-computed AGGREGATE -- one
#' row per target group -- rather than running its own pass over the data.
#'
#' A group whose sources were only partially supplied is skipped, matching the
#' behaviour of the injected-NA formulation this replaced: there the missing
#' row made max/min `NA`, here the repair has already set the value `NA`.
#' Either way a group that cannot be answered is not also reported as
#' inconsistent.
#' @noRd
.check_copy_result <- function(res, copy_cols, backend, unit = "unit") {
  if (length(copy_cols) == 0L) {
    return(invisible(NULL))
  }
  cols <- c(
    paste0(".ms_mx_", copy_cols), paste0(".ms_mn_", copy_cols),
    copy_cols
  )
  chk <- backend_pull(dplyr::select(res, dplyr::all_of(cols)))
  for (v in copy_cols) {
    rng <- chk[[paste0(".ms_mx_", v)]] - chk[[paste0(".ms_mn_", v)]]
    ok <- !is.na(rng) & !is.na(chk[[v]])
    if (any(ok & rng > 1e-9)) {
      stop(sprintf(
        paste0(
          "rule \"copy\" for `%s`: values are not constant within a ",
          "target %s"
        ), v, unit
      ), call. = FALSE)
    }
  }
  invisible(NULL)
}

#' Complete a materialised result to the full target vocabulary, in the
#' contract order: identifier groups in first-appearance order, target codes
#' in member order, the NA row (if any) last.
#' @noRd
.recast_complete <- function(res, idc, out_keys, key, id_cols, values) {
  full <- data.frame(x = out_keys, stringsAsFactors = FALSE)
  names(full) <- key
  if (nrow(idc) > 0L && length(id_cols) > 0L) {
    full <- dplyr::cross_join(idc, full)
  }
  out <- dplyr::left_join(full, res, by = c(id_cols, key), na_matches = "na")
  as.data.frame(out)[, c(key, id_cols, values), drop = FALSE]
}

#' Infer the source frame from `x`'s columns
#' @noRd
.infer_source <- function(x, schema, key) {
  fr <- S7::prop(x, "frames")
  v <- scale_vocab(x)
  if (!is.null(key) && key %in% fr) {
    return(key)
  }
  hit <- intersect(fr, names(schema))
  if (length(hit) != 1L) {
    .stop(
      paste0(
        "cannot infer the source %s from the data's columns ",
        "(found: %s); pass `source=`"
      ),
      v$frame, if (length(hit) == 0L) "none" else .preview(hit)
    )
  }
  hit
}

#' Should this call run its diagnostic scans?
#'
#' Every diagnostic in the engine -- unknown source codes, dropped shares,
#' source units missing from the data -- costs a scan of the DATA, and on a
#' lazy backend that scan defeats the whole point of returning a query. So the
#' default is `"auto"`: diagnostics on eager inputs, where the data is already
#' in memory and the scan is cheap; off on arrow/dtplyr, where it is not.
#' `"on"` forces them on (worth it when a big job is worth
#' validating once), `"off"` off.
#' @noRd
.want_diagnostics <- function(diagnostics, backend) {
  switch(diagnostics,
    auto = !backend_is_lazy(backend),
    on   = TRUE,
    off  = FALSE,
    .stop("`diagnostics` must be \"auto\", \"on\" or \"off\"")
  )
}

#' rule "share" is only meaningful in recast_scale(), whose output key it
#' changes; the halves keep the standard contract
#' @noRd
.no_share <- function(rules, where) {
  if (any(vapply(rules, function(r) r$rule %in% .SHARE_RULES, logical(1)))) {
    .stop(paste0(
      "rule \"share\" is not supported by %s(); use ",
      "recast_scale() with a parent frame"
    ), where)
  }
}

# -----------------------------------------------------------------------------
# recast_scale()
# -----------------------------------------------------------------------------

#' Recast values from one resolution to another
#'
#' The central conversion verb: takes a table keyed by unit code at frame
#' `source` and returns one keyed at `target` -- a frame name of the same
#' [`NestedScale`], or ANOTHER NestedScale (whose atom layer is the target, matched on
#' shared atom keys). Handles both aggregation (fine to coarse) and
#' disaggregation (coarse to fine) with one rule per value column; frames that
#' cross-cut work too, because the route always goes through the atom layer.
#' A crosswalk registered with [`register_scale_map()`] short-circuits the
#' derivation.
#'
#' Columns of the data that are neither the key nor a value column are treated
#' as identifiers (panel columns -- a year, a technology) and preserved as
#' grouping columns, so panel data recasts correctly in one call. This is what
#' makes mixed pipelines across two dimensions work: a recast in one dimension
#' carries the other dimension's key through untouched. Columns named like the
#' scale's own frames are treated as unit attributes and dropped.
#'
#' @section Backends:
#' The data may be a `data.frame`, tibble, `data.table`, `dtplyr` lazy table,
#' or an arrow Dataset/Table/query. The result comes back in the input's class;
#' lazy inputs return the uncollected query unless `collect = TRUE`. Lazy
#' results contain the observed target units only -- the full-vocabulary
#' completion (and its `NA` rows) applies when the result is materialised.
#'
#' @param data The data to recast, in any supported backend, with a column
#'   named by `key` plus one or more numeric value columns; other columns are
#'   preserved as identifiers.
#' @param x The [`NestedScale`] the codes in `data` belong to.
#' @param source Frame name the codes belong to. `NULL` (default) is inferred:
#'   `key` when it is a frame name, else the single frame name appearing among
#'   the data's columns.
#' @param target Target frame name of `x`, or another (named) [`NestedScale`] -- then
#'   the target is that object's atom layer, matched on shared atom keys.
#' @param key Name of the code column in `data`. Defaults to `source` when that
#'   column exists, otherwise the scale's own key.
#' @param values Character vector of value columns to convert. Default: all
#'   numeric columns other than the key and the scale's frame columns. Numeric
#'   identifiers (e.g. `year`) must be excluded explicitly.
#' @param rule One of [`SCALE_RULES`] applied to every value column, or a
#'   named vector with one entry per column; `NULL` (default) looks each
#'   column up with [`get_scale_rule()`]. A column with neither an explicit
#'   rule nor a registry entry is an ERROR -- there is deliberately no
#'   fallback (a silently guessed rule is a silent unit error).
#' @param weight Weight column used by `sum` (splitting) and `weighted_mean`;
#'   scalar or named per column. `NULL` uses each column's registered weight,
#'   falling back to the object's default weight; when the object declares no
#'   weights at all, atoms weigh 1 (an equal split, warned about when it is
#'   material).
#' @param na_action What to do with atoms that have no code at `source` or `target`:
#'   `"drop"` (default, with a warning -- the affected source share is
#'   genuinely lost), `"error"`, or `"keep"` (retain an explicit `NA` row so
#'   totals conserve).
#' @param parent `rule = "share"` only: the frame defining the groups the
#'   shares are taken within. `NULL` (default) uses `target` when it differs from
#'   `source`, else the frame immediately above `source`.
#' @param collect For lazy inputs: materialise the result (`TRUE`) or return
#'   the uncollected query (default).
#' @param diagnostics Whether to run the checks that need a scan of the data:
#'   unknown source codes, dropped shares, and source units missing from the
#'   data. `"auto"` (default) runs them on eager inputs and skips them on
#'   arrow/dtplyr, where a scan would defeat the point of returning a query;
#'   `"on"` and `"off"` force the choice. Errors that do not depend on the
#'   data -- unknown frames, reserved column names, a missing rule -- are
#'   raised regardless.
#' @param missing_sources What to do when a target unit's sources are only
#'   partially present in the data. `"na"` (default) makes the result `NA` --
#'   a partial answer is not an answer. `"ignore"` aggregates whatever is
#'   there, which is faster but silently turns incomplete data into a
#'   plausible number, so it is opt-in.
#' @param batch,batch_by Process the job in chunks of at most `batch` distinct
#'   values of the identifier column `batch_by` (default: the first identifier
#'   column), binding the pieces. Chunking by an identifier partitions the
#'   aggregation groups exactly, so the numbers are unchanged; any other
#'   column is refused. Applies only when materialising, and turns off
#'   per-chunk diagnostics, which would otherwise report sources as missing
#'   merely because they fall in another chunk.
#' @param ... Passed to [`scale_map()`] (e.g. `year` for a calendar).
#'
#' @return The recast table in the input's class, with columns
#'   `c(to, identifiers, values)`.
#'
#' @details
#' `"sum"` splits each source value across its unit's atoms proportionally to
#' the weight before summing up, so totals are conserved. `"weighted_mean"`
#' weights by the atom weights; `"mean"` is the plain atom-count mean -- the
#' two differ exactly when atom weights differ. `"copy"` requires a constant
#' value per target unit; `"sd"` is aggregation-only.
#'
#' `"share"` inverts the output contract: the result stays keyed at `source`,
#' and each value becomes that unit's share of the total over its parent
#' group. `source` must nest within the parent. It cannot be combined with other
#' rules in one call, and `weight=` is ignored -- the observed values
#' themselves are the weights.
#'
#' @examples
#' s <- scale_example()
#'
#' # Extensive quantity, fine -> coarse: totals are preserved
#' d <- data.frame(
#'   unit = c("U1", "U2", "U3", "U4", "U5", "U6"),
#'   capacity = c(1, 2, 3, 4, 5, 6)
#' )
#' recast_scale(d, s, source = "unit", target = "sector", rule = "sum")
#'
#' # Coarse -> fine: split proportionally to size
#' y <- data.frame(sector = c("P", "S"), capacity = c(10, 20))
#' recast_scale(y, s,
#'   source = "sector", target = "class",
#'   rule = "sum", weight = "size"
#' )
#'
#' # Share within parent: result stays at the atoms, sums to 1 per sector
#' recast_scale(
#'   d, s,
#'   source = "unit", target = "sector",
#'   rule = "share",
#'   na_action = "keep"
#' )
#' @export
recast_scale <- function(data, x, source = NULL, target,
                         key = NULL,
                         values = NULL,
                         rule = NULL,
                         weight = NULL,
                         na_action = c("drop", "error", "keep"),
                         parent = NULL,
                         collect = NULL,
                         diagnostics = c("auto", "on", "off"),
                         missing_sources = c("na", "ignore"),
                         batch = NULL, batch_by = NULL,
                         ...) {
  na_action <- match.arg(na_action)
  diagnostics <- match.arg(diagnostics)
  missing_sources <- match.arg(missing_sources)
  .check_scale(x, "x")
  v <- scale_vocab(x)

  backend <- backend_of(data, "data")
  schema <- backend_schema(data)
  .check_ms_cols(schema)

  if (is.null(source)) source <- .infer_source(x, schema, key)
  .check_frame(x, source, "source")
  if (is.null(key)) key <- if (source %in% names(schema)) source else scale_key(x)
  if (!key %in% names(schema)) {
    .stop("the data has no column named `%s`; pass `key=`", key)
  }

  # -- cross-object route: `target` is another NestedScale ------------------------------
  if (S7::S7_inherits(target, NestedScale)) {
    if (any(rule %in% .SHARE_RULES)) {
      .stop(paste0(
        "rule \"share\" needs a parent frame of the same scale; ",
        "it cannot recast across objects"
      ))
    }
    g <- recast_to_atoms(data, x,
      source = source, key = key, values = values,
      rule = rule, weight = weight, collect = collect
    )
    return(recast_from_atoms(g, target,
      target = .atom_level(target),
      values = values, rule = rule,
      na_action = na_action, collect = collect
    ))
  }
  .check_frame(x, target, "target")

  frames_all <- S7::prop(x, "frames")
  values <- .values_for(schema, key, frames_all, values)
  id_cols <- setdiff(names(schema), c(key, values, frames_all))
  rules <- .rules_for(values, rule, weight,
    scope = .scale_scope(x), hint = .rule_hint(x)
  )

  # -- batching ---------------------------------------------------------------
  # Chunk by IDENTIFIER. That axis partitions the aggregation groups exactly,
  # so each chunk's result is final and combining is a plain rbind with no
  # arithmetic -- and, just as importantly, every group is wholly inside one
  # chunk, so the partial-source NA law still sees the same rows it would have
  # seen unbatched. Chunking by anything else would split groups and silently
  # change numbers.
  if (!is.null(batch)) {
    if (backend_is_lazy(backend) && !isTRUE(collect)) {
      .stop(paste0(
        "`batch` applies when materialising; this call returns a ",
        "query. Pass `collect = TRUE` to batch it."
      ))
    }
    if (length(id_cols) == 0L) {
      .stop(paste0(
        "`batch` needs an identifier column to chunk by, and this ",
        "data has none (every column is the key or a value)"
      ))
    }
    if (is.null(batch_by)) batch_by <- id_cols[[1L]]
    if (!batch_by %in% id_cols) {
      .stop(
        paste0(
          "`batch_by` must be an identifier column of the data ",
          "(one of: %s); `%s` is not one, and chunking on it would ",
          "split aggregation groups and change the numbers"
        ),
        paste(id_cols, collapse = ", "), batch_by
      )
    }
    return(.recast_batched(
      data, backend, batch, batch_by,
      args = list(
        x = x, source = source, target = target, key = key, values = values,
        rule = rule, weight = weight, na_action = na_action,
        parent = parent, diagnostics = diagnostics,
        missing_sources = missing_sources, ...
      )
    ))
  }

  leaves <- S7::prop(x, "leaftable")
  do_diag <- .want_diagnostics(diagnostics, backend)

  # Which source codes does the data actually carry? One projected DISTINCT
  # over the key column -- cheap and small, but still a scan of the data, so
  # it is a diagnostic and obeys `diagnostics=`.
  src_keys <- NULL
  if (do_diag) {
    src_keys <- backend_pull(
      dplyr::distinct(dplyr::select(
        backend_lazy(data, backend),
        dplyr::all_of(key)
      ))
    )[[key]]
    src_keys <- unique(stats::na.omit(as.character(src_keys)))
    known <- unique(stats::na.omit(as.character(leaves[[source]])))
    unknown <- setdiff(src_keys, known)
    if (length(unknown) > 0L) {
      .warn(
        paste0(
          "%d code(s) in the `%s` column are not present at %s `%s` ",
          "and were dropped: %s"
        ),
        length(unknown), key, v$frame, source, .preview(unknown)
      )
    }
    if (length(intersect(src_keys, known)) == 0L) {
      .stop(paste0(
        "no rows matched %s `%s`; check `source=` and the `%s` ",
        "column"
      ), v$frame, source, key)
    }
  }

  # -- share within parent: result keyed at `source`, one rule for all ---------
  is_share <- vapply(rules, function(r) r$rule %in% .SHARE_RULES, logical(1))
  if (any(is_share)) {
    if (!all(is_share)) {
      .stop(paste0(
        "rule \"share\" changes the output key to `source` and ",
        "cannot be mixed with other rules in one call; recast the ",
        "columns separately"
      ))
    }
    if (!is.null(weight)) {
      .warn("`weight` is ignored by rule \"share\": the values are the weights")
    }
    return(.recast_share(
      data, backend, x, source, target, key, values, id_cols,
      parent, na_action, collect
    ))
  }
  if (!is.null(parent)) {
    .stop("`parent` applies to rule \"share\" only")
  }

  if (na_action == "error") {
    n_bad <- sum(is.na(leaves[[source]]) | is.na(leaves[[target]]))
    if (n_bad > 0L) {
      .stop(
        paste0(
          "%d atom(s) have no code at %s `%s` or `%s`; use ",
          "na_action = \"drop\" or \"keep\""
        ),
        n_bad, v$frame, source, target
      )
    }
  }

  # One crosswalk per distinct weight (per-column weights may differ)
  wt_of <- vapply(rules, function(r) r$weight %||% "", character(1))
  no_declared <- length(scale_weights(x)) == 0L
  need_split <- vapply(rules, function(r) {
    r$rule %in% c("sum", "weighted_mean")
  }, logical(1))
  if (no_declared && is.null(weight) && any(need_split) &&
    scale_rank(x, target) > scale_rank(x, source)) {
    .warn(paste0(
      "no weight column declared; splitting `%s` equally across ",
      "the atoms of each `%s`. Declare a weight for a ",
      "size-proportional split."
    ), target, source)
  }

  # One crosswalk per distinct weight, folded into a single table: the
  # weight-independent columns are shared and each weight contributes its own
  # split factor. That turns what used to be one pass over the data per weight
  # (plus a join of the large intermediates) into one pass, always.
  wts <- unique(wt_of)
  maps <- lapply(wts, function(wt) {
    scale_map(x, source, target, weight = if (nzchar(wt)) wt else NULL, ...)
  })
  names(maps) <- wts
  map_by <- setdiff(
    names(maps[[1L]]),
    c(source, target, "n_from", "n_overlap", "w", "w_from")
  )

  # Coverage is a property of the atoms, so it is the same in every one of
  # these crosswalks; decide it once and apply it to all of them.
  uncovered <- is.na(maps[[1L]][[target]])
  uncovered_any <- any(uncovered)
  if (uncovered_any && na_action == "drop") {
    # The warning is diagnostic; DROPPING the uncovered rows is semantics and
    # happens either way.
    if (do_diag) {
      affected <- intersect(unique(maps[[1L]][[source]][uncovered]), src_keys)
      if (length(affected) > 0L) {
        .warn(
          paste0(
            "%d atom(s) have no code at %s `%s`; the share of %d ",
            "source unit(s) falling in them is dropped (%s). Use ",
            "na_action = \"keep\" to conserve totals."
          ),
          sum(maps[[1L]]$n_overlap[uncovered]), v$frame, target,
          length(affected), .preview(affected)
        )
      }
    }
    maps <- lapply(maps, function(m) m[!uncovered, , drop = FALSE])
  }
  retained_from <- unique(maps[[1L]][[source]])

  # Residual protection applies only when DISAGGREGATING. Aggregating INTO a
  # coarse residual is legitimate -- it collects its own fine parts -- so the
  # guard must not fire in that direction.
  res_targets <- if (scale_rank(x, target) > scale_rank(x, source)) {
    scale_residuals(x, target)
  } else {
    character()
  }
  wide <- .widen_maps(maps, source, target, key, wt_of, res_targets)
  res <- .recast_pipeline(data, backend, wide$jmap, key, values, rules,
    id_cols, map_by, missing_sources, wide$sfx,
    unit = v$unit,
    check_copy = !(backend_is_lazy(backend) && !isTRUE(collect))
  )

  if (!identical(key, target)) {
    res <- dplyr::rename(res, !!rlang::sym(target) := !!rlang::sym(key))
  }

  # LAZY RETURN. Nothing below this line may run for a lazy caller: everything
  # after it either scans the data for a diagnostic or materialises the
  # result, and a caller asking for a query wants neither.
  if (backend_is_lazy(backend) && !isTRUE(collect)) {
    return(dplyr::select(res, dplyr::all_of(c(target, id_cols, values))))
  }

  # Missing-source diagnostic: crosswalk units absent from an identifier
  # group. This is the most expensive scan in the engine -- DISTINCT over
  # (identifiers, key) approaches the cardinality of the data itself -- and it
  # only produces a warning, so it is the first thing `diagnostics=` turns off.
  if (do_diag) {
    all_missing <- if (length(id_cols) > 0L) {
      keysets <- backend_pull(dplyr::distinct(
        dplyr::select(
          backend_lazy(data, backend),
          dplyr::all_of(c(id_cols, key))
        )
      ))
      gk <- do.call(paste, c(lapply(keysets[id_cols], as.character),
        sep = "\r"
      ))
      unique(unlist(lapply(
        split(keysets[[key]], gk),
        function(kk) setdiff(retained_from, as.character(kk))
      )))
    } else {
      setdiff(retained_from, src_keys)
    }
    if (length(all_missing) > 0L) {
      .warn(
        paste0(
          "%d source unit(s) present in the scale but missing from ",
          "the data (e.g. %s); produced NAs"
        ),
        length(all_missing), .preview(all_missing)
      )
    }
  }

  idc <- if (length(id_cols) > 0L) {
    backend_pull(dplyr::distinct(dplyr::select(
      backend_lazy(data, backend),
      dplyr::all_of(id_cols)
    )))
  } else {
    data.frame()
  }

  res <- as.data.frame(dplyr::collect(res))
  target_keys <- S7::prop(x, "members")[[target]]
  keep_na_row <- na_action == "keep" && uncovered_any
  out_keys <- c(target_keys, if (keep_na_row) NA_character_)
  out <- .recast_complete(res, idc, out_keys, target, id_cols, values)
  backend_restore(out, backend, collect = collect)
}

#' Run a recast in chunks of identifier values and bind the results
#'
#' Diagnostics are forced OFF inside chunks, and not to save time: a source
#' unit absent from one chunk is usually present in another, so per-chunk
#' diagnostics would report missing sources that are not missing from the
#' data. The result is bound with [`backend_bind_rows()`].
#' @noRd
.recast_batched <- function(data, backend, batch, batch_by, args) {
  vals <- backend_pull(dplyr::distinct(dplyr::select(
    backend_lazy(data, backend), dplyr::all_of(batch_by)
  )))[[batch_by]]
  vals <- unique(vals)
  chunks <- .backend_chunks(vals, batch)

  bsym <- rlang::sym(batch_by)
  args$diagnostics <- "off"
  args$collect <- TRUE

  parts <- lapply(chunks, function(ch) {
    d <- dplyr::filter(backend_lazy(data, backend), !!bsym %in% ch)
    do.call(recast_scale, c(list(data = d), args))
  })
  out <- backend_bind_rows(parts)
  backend_restore(out, backend, collect = TRUE)
}

#' Registry scope for a scale: its dimension, not its name
#' @noRd
.scale_scope <- function(x) {
  v <- scale_vocab(x)
  if (identical(v$object, "NestedScale")) NULL else tolower(v$object)
}

#' Resolve the parent frame for rule "share"
#'
#' Explicit `parent=` wins, then `target` when it differs from `source`, then the
#' frame immediately above `source` (frames are ordered coarsest first).
#' @noRd
.share_parent <- function(x, source, target, parent) {
  if (!is.null(parent)) {
    .check_frame(x, parent, "parent")
    if (!identical(target, source) && !identical(target, parent)) {
      .stop(paste0(
        "conflicting parents: `target = \"%s\"` vs `parent = \"%s\"`; ",
        "for rule \"share\" pass the parent once"
      ), target, parent)
    }
  } else if (!identical(target, source)) {
    parent <- target
  } else {
    fr <- S7::prop(x, "frames")
    i <- match(source, fr)
    if (is.na(i) || i <= 1L) {
      .stop("`%s` has no coarser frame; pass `parent=`", source)
    }
    parent <- fr[[i - 1L]]
  }
  if (scale_rank(x, parent) >= scale_rank(x, source)) {
    .stop(paste0(
      "rule \"share\": parent `%s` must be coarser than ",
      "`source = \"%s\"`"
    ), parent, source)
  }
  parent
}

#' rule = "share": each source unit's value over its parent-group total.
#' Output is keyed at `source` -- the one rule that does not change the key.
#' @noRd
.recast_share <- function(data, backend, x, source, target, key, values, id_cols,
                          parent, na_action, collect) {
  parent <- .share_parent(x, source, target, parent)
  v <- scale_vocab(x)

  map <- scale_map(x, source, parent)
  mem <- unique(map[, c(source, parent)])

  # shares within a parent are only well-defined when `source` nests in it
  n_par <- table(mem[[source]][!is.na(mem[[parent]])])
  split_codes <- names(n_par)[n_par > 1L]
  if (length(split_codes) > 0L) {
    .stop(
      paste0(
        "rule \"share\": %d unit(s) of `%s` straddle more than one ",
        "`%s` (%s); `source` must nest within the parent"
      ),
      length(split_codes), source, parent, .preview(split_codes)
    )
  }

  orphan <- is.na(mem[[parent]])
  if (any(orphan)) {
    if (na_action == "error") {
      .stop(
        paste0(
          "%d unit(s) of `%s` have no code at parent `%s`; use ",
          "na_action = \"drop\" or \"keep\""
        ),
        sum(orphan), source, parent
      )
    }
    if (na_action == "drop") {
      .warn(
        paste0(
          "%d unit(s) of `%s` have no code at parent `%s` and get ",
          "NA shares (%s). Use na_action = \"keep\" to treat them ",
          "as one group."
        ),
        sum(orphan), source, parent, .preview(mem[[source]][orphan])
      )
      mem <- mem[!orphan, , drop = FALSE]
    }
  }

  jmem <- mem
  names(jmem) <- c(key, ".ms_parent")

  xq <- dplyr::select(
    backend_lazy(data, backend),
    dplyr::all_of(c(id_cols, key, values))
  )
  joined <- dplyr::inner_join(xq, jmem, by = key)

  tot_nms <- paste0(".ms_tot_", seq_along(values))
  tot_exprs <- lapply(values, function(vv) rlang::expr(sum(!!rlang::sym(vv))))
  names(tot_exprs) <- tot_nms
  tot <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(id_cols, ".ms_parent")))) |>
    dplyr::summarise(!!!tot_exprs, .groups = "drop")

  share_exprs <- lapply(seq_along(values), function(i) {
    vv <- rlang::sym(values[[i]])
    tt <- rlang::sym(tot_nms[[i]])
    rlang::expr(dplyr::if_else(!!tt != 0, !!vv / !!tt, NA_real_))
  })
  names(share_exprs) <- values

  res <- joined |>
    dplyr::left_join(tot, by = c(id_cols, ".ms_parent"), na_matches = "na") |>
    dplyr::mutate(!!!share_exprs) |>
    dplyr::select(dplyr::all_of(c(key, id_cols, values)))
  if (!identical(key, source)) {
    res <- dplyr::rename(res, !!rlang::sym(source) := !!rlang::sym(key))
  }

  if (backend_is_lazy(backend) && !isTRUE(collect)) {
    return(dplyr::select(res, dplyr::all_of(c(source, id_cols, values))))
  }

  idc <- if (length(id_cols) > 0L) {
    backend_pull(dplyr::distinct(dplyr::select(
      backend_lazy(data, backend),
      dplyr::all_of(id_cols)
    )))
  } else {
    data.frame()
  }
  res <- as.data.frame(dplyr::collect(res))
  out_keys <- S7::prop(x, "members")[[source]]
  out <- .recast_complete(res, idc, out_keys, source, id_cols, values)
  backend_restore(out, backend, collect = collect)
}

#' Fold the per-weight crosswalks into ONE
#'
#' `source`, `target`, `n_from` and `n_overlap` do not depend on the weight -- they
#' come from grouping the atoms, which the weight never touches -- so the
#' crosswalks for several weights differ only in `w`/`w_from`. Carrying each
#' weight's split factor as its own column therefore lets one join and one
#' summarise do what used to take a full pass over the data per weight, plus a
#' join of the large intermediates.
#' @noRd
.widen_maps <- function(maps, source, target, key, wt_of,
                        residual_targets = character()) {
  wts <- names(maps)
  base <- maps[[1L]]
  shared <- setdiff(names(base), c("w", "w_from"))
  for (m in maps[-1L]) {
    if (!identical(m[shared], base[shared])) {
      .stop(paste0(
        "the crosswalks for different weights disagree on their ",
        "structure; this should be impossible for derived maps, ",
        "so a registered map is likely malformed"
      ))
    }
  }

  jmap <- base[shared]
  names(jmap)[names(jmap) == source] <- key
  names(jmap)[names(jmap) == target] <- ".ms_to"
  names(jmap)[names(jmap) == "n_from"] <- ".ms_n_from"
  names(jmap)[names(jmap) == "n_overlap"] <- ".ms_n_overlap"

  # A declared residual is not a destination for allocation, so the split
  # shares are taken over the ALLOCABLE targets only. Zeroing the residual's
  # share alone would not do: the rest would then sum to less than one and the
  # parent's total would quietly go missing. Renormalising is what conserves it.
  is_res <- !is.na(jmap$.ms_to) & jmap$.ms_to %in% residual_targets
  grp <- jmap[[key]]

  sfx <- stats::setNames(rep("", length(wt_of)), names(wt_of))
  for (i in seq_along(wts)) {
    m <- maps[[i]]
    sx <- if (length(wts) == 1L) "" else paste0("_", i)
    jmap[[paste0(".ms_w", sx)]] <- m$w

    if (any(is_res)) {
      w_ok <- ifelse(is_res, 0, m$w)
      n_ok <- ifelse(is_res, 0L, jmap$.ms_n_overlap)
      w_tot <- as.numeric(tapply(w_ok, grp, sum)[as.character(grp)])
      n_tot <- as.numeric(tapply(n_ok, grp, sum)[as.character(grp)])
      dead <- w_tot <= 0 & n_tot <= 0
      if (any(dead)) {
        .stop(
          paste0(
            "every target of `%s` is a declared residual, so a ",
            "figure at `%s` has nowhere allocable to go: %s"
          ),
          source, source, .preview(unique(grp[dead]))
        )
      }
      f <- ifelse(is_res, 0, ifelse(w_tot > 0, w_ok / w_tot, n_ok / n_tot))
    } else {
      f <- ifelse(m$w_from > 0, m$w / m$w_from,
        jmap$.ms_n_overlap / jmap$.ms_n_from
      )
    }
    jmap[[paste0(".ms_f", sx)]] <- f
    sfx[wt_of == wts[[i]]] <- sx
  }
  list(jmap = jmap, sfx = sfx)
}

#' The crosswalk-join pipeline for one weight's value columns
#'
#' `map_by` names extra identifier columns the crosswalk carries (a dimension
#' whose atom layer is generated, e.g. time's `year`). Where such a column is
#' also an identifier of the data, the identifier grid JOINS the crosswalk on
#' it instead of crossing with it -- crossing would duplicate the column.
#' @noRd
.recast_pipeline <- function(data, backend, jmap, key, values, rules,
                             id_cols, map_by = character(),
                             missing_sources = "na", sfx = NULL,
                             unit = "unit", check_copy = TRUE) {
  shared_ids <- intersect(map_by, id_cols)

  # THE JOIN. The crosswalk is the build side -- |map| rows, which is what the
  # whole route-through-the-atoms design exists to achieve. Previously this
  # was a right join against `cross_join(identifier combos, crosswalk)`, an
  # in-memory frame the size of the source data; that grid existed only to
  # inject NA rows for absent (identifier, source) pairs, and the counting
  # repair below reproduces its effect from the aggregate instead.
  xq <- dplyr::select(
    backend_lazy(data, backend),
    dplyr::all_of(c(id_cols, key, values))
  )
  joined <- dplyr::inner_join(xq, jmap, by = c(shared_ids, key))

  grp_cols <- c(id_cols, ".ms_to")
  copy_cols <- values[vapply(rules, function(r) r$rule == "copy", logical(1))]

  # The copy-constancy guard rides this same summarise instead of the separate
  # eager grouped aggregate it used to run before the lazy return. Its min and
  # max must be listed BEFORE the value expressions: summarise() evaluates in
  # order and later expressions see earlier results, so `max(v)` placed after
  # `v = mean(v)` would read the aggregated scalar and never detect anything.
  exprs <- list()
  for (v in copy_cols) {
    exprs[[paste0(".ms_mx_", v)]] <- rlang::expr(max(!!rlang::sym(v)))
    exprs[[paste0(".ms_mn_", v)]] <- rlang::expr(min(!!rlang::sym(v)))
  }
  exprs <- c(exprs, .rule_exprs(values, rules, sfx))
  if (identical(missing_sources, "na")) {
    # How many distinct sources did this group actually see? Rides the
    # summarise that was happening anyway -- no extra pass over the data.
    exprs[[".ms_nsrc"]] <- rlang::expr(
      dplyr::n_distinct(!!rlang::sym(key))
    )
  }

  res <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grp_cols))) |>
    dplyr::summarise(!!!exprs, .groups = "drop")

  # THE REPAIR. A group that saw fewer distinct sources than the crosswalk
  # lists for it was only partially supplied, and its value is NA -- exactly
  # what the injected NA rows used to produce. `expected` is scale-side and
  # tiny: one row per (extra identifier, target).
  if (identical(missing_sources, "na")) {
    expected <- jmap |>
      dplyr::distinct(dplyr::across(
        dplyr::all_of(c(shared_ids, ".ms_to", key))
      )) |>
      dplyr::count(dplyr::across(dplyr::all_of(c(shared_ids, ".ms_to"))),
        name = ".ms_nexp"
      )
    res <- res |>
      dplyr::left_join(expected,
        by = c(shared_ids, ".ms_to"),
        na_matches = "na"
      ) |>
      dplyr::mutate(dplyr::across(
        dplyr::all_of(values),
        ~ dplyr::if_else(.ms_nsrc < .ms_nexp, NA_real_, .x)
      ))
  }

  # The constancy guard collects the aggregate; a caller that wants a lazy
  # query passes check_copy = FALSE, as for the other diagnostics.
  if (check_copy && length(copy_cols) > 0L) {
    .check_copy_result(res, copy_cols, backend, unit)
  }

  drop_cols <- c(
    if (identical(missing_sources, "na")) {
      c(".ms_nsrc", ".ms_nexp")
    },
    paste0(".ms_mx_", copy_cols),
    paste0(".ms_mn_", copy_cols)
  )
  res |>
    dplyr::select(-dplyr::any_of(drop_cols)) |>
    dplyr::rename(!!rlang::sym(key) := !!rlang::sym(".ms_to"))
}

# -----------------------------------------------------------------------------
# recast_crosswalk()
# -----------------------------------------------------------------------------

#' Recast values through a given crosswalk
#'
#' The engine behind [`recast_scale()`], for a crosswalk built elsewhere: by a
#' dimension package whose conversion cannot be read off one scale's
#' leaftable, such as timescales mapping one calendar onto another through a
#' datetime grid. The crosswalk says how much of each source code falls in
#' each target code; the rules then aggregate exactly as in `recast_scale()`,
#' on any supported backend.
#'
#' The crosswalk is a data frame with one row per (source, target) pair:
#'
#' * the source and target codes, in the columns named by `source` and `target`;
#' * `n_from`, the number of atoms (grid points) in the source code, and
#'   `n_overlap`, the number of them that fall in the target;
#' * optionally `w`, the weight of the pair for `"weighted_mean"` -- by default
#'   `n_overlap`;
#' * optionally `w_from`, the source's total weight. With it, `"sum"` splits a
#'   source across its targets by `w / w_from`; without it, by
#'   `n_overlap / n_from`, an equal split over atoms;
#' * any columns named in `by`.
#'
#' A target whose sources are only partly present in the data, per identifier
#' combination, comes back `NA` unless `missing_sources = "ignore"`.
#'
#' @param data The data, in any supported backend, with a code column and one
#'   or more numeric value columns.
#' @param map The crosswalk, a `data.frame`.
#' @param source,target Names of the source and target code columns of `map`.
#' @param key Name of the code column of `data`. Defaults to `source`.
#' @param values Value columns. Default: every numeric column that is neither
#'   `key` nor in `ids`.
#' @param rule One of [`SCALE_RULES`] other than the share rules, for every
#'   value column, or a named vector with one entry per column. `NULL` looks
#'   each column up with [`get_scale_rule()`].
#' @param ids Identifier columns, preserved as groups. Default: every column
#'   that is neither `key` nor a value column. Other columns are dropped.
#' @param by Columns of `map` matched against the identically named
#'   identifier columns of `data`, for a crosswalk that differs between
#'   identifier values (a calendar crosswalk per year, say).
#' @param targets Optional full target vocabulary. A materialised result is
#'   completed to every target per identifier combination, in this order, with
#'   `NA` where nothing landed; an `NA` entry adds an explicit `NA` row.
#' @param missing_sources `"na"` (default) or `"ignore"`; see
#'   [`recast_scale()`].
#' @param unit The word for a target code in error messages.
#' @param collect For lazy inputs: materialise (`TRUE`) or return the query.
#'
#' @return The recast data in its own class, with columns
#'   `c(to, ids, values)`. Lazy in, lazy out.
#'
#' @examples
#' # Two months onto one quarter, with the months' day counts as atoms
#' map <- data.frame(
#'   month = c("m01", "m02"), quarter = "Q1",
#'   n_from = c(31, 28), n_overlap = c(31, 28)
#' )
#' d <- data.frame(
#'   month = c("m01", "m02"), energy = c(310, 280),
#'   price = c(10, 20)
#' )
#' recast_crosswalk(d, map,
#'   source = "month", target = "quarter",
#'   rule = c(energy = "sum", price = "weighted_mean")
#' )
#' @export
recast_crosswalk <- function(data, map, source, target, key = source,
                             values = NULL, rule = NULL, ids = NULL,
                             by = character(), targets = NULL,
                             missing_sources = c("na", "ignore"),
                             unit = "unit", collect = NULL) {
  missing_sources <- match.arg(missing_sources)
  backend <- backend_of(data, "data")
  schema <- backend_schema(data)
  .check_ms_cols(schema)
  if (!is.data.frame(map)) .stop("`map` must be a data.frame")
  need <- c(source, target, "n_from", "n_overlap", by)
  absent <- setdiff(need, names(map))
  if (length(absent) > 0L) {
    .stop("`map` is missing column(s): %s", .preview(absent))
  }
  if (!key %in% names(schema)) {
    .stop("the data has no column named `%s`; pass `key=`", key)
  }

  values <- .values_for(schema, key, ids %||% character(), values)
  if (is.null(ids)) ids <- setdiff(names(schema), c(key, values))
  bad_by <- setdiff(by, ids)
  if (length(bad_by) > 0L) {
    .stop(
      "`by` column(s) are not identifier columns of the data: %s",
      .preview(bad_by)
    )
  }
  rules <- .rules_for(values, rule)
  .no_share(rules, "recast_crosswalk")

  map <- as.data.frame(map)
  jmap <- map[c(source, target, "n_from", "n_overlap", by)]
  names(jmap)[1:4] <- c(key, ".ms_to", ".ms_n_from", ".ms_n_overlap")
  # Weighted split needs both `w` and `w_from`; `[[` because `map$w` would
  # partial-match `w_from` when `w` is absent.
  has_w <- all(c("w", "w_from") %in% names(map))
  jmap$.ms_w <- if ("w" %in% names(map)) map[["w"]] else map$n_overlap
  jmap$.ms_f <- if (has_w) {
    ifelse(map[["w_from"]] > 0, map[["w"]] / map[["w_from"]],
           map$n_overlap / map$n_from)
  } else {
    map$n_overlap / map$n_from
  }

  res <- .recast_pipeline(data, backend, jmap, key, values, rules, ids,
    map_by = by, missing_sources = missing_sources,
    unit = unit,
    check_copy = !(backend_is_lazy(backend) && !isTRUE(collect))
  )
  if (!identical(key, target)) {
    res <- dplyr::rename(res, !!rlang::sym(target) := !!rlang::sym(key))
  }

  if (backend_is_lazy(backend) && !isTRUE(collect)) {
    return(dplyr::select(res, dplyr::all_of(c(target, ids, values))))
  }
  res <- as.data.frame(dplyr::collect(res))
  out <- if (is.null(targets)) {
    res[, c(target, ids, values), drop = FALSE]
  } else {
    idc <- if (length(ids) > 0L) {
      backend_pull(dplyr::distinct(dplyr::select(
        backend_lazy(data, backend),
        dplyr::all_of(ids)
      )))
    } else {
      data.frame()
    }
    .recast_complete(res, idc, targets, target, ids, values)
  }
  backend_restore(out, backend, collect = collect)
}

# -----------------------------------------------------------------------------
# The route halves
# -----------------------------------------------------------------------------

#' Recast unit data down to the atom layer, and back
#'
#' The two public halves of the `from -> atoms -> to` route:
#' `recast_to_atoms()` projects unit-keyed data DOWN to the atom layer (one
#' row per atom), and `recast_from_atoms()` aggregates atom-keyed data UP into
#' a frame's units. Their composition is [`recast_scale()`], and because the
#' atom rows are keyed by the atom IDs,
#' `recast_from_atoms(recast_to_atoms(data, a), b, target)` recasts across two
#' scales that share atom keys.
#'
#' Going down, extensive columns (rule `"sum"`) are split across a unit's
#' atoms proportionally to the chosen weight so totals conserve; intensive
#' columns are repeated. A `weight` column is attached by default so the
#' return trip's `"weighted_mean"` reproduces the source weighting exactly.
#'
#' @param data The data: for `recast_to_atoms()` keyed by unit code at frame
#'   `source`; for `recast_from_atoms()` keyed by atom IDs.
#' @param x The [`NestedScale`] the data is keyed in, or aggregated into.
#' @param source `to_atoms` only: frame name the codes belong to. `NULL`
#'   (default) is inferred as in [`recast_scale()`].
#' @param target `from_atoms` only: target frame name.
#' @param key The key column; defaults as in [`recast_scale()`].
#' @param values,rule As in [`recast_scale()`].
#' @param weight `to_atoms`: a declared weight column of `x`. `from_atoms`:
#'   the name of a column of `data` to weight by, so the weight may vary by
#'   identifier. `NULL` uses a `weight` column of the data if present, else
#'   the scale's declared weight.
#' @param attach_weight `to_atoms` only: attach the `weight` column (default
#'   `TRUE`).
#' @param na_rm `from_atoms` only: read an `NA` value as "this member says
#'   nothing" rather than as an unknown that makes the whole group `NA`.
#' @param na_action `from_atoms` only: what to do with atoms that have no code
#'   at `target`.
#' @param collect For lazy inputs: materialise (`TRUE`) or return the query.
#'
#' @return `recast_to_atoms()`: one row per (atom x identifier combination).
#'   `recast_from_atoms()`: one row per (unit x identifier combination). Both
#'   in the input's class; lazy in, lazy out.
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(sector = c("P", "S"), capacity = c(10, 20))
#' atoms <- recast_to_atoms(d, s,
#'   source = "sector", rule = "sum",
#'   weight = "size"
#' )
#' head(atoms)
#' recast_from_atoms(
#'   atoms, s,
#'   target = "class",
#'   rule = "sum",
#'   na_action = "keep"
#' )
#' @export
recast_to_atoms <- function(data, x, source = NULL, key = NULL, values = NULL,
                            rule = NULL, weight = NULL, attach_weight = TRUE,
                            collect = NULL) {
  .check_scale(x, "x")
  backend <- backend_of(data, "data")
  schema <- backend_schema(data)
  .check_ms_cols(schema)

  if (is.null(source)) source <- .infer_source(x, schema, key)
  .check_frame(x, source, "source")
  if (is.null(key)) key <- if (source %in% names(schema)) source else scale_key(x)
  if (!key %in% names(schema)) {
    .stop("the data has no column named `%s`; pass `key=`", key)
  }

  frames_all <- S7::prop(x, "frames")
  values <- .values_for(schema, key, frames_all, values)
  id_cols <- setdiff(names(schema), c(key, values, frames_all))
  rules <- .rules_for(values, rule, weight,
    scope = .scale_scope(x),
    hint = .rule_hint(x)
  )
  .no_share(rules, "recast_to_atoms")

  akey <- scale_key(x)
  leaves <- S7::prop(x, "leaftable")
  wcol <- .map_weight(x, weight)

  atoms <- data.frame(
    .from = as.character(leaves[[source]]),
    .atom = as.character(leaves[[akey]]),
    .w = if (is.null(wcol)) 1 else as.numeric(leaves[[wcol]]),
    stringsAsFactors = FALSE
  )
  atoms <- atoms[!is.na(atoms$.from), , drop = FALSE]
  atoms$.w[is.na(atoms$.w)] <- 0
  tot <- stats::aggregate(list(.w_from = atoms$.w),
    by = list(.from = atoms$.from), FUN = sum
  )
  atoms <- merge(atoms, tot, by = ".from", all.x = TRUE)
  n <- stats::aggregate(list(.n = rep(1L, nrow(atoms))),
    by = list(.from = atoms$.from), FUN = sum
  )
  atoms <- merge(atoms, n, by = ".from", all.x = TRUE)
  atoms$.f <- ifelse(atoms$.w_from > 0, atoms$.w / atoms$.w_from,
    1 / atoms$.n
  )

  jmap <- atoms[, c(".from", ".atom", ".w", ".f")]
  names(jmap) <- c(key, akey, "weight", ".ms_f")
  if (identical(key, akey)) names(jmap)[1L] <- ".ms_src"

  down_exprs <- lapply(values, function(vv) {
    sym <- rlang::sym(vv)
    if (rules[[vv]]$rule == "sum") {
      rlang::expr(!!sym * !!rlang::sym(".ms_f"))
    } else {
      rlang::expr(!!sym)
    }
  })
  names(down_exprs) <- values

  xq <- dplyr::select(
    backend_lazy(data, backend),
    dplyr::all_of(c(id_cols, key, values))
  )
  out <- dplyr::inner_join(
    xq, jmap,
    by = stats::setNames(names(jmap)[1L], key)
  ) |>
    dplyr::mutate(!!!down_exprs) |>
    dplyr::select(dplyr::all_of(
      c(akey, id_cols, values, if (attach_weight) "weight")
    ))

  if (backend_is_lazy(backend) && !isTRUE(collect)) {
    return(out)
  }
  backend_restore(out, backend, collect = collect)
}

#' @rdname recast_to_atoms
#' @export
recast_from_atoms <- function(data, x, target, key = NULL, values = NULL,
                              rule = NULL, weight = NULL, na_rm = FALSE,
                              na_action = c("drop", "error", "keep"),
                              collect = NULL) {
  na_action <- match.arg(na_action)
  .check_scale(x, "x")
  .check_frame(x, target, "target")
  backend <- backend_of(data, "data")
  schema <- backend_schema(data)
  .check_ms_cols(schema)

  akey <- scale_key(x)
  if (is.null(key)) key <- akey
  if (!key %in% names(schema)) {
    .stop("the data has no column named `%s`; pass `key=`", key)
  }

  # The weight column: a named column of the data (so it can vary by
  # identifier), else an attached `weight`. Resolved BEFORE the identifier
  # split, so the column carrying the weights is never mistaken for a panel
  # column.
  wt_col <- weight %||% (if ("weight" %in% names(schema)) "weight" else NULL)
  if (!is.null(wt_col) && !wt_col %in% names(schema)) {
    .stop("`weight` column `%s` is not in the data", wt_col)
  }

  frames_all <- S7::prop(x, "frames")
  values <- .values_for(schema, key, c(frames_all, "weight", wt_col), values)
  id_cols <- setdiff(
    names(schema),
    c(key, values, frames_all, "weight", wt_col)
  )
  rules <- .rules_for(values, rule,
    weight = NULL, scope = .scale_scope(x),
    hint = .rule_hint(x)
  )
  .no_share(rules, "recast_from_atoms")

  leaves <- S7::prop(x, "leaftable")
  jmem <- data.frame(
    k = as.character(leaves[[akey]]),
    t = as.character(leaves[[target]]),
    stringsAsFactors = FALSE
  )
  uncovered_any <- any(is.na(jmem$t))
  if (uncovered_any) {
    if (na_action == "error") {
      .stop(
        "%d atom(s) have no code at `%s`; use na_action = \"drop\" or \"keep\"",
        sum(is.na(jmem$t)), target
      )
    }
    if (na_action == "drop") {
      .warn(
        "%d atom(s) have no code at `%s` and were dropped",
        sum(is.na(jmem$t)), target
      )
      jmem <- jmem[!is.na(jmem$t), , drop = FALSE]
    }
  }
  names(jmem) <- c(key, ".ms_to")

  xq <- dplyr::select(
    backend_lazy(data, backend),
    dplyr::all_of(c(
      id_cols, key, values,
      if (!is.null(wt_col)) wt_col
    ))
  )
  if (is.null(wt_col)) {
    wcol <- .map_weight(x, NULL)
    aw <- data.frame(
      k = as.character(leaves[[akey]]),
      .ms_w = if (is.null(wcol)) 1 else as.numeric(leaves[[wcol]]),
      stringsAsFactors = FALSE
    )
    names(aw)[1L] <- key
    xq <- dplyr::left_join(xq, aw, by = key)
    wt_col <- ".ms_w"
  }

  joined <- dplyr::inner_join(xq, jmem, by = key)
  grp_cols <- c(id_cols, ".ms_to")
  copy_cols <- values[vapply(rules, function(r) r$rule == "copy", logical(1))]

  # Same arrangement as `.recast_pipeline()`: the constancy guard's min and
  # max ride the summarise, listed FIRST so they read the raw column rather
  # than the aggregate that replaces it.
  exprs <- list()
  for (v in copy_cols) {
    exprs[[paste0(".ms_mx_", v)]] <- rlang::expr(max(!!rlang::sym(v)))
    exprs[[paste0(".ms_mn_", v)]] <- rlang::expr(min(!!rlang::sym(v)))
  }
  exprs <- c(exprs, .group_exprs(values, rules, wt_col, na_rm))

  res <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grp_cols))) |>
    dplyr::summarise(!!!exprs, .groups = "drop")
  if (length(copy_cols) > 0L) {
    if (!(backend_is_lazy(backend) && !isTRUE(collect))) {
      .check_copy_result(res, copy_cols, backend, scale_vocab(x)$unit)
    }
    res <- dplyr::select(res, -dplyr::any_of(
      c(paste0(".ms_mx_", copy_cols), paste0(".ms_mn_", copy_cols))
    ))
  }
  res <- dplyr::rename(res, !!rlang::sym(target) := !!rlang::sym(".ms_to"))

  if (backend_is_lazy(backend) && !isTRUE(collect)) {
    return(dplyr::select(res, dplyr::all_of(c(target, id_cols, values))))
  }

  idc <- if (length(id_cols) > 0L) {
    backend_pull(dplyr::distinct(dplyr::select(
      backend_lazy(data, backend),
      dplyr::all_of(id_cols)
    )))
  } else {
    data.frame()
  }
  res <- as.data.frame(dplyr::collect(res))
  out_keys <- c(
    S7::prop(x, "members")[[target]],
    if (na_action == "keep" && uncovered_any) NA_character_
  )
  out <- .recast_complete(res, idc, out_keys, target, id_cols, values)
  backend_restore(out, backend, collect = collect)
}

# -----------------------------------------------------------------------------
# The bare pipeline generic
# -----------------------------------------------------------------------------

#' Recast data through a scale
#'
#' The bare pipeline verb, dispatching on the scale so one entry point serves
#' a [`NestedScale`], a [`ScaleProduct`], and the dimension subclasses in
#' `timescales` and `geoscales`, which register their own methods against this
#' generic. [`recast_scale()`] and [`recast_product()`] are the explicit
#' workers.
#'
#' The scale is `scale`; the source frame is `source` and the target `target`,
#' as in [`recast_scale()`], so a call reads the same through the generic and
#' through the worker.
#'
#' @param x The data to recast.
#' @param scale The scale to recast through.
#' @param ... Passed to the dispatched method: for a [`NestedScale`] the
#'   arguments of [`recast_scale()`], with `target` the target frame and
#'   `source` the source frame (inferred when omitted); for a
#'   [`ScaleProduct`] those of [`recast_product()`].
#'
#' @return The recast data, in the input's class.
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(
#'   unit = c("U1", "U2", "U3", "U4", "U5", "U6"),
#'   capacity = c(1, 2, 3, 4, 5, 6)
#' )
#' recast(d, s, target = "sector", rule = "sum")
#' @export
recast <- S7::new_generic("recast", dispatch_args = c("x", "scale"))

S7::method(recast, list(S7::class_any, NestedScale)) <-
  function(x, scale, target, source = NULL, ...) {
    recast_scale(data = x, x = scale, source = source, target = target, ...)
  }
