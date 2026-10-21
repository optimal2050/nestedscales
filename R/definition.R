# =============================================================================
# Scale definition files -- a scale as a language-neutral bundle
# =============================================================================
# A definition is a HEADER plus TABLES. The header (JSON; YAML accepted on the
# way in and offered on the way out) says what the scale is: its class, key,
# frames, members, meta, and where each table lives. A table is either INLINE
# in the header (column-wise, with a type per column, the encoding the
# cross-language goldens already use) or a FILE next to it (Arrow IPC, or CSV
# with the types recorded so it reads back typed).
#
#   <name>.json                 one file, every table inline  (small scales)
#   <name>.scale/               a bundle
#     scale.json                the header
#     leaftable.arrow           tables that were not inlined
#     attributes.arrow, aliases.arrow
#     <payload files>           whatever a dimension package adds
#
# Python, Julia and C++ read the same bytes with a JSON parser and Arrow. A
# dimension package adds its own payload (geometry, say) through two hooks,
# `scale_write_payload()` and `scale_read_payload()`, and registers its class
# with `register_scale_class()` so `read_scale()` can give the subclass back.
# =============================================================================

#' @include scale-class.R
#' @include attributes.R
#' @include aliases.R
NULL

.SCHEMA_VERSION <- 1L
.INLINE_MAX_ROWS <- 1000L
.COL_TYPES <- c("string", "double", "integer", "logical")

# -----------------------------------------------------------------------------
# Tables
# -----------------------------------------------------------------------------

#' The type code of a column
#' @noRd
.col_type <- function(v, name) {
  if (is.factor(v) || is.character(v)) {
    return("string")
  }
  if (is.logical(v)) {
    return("logical")
  }
  if (is.integer(v)) {
    return("integer")
  }
  if (is.numeric(v)) {
    return("double")
  }
  .stop("column `%s` is of class %s, which a definition cannot hold",
        name, class(v)[[1L]])
}

#' Column-wise encoding of a table (the goldens' `{columns, types}` shape)
#' @noRd
.table_inline <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  types <- vapply(names(df), function(n) .col_type(df[[n]], n), character(1))
  cols <- lapply(names(df), function(n) {
    v <- df[[n]]
    if (is.factor(v)) v <- as.character(v)
    I(v)
  })
  names(cols) <- names(df)
  list(columns = cols, types = as.list(types))
}

#' One column back from its encoded values and type
#' @noRd
.col_decode <- function(vals, type) {
  if (!type %in% .COL_TYPES) .stop("unknown column type \"%s\"", type)
  vals <- lapply(.as_list(vals), function(z) if (is.null(z)) NA else z)
  v <- unlist(vals, use.names = FALSE)
  if (length(vals) == 0L) {
    v <- switch(type,
      string = character(), double = numeric(),
      integer = integer(), logical = logical()
    )
  }
  switch(type,
    string = as.character(v),
    double = as.numeric(v),
    integer = as.integer(v),
    logical = as.logical(v)
  )
}

#' A parsed sequence as a list, whatever the parser made of it: a YAML
#' reader gives a length-1 sequence back as a scalar
#' @noRd
.as_list <- function(z) {
  if (is.null(z)) {
    return(list())
  }
  if (is.list(z)) z else as.list(z)
}

#' @noRd
.table_from_inline <- function(enc) {
  cols <- enc$columns
  types <- enc$types
  if (is.null(cols) || is.null(types)) {
    .stop("an inline table needs `columns` and `types`")
  }
  out <- lapply(names(cols), function(n) {
    ty <- types[[n]]
    if (is.null(ty)) .stop("inline table: column `%s` has no type", n)
    .col_decode(cols[[n]], ty)
  })
  names(out) <- names(cols)
  if (length(out) == 0L) {
    return(data.frame())
  }
  as.data.frame(out, stringsAsFactors = FALSE)
}

