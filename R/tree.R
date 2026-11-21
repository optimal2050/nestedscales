# =============================================================================
# scale_tree() -- the parts of a scale, and which of them may change
# =============================================================================
# The identity of a scale (`scale_id()`) is a hash of the key column, the frame
# names and the frame codes. A part is
#   fixed    when it enters that hash: changing it makes another scale;
#   derived  when it is computed from another part;
#   mutable  when changing it leaves the identity as it was.
# =============================================================================

#' @include scale-class.R product-class.R str.R
NULL

.TREE_COLS <- c("part", "parent", "kind", "shape", "mark", "verb", "note")

.SCALE_MARKS <- c("fixed", "derived", "mutable")

#' @noRd
.part_row <- function(part, parent = "", kind = "property", shape = "",
                      mark = "", verb = "", note = "") {
  data.frame(
    part = part, parent = parent, kind = kind, shape = shape, mark = mark,
    verb = verb, note = note, stringsAsFactors = FALSE
  )
}

#' Rows a subclass returned, completed to the full set of columns
#' @noRd
.as_part_rows <- function(rows) {
  if (is.null(rows)) {
    return(.part_row("")[0L, , drop = FALSE])
  }
  if (!is.data.frame(rows) || !"part" %in% names(rows)) {
    .stop(
      "`scale_payload_parts()` must return a data.frame with a `part` column"
    )
  }
  for (nm in setdiff(.TREE_COLS, names(rows))) {
    rows[[nm]] <- rep(NA_character_, nrow(rows))
  }
  rows <- rows[.TREE_COLS]
  rows[] <- lapply(rows, as.character)
  rows$parent[is.na(rows$parent)] <- ""
  bad <- setdiff(rows$mark[!is.na(rows$mark) & nzchar(rows$mark)], .SCALE_MARKS)
  if (length(bad) > 0L) {
    .stop(
      "unknown mark(s) %s; a part is %s", .preview(bad),
      paste(.SCALE_MARKS, collapse = ", ")
    )
  }
  rows
}

#' Describe the parts a subclass adds to a scale
#'
#' The seam a dimension package overrides so that [`scale_tree()`] can mark
#' the properties it adds and name its own verbs. The method returns a
#' data.frame with a `part` column and any of `parent`, `kind`, `shape`,
#' `mark`, `verb` and `note`. A row whose `part` and `parent` match a part the
#' core already lists replaces the fields it gives; any other row is added. A
#' top-level part is a property of the object; `parent` names the property a
#' part belongs to. `mark` is one of `"fixed"`, `"derived"` or `"mutable"`.
#' The `NestedScale` default adds nothing.
#'
#' @param x A [`NestedScale`].
#' @param ... Not used.
#'
#' @return A data.frame of parts, or `NULL`.
#'
#' @seealso [`scale_tree()`]
#' @examples
#' scale_payload_parts(scale_example())
#' @export
scale_payload_parts <- S7::new_generic("scale_payload_parts", "x")

S7::method(scale_payload_parts, NestedScale) <- function(x, ...) NULL

#' @noRd
.frame_counts <- function(lt, frames) {
  n <- vapply(frames, function(f) {
    length(unique(stats::na.omit(lt[[f]])))
  }, integer(1))
  paste(sprintf("%s %d", frames, n), collapse = ", ")
}

