# =============================================================================
# Labels -- display names for members and frames, in named variants
# =============================================================================
# A long table keyed by (frame, member, variant): one row per display name.
# The table is sparse -- a frame, or a member, without a row is shown by its
# code -- and a row with `member = NA` names the frame itself. Labels are for
# display only; `scale_match()` resolves spellings through the alias table
# instead.
# =============================================================================

#' @include scale-class.R
NULL

.LABEL_COLS <- c("frame", "member", "variant", "label")
.DEFAULT_VARIANT <- "label"

#' @noRd
.empty_labels <- function() {
  data.frame(
    frame = character(), member = character(), variant = character(),
    label = character(), stringsAsFactors = FALSE
  )
}

#' The label table, with NULL (a class without the property) as empty
#' @noRd
.label_table <- function(x) {
  .legacy_member_col(attr(x, "labels", exact = TRUE) %||% .empty_labels())
}

#' Whether the object's embedded class declares the `labels` property
#' @noRd
.has_labels_prop <- function(x) {
  cls <- .s7_class(x)
  !is.null(cls) && "labels" %in% names(cls@properties)
}

#' @noRd
.as_labels <- function(labels, variant = NULL) {
  if (is.null(labels)) {
    return(.empty_labels())
  }
  if (!is.data.frame(labels)) .stop("`labels` must be a data.frame")
  labels <- as.data.frame(labels, stringsAsFactors = FALSE)
  if ("variant" %in% names(labels)) {
    if (!is.null(variant)) {
      .stop("`labels` already has a `variant` column; drop `variant=`")
    }
  } else {
    variant <- variant %||% .DEFAULT_VARIANT
    if (!.is_string(variant)) .stop("`variant` must be a single string")
    labels$variant <- rep(variant, nrow(labels))
  }
  missing_cols <- setdiff(.LABEL_COLS, names(labels))
  if (length(missing_cols) > 0L) {
    .stop("`labels` is missing column(s): %s", .preview(missing_cols))
  }
  extra <- setdiff(names(labels), .LABEL_COLS)
  if (length(extra) > 0L) {
    .stop("`labels` has unknown column(s): %s", .preview(extra))
  }
  out <- labels[.LABEL_COLS]
  for (ch in .LABEL_COLS) out[[ch]] <- as.character(out[[ch]])
  rownames(out) <- NULL
  out
}

#' "frame\rmember\rvariant" row keys (an NA member is the frame's own label)
#' @noRd
.label_keys <- function(lb) {
  paste(lb$frame, ifelse(is.na(lb$member), "", lb$member), lb$variant,
    is.na(lb$member),
    sep = "\r"
  )
}

#' @noRd
.check_labels_table <- function(lb, frames, members, v) {
  errs <- character()
  lb <- .legacy_member_col(lb)
  if (!identical(names(lb), .LABEL_COLS)) {
    return(sprintf(
      "`labels` must have exactly the columns: %s",
      paste(.LABEL_COLS, collapse = ", ")
    ))
  }
  if (nrow(lb) == 0L) {
    return(errs)
  }
  bad_frame <- unique(lb$frame[!lb$frame %in% frames])
  if (length(bad_frame) > 0L) {
    errs <- c(errs, sprintf(
      "`labels` names %s(s) not in the object: %s", v$frame,
      .preview(bad_frame)
    ))
  }
  check <- lb$frame %in% frames & !is.na(lb$member)
  is_member <- rep(TRUE, nrow(lb))
  is_member[check] <- vapply(
    which(check), function(i) lb$member[[i]] %in% members[[lb$frame[[i]]]],
    logical(1)
  )
  if (any(!is_member)) {
    bad <- unique(paste0(lb$frame, "/", lb$member)[!is_member])
    errs <- c(errs, sprintf(
      "`labels` names (%s/%s) pairs that are not members: %s",
      v$frame, v$member, .preview(bad)
    ))
  }
  for (nm in c("variant", "label")) {
    val <- lb[[nm]]
    if (!is.character(val) || anyNA(val) || any(!nzchar(val))) {
      errs <- c(errs, sprintf("`labels$%s` must be non-empty strings", nm))
    }
  }
  k <- .label_keys(lb)
  if (anyDuplicated(k)) {
    dup <- lb[duplicated(k), , drop = FALSE]
    errs <- c(errs, sprintf(
      "`labels` has more than one label for: %s",
      .preview(unique(paste0(
        dup$frame, "/", ifelse(is.na(dup$member), "<frame>", dup$member),
        " [", dup$variant, "]"
      )))
    ))
  }
  errs
}

#' The variant a lookup uses: the one asked for, else the declared default,
#' else the first in the table
#' @noRd
.label_variant <- function(x, variant = NULL) {
  lb <- .label_table(x)
  if (is.null(variant)) {
    variant <- S7::prop(x, "meta")[["default_label"]]
    if (is.null(variant) || !variant %in% lb$variant) {
      variant <- if (nrow(lb) > 0L) lb$variant[[1L]] else .DEFAULT_VARIANT
    }
    return(variant)
  }
  if (!.is_string(variant)) .stop("`variant` must be a single string")
  if (nrow(lb) > 0L && !variant %in% lb$variant) {
    .stop(
      "no labels of variant \"%s\"; available: %s", variant,
      .preview(unique(lb$variant))
    )
  }
  variant
}