#' Write one table as a file next to the header; returns its reference
#' @noRd
.table_to_file <- function(df, dir, stem, mode) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  for (n in names(df)) if (is.factor(df[[n]])) df[[n]] <- as.character(df[[n]])
  if (mode == "arrow") {
    .need_arrow("write_scale(tables = \"arrow\")")
    file <- paste0(stem, ".arrow")
    arrow::write_feather(arrow::as_arrow_table(df), file.path(dir, file),
      compression = "uncompressed"
    )
    return(list(file = file, format = "arrow"))
  }
  file <- paste0(stem, ".csv")
  utils::write.csv(df, file.path(dir, file), row.names = FALSE, na = "")
  types <- vapply(names(df), function(n) .col_type(df[[n]], n), character(1))
  list(file = file, format = "csv", types = as.list(types))
}

#' Read a table from its reference (inline or file)
#' @noRd
.table_from_ref <- function(ref, dir, what) {
  if (!is.null(ref$inline)) {
    return(.table_from_inline(ref$inline))
  }
  if (is.null(ref$file)) {
    .stop("the `%s` table has neither `inline` data nor a `file`", what)
  }
  if (is.null(dir)) {
    .stop("the `%s` table refers to a file, but the definition is a single file",
          what)
  }
  path <- file.path(dir, ref$file)
  if (!file.exists(path)) {
    .stop("the `%s` table's file is missing: %s", what, path)
  }
  fmt <- ref$format %||% tools::file_ext(ref$file)
  if (identical(fmt, "arrow")) {
    .need_arrow("read_scale()")
    df <- as.data.frame(arrow::read_feather(path))
    for (n in names(df)) if (is.factor(df[[n]])) df[[n]] <- as.character(df[[n]])
    return(df)
  }
  if (identical(fmt, "csv")) {
    types <- ref$types
    cls <- if (is.null(types)) {
      NA
    } else {
      vapply(unlist(types), function(t) switch(t,
        string = "character", double = "numeric", integer = "integer",
        logical = "logical", "character"
      ), character(1))
    }
    df <- utils::read.csv(path,
      stringsAsFactors = FALSE, colClasses = cls,
      na.strings = "", check.names = FALSE
    )
    return(df)
  }
  .stop("unknown table format \"%s\" for `%s`", fmt, what)
}

# -----------------------------------------------------------------------------
# Meta
# -----------------------------------------------------------------------------

#' Encode `meta` for a header
#'
#' Scalars stay scalars, vectors become arrays, a NAMED atomic vector becomes
#' an object and is listed in `vectors` (an object is otherwise a list, and
#' nothing in JSON tells the two apart), a data.frame becomes `{"_table":
#' {columns, types}}`, lists recurse. Anything else (a function, an sf CRS)
#' is refused by name before any file is written.
#' @noRd
.meta_encode <- function(meta, nm = "") {
  vectors <- character()
  enc <- function(z, path) {
    if (is.null(z)) {
      return(NULL)
    }
    if (is.data.frame(z)) {
      return(list(`_table` = .table_inline(z)))
    }
    if (is.factor(z)) z <- as.character(z)
    if (is.atomic(z)) {
      if (!is.character(z) && !is.numeric(z) && !is.logical(z)) {
        .stop("the `meta` of \"%s\" holds a value that cannot be written: %s",
              nm, path)
      }
      if (!is.null(names(z))) {
        if (length(path) == 1L) vectors <<- c(vectors, path)
        return(as.list(z))
      }
      if (length(z) == 1L) {
        return(z)
      }
      return(I(unname(z)))
    }
    if (is.list(z)) {
      out <- lapply(seq_along(z), function(i) {
        enc(z[[i]], c(path, if (!is.null(names(z))) names(z)[i] else i))
      })
      names(out) <- names(z)
      if (is.null(names(z))) {
        return(out)
      }
      if (length(out) == 0L) {
        return(structure(list(), names = character()))
      }
      return(out)
    }
    .stop("the `meta` of \"%s\" holds a value that cannot be written: %s",
          nm, paste(path, collapse = "$"))
  }
  if (length(meta) == 0L) {
    return(list(values = structure(list(), names = character()),
                vectors = character()))
  }
  if (is.null(names(meta))) .stop("`meta` must be a named list")
  values <- lapply(names(meta), function(n) enc(meta[[n]], n))
  names(values) <- names(meta)
  list(values = values, vectors = vectors)
}

