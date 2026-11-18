# =============================================================================
# str() -- the structure of a scale, one line per property
# =============================================================================

#' @include scale-class.R
NULL

.PROP_ROLES <- c(
  leaftable  = "one row per atom: key, frame codes, weights",
  frames     = "frame names, coarsest first",
  members    = "the codes at each frame",
  key        = "name of the atom key column",
  meta       = "name, description, weights, bookkeeping",
  attributes = "member values, by (frame, unit)",
  aliases    = "alternative spellings, by (frame, unit)",
  labels     = "display names, by (frame, unit, variant)"
)

#' @noRd
.prop_shape <- function(v) {
  if (is.null(v)) {
    return("NULL")
  }
  if (is.data.frame(v)) {
    return(sprintf("data.frame [%d x %d]", nrow(v), ncol(v)))
  }
  if (is.character(v)) {
    return(sprintf("chr [%d]", length(v)))
  }
  if (is.list(v) && !is.object(v)) {
    return(sprintf("list [%d]", length(v)))
  }
  sprintf("%s [%d]", class(v)[[1L]], length(v))
}

#' @noRd
.prop_detail <- function(name, v) {
  if (is.character(v) && !is.object(v)) {
    return(.preview(v, 6L))
  }
  if (is.data.frame(v) || (is.list(v) && !is.object(v))) {
    if (!is.null(names(v)) && length(v) > 0L) {
      return(.preview(names(v), 8L))
    }
  }
  ""
}

#' Show the structure of a scale
#'
#' Lists the properties of the object, one per line: what kind of value each
#' holds, its size, and what it is for. Properties a subclass adds are
#' listed after the core ones. The properties themselves are read with `@`
#' or `S7::prop()`; `S7::prop_names()` gives their names.
#'
#' @param object A [`NestedScale`].
#' @param ... Ignored.
#' @return `object`, invisibly.
#' @examples
#' str(scale_example())
#' S7::prop_names(scale_example())
#' @method str NestedScale
str.NestedScale <- function(object, ...) {
  cls <- attr(object, "S7_class", exact = TRUE)
  props <- names(cls@properties)
  # A property that only renames another (`timeframes` for `frames`) is the
  # same value twice; show it once, under the core name.
  core <- intersect(names(.PROP_ROLES), props)
  extra <- setdiff(props, core)
  vals <- lapply(props, function(p) {
    tryCatch(S7::prop(object, p), error = function(e) NULL)
  })
  names(vals) <- props
  same_as <- vapply(extra, function(p) {
    hit <- core[vapply(core, function(k) identical(vals[[p]], vals[[k]]),
                       logical(1))]
    if (length(hit) > 0L && is.character(vals[[p]])) hit[[1L]] else ""
  }, character(1))

  cat("<", class(object)[[1L]], "> ", scale_id(object), "\n", sep = "")
  w <- max(nchar(props))
  line <- function(p, role) {
    detail <- .prop_detail(p, vals[[p]])
    cat(" @ ", format(p, width = w), " : ",
      format(.prop_shape(vals[[p]]), width = 20), " ", role,
      if (nzchar(detail)) paste0("\n", strrep(" ", w + 6L), detail),
      "\n",
      sep = ""
    )
  }
  for (p in core) line(p, .PROP_ROLES[[p]])
  for (p in extra) {
    line(p, if (nzchar(same_as[[p]])) {
      paste0("another name for @", same_as[[p]])
    } else {
      "added by the subclass"
    })
  }
  invisible(object)
}

#' @rdname str.NestedScale
#' @export
`str.nestedscales::NestedScale` <- str.NestedScale