#' Attach labels to a scale
#'
#' Adds display names to the object's label table. A label belongs to a
#' member (`frame`, `member`) and to a `variant` -- a free name such as
#' `"name"`, `"short"` or a language code -- so a member may carry several.
#' The table is sparse: frames and members without a row are shown by their
#' code. A row with `member = NA` labels the frame itself.
#'
#' Labels are for display. Alternative spellings to be *matched* belong in
#' the alias table, see [`attach_aliases_scale()`].
#'
#' @param x A [`NestedScale`].
#' @param labels A `data.frame` with columns `frame`, `member`, `label` and,
#'   unless `variant` is given, optionally `variant`.
#' @param variant Single string filled into the `variant` column when
#'   `labels` has none. Defaults to `"label"`.
#' @param default Single string naming the variant used when a lookup names
#'   none. `NULL` keeps the current default (initially the first variant
#'   attached).
#' @param overwrite Replace the label of a (`frame`, `member`, `variant`)
#'   already present. `FALSE` (default) makes that an error.
#'
#' @return The scale with the rows added.
#'
#' @examples
#' s <- attach_labels_scale(
#'   scale_example(),
#'   data.frame(frame = "sector", member = c("P", "S", NA),
#'              label = c("Primary", "Secondary", "Sector"))
#' )
#' scale_labels(s)
#' scale_label(s, c("P", "S", "T"), frame = "sector")
#' @seealso [`scale_labels()`], [`scale_label()`]
#' @export
attach_labels_scale <- function(x, labels, variant = NULL, default = NULL,
                                overwrite = FALSE) {
  .check_scale(x)
  x <- .upgrade_scale(x)
  if (!.has_labels_prop(x)) {
    .stop(paste0(
      "this %s comes from a class built before labels existed; ",
      "reinstall the package that defines it"
    ), class(x)[[1L]])
  }
  new <- .as_labels(labels, variant = variant)
  old <- .label_table(x)
  k_old <- .label_keys(old)
  k_new <- .label_keys(new)
  clash <- k_old %in% k_new
  if (any(clash)) {
    if (!isTRUE(overwrite)) {
      .stop(
        "label(s) already present: %s; pass overwrite = TRUE to replace",
        .preview(unique(paste0(old$frame, "/", old$member)[clash]))
      )
    }
    old <- old[!clash, , drop = FALSE]
  }
  out <- rbind(old, new)
  rownames(out) <- NULL
  if (!is.null(default)) {
    if (!.is_string(default)) .stop("`default` must be a single string")
    if (!default %in% out$variant) {
      .stop(
        "`default` must be a variant of the label table: %s",
        .preview(unique(out$variant))
      )
    }
    meta <- S7::prop(x, "meta")
    meta$default_label <- default
    return(S7::set_props(x, labels = out, meta = meta))
  }
  S7::prop(x, "labels") <- out
  x
}

#' Read the label table
#'
#' @param x A [`NestedScale`].
#' @param frame Restrict to one frame; `NULL` for all.
#' @param variant Restrict to one variant (or several); `NULL` for all.
#'
#' @return A `data.frame` with columns `frame`, `member`, `variant`, `label`.
#'   A row with `member = NA` is the label of the frame itself.
#'
#' @examples
#' s <- attach_labels_scale(
#'   scale_example(),
#'   data.frame(frame = "sector", member = c("P", "S"),
#'              label = c("Primary", "Secondary"))
#' )
#' scale_labels(s)
#' scale_labels(s, frame = "class")
#' @seealso [`attach_labels_scale()`], [`scale_label()`]
#' @export
scale_labels <- function(x, frame = NULL, variant = NULL) {
  .check_scale(x)
  lb <- .label_table(x)
  if (!is.null(frame)) {
    .check_frame(x, frame)
    lb <- lb[lb$frame == frame, , drop = FALSE]
  }
  if (!is.null(variant)) {
    lb <- lb[lb$variant %in% variant, , drop = FALSE]
  }
  rownames(lb) <- NULL
  lb
}

#' Look up the labels of members
#'
#' Returns one display name per code. A code without a label of the chosen
#' variant is returned unchanged, so the result is always usable as an axis
#' or legend text. `NA` in `members` stands for the frame itself and returns
#' the frame's label, or its name when it has none.
#'
#' @param x A [`NestedScale`].
#' @param members Character vector of member codes at `frame`.
#' @param frame The frame the codes are at.
#' @param variant The label variant. `NULL` uses the scale's default, see
#'   [`attach_labels_scale()`].
#'
#' @return A character vector as long as `members`.
#'
#' @examples
#' s <- attach_labels_scale(
#'   scale_example(),
#'   data.frame(frame = "sector", member = c("P", "S", NA),
#'              label = c("Primary", "Secondary", "Sector"))
#' )
#' scale_label(s, c("S", "P", "T"), frame = "sector")
#' scale_label(s, NA, frame = "sector")
#' scale_label(s, c("G1", "G2"), frame = "class")   # no labels: the codes
#' @seealso [`attach_labels_scale()`], [`scale_labels()`]
#' @export
scale_label <- function(x, members, frame, variant = NULL) {
  .check_scale(x)
  .check_frame(x, frame)
  members <- as.character(members)
  variant <- .label_variant(x, variant)
  lb <- .label_table(x)
  lb <- lb[lb$frame == frame & lb$variant == variant, , drop = FALSE]
  out <- lb$label[match(members, lb$member)]
  miss <- is.na(out)
  out[miss] <- ifelse(is.na(members[miss]), frame, members[miss])
  out
}
