# =============================================================================
# Aliases -- alternative labels for members, and strict matching
# =============================================================================
# A long table keyed by (frame, unit): one row per alternative spelling a
# member is known by (a palette's aliases, a model's commodity codes).
# `scale_match()` resolves labels against member names and aliases EXACTLY
# (case-insensitive) and reports ambiguity rather than guessing.
# =============================================================================

#' @include scale-class.R
NULL

.ALIAS_COLS <- c("frame", "unit", "alias", "source")

#' @noRd
.empty_aliases <- function() {
  data.frame(
    frame = character(), unit = character(), alias = character(),
    source = character(), stringsAsFactors = FALSE
  )
}

#' The alias table, with NULL (an object saved before 0.2.0) as empty
#' @noRd
.alias_table <- function(x) {
  attr(x, "aliases", exact = TRUE) %||% .empty_aliases()
}

#' @noRd
.as_aliases <- function(aliases, source = NULL) {
  if (is.null(aliases)) {
    return(.empty_aliases())
  }
  if (!is.data.frame(aliases)) .stop("`aliases` must be a data.frame")
  aliases <- as.data.frame(aliases, stringsAsFactors = FALSE)
  if (!is.null(source)) {
    if (!.is_string(source)) .stop("`source` must be a single string")
    if ("source" %in% names(aliases)) {
      .stop("`aliases` already has a `source` column; drop `source=`")
    }
    aliases$source <- source
  }
  missing_cols <- setdiff(.ALIAS_COLS, names(aliases))
  if (length(missing_cols) > 0L) {
    .stop("`aliases` is missing column(s): %s", .preview(missing_cols))
  }
  extra <- setdiff(names(aliases), .ALIAS_COLS)
  if (length(extra) > 0L) {
    .stop("`aliases` has unknown column(s): %s", .preview(extra))
  }
  out <- aliases[.ALIAS_COLS]
  for (ch in .ALIAS_COLS) out[[ch]] <- as.character(out[[ch]])
  rownames(out) <- NULL
  out
}

#' @noRd
.check_aliases_table <- function(al, frames, members, v) {
  errs <- character()
  if (!identical(names(al), .ALIAS_COLS)) {
    return(sprintf(
      "`aliases` must have exactly the columns: %s",
      paste(.ALIAS_COLS, collapse = ", ")
    ))
  }
  if (nrow(al) == 0L) {
    return(errs)
  }
  bad_frame <- unique(al$frame[!al$frame %in% frames])
  if (length(bad_frame) > 0L) {
    errs <- c(errs, sprintf(
      "`aliases` names %s(s) not in the object: %s", v$frame,
      .preview(bad_frame)
    ))
  }
  ok_frame <- al$frame %in% frames
  is_member <- rep(FALSE, nrow(al))
  is_member[ok_frame] <- mapply(
    function(f, u) u %in% members[[f]], al$frame[ok_frame],
    al$unit[ok_frame]
  )
  if (any(!is_member & ok_frame)) {
    bad <- unique(paste0(al$frame, "/", al$unit)[!is_member & ok_frame])
    errs <- c(errs, sprintf(
      "`aliases` names (%s/%s) pairs that are not members: %s",
      v$frame, v$unit, .preview(bad)
    ))
  }
  for (nm in c("alias", "source")) {
    val <- al[[nm]]
    if (!is.character(val) || anyNA(val) || any(!nzchar(val))) {
      errs <- c(errs, sprintf("`aliases$%s` must be non-empty strings", nm))
    }
  }
  k <- paste(al$alias, al$frame, al$unit, al$source, sep = "\r")
  if (anyDuplicated(k)) {
    errs <- c(errs, sprintf(
      "`aliases` has duplicate rows: %s",
      .preview(unique(al$alias[duplicated(k)]))
    ))
  }
  errs
}

#' Attach aliases to a scale
#'
#' Appends rows to the object's alias table: alternative labels by which a
#' member (`frame`, `unit`) is known, tagged with the `source` the spelling
#' comes from (a palette, a model's commodity codes, a dataset). The same
#' alias may legitimately point at several members; [`scale_match()`]
#' reports that as ambiguous unless the caller names the frame.
#'
#' @param x A [`NestedScale`].
#' @param aliases A `data.frame` with columns `frame`, `unit`, `alias` and,
#'   unless `source` is given, `source`.
#' @param source Optional single string filled into the `source` column.
#'
#' @return The scale with the rows appended.
#'
#' @examples
#' s <- attach_aliases_scale(
#'   scale_example(),
#'   data.frame(frame = "sector", unit = c("P", "S"),
#'              alias = c("primary", "secondary")),
#'   source = "labels"
#' )
#' scale_match(s, c("Primary", "G1", "nope"))
#' @export
attach_aliases_scale <- function(x, aliases, source = NULL) {
  .check_scale(x)
  x <- .upgrade_scale(x)
  new <- .as_aliases(aliases, source = source)
  old <- .alias_table(x)
  k_old <- paste(old$alias, old$frame, old$unit, old$source, sep = "\r")
  k_new <- paste(new$alias, new$frame, new$unit, new$source, sep = "\r")
  clash <- intersect(k_new, k_old)
  if (length(clash) > 0L) {
    .stop(
      "alias row(s) already present: %s",
      .preview(unique(new$alias[k_new %in% clash]))
    )
  }
  out <- rbind(old, new)
  rownames(out) <- NULL
  S7::prop(x, "aliases") <- out
  x
}

