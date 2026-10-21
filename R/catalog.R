# =============================================================================
# The catalogue of shipped scale definitions
# =============================================================================
# A package ships definitions as files under `inst/scales/` (one `.json` or
# `.yaml` per scale, or one `<id>.scale/` bundle each) and registers that
# directory in its `.onLoad()`. `scale_catalog()` lists every definition the
# registered directories hold, reading headers only, and `read_scale(id)`
# resolves an id through it.
# =============================================================================

#' @include definition.R
NULL

#' @noRd
.SCALE_DIRS <- new.env(parent = emptyenv())

#' Shipped scale definitions
#'
#' Packages ship scale definitions as files (see [`write_scale()`]) and
#' register the directory holding them; `scale_catalog()` lists what every
#' registered directory holds and [`read_scale()`] takes an id from it.
#' nestedscales registers its own `inst/scales/` on load, so
#' `read_scale("carriers")` works with nothing else attached.
#'
#' `register_scale_dir()` is what a dimension package calls in its
#' `.onLoad()`: `register_scale_dir(system.file("scales", package =
#' pkgname), package = pkgname)`.
#'
#' @param path A directory of definition files or bundles.
#' @param package The package registering it; `NULL` for a directory
#'   registered by hand (listed under `package = NA`).
#'
#' @return `scale_catalog()` a `data.frame` with one row per definition:
#'   `id`, `name`, `kind` (the class, without its package prefix), `key`,
#'   `frames` (joined by `/`), `n_atoms`, `package`, `path`.
#'   `register_scale_dir()` the registry key, invisibly; `list_scale_dirs()`
#'   a `data.frame` with `package` and `path`; `clear_scale_dirs()` `NULL`,
#'   invisibly.
#'
#' @examples
#' scale_catalog()
#' @name scale_catalog
NULL

#' @rdname scale_catalog
#' @export
register_scale_dir <- function(path, package = NULL) {
  if (!.is_string(path)) .stop("`path` must be a single string")
  if (!dir.exists(path)) .stop("`%s` is not a directory", path)
  if (!is.null(package) && !.is_string(package)) {
    .stop("`package` must be a single string or NULL")
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  key <- package %||% path
  assign(key, list(package = package, path = path), envir = .SCALE_DIRS)
  invisible(key)
}

#' @rdname scale_catalog
#' @export
list_scale_dirs <- function() {
  keys <- sort(ls(envir = .SCALE_DIRS, all.names = TRUE))
  entries <- lapply(keys, function(k) get(k, envir = .SCALE_DIRS))
  data.frame(
    package = vapply(entries, function(e) e$package %||% NA_character_,
                     character(1)),
    path = vapply(entries, function(e) e$path, character(1)),
    stringsAsFactors = FALSE
  )
}

#' @rdname scale_catalog
#' @export
clear_scale_dirs <- function() {
  rm(list = ls(envir = .SCALE_DIRS, all.names = TRUE), envir = .SCALE_DIRS)
  invisible(NULL)
}

#' The definitions one directory holds: id and header file
#' @noRd
.dir_definitions <- function(path) {
  entries <- list.files(path, full.names = TRUE)
  rows <- lapply(entries, function(e) {
    if (dir.exists(e)) {
      hdr <- intersect(
        c("scale.json", "scale.yaml", "scale.yml"), list.files(e)
      )
      if (length(hdr) == 0L) {
        return(NULL)
      }
      return(data.frame(
        id = sub("\\.scale$", "", basename(e)),
        file = file.path(e, hdr[[1L]]), stringsAsFactors = FALSE
      ))
    }
    ext <- tolower(tools::file_ext(e))
    if (!ext %in% c("json", "yaml", "yml")) {
      return(NULL)
    }
    data.frame(
      id = tools::file_path_sans_ext(basename(e)), file = e,
      stringsAsFactors = FALSE
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) {
    return(data.frame(id = character(), file = character(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' Atom count of a definition from its header alone where possible
#' @noRd
.header_n_atoms <- function(hdr, dir) {
  ref <- hdr$tables$leaftable
  if (is.null(ref)) {
    return(NA_integer_)
  }
  if (!is.null(ref$inline)) {
    cols <- ref$inline$columns
    if (length(cols) == 0L) {
      return(0L)
    }
    return(length(.as_list(cols[[1L]])))
  }
  n <- tryCatch(nrow(.table_from_ref(ref, dir, "leaftable")),
                error = function(e) NA_integer_)
  as.integer(n)
}

#' @rdname scale_catalog
#' @export
scale_catalog <- function() {
  dirs <- list_scale_dirs()
  empty <- data.frame(
    id = character(), name = character(), kind = character(),
    key = character(), frames = character(), n_atoms = integer(),
    package = character(), path = character(), stringsAsFactors = FALSE
  )
  if (nrow(dirs) == 0L) {
    return(empty)
  }
  rows <- list()
  for (i in seq_len(nrow(dirs))) {
    defs <- .dir_definitions(dirs$path[i])
    for (j in seq_len(nrow(defs))) {
      hdr <- tryCatch(.read_header(defs$file[j]), error = function(e) NULL)
      if (is.null(hdr)) next
      frames <- as.character(unlist(.as_list(hdr$frames)))
      cls <- hdr$class %||% "nestedscales::NestedScale"
      rows[[length(rows) + 1L]] <- data.frame(
        id = defs$id[j],
        name = hdr$name %||% NA_character_,
        kind = sub("^.*::", "", cls),
        key = hdr$key %||% "unit",
        frames = paste(frames, collapse = "/"),
        n_atoms = .header_n_atoms(hdr, dirname(defs$file[j])),
        package = dirs$package[i],
        path = defs$file[j],
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) {
    return(empty)
  }
  out <- do.call(rbind, rows)
  out <- out[order(out$id, out$package), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The header file of a catalogue id
#' @noRd
.resolve_scale_id <- function(id, package = NULL) {
  cat <- scale_catalog()
  hit <- cat[cat$id == id, , drop = FALSE]
  if (!is.null(package)) {
    hit <- hit[!is.na(hit$package) & hit$package == package, , drop = FALSE]
  }
  if (nrow(hit) == 0L) {
    .stop(
      "`%s` is neither a file nor a definition in the catalogue (ids: %s)",
      id, if (nrow(cat)) .preview(unique(cat$id), 6L) else "<none>"
    )
  }
  if (nrow(hit) > 1L) {
    .stop(
      "`%s` is shipped by several packages (%s); pass `package=`",
      id, paste(hit$package, collapse = ", ")
    )
  }
  hit$path[[1L]]
}
