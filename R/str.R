# =============================================================================
# str() -- the structure of a scale, as the tree of scale_tree()
# =============================================================================

#' @include scale-class.R
NULL

.PROP_ROLES <- c(
  leaftable  = "one row per leaf: leaf column, frame codes, weights",
  frames     = "frame names, coarsest first",
  members    = "the codes at each frame",
  leaf       = "name of the leaf column",
  meta       = "name, description, weights, bookkeeping",
  attributes = "member values, by (frame, member)",
  aliases    = "alternative spellings, by (frame, member)",
  labels     = "display names, by (frame, member, variant)"
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

#' Show the structure of a scale
#'
#' Prints the tree of [`scale_tree()`]: the properties of the object, the
#' columns of its leaftable and what a subclass adds, each with its size and
#' whether it is fixed, derived or mutable. The properties themselves are
#' read with `@` or `S7::prop()`; `S7::prop_names()` gives their names.
#'
#' @param object A [`NestedScale`] or a [`ScaleProduct`].
#' @param ... Passed to the print method of [`scale_tree()`].
#' @return `object`, invisibly.
#' @seealso [`scale_tree()`]
#' @examples
#' str(scale_example())
#' S7::prop_names(scale_example())
#' @method str NestedScale
str.NestedScale <- function(object, ...) {
  print(scale_tree(object), ...)
  invisible(object)
}

#' @rdname str.NestedScale
#' @export
`str.nestedscales::NestedScale` <- str.NestedScale

#' @rdname str.NestedScale
#' @export
`str.nestedscales::ScaleProduct` <- str.NestedScale
