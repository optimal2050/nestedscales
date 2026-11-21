# =============================================================================
# The data link -- which scale, and which frame, a column of codes is on
# =============================================================================
# A scale never holds data. The link between a table and a scale is carried by
# the code column itself: `bind_scale()` turns it into a `scale_member` vector,
# a character vector that remembers the scale's name, the scale's identity
# (`scale_id()`) and the frame its codes are at. Living on the column, the
# link follows it through subsetting, joins and row binding, and is gone the
# moment the column is turned back into a plain character vector.
#
# The verbs read the link instead of guessing from column names, refuse data
# bound to a different scale, and bind their result. Data that was never
# bound is treated exactly as before, and its result is left unbound: the
# link is propagated, never invented.
# =============================================================================

#' @include scale-class.R
#' @importFrom vctrs vec_ptype2 vec_cast vec_ptype_abbr vec_ptype_full
NULL

# Identity ---------------------------------------------------------------------

#' The identity of a scale
#'
#' A short string that says which scale an object is: its name and a hash of
#' its structure, `"<name>@<hash>"`. The hash covers the leaf column, the
#' frames and
#' the leaf-to-frame memberships; weights, attributes, aliases, labels and the
#' order of rows or members do not enter, so adding a weight keeps data bound
#' to the scale valid, while a subset or a re-grouping is a different scale.
#' A data link compares the hash alone: two objects with the same structure
#' under different names are the same scale to it, and the name is kept for
#' messages.
#'
#' The hash is the first eight hexadecimal digits of the MD5 of a canonical
#' UTF-8 text: the line `key=<leaf column name>` (the prefix `key=` is part
#' of the hashed text and is kept so that identities do not change), the
#' line `frames=` with the frame names tab-separated, then one tab-separated
#' line per leaf (its code in the leaf column first, then its code at each
#' frame, empty where unassigned), leaves sorted by the leaf column in the C
#' locale, lines joined by `"\n"`.
#'
#' @param x A [`NestedScale`].
#' @return A single string.
#' @examples
#' scale_id(scale_example())
#' @seealso [`bind_scale()`]
#' @export
scale_id <- function(x) {
  .check_scale(x)
  key <- .leaf_col(x)
  fr <- S7::prop(x, "frames")
  lt <- S7::prop(x, "leaftable")
  cols <- unique(c(key, fr))
  tab <- lapply(cols, function(n) {
    v <- enc2utf8(as.character(lt[[n]]))
    v[is.na(v)] <- ""
    v
  })
  rows <- do.call(paste, c(tab, sep = "\t"))
  rows <- rows[order(tab[[1L]], method = "radix")]
  txt <- paste(
    c(
      paste0("key=", enc2utf8(key)),
      paste0("frames=", paste(enc2utf8(fr), collapse = "\t")),
      rows
    ),
    collapse = "\n"
  )
  f <- tempfile("scale_id")
  on.exit(unlink(f), add = TRUE)
  writeBin(charToRaw(txt), f)
  paste0(
    .scale_name(x, require = FALSE), "@",
    substr(unname(tools::md5sum(f)), 1L, 8L)
  )
}

# The vector class -------------------------------------------------------------

#' @noRd
.new_scale_member <- function(x = character(), scale = "", id = "",
                              frame = "") {
  vctrs::new_vctr(
    as.character(x),
    scale = scale, id = id, frame = frame,
    class = "scale_member", inherit_base_type = TRUE
  )
}

#' @noRd
.is_scale_member <- function(x) inherits(x, "scale_member")

#' The structure hash of an identity. Two scales are the same scale for a
#' link when their hashes agree; the name is carried for messages only.
#' @noRd
.id_hash <- function(id) sub("^.*@", "", id)

#' "'name' @hash, frame 'f'" for messages
#' @noRd
.tag_text <- function(scale, id, frame = NULL) {
  hash <- .id_hash(id)
  paste0(
    if (nzchar(scale)) paste0("'", scale, "'") else "<unnamed>",
    " [", hash, "]",
    if (!is.null(frame)) paste0(", ", frame)
  )
}