#' The parts of one scale, core rows first
#' @noRd
.scale_parts <- function(x) {
  cls <- attr(x, "S7_class", exact = TRUE)
  props <- names(cls@properties)
  core <- intersect(names(.PROP_ROLES), props)
  extra <- setdiff(props, core)

  lt <- S7::prop(x, "leaftable")
  frames <- S7::prop(x, "frames")
  key <- S7::prop(x, "key")
  meta <- S7::prop(x, "meta")
  vals <- list(
    leaftable = lt, frames = frames, members = S7::prop(x, "members"),
    key = key, meta = meta, attributes = .attr_table(x),
    aliases = .alias_table(x), labels = .label_table(x)
  )

  # A subclass property that only renames a core one is the same value twice:
  # the part is listed once, under the subclass's name.
  shown <- stats::setNames(core, core)
  renamed <- character()
  for (p in extra) {
    # only a computed property can be another name; a stored one that happens
    # to hold the same value is a part of its own
    if (is.null(cls@properties[[p]]$getter)) next
    v <- tryCatch(S7::prop(x, p), error = function(e) NULL)
    hit <- core[vapply(core, function(k) {
      is.character(v) && identical(v, vals[[k]])
    }, logical(1))]
    if (length(hit) > 0L) {
      shown[[hit[[1L]]]] <- p
      renamed <- c(renamed, p)
    }
  }
  extra <- setdiff(extra, renamed)

  weights <- intersect(meta[["weights"]] %||% character(), names(lt))
  cols <- names(lt)
  col_kind <- ifelse(cols == key, "key",
    ifelse(cols %in% frames, "frame",
      ifelse(cols %in% weights, "weight", "column")
    )
  )
  col_mark <- ifelse(col_kind %in% c("key", "frame"), "fixed", "mutable")
  ord <- order(match(col_kind, c("key", "frame", "weight", "column")))

  top <- list(
    leaftable = .part_row(shown[["leaftable"]],
      shape = .prop_shape(lt), note = "one row per atom"
    ),
    frames = .part_row(shown[["frames"]],
      shape = .prop_shape(frames), mark = "fixed", note = .preview(frames, 6L)
    ),
    members = .part_row(shown[["members"]],
      shape = .prop_shape(vals$members), mark = "derived",
      note = paste0(
        "from ", shown[["leaftable"]], ": ", .frame_counts(lt, frames)
      )
    ),
    key = .part_row(shown[["key"]],
      shape = .prop_shape(key), mark = "fixed", note = key
    ),
    meta = .part_row(shown[["meta"]],
      shape = .prop_shape(meta), mark = "mutable",
      note = .preview(names(meta), 8L)
    ),
    attributes = .part_row(shown[["attributes"]],
      shape = .prop_shape(vals$attributes), mark = "mutable",
      verb = "attach_attributes_scale()", note = .PROP_ROLES[["attributes"]]
    ),
    aliases = .part_row(shown[["aliases"]],
      shape = .prop_shape(vals$aliases), mark = "mutable",
      verb = "attach_aliases_scale()", note = .PROP_ROLES[["aliases"]]
    ),
    labels = .part_row(shown[["labels"]],
      shape = .prop_shape(vals$labels), mark = "mutable",
      verb = "attach_labels_scale()", note = .PROP_ROLES[["labels"]]
    )
  )[core]
  columns <- .part_row(cols[ord],
    parent = shown[["leaftable"]], kind = col_kind[ord], mark = col_mark[ord]
  )
  out <- do.call(rbind, c(
    top["leaftable"], list(columns), top[setdiff(core, "leaftable")]
  ))

  for (p in extra) {
    v <- tryCatch(S7::prop(x, p), error = function(e) NULL)
    out <- rbind(out, .part_row(p,
      shape = .prop_shape(v), note = "added by the subclass"
    ))
  }

  # the subclass's own account of its parts
  add <- .as_part_rows(scale_payload_parts(x))
  for (i in seq_len(nrow(add))) {
    hit <- which(out$part == add$part[[i]] & out$parent == add$parent[[i]])
    if (length(hit) == 0L) {
      row <- add[i, , drop = FALSE]
      row[is.na(row)] <- ""
      if (!nzchar(row$kind)) row$kind <- "property"
      # a new child goes after the last child of its parent
      at <- if (nzchar(row$parent)) {
        own <- out$part == row$parent & out$parent == ""
        max(which(out$parent == row$parent | own), 0L)
      } else {
        nrow(out)
      }
      if (at == 0L) at <- nrow(out)
      out <- rbind(out[seq_len(at), , drop = FALSE], row,
                   out[seq_len(nrow(out) - at) + at, , drop = FALSE])
      next
    }
    for (nm in setdiff(.TREE_COLS, c("part", "parent"))) {
      v <- add[[nm]][[i]]
      if (!is.na(v)) out[[nm]][hit[[1L]]] <- v
    }
  }
  rownames(out) <- NULL
  out
}

#' The parts of a product
#' @noRd
.product_parts <- function(x) {
  axes <- S7::prop(x, "axes")
  keys <- S7::prop(x, "keys")
  jw <- S7::prop(x, "joint_weights")
  meta <- S7::prop(x, "meta")
  rbind(
    .part_row("axes", shape = .prop_shape(axes), note = "one scale per axis"),
    .part_row(names(axes),
      parent = "axes", kind = "axis", mark = "fixed",
      shape = vapply(axes, function(a) {
        sub("^.*::", "", class(a)[[1L]])
      }, character(1)),
      note = vapply(axes, scale_id, character(1))
    ),
    .part_row("keys",
      shape = .prop_shape(keys), mark = "fixed",
      note = paste(sprintf("%s = %s", names(keys), keys), collapse = ", ")
    ),
    .part_row("joint_weights", shape = .prop_shape(jw), mark = "mutable",
              note = "reserved"),
    .part_row("meta",
      shape = .prop_shape(meta), mark = "mutable",
      note = .preview(names(meta), 8L)
    )
  )
}

