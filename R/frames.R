# =============================================================================
# Frame vocabulary
# =============================================================================
# A *frame* is one resolution of a scale -- the dimension-agnostic word for a
# `timescales` timeframe or a `geoscales` geoframe. Names are validated for
# syntax only: any name usable as a data.frame column is accepted, so existing
# tables load unchanged whatever their conventions.
# =============================================================================

#' Validate frame names
#'
#' A frame name must be a non-empty, non-`NA` string that is a syntactically
#' valid R name (so it can be used as a data.frame column without quoting).
#'
#' @param x Character vector of candidate frame names.
#'
#' @return A logical vector the same length as `x`.
#'
#' @examples
#' is_valid_frame(c("industry", "reg32", "", "2bad"))
#' @export
is_valid_frame <- function(x) {
  if (!is.character(x)) {
    return(rep(FALSE, length(x)))
  }
  ok <- !is.na(x) & nzchar(x)
  ok[ok] <- make.names(x[ok]) == x[ok]
  ok
}

#' Reserved column names in a leaftable
#'
#' Column names that carry a fixed meaning and therefore cannot be used as
#' frame names. The leaf column (`x@leaf`, default `"leaf"`) is reserved in
#' addition to these, except as the name of the FINEST frame -- there the frame
#' column *is* the leaf column, so nothing collides.
#'
#' @noRd
.RESERVED_COLS <- c("share", ".weight", ".order")