#' Codes bound to a scale
#'
#' @description
#' `r lifecycle::badge("experimental")`
#' This feature may change or be removed in a later version.
#'
#' `as_scale_member()` marks a vector of codes as belonging to one frame of
#' one scale; it is what [`bind_scale()`] puts in a column. The result is a
#' character vector of class `scale_member` that carries the scale's name, its
#' [`scale_id()`] and the frame. `is_scale_member()` tests for it.
#' Experimental, with the rest of the data link; see [`bind_scale()`].
#'
#' @details
#' Combining two such vectors (binding rows, joining) works when they are on
#' the same scale and frame and is an error otherwise. Combined with a plain
#' character vector the result stays bound, the plain codes being taken on
#' trust; the verbs check codes against the scale when they use them.
#'
#' @param x A vector of codes; for `is_scale_member()`, any object.
#' @param scale The [`NestedScale`] the codes belong to.
#' @param frame The frame the codes are at.
#'
#' @return `as_scale_member()` a `scale_member` vector as long as `x`;
#'   `is_scale_member()` a single logical.
#'
#' @examples
#' s <- scale_example()
#' u <- as_scale_member(c("P", "S", "P"), s, "sector")
#' u
#' is_scale_member(u)
#' as.character(u)
#' @seealso [`bind_scale()`], [`scale_link()`]
#' @export
as_scale_member <- function(x, scale, frame) {
  .check_scale(scale, "scale")
  .check_frame(scale, frame, "frame")
  codes <- as.character(x)
  strangers <- setdiff(
    unique(codes[!is.na(codes)]), scale_members(scale, frame)
  )
  if (length(strangers) > 0L) {
    v <- scale_vocab(scale)
    .stop(
      "%d code(s) are not %s at %s '%s': %s",
      length(strangers), v$members, v$frame, frame, .preview(strangers)
    )
  }
  .new_scale_member(
    codes,
    scale = .scale_name(scale, require = FALSE),
    id = scale_id(scale), frame = frame
  )
}

#' @rdname as_scale_member
#' @export
is_scale_member <- function(x) .is_scale_member(x)

#' @export
vec_ptype_abbr.scale_member <- function(x, ...) {
  sc <- attr(x, "scale")
  paste0(attr(x, "frame"), if (nzchar(sc)) paste0("[", sc, "]"))
}

#' @export
vec_ptype_full.scale_member <- function(x, ...) {
  paste0("scale_member<", .tag_text(attr(x, "scale"), attr(x, "id"),
    attr(x, "frame")
  ), ">")
}

#' @noRd
.same_tag <- function(x, y) {
  identical(.id_hash(attr(x, "id")), .id_hash(attr(y, "id"))) &&
    identical(attr(x, "frame"), attr(y, "frame"))
}

#' @noRd
.ptype_like <- function(x) {
  .new_scale_member(
    scale = attr(x, "scale"), id = attr(x, "id"), frame = attr(x, "frame")
  )
}

#' @noRd
.tag_clash <- function(x, y) {
  sprintf(
    "The codes are on different scales or frames: %s and %s.",
    .tag_text(attr(x, "scale"), attr(x, "id"), attr(x, "frame")),
    .tag_text(attr(y, "scale"), attr(y, "id"), attr(y, "frame"))
  )
}

#' @method vec_ptype2 scale_member.scale_member
#' @export
vec_ptype2.scale_member.scale_member <- function(x, y, ..., x_arg = "",
                                             y_arg = "") {
  if (!.same_tag(x, y)) {
    vctrs::stop_incompatible_type(x, y,
      x_arg = x_arg, y_arg = y_arg, details = .tag_clash(x, y)
    )
  }
  .ptype_like(x)
}

#' @method vec_ptype2 scale_member.character
#' @export
vec_ptype2.scale_member.character <- function(x, y, ...) .ptype_like(x)

#' @method vec_ptype2 character.scale_member
#' @export
vec_ptype2.character.scale_member <- function(x, y, ...) .ptype_like(y)

#' @method vec_cast scale_member.scale_member
#' @export
vec_cast.scale_member.scale_member <- function(x, to, ..., x_arg = "",
                                           to_arg = "") {
  if (!.same_tag(x, to)) {
    vctrs::stop_incompatible_cast(x, to,
      x_arg = x_arg, to_arg = to_arg, details = .tag_clash(x, to)
    )
  }
  x
}