#' Decode a header's `meta`
#' @noRd
.meta_decode <- function(values, vectors = character()) {
  dec <- function(z, top) {
    if (is.null(z)) {
      return(NULL)
    }
    if (is.list(z)) {
      nms <- names(z)
      if (!is.null(nms) && identical(nms, "_table")) {
        return(.table_from_inline(z[["_table"]]))
      }
      if (!is.null(nms) && !is.null(top) && top %in% vectors) {
        v <- unlist(lapply(z, function(y) if (is.null(y)) NA else y))
        names(v) <- nms
        return(v)
      }
      if (is.null(nms)) {
        # an empty array carries no type; the vectors that can be empty
        # (`weights`) are character
        if (length(z) == 0L) {
          return(character())
        }
        parts <- lapply(z, function(y) if (is.null(y)) NA else y)
        if (all(vapply(parts, function(p) is.atomic(p) && length(p) == 1L,
                       logical(1)))) {
          return(unlist(parts, use.names = FALSE))
        }
        return(lapply(parts, dec, top = NULL))
      }
      out <- lapply(z, dec, top = NULL)
      names(out) <- nms
      return(out)
    }
    z
  }
  if (length(values) == 0L) {
    return(list())
  }
  out <- lapply(names(values), function(n) dec(values[[n]], n))
  names(out) <- names(values)
  out
}

# -----------------------------------------------------------------------------
# Header
# -----------------------------------------------------------------------------

#' The header of a scale, with the three core tables as references
#' @noRd
.scale_header <- function(x, tables) {
  nm <- .scale_name(x, require = FALSE)
  members <- S7::prop(x, "members")
  m <- .meta_encode(S7::prop(x, "meta"), nm)
  hdr <- list(
    schema_version = .SCHEMA_VERSION,
    nestedscales = as.character(utils::packageVersion("nestedscales")),
    class = class(x)[[1L]],
    name = if (nzchar(nm)) nm else NULL,
    key = scale_key(x),
    frames = I(scale_frames(x)),
    members = lapply(members, I),
    meta = m$values,
    tables = tables,
    payload = structure(list(), names = character())
  )
  if (length(m$vectors) > 0L) hdr$meta_vectors <- I(m$vectors)
  hdr
}

#' Rebuild the CORE scale from a header and the directory its files are in
#' @noRd
.scale_from_header <- function(hdr, dir) {
  sv <- hdr$schema_version
  if (is.null(sv) || !is.numeric(sv) || sv > .SCHEMA_VERSION) {
    .stop(
      "this definition has schema_version %s; this version of nestedscales reads up to %d",
      if (is.null(sv)) "<none>" else as.character(sv), .SCHEMA_VERSION
    )
  }
  tables <- hdr$tables %||% list()
  if (is.null(tables$leaftable)) .stop("the definition has no `leaftable`")
  leaftable <- .table_from_ref(tables$leaftable, dir, "leaftable")
  at <- if (is.null(tables$attributes)) {
    NULL
  } else {
    .as_attributes(.table_from_ref(tables$attributes, dir, "attributes"))
  }
  al <- if (is.null(tables$aliases)) {
    NULL
  } else {
    .as_aliases(.table_from_ref(tables$aliases, dir, "aliases"))
  }
  members <- lapply(hdr$members, function(z) as.character(unlist(.as_list(z))))
  frames <- as.character(unlist(.as_list(hdr$frames)))
  meta <- .meta_decode(hdr$meta %||% list(),
    as.character(unlist(.as_list(hdr$meta_vectors)))
  )
  if (!is.null(hdr$name) && is.null(meta[["name"]])) meta$name <- hdr$name
  NestedScale(
    leaftable = leaftable, frames = frames, members = members,
    key = hdr$key %||% "unit", meta = meta, attributes = at, aliases = al
  )
}

#' Strip the `I()` markers (needed by jsonlite) before handing to yaml
#' @noRd
.strip_asis <- function(z) {
  if (inherits(z, "AsIs")) z <- unclass(z)
  if (is.list(z)) {
    out <- lapply(z, .strip_asis)
    names(out) <- names(z)
    return(out)
  }
  z
}