#' Read the alias table
#'
#' @param x A [`NestedScale`].
#' @param frame Restrict to one frame; `NULL` for all.
#' @param source Restrict to one source (or several); `NULL` for all.
#'
#' @return A `data.frame` with columns `frame`, `unit`, `alias`, `source`.
#'
#' @examples
#' s <- attach_aliases_scale(
#'   scale_example(),
#'   data.frame(frame = "sector", unit = "P", alias = "primary"),
#'   source = "labels"
#' )
#' scale_aliases(s)
#' scale_aliases(s, frame = "class")
#' @export
scale_aliases <- function(x, frame = NULL, source = NULL) {
  .check_scale(x)
  al <- .alias_table(x)
  if (!is.null(frame)) {
    .check_frame(x, frame)
    al <- al[al$frame == frame, , drop = FALSE]
  }
  if (!is.null(source)) {
    al <- al[al$source %in% source, , drop = FALSE]
  }
  rownames(al) <- NULL
  al
}

#' Match labels to members, strictly
#'
#' Resolves each label to a `(frame, unit)` member in two stages, stopping
#' at the first that hits: an **exact** member name (case-insensitive), then
#' an **alias** (case-insensitive). A label that hits several members --
#' the same name at two frames, or an alias shared by two members -- is
#' reported as `"ambiguous"` with the candidates, unless `frame=` narrows
#' the search to one frame. A label that hits nothing is `"none"`. Nothing
#' is guessed: no fuzzy matching, no substring matching.
#'
#' @param x A [`NestedScale`].
#' @param labels Character vector of labels to resolve.
#' @param frame Restrict matching to one frame; `NULL` searches all frames
#'   and the atom level.
#' @param source Restrict the alias stage to one source (or several).
#'
#' @return A `data.frame` with one row per label: `label`, `frame`, `unit`,
#'   `method` (`"exact"`, `"alias"`, `"ambiguous"`, `"none"`) and
#'   `candidates` (the `frame/unit` pairs of an ambiguous hit, joined by
#'   `"; "`, else `NA`).
#'
#' @examples
#' s <- scale_example()
#' scale_match(s, c("P", "G1", "u1", "nope"))   # G1 is a class AND a group
#' scale_match(s, "G1", frame = "group")
#' @export
scale_match <- function(x, labels, frame = NULL, source = NULL) {
  .check_scale(x)
  if (!is.character(labels)) .stop("`labels` must be character")
  levels <- .nav_levels(x)
  if (!is.null(frame)) {
    .check_frame(x, frame)
    levels <- frame
  }
  names_tbl <- do.call(rbind, lapply(levels, function(f) {
    data.frame(frame = f, unit = scale_units(x, f), stringsAsFactors = FALSE)
  }))
  al <- scale_aliases(x, source = source)
  al <- al[al$frame %in% levels, , drop = FALSE]

  one <- function(lab) {
    key <- tolower(trimws(lab))
    hit <- names_tbl[tolower(names_tbl$unit) == key, , drop = FALSE]
    method <- "exact"
    if (nrow(hit) == 0L) {
      ah <- al[tolower(al$alias) == key, , drop = FALSE]
      hit <- unique(ah[c("frame", "unit")])
      method <- "alias"
    }
    if (nrow(hit) == 0L) {
      return(data.frame(
        label = lab, frame = NA_character_, unit = NA_character_,
        method = "none", candidates = NA_character_,
        stringsAsFactors = FALSE
      ))
    }
    if (nrow(hit) > 1L) {
      return(data.frame(
        label = lab, frame = NA_character_, unit = NA_character_,
        method = "ambiguous",
        candidates = paste(paste0(hit$frame, "/", hit$unit), collapse = "; "),
        stringsAsFactors = FALSE
      ))
    }
    data.frame(
      label = lab, frame = hit$frame, unit = hit$unit, method = method,
      candidates = NA_character_, stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, lapply(labels, one))
  rownames(out) <- NULL
  out
}