#' @method vec_cast scale_member.character
#' @export
vec_cast.scale_member.character <- function(x, to, ...) {
  .new_scale_member(x,
    scale = attr(to, "scale"), id = attr(to, "id"), frame = attr(to, "frame")
  )
}

#' @method vec_cast character.scale_member
#' @export
vec_cast.character.scale_member <- function(x, to, ...) vctrs::vec_data(x)

# Binding a table --------------------------------------------------------------

#' The bound columns of a table: column, scale, frame, id
#' @noRd
.scale_tags <- function(data) {
  empty <- data.frame(
    column = character(), scale = character(), frame = character(),
    id = character(), stringsAsFactors = FALSE
  )
  if (!is.data.frame(data)) {
    return(empty)
  }
  hit <- names(data)[vapply(data, .is_scale_member, logical(1))]
  if (length(hit) == 0L) {
    return(empty)
  }
  data.frame(
    column = hit,
    scale = vapply(hit, function(n) attr(data[[n]], "scale"), character(1)),
    frame = vapply(hit, function(n) attr(data[[n]], "frame"), character(1)),
    id = vapply(hit, function(n) attr(data[[n]], "id"), character(1)),
    stringsAsFactors = FALSE, row.names = NULL
  )
}

#' Replace one column, by reference on a data.table
#' @noRd
.set_col <- function(data, col, value) {
  if (inherits(data, "data.table") &&
    requireNamespace("data.table", quietly = TRUE)) {
    data <- data.table::copy(data)
    data.table::set(data, j = col, value = value)
    return(data)
  }
  data[[col]] <- value
  data
}

#' Bind a table to a scale
#'
#' @description
#' `r lifecycle::badge("experimental")`
#' This feature may change or be removed in a later version.
#'
#' Records, on the code columns themselves, which scale and which frame
#' their codes are on. A bound column is a [`scale_member`][as_scale_member()]
#' vector: it prints and behaves as a character vector, and keeps the link
#' through row subsetting, `mutate()`, grouping, joins and row binding.
#' The verbs ([`recast_scale()`], [`join_scale()`], the leaf routes) then
#' take the source frame from the link, stop when the data is bound to a
#' different scale, and bind their result.
#'
#' @details
#' The link is experimental and may change or be removed. It is an R
#' construct: converting a bound column to a factor or to a plain character
#' vector drops it, and other languages reading the same data do not see
#' it. Data that is not bound is matched to a scale by its codes alone.
#'
#' Every code is checked against the scale when binding; a code that is not a
#' member is an error. `scale_link()` reports what a table is bound to and
#' `unbind_scale()` returns the columns to plain character.
#'
#' A lazy table (arrow, dtplyr) cannot carry the link: collect it first, or
#' keep the link on disk with [`write_scale_dataset()`].
#'
#' @param data A `data.frame`, tibble or `data.table`; for `scale_link()`
#'   also a `scale_dataset` from [`open_scale_dataset()`].
#' @param x The [`NestedScale`] the codes belong to.
#' @param cols Which columns to bind. `NULL` (default) binds every column
#'   named after a frame of `x` (or after its leaf column). Otherwise a
#'   character
#'   vector of frame names, named by column where the column is called
#'   something else: `c(origin = "sector")`. For `unbind_scale()`, the
#'   columns to unbind; `NULL` for all bound columns.
#'
#' @return `bind_scale()` and `unbind_scale()` return `data`; `scale_link()`
#'   a `data.frame` with one row per bound column: `column`, `scale`,
#'   `frame`, `id`.
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(class = c("G1", "G2", "S1"), v = 1:3)
#' b <- bind_scale(d, s)
#' scale_link(b)
#'
#' # the source frame comes from the link, and the result is bound
#' out <- recast_scale(b, s, target = "sector", rule = "sum")
#' scale_link(out)
#'
#' # data bound to one scale is refused by another
#' try(recast_scale(b, scale_example2(), target = "sector", rule = "sum"))
#'
#' unbind_scale(b)$class
#' @seealso [`scale_id()`], [`as_scale_member()`]
#' @export
bind_scale <- function(data, x, cols = NULL) {
  .check_scale(x)
  backend <- backend_of(data, "data")
  if (backend_is_lazy(backend)) {
    .stop(paste0(
      "a lazy table cannot carry the link; collect it first, or ",
      "keep the link on disk with write_scale_dataset()"
    ))
  }
  v <- scale_vocab(x)
  if (is.null(cols)) {
    hit <- intersect(names(data), .nav_levels(x))
    if (length(hit) == 0L) {
      .stop(
        "the data has no column named after a %s of this %s (%s); pass `cols=`",
        v$frame, v$object, paste(.nav_levels(x), collapse = ", ")
      )
    }
    cols <- stats::setNames(hit, hit)
  } else {
    if (!is.character(cols) || anyNA(cols) || length(cols) == 0L) {
      .stop("`cols` must be a character vector of %s names", v$frame)
    }
    nm <- names(cols) %||% rep("", length(cols))
    nm[!nzchar(nm)] <- cols[!nzchar(nm)]
    cols <- stats::setNames(as.character(cols), nm)
  }
  absent <- setdiff(names(cols), names(data))
  if (length(absent) > 0L) {
    .stop("the data has no column(s): %s", .preview(absent))
  }
  sc <- .scale_name(x, require = FALSE)
  id <- scale_id(x)
  for (col in names(cols)) {
    frame <- cols[[col]]
    .check_frame(x, frame, "cols")
    codes <- as.character(data[[col]])
    strangers <- setdiff(unique(codes[!is.na(codes)]), scale_members(x, frame))
    if (length(strangers) > 0L) {
      .stop(
        "%d code(s) in the `%s` column are not %s at %s '%s': %s",
        length(strangers), col, v$members, v$frame, frame, .preview(strangers)
      )
    }
    data <- .set_col(data, col, .new_scale_member(codes,
      scale = sc, id = id, frame = frame
    ))
  }
  data
}