#' @noRd
.write_header <- function(hdr, file, format) {
  if (format == "json") {
    txt <- jsonlite::toJSON(hdr,
      auto_unbox = TRUE, null = "null", na = "null",
      digits = NA, pretty = 2
    )
    writeLines(txt, file, useBytes = TRUE)
  } else {
    .need_yaml("write_scale(format = \"yaml\")")
    yaml::write_yaml(.strip_asis(hdr), file)
  }
  invisible(file)
}

#' @noRd
.read_header <- function(file) {
  ext <- tolower(tools::file_ext(file))
  if (ext == "json") {
    return(jsonlite::fromJSON(file, simplifyVector = FALSE))
  }
  if (ext %in% c("yaml", "yml")) {
    .need_yaml("read_scale() on a YAML header")
    return(yaml::read_yaml(file))
  }
  .stop("`%s` is not a .json, .yaml or .yml header", file)
}

# -----------------------------------------------------------------------------
# Payload hooks and the class registry
# -----------------------------------------------------------------------------

#' Write and read a subclass's payload in a definition file
#'
#' The seam a dimension package uses to carry what the core does not know
#' about -- `geoscales`' geometry -- in a scale definition written by
#' [`write_scale()`] and read by [`read_scale()`].
#'
#' `scale_write_payload(x, dir, header)` is called after the core tables are
#' written, with the bundle directory (`NULL` for a single-file definition,
#' which can hold inline data only) and the header so far; it writes its
#' files and returns the header with its entries added under `payload`.
#' `scale_read_payload(x, dir, header)` is called with the CORE scale rebuilt
#' from the header and returns the subclass object. The `NestedScale`
#' defaults return the header and `x` unchanged.
#'
#' `read_scale()` finds the method through the class recorded in the
#' header, so a dimension package registers its class once, in `.onLoad()`,
#' with `register_scale_class()`.
#'
#' @param x A [`NestedScale`] (the subclass instance when writing; the core
#'   object when reading).
#' @param ... Method arguments: `dir`, the bundle directory or `NULL`, and
#'   `header`, the header list.
#' @param class An S7 class that inherits from [`scale_class()`].
#'
#' @return `scale_write_payload()` the header; `scale_read_payload()` a
#'   scale; `register_scale_class()` the registry key, invisibly;
#'   `list_scale_classes()` a character vector of registered class names.
#'
#' @examples
#' list_scale_classes()
#' @name scale_payload_io
NULL

#' @rdname scale_payload_io
#' @export
scale_write_payload <- S7::new_generic("scale_write_payload", "x")

S7::method(scale_write_payload, NestedScale) <- function(x, dir, header, ...) {
  header
}

#' @rdname scale_payload_io
#' @export
scale_read_payload <- S7::new_generic("scale_read_payload", "x")

S7::method(scale_read_payload, NestedScale) <- function(x, dir, header, ...) x

#' @noRd
.SCALE_CLASSES <- new.env(parent = emptyenv())

#' @noRd
.class_key <- function(cls) {
  pkg <- cls@package
  if (is.null(pkg) || !nzchar(pkg)) cls@name else paste0(pkg, "::", cls@name)
}

#' @rdname scale_payload_io
#' @export
register_scale_class <- function(class) {
  if (!inherits(class, "S7_class")) .stop("`class` must be an S7 class")
  if (!identical(class, NestedScale)) {
    parent <- class@parent
    ok <- FALSE
    while (inherits(parent, "S7_class")) {
      if (identical(parent@name, NestedScale@name)) {
        ok <- TRUE
        break
      }
      parent <- parent@parent
    }
    if (!ok) .stop("`class` must inherit from scale_class()")
  }
  key <- .class_key(class)
  assign(key, class, envir = .SCALE_CLASSES)
  invisible(key)
}

#' @rdname scale_payload_io
#' @export
list_scale_classes <- function() {
  sort(ls(envir = .SCALE_CLASSES, all.names = TRUE))
}

# -----------------------------------------------------------------------------
# write_scale() / read_scale()
# -----------------------------------------------------------------------------

