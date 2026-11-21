# =============================================================================
# join_scale() -- attach a scale's labels and memberships to a dataset
# =============================================================================
# Everything attached is named after the scale (`meta$name`), so SEVERAL
# scales can live side by side on one dataset: a table carrying two label
# columns is a direct crosswalk between those two objects, and that is what
# lets one dataset be indexed by time, space and anything else at once.
#
# The scale side of the join is a small in-memory frame, so a lazy input never
# has to be materialised.
# =============================================================================

#' @include scale-class.R
NULL

#' Attach scale labels and memberships to a dataset
#'
#' Adds a code column named after the scale, and optionally the codes of
#' coarser frames (`"<name>.<frame>"`), the display names of the codes
#' (`"<name>.label"`) and the member's share and weight (`"<name>.share"`,
#' `"<name>.weight"`).
#'
#' Existing columns are never overwritten -- a collision is an error.
#'
#' @param data The data, in any supported backend, with a column of member
#'   codes.
#' @param x The [`NestedScale`] to attach.
#' @param key Name of the code column in `data`. Inferred from the scale's
#'   name, the keyed frame, or the scale's leaf column.
#' @param frame The frame the codes in `key` are at. `NULL` (default) is
#'   inferred as the single frame name appearing among the data's columns.
#' @param attach Coarser frames whose codes to attach as new columns: `TRUE`
#'   for all of them, a character vector to choose, `NULL`/`FALSE` for none.
#' @param meta Attach the member's `share` and `weight` at the keyed frame.
#' @param weight Weight column used for `meta`. `NULL` uses the default.
#' @param as_factor Return attached membership columns as factors with the
#'   frame's full vocabulary as levels (so empty groups still plot).
#' @param collect For lazy inputs: materialise (`TRUE`) or return the query.
#' @param diagnostics Whether to run the checks that read the data (no
#'   matching codes; codes that are not members). `"auto"` (default) runs them
#'   on eager inputs and skips them on arrow/dtplyr, which makes this verb
#'   zero-scan there; `"on"`/`"off"` force the choice.
#' @param labels Attach the display names of the keyed codes as
#'   `"<name>.label"`: `TRUE` for the default variant, a string to name one,
#'   `NULL`/`FALSE` (default) for none. See [`attach_labels_scale()`].
#'
#' @return `data` with the attached columns, in its own class.
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(class = c("G1", "G2", "S1"), v = 1:3)
#' join_scale(d, s, attach = TRUE)
#' join_scale(d, s, attach = "sector")
#' join_scale(d, s, meta = TRUE)
#' @export
join_scale <- function(data, x, key = NULL, frame = NULL, attach = NULL,
                       meta = FALSE, weight = NULL, as_factor = TRUE,
                       collect = NULL,
                       diagnostics = c("auto", "on", "off"),
                       labels = NULL) {
  .check_scale(x, "x")
  link <- .link_enter(data, x, key = key, source = frame)
  out <- .join_scale(link$data, x,
    key = link$key, frame = link$source, attach = attach, meta = meta,
    weight = weight, as_factor = as_factor, collect = collect,
    diagnostics = diagnostics, labels = labels
  )
  if (nrow(link$tags) == 0L || !is.data.frame(out)) {
    return(out)
  }
  # What the join added: the code column named after the scale is at the
  # keyed frame, and each `<name>.<frame>` column is at that frame.
  nm <- .scale_name(x)
  keyed <- link$source %||% intersect(
    c(S7::prop(x, "frames"), .leaf_frame(x)), names(link$data)
  )[1L]
  added <- setdiff(names(out), names(link$data))
  new <- list()
  if (nm %in% added) new[[nm]] <- list(scale = x, frame = keyed)
  for (fr in S7::prop(x, "frames")) {
    col <- paste0(nm, ".", fr)
    if (col %in% added) new[[col]] <- list(scale = x, frame = fr)
  }
  .link_exit(out, link, new)
}

