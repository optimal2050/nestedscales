# =============================================================================
# Internal utilities
# =============================================================================

#' Null-coalescing operator
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Blank-or-NA to NA
#'
#' Real-world scale tables use `""` and `NA` interchangeably for "this atom has
#' no code at this frame" (a rest-of-world row, an unclassified industry).
#' Normalise both to `NA_character_` on the way in.
#' @noRd
.blank_to_na <- function(x) {
  x <- as.character(x)
  x[!is.na(x) & trimws(x) == ""] <- NA_character_
  x
}

#' Stop with a formatted message and no call context
#' @noRd
.stop <- function(...) stop(sprintf(...), call. = FALSE)

#' Warn with a formatted message and no call context
#' @noRd
.warn <- function(...) warning(sprintf(...), call. = FALSE)

#' Name of a NestedScale (meta$name), required for conversion and attach
#'
#' The crosswalk's label columns and `join_scale()`'s attached columns are
#' named after the object, so those operations need a non-empty name.
#' @noRd
.scale_name <- function(x, require = TRUE, arg = "x") {
  nm <- S7::prop(x, "meta")[["name"]] %||% ""
  if (require && (!is.character(nm) || length(nm) != 1L || is.na(nm) ||
    !nzchar(nm))) {
    .stop(paste0(
      "`%s` has no name; conversion and attach need a named ",
      "scale -- set meta$name, or pass `name=` to ",
      "scale_from_leaftable()"
    ), arg)
  }
  nm
}

#' Truncated comma-separated preview of a vector
#' @noRd
.preview <- function(x, n = 3L) {
  x <- as.character(x)
  if (length(x) <= n) {
    return(paste(x, collapse = ", "))
  }
  sprintf(
    "%s, ... (%d total)", paste(utils::head(x, n), collapse = ", "),
    length(x)
  )
}

#' Build the unit-by-feature matrix a clustering works on
#'
#' Data arrives long, keyed by a scale's units: one column identifies the
#' unit, the remaining identifier columns say WHICH observation it is (a
#' timeslice, an hour, a variable), and one column carries the value. Rows of
#' the matrix are units; columns are the observations they are compared over.
#'
#' A unit missing an observation the others have leaves a hole, and every
#' distance here would silently treat that hole as something. It is an error
#' instead, with the offending units named.
#'
#' @param data Long data frame.
#' @param key Column naming the unit.
#' @param value Value column; inferred when there is exactly one numeric
#'   non-key, non-identifier column.
#' @param units Units to include, in the order the rows should take.
#' @return A numeric matrix with `units` as rownames.
#' @noRd
.feature_matrix <- function(data, key, value = NULL, units = NULL) {
  data <- as.data.frame(data)
  if (!key %in% names(data)) {
    .stop("the data has no `%s` column", key)
  }
  id_cols <- setdiff(names(data), key)
  if (is.null(value)) {
    num <- id_cols[vapply(data[id_cols], is.numeric, logical(1))]
    if (length(num) != 1L) {
      .stop(
        paste0(
          "cannot infer the value column (numeric columns: %s); ",
          "pass `value=`"
        ),
        if (length(num) == 0L) "none" else .preview(num)
      )
    }
    value <- num
  }
  if (!value %in% names(data)) {
    .stop("`value` column `%s` is not in the data", value)
  }
  feat <- setdiff(names(data), c(key, value))
  if (length(feat) == 0L) {
    .stop(paste0(
      "the data has no identifier column to compare units over; ",
      "clustering needs each unit observed across something"
    ))
  }

  u <- as.character(data[[key]])
  f <- do.call(paste, c(lapply(data[feat], as.character), sep = "\r"))
  if (is.null(units)) units <- unique(u)
  fl <- unique(f)

  ui <- match(u, units)
  fi <- match(f, fl)
  keep <- !is.na(ui)
  if (!all(keep)) {
    ui <- ui[keep]
    fi <- fi[keep]
  }

  m <- matrix(NA_real_,
    nrow = length(units), ncol = length(fl),
    dimnames = list(units, NULL)
  )
  m[cbind(ui, fi)] <- as.numeric(data[[value]])[keep]

  gaps <- rownames(m)[!stats::complete.cases(m)]
  if (length(gaps) > 0L) {
    .stop(
      paste0(
        "%d unit(s) are not observed over every one of the %d ",
        "feature combinations (%s). Every distance would read those ",
        "holes as something; fill or drop them first."
      ),
      length(gaps), length(fl), .preview(gaps)
    )
  }
  m
}

#' A single non-empty string?
#' @noRd
.is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}