#' Write a scale as a definition file, and read one back
#'
#' A definition is a header (JSON, the stored form; YAML on request) plus
#' tables. A small scale fits in **one file** with every table inline; a
#' large one is a **bundle** directory holding `scale.json` and its tables as
#' Arrow IPC files (or CSV when arrow is not installed). Either form is
#' language-neutral: the header is plain JSON and the tables are Arrow or
#' CSV with their column types recorded.
#'
#' `path` ending in `.json`, `.yaml` or `.yml` writes a single file; any
#' other `path` is a bundle directory. A bundle is only ever written into an
#' empty directory or over a bundle written before (`overwrite = TRUE`);
#' nothing else in a directory is touched.
#'
#' `read_scale()` takes a file, a bundle directory, or the id of a shipped
#' definition (see [`scale_catalog()`]). The scale comes back as the class it
#' was written from when that class is registered (see
#' [`register_scale_class()`]); `class = "core"` asks for the plain
#' [`NestedScale`] instead, dropping any payload.
#'
#' @section Round trips:
#' An arrow bundle reads back identical. A JSON or YAML header carries
#' numbers at 15 significant digits, so an inline table reads back equal
#' (`all.equal()`), not necessarily identical, for arbitrary doubles.
#'
#' @param x A [`NestedScale`].
#' @param path A file (`.json`, `.yaml`, `.yml`) or a bundle directory; for
#'   `read_scale()` also a catalogue id.
#' @param format Header format: `"json"` (default) or `"yaml"`. A single-file
#'   `path` fixes it by its extension.
#' @param tables Where the tables go: `"auto"` (inline when the tables hold
#'   at most 1000 rows in all, else `"arrow"` when arrow is installed, else
#'   `"csv"`), `"inline"`, `"arrow"` or `"csv"`. A single file can only
#'   inline.
#' @param overwrite Replace a definition already at `path`.
#' @param package For a catalogue id: the package whose definition to take
#'   when several packages ship the same id.
#' @param class `"stored"` (default) returns the class recorded in the
#'   header; `"core"` the plain [`NestedScale`].
#'
#' @return `write_scale()` returns `path`, invisibly. `read_scale()` returns
#'   the scale.
#'
#' @examples
#' s <- scale_example()
#' f <- file.path(tempdir(), "example.json")
#' write_scale(s, f, overwrite = TRUE)
#' back <- read_scale(f)
#' identical(scale_frames(back), scale_frames(s))
#' all.equal(scale_leaftable(back), scale_leaftable(s))
#'
#' # a bundle, with the tables as files
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   d <- file.path(tempdir(), "example.scale")
#'   write_scale(s, d, tables = "arrow", overwrite = TRUE)
#'   list.files(d)
#'   identical(scale_leaftable(read_scale(d)), scale_leaftable(s))
#' }
#' @export
write_scale <- function(x, path, format = c("json", "yaml"),
                        tables = c("auto", "inline", "arrow", "csv"),
                        overwrite = FALSE) {
  .check_scale(x, "x")
  x <- .upgrade_scale(x)
  tables <- match.arg(tables)
  if (!.is_string(path)) .stop("`path` must be a single string")
  ext <- tolower(tools::file_ext(path))
  single <- ext %in% c("json", "yaml", "yml")
  if (single) {
    fmt_ext <- if (ext == "json") "json" else "yaml"
    if (!missing(format) && !identical(match.arg(format), fmt_ext)) {
      .stop("`path` ends in .%s but `format` is \"%s\"", ext,
            match.arg(format))
    }
    format <- fmt_ext
    if (!tables %in% c("auto", "inline")) {
      .stop(paste0(
        "a single-file definition can only inline its tables; write a ",
        "bundle directory for tables = \"%s\""
      ), tables)
    }
    tables <- "inline"
  } else {
    format <- match.arg(format)
  }

  core <- list(
    leaftable = scale_leaftable(x),
    attributes = .attr_table(x),
    aliases = .alias_table(x)
  )
  if (tables == "auto") {
    n <- sum(vapply(core, nrow, integer(1)))
    tables <- if (n <= .INLINE_MAX_ROWS) {
      "inline"
    } else if (requireNamespace("arrow", quietly = TRUE)) {
      "arrow"
    } else {
      "csv"
    }
  }

  # the destination ---------------------------------------------------------
  if (single) {
    if (file.exists(path) && !isTRUE(overwrite)) {
      .stop("`%s` already exists; pass overwrite = TRUE to replace it", path)
    }
    dir <- NULL
    header_file <- path
  } else {
    dir <- path
    header_file <- file.path(dir, paste0("scale.", format))
    if (dir.exists(dir)) {
      present <- list.files(dir, all.files = TRUE, no.. = TRUE)
      old_hdr <- intersect(c("scale.json", "scale.yaml", "scale.yml"), present)
      if (length(old_hdr) > 0L) {
        if (!isTRUE(overwrite)) {
          .stop("`%s` already holds a definition; pass overwrite = TRUE", dir)
        }
        .remove_bundle(dir, old_hdr)
      } else if (length(present) > 0L) {
        .stop(paste0(
          "`%s` exists and is not a scale bundle; a bundle is only written ",
          "into an empty directory"
        ), dir)
      }
    } else {
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    }
  }

  # the header, tables first so a failure leaves nothing half-written ------
  refs <- lapply(names(core), function(what) {
    df <- core[[what]]
    if (tables == "inline" || nrow(df) == 0L) {
      list(inline = .table_inline(df))
    } else {
      .table_to_file(df, dir, what, tables)
    }
  })
  names(refs) <- names(core)
  hdr <- .scale_header(x, refs)
  hdr <- scale_write_payload(x, dir, hdr)
  .write_header(hdr, header_file, format)
  invisible(path)
}

