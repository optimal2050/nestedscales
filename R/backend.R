# =============================================================================
# Backend handling for the conversion verbs
# =============================================================================
# The converters are written on dplyr verbs only, so the SAME pipeline runs on
# an in-memory data.frame/tibble, a data.table (through dtplyr), and an arrow
# Dataset/query. Contract:
#
#   data.frame  -> data.frame          (computed)
#   tibble      -> tibble              (computed)
#   data.table  -> data.table          (computed)
#   dtplyr/arrow (lazy) -> the UNCOLLECTED query, unless collect = TRUE
#
# The scale side of every join (crosswalks, atom attributes) is a small
# in-memory frame, so lazy inputs never have to be materialised for the scale
# arithmetic; only cheap aggregates are collected eagerly.
#
# Two discipline rules hold throughout the engine:
#   1. Bare `rlang::sym()`, never `.data[[...]]` -- dtplyr and arrow both
#      mistranslate pronoun subsetting where plain symbols work. Working
#      columns are declared in `utils::globalVariables()`.
#   2. Only cheap aggregates are pulled eagerly, via `backend_pull()`.
#
# The `backend_*` functions are the backend contract every binding exposes
# (see API.md), so the dimension packages built on this engine accept the same
# inputs as the core verbs and return results in the caller's type.
# =============================================================================

# dtplyr generates data.table syntax evaluated with THIS package as the calling
# namespace; without this flag data.table's cedta() check makes `[.data.table`
# fall through to `[.data.frame` and the joins break.
.datatable.aware <- TRUE

#' Which backend does `x` belong to, or `NA` when unsupported
#' @noRd
.backend_class <- function(x) {
  if (inherits(x, c(
    "arrow_dplyr_query", "ArrowObject", "Dataset",
    "ArrowTabular", "RecordBatchReader"
  ))) {
    return("arrow")
  }
  if (inherits(x, "dtplyr_step")) {
    return("dtplyr")
  }
  if (inherits(x, "data.table")) {
    return("data.table")
  }
  if (inherits(x, "tbl_df")) {
    return("tibble")
  }
  if (is.data.frame(x)) {
    return("data.frame")
  }
  NA_character_
}

#' Backends: the table types the verbs accept
#'
#' The conversion verbs run on a `data.frame`, a tibble, a `data.table`, a
#' dtplyr lazy table or an arrow Dataset/Table/query, and return results in
#' the caller's type; lazy inputs stay lazy unless collected. These functions
#' are that contract, exposed so a dimension package built on nestedscales
#' can accept the same inputs as the core verbs.
#'
#' * `backend_of()` names the backend of `data`, and errors on an unsupported
#'   input -- the one place that message is written.
#' * `backend_is_lazy()` says whether a backend produces queries.
#' * `backend_schema()` describes the columns without scanning the data.
#' * `backend_lazy()` lifts `data` into a dplyr-compatible carrier for a
#'   pipeline (a `data.table` becomes a dtplyr step when dtplyr is installed).
#' * `backend_scan()` reads the needed columns and rows into memory.
#' * `backend_distinct()` is the distinct rows of some columns, in
#'   first-appearance order, read into memory.
#' * `backend_pull()` materialises a query or table as a `data.frame`.
#' * `backend_restore()` returns a pipeline result in the caller's type.
#' * `backend_bind_rows()` binds chunk results into one frame.
#'
#' @param data A data object on any supported backend.
#' @param arg Argument name used in the error message.
#' @param backend A backend name from `backend_of()`; `NULL` resolves it from
#'   `data`.
#' @param columns Column names to read; `NULL` reads every column.
#' @param filter An unevaluated dplyr filter expression (built with
#'   `rlang::expr()`), or `NULL` for every row.
#' @param table A query or table.
#' @param collect Force materialisation of a lazy result.
#' @param parts List of data frames.
#' @param use_dt Use `data.table::rbindlist()`. Defaults to whether data.table
#'   is installed; an explicit value makes both branches testable.
#'
#' @return `backend_of()` a single string naming the backend;
#'   `backend_is_lazy()` a logical; `backend_schema()` a zero-row
#'   `data.frame`; `backend_lazy()` `data`, wrapped where the backend needs
#'   it; `backend_scan()`, `backend_distinct()` and `backend_pull()` a
#'   `data.frame`; `backend_restore()` the result in the input's class;
#'   `backend_bind_rows()` one data frame, or `NULL` when every part is
#'   empty.
#'
#' @examples
#' d <- data.frame(unit = c("U1", "U2", "U2"), v = 1:3)
#' backend_of(d)
#' backend_is_lazy(backend_of(d))
#' backend_schema(d)
#' backend_distinct(d, "unit")
#' backend_scan(d, columns = "v", filter = rlang::expr(v > 1))
#' @name backend
NULL

