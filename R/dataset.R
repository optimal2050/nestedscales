# =============================================================================
# The scale-aware dataset store
# =============================================================================
# A folder that reopens as DATA ON SCALES, not as a bare table. The data is a
# hive-partitioned Arrow IPC dataset -- lazily readable, and already a
# first-class input to every verb here (see R/backend.R) -- and the scales
# that index it travel with it in a sidecar.
#
#   path/
#     data/                 hive-partitioned .arrow files
#       year=2021/part-0.arrow
#     _scales/
#       manifest.json       what the scales are: one definition header per axis
#       <axis>-leaftable.arrow
#       <axis>-attributes.arrow, <axis>-aliases.arrow   (when not inlined)
#
# Each axis is described by the same header `write_scale()` writes (see
# R/definition.R), with its leaftable as an Arrow file; the manifest is JSON
# so any language reads it with Arrow and a JSON parser. A store written by
# an earlier version carries `manifest.yaml`, which is still read.
# =============================================================================

#' @include product-class.R
#' @include definition.R
NULL

#' @noRd
.need_arrow <- function(what) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    .stop("%s needs the arrow package", what)
  }
}

#' Compression codec for an IPC dataset
#'
#' `write_feather()` takes a compression NAME, while
#' `write_dataset(format = "feather")` takes a `Codec` OBJECT as `codec` and
#' errors on the string. Falls back to no compression when the codec is not
#' available in this arrow build.
#' @noRd
.ipc_codec <- function(compression) {
  cmp <- tolower(compression)
  if (identical(cmp, "uncompressed") || identical(cmp, "none")) {
    return(NULL)
  }
  if (identical(cmp, "lz4")) cmp <- "lz4_frame"
  z <- try(arrow::Codec$create(cmp), silent = TRUE)
  if (inherits(z, "try-error")) {
    .warn(
      "compression codec '%s' is unavailable; writing uncompressed",
      compression
    )
    return(NULL)
  }
  z
}

#' @noRd
.need_yaml <- function(what) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    .stop("%s needs the yaml package", what)
  }
}

#' Describe one axis for the manifest: its definition header, leaftable as
#' an Arrow file, attributes and aliases inline when small
#' @noRd
.axis_header <- function(s, axis, sdir, compression) {
  s <- .upgrade_scale(s)
  arrow::write_feather(
    arrow::as_arrow_table(scale_leaftable(s)),
    file.path(sdir, paste0(axis, "-leaftable.arrow")),
    compression = compression
  )
  refs <- list(leaftable = list(
    file = paste0(axis, "-leaftable.arrow"), format = "arrow"
  ))
  for (what in c("attributes", "aliases")) {
    df <- if (what == "attributes") .attr_table(s) else .alias_table(s)
    refs[[what]] <- if (nrow(df) <= .INLINE_MAX_ROWS) {
      list(inline = .table_inline(df))
    } else {
      .table_to_file(df, sdir, paste0(axis, "-", what), "arrow")
    }
  }
  .scale_header(s, refs)
}

#' Rebuild a scale from a LEGACY (manifest.yaml) entry and its leaftable
#' @noRd
.scale_from_legacy_manifest <- function(entry, leaftable) {
  members <- lapply(entry$members, function(z) as.character(unlist(z)))
  meta <- entry$meta %||% list()
  # YAML gives back plain lists; the validator wants atomic vectors for the
  # fields it checks.
  for (f in c("weights", "coverage", "parent_totals")) {
    if (!is.null(meta[[f]]) && is.list(meta[[f]])) {
      meta[[f]] <- unlist(meta[[f]])
    }
  }
  # `residuals` is a named list OF vectors, so each element needs flattening
  # rather than the whole field: YAML hands back list("DE_XR", "FR_XR") where
  # the validator wants c("DE_XR", "FR_XR").
  if (is.list(meta[["residuals"]])) {
    meta[["residuals"]] <- lapply(
      meta[["residuals"]],
      function(z) as.character(unlist(z))
    )
  }
  NestedScale(
    leaftable = as.data.frame(leaftable),
    frames = as.character(unlist(entry$frames)),
    members = members,
    key = entry$key,
    meta = meta
  )
}