#' Remove the files of a bundle written before: its header and the files the
#' header names, nothing else
#' @noRd
.remove_bundle <- function(dir, old_hdr) {
  for (h in old_hdr) {
    hdr <- tryCatch(.read_header(file.path(dir, h)), error = function(e) NULL)
    files <- character()
    if (!is.null(hdr)) {
      for (ref in c(hdr$tables, hdr$payload)) {
        if (!is.null(ref$file)) files <- c(files, ref$file)
      }
    }
    unlink(file.path(dir, unique(c(h, files))))
  }
  invisible(NULL)
}

#' @rdname write_scale
#' @export
read_scale <- function(path, package = NULL, class = c("stored", "core")) {
  class <- match.arg(class)
  if (!.is_string(path)) .stop("`path` must be a single string")
  if (dir.exists(path)) {
    hdrs <- intersect(
      c("scale.json", "scale.yaml", "scale.yml"),
      list.files(path, all.files = TRUE)
    )
    if (length(hdrs) == 0L) {
      .stop("`%s` is a directory but holds no scale.json or scale.yaml", path)
    }
    if (length(hdrs) > 1L) {
      .stop("`%s` holds both %s; keep one", path, paste(hdrs, collapse = " and "))
    }
    dir <- path
    header_file <- file.path(path, hdrs)
  } else if (file.exists(path)) {
    dir <- dirname(path)
    header_file <- path
  } else {
    header_file <- .resolve_scale_id(path, package)
    dir <- dirname(header_file)
    if (basename(header_file) %in% c("scale.json", "scale.yaml", "scale.yml")) {
      dir <- dirname(header_file)
    }
  }
  hdr <- .read_header(header_file)
  core <- .scale_from_header(hdr, dir)
  stored <- hdr$class %||% class(core)[[1L]]
  if (class == "core" || identical(stored, class(core)[[1L]])) {
    return(core)
  }
  cls <- get0(stored, envir = .SCALE_CLASSES, inherits = FALSE)
  if (is.null(cls)) {
    .stop(paste0(
      "this definition was written from a %s, and no such class is ",
      "registered (is its package loaded?); pass class = \"core\" for the ",
      "plain NestedScale"
    ), stored)
  }
  m <- tryCatch(S7::method(scale_read_payload, cls), error = function(e) NULL)
  if (is.null(m)) {
    .stop("class %s is registered but has no scale_read_payload() method",
          stored)
  }
  m(core, dir, hdr)
}