#' @rdname bind_scale
#' @export
unbind_scale <- function(data, cols = NULL) {
  tags <- .scale_tags(data)
  hit <- if (is.null(cols)) tags$column else intersect(cols, tags$column)
  for (col in hit) {
    data <- .set_col(data, col, vctrs::vec_data(data[[col]]))
  }
  data
}

#' @rdname bind_scale
#' @export
scale_link <- function(data) {
  if (inherits(data, "scale_dataset")) {
    return(.dataset_link(data))
  }
  .scale_tags(data)
}

#' The link of a stored dataset, from its manifest
#'
#' A store written before the link was recorded is keyed by the leaves of
#' each axis, one column per axis, which is what the fallback reports.
#' @noRd
.dataset_link <- function(ds) {
  manifest <- .read_manifest(ds$path)$manifest
  axes <- if (S7::S7_inherits(ds$scale, ScaleProduct)) {
    S7::prop(ds$scale, "axes")
  } else {
    stats::setNames(list(ds$scale), names(manifest$axes)[[1L]])
  }
  link <- manifest$link
  if (is.null(link)) {
    link <- lapply(names(axes), function(a) {
      list(
        column = manifest$keys[[a]], axis = a,
        frame = .leaf_frame(axes[[a]])
      )
    })
  }
  ax <- vapply(link, function(l) l$axis, character(1))
  data.frame(
    column = vapply(link, function(l) l$column, character(1)),
    scale = vapply(axes[ax], .scale_name, character(1), require = FALSE),
    frame = vapply(link, function(l) l$frame, character(1)),
    id = vapply(axes[ax], scale_id, character(1)),
    stringsAsFactors = FALSE, row.names = NULL
  )
}

# The verbs' side --------------------------------------------------------------