#' The parts of a scale and which of them may change
#'
#' Lists the parts of a scale as a tree: its properties, the columns of the
#' leaftable, and whatever a subclass adds. Each part carries one of three
#' marks, defined by the identity of the scale ([`scale_id()`]), which is
#' computed from the key column, the frame names and the frame codes:
#'
#' * `fixed`: the part enters the identity. Changing it gives another scale,
#'   which data bound to the first one no longer matches; the route is to
#'   build a new scale.
#' * `derived`: the part is computed from another one and is never set.
#' * `mutable`: the part can change and the scale stays the same scale. The
#'   function that changes it is named where there is one.
#'
#' The marks describe the object; they are not enforced on assignment.
#' `str()` on a scale prints the same tree.
#'
#' @param x A [`NestedScale`] or a [`ScaleProduct`]; in `print()`, the
#'   table `scale_tree()` returned.
#'
#' @return A data.frame of class `scale_tree`, one row per part: `part`, the
#'   `parent` property it belongs to (`""` for a property), its `kind`,
#'   `shape`, `mark`, the `verb` that changes it and a `note`. Printing it
#'   draws the tree.
#'
#' @seealso [`scale_id()`], [`scale_payload_parts()`]
#' @examples
#' scale_tree(scale_example())
#' tr <- scale_tree(scale_example())
#' tr$part[tr$mark == "fixed"]
#' scale_tree(scale_product(a = scale_example(), b = scale_example2()))
#' @export
scale_tree <- function(x) {
  if (S7::S7_inherits(x, ScaleProduct)) {
    out <- .product_parts(x)
    id <- S7::prop(x, "meta")[["name"]] %||% ""
  } else {
    .check_scale(x)
    out <- .scale_parts(x)
    id <- scale_id(x)
  }
  rownames(out) <- NULL
  attr(out, "header") <- trimws(paste0(
    "<", sub("^.*::", "", class(x)[[1L]]), "> ", id
  ))
  class(out) <- c("scale_tree", "data.frame")
  out
}

#' @noRd
.tree_glyphs <- function(ascii) {
  if (ascii) {
    list(tee = "+- ", end = "+- ", bar = "|  ", gap = "   ")
  } else {
    list(
      tee = "├─ ", end = "└─ ", bar = "│  ",
      gap = "   "
    )
  }
}

#' The lines of the drawing, header first
#' @noRd
.tree_lines <- function(x, ascii) {
  g <- .tree_glyphs(isTRUE(ascii))
  top <- which(x$parent == "")
  lines <- character()
  label <- character()
  for (k in seq_along(top)) {
    i <- top[[k]]
    last <- k == length(top)
    label <- c(label, paste0(if (last) g$end else g$tee, x$part[[i]]))
    lines <- c(lines, i)
    kids <- which(x$parent == x$part[[i]])
    for (j in seq_along(kids)) {
      label <- c(label, paste0(
        if (last) g$gap else g$bar,
        if (j == length(kids)) g$end else g$tee, x$part[[kids[[j]]]]
      ))
      lines <- c(lines, kids[[j]])
    }
  }
  d <- x[lines, , drop = FALSE]
  info <- ifelse(d$parent == "", d$shape,
    ifelse(nzchar(d$shape), paste(d$kind, d$shape), d$kind)
  )
  rest <- ifelse(nzchar(d$verb), d$verb, d$note)
  body <- paste(
    format(label), format(info), format(d$mark), rest,
    sep = "  "
  )
  c(attr(x, "header") %||% "<scale>", sub("\\s+$", "", body))
}

#' @param ascii Draw the branches with `+`, `-` and `|`. The default does so
#'   outside a UTF-8 session.
#' @param ... Ignored.
#' @rdname scale_tree
#' @export
print.scale_tree <- function(x, ascii = !isTRUE(l10n_info()[["UTF-8"]]), ...) {
  cat(.tree_lines(x, ascii), sep = "\n")
  invisible(x)
}