#' @rdname backend
#' @export
backend_of <- function(data, arg = "data") {
  backend <- .backend_class(data)
  if (is.na(backend)) {
    .stop(paste0(
      "`%s` must be a data.frame, tibble, data.table, dtplyr step ",
      "or arrow table/query"
    ), arg)
  }
  backend
}

#' @rdname backend
#' @export
backend_is_lazy <- function(backend) backend %in% c("arrow", "dtplyr")

#' @rdname backend
#' @export
backend_schema <- function(data, backend = NULL) {
  as.data.frame(dplyr::collect(utils::head(data, 0L)))
}

#' @rdname backend
#' @export
backend_lazy <- function(data, backend = NULL) {
  if (is.null(backend)) backend <- backend_of(data)
  if (backend == "data.table") {
    if (!requireNamespace("dtplyr", quietly = TRUE)) {
      # dplyr verbs work on a bare data.table too (it is a data.frame);
      # dtplyr just makes them translate to data.table code
      return(data)
    }
    return(dtplyr::lazy_dt(data))
  }
  data
}

#' @rdname backend
#' @export
backend_scan <- function(data, backend = NULL, columns = NULL, filter = NULL) {
  if (is.null(backend)) backend <- backend_of(data)
  q <- backend_lazy(data, backend)
  if (!is.null(filter)) q <- dplyr::filter(q, !!filter)
  if (!is.null(columns)) q <- dplyr::select(q, dplyr::all_of(columns))
  backend_pull(q)
}

#' @rdname backend
#' @export
backend_distinct <- function(data, columns, backend = NULL) {
  if (is.null(backend)) backend <- backend_of(data)
  backend_pull(dplyr::distinct(dplyr::select(
    backend_lazy(data, backend), dplyr::all_of(columns)
  )))
}

#' @rdname backend
#' @export
backend_pull <- function(table) {
  as.data.frame(dplyr::collect(table))
}

#' @rdname backend
#' @export
backend_restore <- function(table, backend, collect = NULL) {
  lazy <- backend_is_lazy(backend)
  if (lazy && !isTRUE(collect)) {
    return(table)
  }
  res <- dplyr::collect(table)
  switch(backend,
    "data.table" = if (requireNamespace("data.table", quietly = TRUE)) {
      data.table::as.data.table(res)
    } else {
      as.data.frame(res)
    },
    "tibble" = if (requireNamespace("tibble", quietly = TRUE)) {
      tibble::as_tibble(res)
    } else {
      as.data.frame(res)
    },
    "arrow" = res,
    "dtplyr" = if (requireNamespace("data.table", quietly = TRUE)) {
      data.table::as.data.table(res)
    } else {
      as.data.frame(res)
    },
    as.data.frame(res)
  )
}

#' @rdname backend
#' @export
backend_bind_rows <- function(parts,
                              use_dt = requireNamespace("data.table",
                                quietly = TRUE
                              )) {
  # Chunks come out of the same `summarise()`, so their schemas match by
  # construction. `fill = FALSE` is deliberate: a mismatch means something is
  # wrong upstream and should be an error, not a silently widened frame.
  parts <- Filter(function(p) !is.null(p) && nrow(p) > 0L, parts)
  if (length(parts) == 0L) {
    return(NULL)
  }
  if (length(parts) == 1L) {
    return(as.data.frame(parts[[1L]]))
  }
  if (isTRUE(use_dt)) {
    return(as.data.frame(
      data.table::rbindlist(parts, use.names = TRUE, fill = FALSE)
    ))
  }
  as.data.frame(dplyr::bind_rows(parts))
}

#' Split a set of values into chunks of at most `size`
#' @noRd
.backend_chunks <- function(values, size) {
  n <- length(values)
  if (n == 0L) {
    return(list())
  }
  size <- max(1L, as.integer(size))
  split(values, ceiling(seq_len(n) / size))
}