#' Read the link on entry to a verb
#'
#' Resolves `key` and `source` from the bound columns where the caller left
#' them open, refuses a code column bound to another scale, and hands the
#' engine plain character columns. Unbound data passes through untouched.
#' @noRd
.link_enter <- function(data, x, key = NULL, source = NULL, infer = TRUE) {
  tags <- .scale_tags(data)
  out <- list(data = data, key = key, source = source, tags = tags)
  if (nrow(tags) == 0L) {
    return(out)
  }
  id <- scale_id(x)
  sc <- .scale_name(x, require = FALSE)
  same <- .id_hash(tags$id) == .id_hash(id)
  mine <- tags[same, , drop = FALSE]

  # A column this scale would read as its own codes, bound to another scale.
  own_names <- unique(c(.nav_levels(x), .leaf_col(x), if (nzchar(sc)) sc))
  foreign <- tags[!same &
    tags$column %in% c(own_names, key), , drop = FALSE]
  if (nrow(foreign) > 0L) {
    .stop(
      "the `%s` column is bound to %s, not to %s",
      foreign$column[[1L]],
      .tag_text(foreign$scale[[1L]], foreign$id[[1L]]),
      .tag_text(sc, id)
    )
  }

  if (isTRUE(infer)) {
    if (is.null(key)) {
      cand <- if (is.null(source)) {
        mine
      } else {
        mine[mine$frame == source, , drop = FALSE]
      }
      if (nrow(cand) == 1L) {
        key <- cand$column
      } else if (nrow(cand) > 1L && is.null(source)) {
        .stop(
          "several columns are bound to this scale (%s); pass `key=`",
          .preview(cand$column)
        )
      }
    }
    if (!is.null(key) && key %in% mine$column) {
      bound <- mine$frame[match(key, mine$column)]
      if (is.null(source)) {
        source <- bound
      } else if (!identical(source, bound)) {
        .stop(
          "the `%s` column is bound to %s '%s', but '%s' was asked for",
          key, scale_vocab(x)$frame, bound, source
        )
      }
    }
  }
  out$data <- unbind_scale(data)
  out$key <- key
  out$source <- source
  out
}

#' Bind the result of a verb whose input was bound
#'
#' Columns that passed through keep the link they had; `new` (column ->
#' list(scale, frame)) binds what the verb produced.
#' @noRd
.link_exit <- function(out, link, new = list()) {
  tags <- link$tags
  if (nrow(tags) == 0L || !is.data.frame(out)) {
    return(out)
  }
  for (i in seq_len(nrow(tags))) {
    col <- tags$column[[i]]
    if (col %in% names(out) && !col %in% names(new) &&
      is.character(out[[col]])) {
      out <- .set_col(out, col, .new_scale_member(out[[col]],
        scale = tags$scale[[i]], id = tags$id[[i]], frame = tags$frame[[i]]
      ))
    }
  }
  for (col in names(new)) {
    if (col %in% names(out) && is.character(out[[col]])) {
      s <- new[[col]]$scale
      out <- .set_col(out, col, .new_scale_member(out[[col]],
        scale = .scale_name(s, require = FALSE), id = scale_id(s),
        frame = new[[col]]$frame
      ))
    }
  }
  out
}

#' The data link, for dimension packages
#'
#' The two halves of what every verb here does with bound data, kept as
#' functions so that verbs built on a subclass can read and write the link
#' the same way. `scale_link_enter()` resolves `key` and `source` from the
#' bound columns where the caller left them open, stops when a code column
#' is bound to another scale, and returns the data with plain character
#' columns. `scale_link_exit()` binds the result: columns that passed
#' through keep the link they had, and `new` names what the verb produced.
#' Unbound data passes through both untouched.
#'
#' @param data The verb's input table.
#' @param x The [`NestedScale`] the verb was given.
#' @param key,source The verb's own arguments: the code column and the frame
#'   its codes are at; `NULL` where the caller left them open.
#' @param infer Whether to resolve `key` and `source` from the link (`FALSE`
#'   only checks and unbinds).
#' @param out The verb's result.
#' @param link The value `scale_link_enter()` returned.
#' @param new A named list, one entry per result column to bind:
#'   `list(scale = <NestedScale>, frame = <frame name>)`, named by column.
#'
#' @return `scale_link_enter()` a list with `data`, `key`, `source` and
#'   `tags` (the link the data came with); `scale_link_exit()` the result.
#'
#' @examples
#' s <- scale_example()
#' b <- bind_scale(data.frame(class = c("G1", "S1"), v = 1:2), s)
#' link <- scale_link_enter(b, s)
#' link$key
#' link$source
#' is_scale_member(link$data$class)
#' @seealso [`bind_scale()`]
#' @noRd
scale_link_enter <- function(data, x, key = NULL, source = NULL,
                             infer = TRUE) {
  .check_scale(x)
  .link_enter(data, x, key = key, source = source, infer = infer)
}

#' @noRd
scale_link_exit <- function(out, link, new = list()) {
  .link_exit(out, link, new)
}