#' Write data and the scales that index it to one folder
#'
#' The data is written as a hive-partitioned Arrow IPC dataset and the scales
#' travel with it, so [`open_scale_dataset()`] gives back both and the result
#' can be recast without re-declaring anything. Each scale is stored as the
#' definition [`write_scale()`] writes, so its attributes and aliases travel
#' too.
#'
#' @param data The table to write, in any supported backend.
#' @param x The [`NestedScale`] or [`ScaleProduct`] the data is indexed by.
#' @param path Directory to create. It must not already contain a store
#'   unless `overwrite = TRUE`.
#' @param partitioning Columns to partition the data by (hive style). `NULL`
#'   (default) picks nothing; a good choice is a low-cardinality identifier
#'   such as a year, which lets a filtered read skip whole files.
#' @param compression Codec for the IPC files, e.g. `"zstd"` (default),
#'   `"lz4"` or `"uncompressed"`. If the codec is unavailable in the installed
#'   Arrow build, the files are written uncompressed with a warning.
#' @param overwrite Replace an existing store at `path`.
#'
#' @return `path`, invisibly.
#'
#' @examples
#' p <- scale_product(a = scale_example(), b = scale_example2())
#' d <- merge(
#'   data.frame(unit = c("U1", "U2")),
#'   data.frame(period = c("p1", "p2"))
#' )
#' d$v <- 1:4
#' dir <- file.path(tempdir(), "store")
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   write_scale_dataset(d, p, dir, overwrite = TRUE)
#'   ds <- open_scale_dataset(dir)
#'   ds
#' }
#' @export
write_scale_dataset <- function(data, x, path, partitioning = NULL,
                                compression = "zstd", overwrite = FALSE) {
  .need_arrow("write_scale_dataset()")

  is_prod <- S7::S7_inherits(x, ScaleProduct)
  if (!is_prod) .check_scale(x, "x")

  backend <- backend_of(data, "data")
  d <- as.data.frame(dplyr::collect(backend_lazy(data, backend)))

  axes <- if (is_prod) {
    S7::prop(x, "axes")
  } else {
    nm <- .scale_name(x, require = FALSE)
    stats::setNames(list(x), if (nzchar(nm)) nm else "scale")
  }
  keys <- if (is_prod) {
    product_keys(x)
  } else {
    stats::setNames(scale_key(x), names(axes))
  }

  missing_keys <- setdiff(unname(keys), names(d))
  if (length(missing_keys) > 0L) {
    .stop(
      "the data has no column(s) %s (one key column per axis)",
      .preview(missing_keys)
    )
  }
  if (!is.null(partitioning)) {
    bad <- setdiff(partitioning, names(d))
    if (length(bad) > 0L) {
      .stop(
        "`partitioning` names column(s) not in the data: %s",
        .preview(bad)
      )
    }
  }

  codec <- .ipc_codec(compression)
  feather_compression <- if (is.null(codec)) "uncompressed" else compression

  # Scales first, and their headers before any file: if a meta cannot be
  # serialised, fail before writing gigabytes of data that would then
  # describe nothing.
  for (a in names(axes)) {
    .meta_encode(S7::prop(axes[[a]], "meta"), a)
  }

  if (dir.exists(path)) {
    if (!isTRUE(overwrite)) {
      .stop("`%s` already exists; pass overwrite = TRUE to replace it", path)
    }
    unlink(path, recursive = TRUE)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  sdir <- file.path(path, "_scales")
  dir.create(sdir, showWarnings = FALSE)

  headers <- lapply(names(axes), function(a) {
    .axis_header(axes[[a]], a, sdir, feather_compression)
  })
  names(headers) <- names(axes)
  manifest <- list(
    nestedscales = as.character(utils::packageVersion("nestedscales")),
    kind = if (is_prod) "product" else "scale",
    keys = as.list(keys),
    axes = headers
  )
  .write_header(manifest, file.path(sdir, "manifest.json"), "json")

  ddir <- file.path(path, "data")
  args <- list(d,
    path = ddir, format = "feather",
    partitioning = partitioning
  )
  if (!is.null(codec)) args$codec <- codec
  do.call(arrow::write_dataset, args)
  invisible(path)
}

#' Read a store's manifest: JSON, or the legacy YAML
#' @noRd
.read_manifest <- function(path) {
  sdir <- file.path(path, "_scales")
  mj <- file.path(sdir, "manifest.json")
  my <- file.path(sdir, "manifest.yaml")
  if (file.exists(mj)) {
    return(list(manifest = jsonlite::fromJSON(mj, simplifyVector = FALSE),
                legacy = FALSE))
  }
  if (file.exists(my)) {
    .need_yaml("reading a store with a legacy manifest.yaml")
    return(list(manifest = yaml::read_yaml(my), legacy = TRUE))
  }
  .stop("`%s` is not a scale dataset (no _scales/manifest.json)", path)
}

#' Open a scale-aware dataset
#'
#' @param path A folder written by [`write_scale_dataset()`].
#'
#' @return A `scale_dataset`: a list with `data` (a lazily-read arrow
#'   Dataset) and `scale` (the [`NestedScale`] or [`ScaleProduct`] it is indexed
#'   by). Feed them to the verbs as
#'   `recast_scale(ds$data, ds$scale, ...)`.
#'
#' @examples
#' # see write_scale_dataset()
#' @export
open_scale_dataset <- function(path) {
  .need_arrow("open_scale_dataset()")
  m <- .read_manifest(path)
  manifest <- m$manifest
  sdir <- file.path(path, "_scales")

  scales <- lapply(names(manifest$axes), function(a) {
    if (m$legacy) {
      lt <- as.data.frame(arrow::read_feather(
        file.path(sdir, paste0(a, "-leaftable.arrow"))
      ))
      .scale_from_legacy_manifest(manifest$axes[[a]], lt)
    } else {
      .scale_from_header(manifest$axes[[a]], sdir)
    }
  })
  names(scales) <- names(manifest$axes)

  sc <- if (identical(manifest$kind, "product")) {
    keys <- unlist(manifest$keys)
    do.call(
      scale_product,
      c(scales, list(keys = keys[names(scales)]))
    )
  } else {
    scales[[1L]]
  }

  structure(
    list(
      data = arrow::open_dataset(file.path(path, "data"),
        format = "feather"
      ),
      scale = sc,
      path = path
    ),
    class = "scale_dataset"
  )
}

#' Describe a stored dataset without opening it fully
#'
#' @param path A folder written by [`write_scale_dataset()`].
#' @return A list with `kind`, `axes`, `keys`, `files` and `bytes`.
#' @examples
#' # see write_scale_dataset()
#' @export
scale_dataset_info <- function(path) {
  manifest <- .read_manifest(path)$manifest
  files <- list.files(file.path(path, "data"),
    recursive = TRUE,
    full.names = TRUE
  )
  list(
    kind = manifest$kind,
    axes = names(manifest$axes),
    keys = unlist(manifest$keys),
    files = length(files),
    bytes = sum(file.info(files)$size, na.rm = TRUE)
  )
}

#' @param x A `scale_dataset`.
#' @param ... Ignored.
#' @rdname open_scale_dataset
#' @export
#' @method print scale_dataset
print.scale_dataset <- function(x, ...) {
  info <- scale_dataset_info(x$path)
  cat("<scale_dataset>", x$path, "\n")
  cat("  rows:  ", tryCatch(format(nrow(x$data), big.mark = ","),
    error = function(e) "?"
  ), "\n", sep = "")
  cat("  files: ", info$files, " (",
    format(round(info$bytes / 1024), big.mark = ","), " KB)\n",
    sep = ""
  )
  cat("  scale: ", info$kind, " over ",
    paste(info$axes, collapse = " x "), "\n",
    sep = ""
  )
  invisible(x)
}