#' @noRd
.join_scale <- function(data, x, key = NULL, frame = NULL, attach = NULL,
                        meta = FALSE, weight = NULL, as_factor = TRUE,
                        collect = NULL,
                        diagnostics = c("auto", "on", "off"),
                        labels = NULL) {
  diagnostics <- match.arg(diagnostics)
  label_variant <- if (is.null(labels) || isFALSE(labels)) {
    NULL
  } else {
    .label_variant(x, if (isTRUE(labels)) NULL else labels)
  }
  backend <- backend_of(data, "data")
  nm <- .scale_name(x)
  schema <- backend_schema(data)
  v <- scale_vocab(x)

  leaves <- S7::prop(x, "leaftable")
  fr_all <- S7::prop(x, "frames")
  members <- S7::prop(x, "members")

  # -- resolve the keyed frame and the key -----------------------------------
  if (is.null(frame)) {
    hit <- intersect(fr_all, names(schema))
    # Fall back to the leaf column when no frame column is present: a Calendar
    # is keyed by its timeslices, which are combinations of its frames rather
    # than codes of one. Only fires where this previously errored.
    if (length(hit) == 0L) hit <- intersect(.leaf_frame(x), names(schema))
    if (length(hit) != 1L) {
      .stop(
        paste0(
          "cannot infer the code %s from the data's columns ",
          "(found: %s); pass `frame=`"
        ),
        v$frame, if (length(hit) == 0L) "none" else .preview(hit)
      )
    }
    frame <- hit
  }
  .check_frame(x, frame, "frame")
  if (is.null(key)) {
    key <- if (nm %in% names(schema)) {
      nm
    } else if (frame %in% names(schema)) {
      frame
    } else if (scale_leaf_column(x) %in% names(schema)) {
      scale_leaf_column(x)
    } else {
      .stop(paste0(
        "the data has no `%s`, `%s`, or `%s` column; ",
        "pass `key=`"
      ), nm, frame, scale_leaf_column(x))
    }
  }
  if (!key %in% names(schema)) {
    .stop("the data has no column named `%s`; pass `key=`", key)
  }

  # -- what gets attached ----------------------------------------------------
  # scale_rank(), not match(): `frame` may be the leaf column, which is not
  # in `frames` and ranks one past the last. A raw match() gives NA here.
  coarser <- fr_all[seq_len(scale_rank(x, frame) - 1L)]
  if (isTRUE(attach)) attach <- coarser
  if (!is.null(attach) && !isFALSE(attach)) {
    bad <- setdiff(attach, coarser)
    if (length(bad) > 0L) {
      .stop(
        "`attach` must be coarser than '%s'; not: %s", frame,
        .preview(bad)
      )
    }
  } else {
    attach <- character(0)
  }
  new_cols <- c(
    if (key != nm) nm,
    paste0(nm, ".", attach),
    if (!is.null(label_variant)) paste0(nm, ".label"),
    if (isTRUE(meta)) paste0(nm, c(".share", ".weight"))
  )
  clash <- intersect(new_cols, names(schema))
  if (length(clash) > 0L) {
    .stop(
      "attaching \"%s\" would overwrite existing column(s): %s",
      nm, .preview(clash)
    )
  }
  if (length(new_cols) == 0L) {
    return(data) # label column already there, nothing else requested
  }

  # -- validate the keys -----------------------------------------------------
  # This verb is otherwise a single left join against a small in-memory frame,
  # so it can be a ZERO-SCAN operation. The two checks below are the only
  # reason it would ever read the data, and both are FILTERED: the match test
  # asks for one row and stops, and the unknown-code query returns nothing at
  # all on healthy data.
  known <- unique(stats::na.omit(as.character(leaves[[frame]])))
  if (.want_diagnostics(diagnostics, backend)) {
    ksym <- rlang::sym(key)
    any_match <- backend_pull(
      utils::head(
        dplyr::filter(backend_lazy(data, backend), !!ksym %in% known),
        1L
      )
    )
    if (nrow(any_match) == 0L) {
      .stop(
        "no rows of the `%s` column match members at %s '%s'",
        key, v$frame, frame
      )
    }
    unknown <- backend_pull(dplyr::distinct(dplyr::select(
      dplyr::filter(
        backend_lazy(data, backend),
        !is.na(!!ksym) & !(!!ksym %in% known)
      ),
      dplyr::all_of(key)
    )))[[key]]
    if (length(unknown) > 0L) {
      .warn(
        "%d code(s) in the `%s` column are not %s at %s '%s': %s",
        length(unknown), key, v$members, v$frame, frame,
        .preview(unique(as.character(unknown)))
      )
    }
  }

  # -- the in-memory attach frame --------------------------------------------
  attach_df <- data.frame(.ms_label = known, stringsAsFactors = FALSE)

  # membership columns: unique (frame, coarser) pairs; codes under more than
  # one parent are ambiguous -> NA + warning
  for (cl in attach) {
    pairs <- unique(leaves[!is.na(leaves[[frame]]), c(frame, cl),
      drop = FALSE
    ])
    n_par <- table(pairs[[frame]])
    multi <- names(n_par)[n_par > 1L]
    if (length(multi) > 0L) {
      .warn(
        paste0(
          "%s '%s' does not nest in '%s'; %d code(s) have multiple ",
          "parents and get NA (e.g. %s)"
        ),
        v$frame, frame, cl, length(multi), .preview(multi)
      )
      pairs <- pairs[!pairs[[frame]] %in% multi, , drop = FALSE]
    }
    val <- as.character(pairs[[cl]])[match(known, pairs[[frame]])]
    attach_df[[paste0(nm, ".", cl)]] <-
      if (isTRUE(as_factor)) factor(val, levels = members[[cl]]) else val
  }

  if (!is.null(label_variant)) {
    attach_df[[paste0(nm, ".label")]] <-
      scale_label(x, known, frame, label_variant)
  }

  # share / weight at the keyed frame (skipped when no weight exists)
  if (isTRUE(meta)) {
    wcol <- tryCatch(.resolve_weight(x, weight), error = function(e) NULL)
    if (is.null(wcol)) {
      .warn(paste0(
        "\"%s\" declares no weight columns; `meta = TRUE` ",
        "share/weight skipped"
      ), nm)
    } else {
      w <- stats::aggregate(as.numeric(leaves[[wcol]]),
        by = list(code = as.character(leaves[[frame]])),
        FUN = sum, na.rm = TRUE
      )
      ww <- w$x[match(known, w$code)]
      attach_df[[paste0(nm, ".weight")]] <- ww
      attach_df[[paste0(nm, ".share")]] <- ww / sum(w$x)
    }
  }

  # -- the join --------------------------------------------------------------
  lab_map <- attach_df
  names(lab_map)[names(lab_map) == ".ms_label"] <- key
  lab_map$.ms_label <- lab_map[[key]]

  out <- dplyr::left_join(backend_lazy(data, backend), lab_map,
    by = key,
    na_matches = "na"
  )
  if (key != nm) {
    out <- dplyr::rename(out, !!rlang::sym(nm) := !!rlang::sym(".ms_label"))
  } else {
    out <- dplyr::select(out, -dplyr::all_of(".ms_label"))
  }
  backend_restore(out, backend, collect = collect)
}
