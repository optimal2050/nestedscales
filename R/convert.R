# =============================================================================
# convert_scale() -- quantities <-> quantities with a member attribute
# =============================================================================
# A calorific value or an emission factor is a per-member conversion FACTOR,
# not a quantity: tonnes of a fuel become gigajoules by multiplying each row
# by that fuel's `lhv`. This is deliberately not a recast -- nothing is
# aggregated, no weight is involved -- and it is where attributes are
# consumed. Direction is read off the attribute's unit of measure (`"GJ/t"`
# converts t -> GJ); the inverse is allowed only for a `property`, never for
# a `factor` (see SCALE_ATTRIBUTE_KINDS).
# =============================================================================

#' @include scale-class.R
#' @include attributes.R
NULL

utils::globalVariables(c(".ms_factor", ".ms_origin_frame"))

#' Convert unit-keyed quantities with a member attribute
#'
#' Multiplies (or divides) the numeric value columns of `data` by the value
#' of `attribute` resolved for each row's unit -- a net calorific value to
#' turn mass into energy, an emission factor to turn energy into CO2, a
#' density to turn volume into mass. Values are resolved along the hierarchy
#' exactly as [`scale_attributes()`] does, so a factor stored on a coarser
#' member applies to every atom under it that has no factor of its own.
#'
#' Direction comes from the attribute's unit of measure, read as
#' `"<numerator>/<denominator>"`: with `lhv` in `"GJ/t"`, `from_unit = "t",
#' to_unit = "GJ"` multiplies, and `from_unit = "GJ", to_unit = "t"` divides.
#' The inverse is allowed only when the attribute's `kind` is `"property"`;
#' a `"factor"` is one-way. No unit-prefix arithmetic is done: a column in
#' kilotonnes must be turned into tonnes before converting with a GJ/t
#' factor.
#'
#' A unit for which no value resolves is an **error** by default -- a
#' silently dropped row is a wrong total -- unless `na_action = "keep"`,
#' which leaves `NA` in its rows.
#'
#' @param data The data, in any supported backend, with a column of codes at
#'   `frame`.
#' @param x A [`NestedScale`] carrying `attribute`.
#' @param attribute Name of the attribute to convert with.
#' @param from_unit,to_unit The physical units of the values before and
#'   after, matching the attribute's unit of measure.
#' @param key Name of the code column in `data`; defaults to `frame`.
#' @param frame Frame the codes belong to. Inferred when exactly one of the
#'   scale's frame names (or its atom level) is a column of `data`.
#' @param values Value columns to convert; `NULL` takes every numeric column
#'   that is not the key.
#' @param source Restrict the attribute to one source; `NULL` errors on a
#'   conflict between sources.
#' @param na_action What to do with rows whose unit has no value:
#'   `"error"` (default) or `"keep"` (an `NA` result).
#' @param collect For lazy inputs: materialise (`TRUE`) or return the query.
#'
#' @return `data` with the value columns converted, plus two columns named
#'   after the attribute: `<attribute>` (the factor applied) and
#'   `<attribute>.origin_frame` (the frame the factor was taken from), in the
#'   input's class.
#'
#' @examples
#' s <- attach_attributes_scale(
#'   scale_example(),
#'   data.frame(frame = c("sector", "unit"), unit = c("P", "U5"),
#'              attribute = "lhv", value = c(20, 30),
#'              unit_of_measure = "GJ/t"),
#'   source = "example", kind = "property"
#' )
#' mass <- data.frame(unit = c("U1", "U2", "U5"), t = c(100, 200, 50))
#' energy <- convert_scale(mass, s, attribute = "lhv",
#'                         from_unit = "t", to_unit = "GJ")
#' energy
#' # back to tonnes: a property is invertible
#' convert_scale(energy[c("unit", "t")], s, attribute = "lhv",
#'               from_unit = "GJ", to_unit = "t")
#' @export
convert_scale <- function(data, x, attribute, from_unit, to_unit,
                          key = NULL, frame = NULL, values = NULL,
                          source = NULL, na_action = c("error", "keep"),
                          collect = NULL) {
  na_action <- match.arg(na_action)
  .check_scale(x, "x")
  v <- scale_vocab(x)
  if (!.is_string(attribute)) .stop("`attribute` must be a single string")
  if (!.is_string(from_unit) || !.is_string(to_unit)) {
    .stop("`from_unit` and `to_unit` must be single strings")
  }
  backend <- backend_of(data, "data")
  schema <- backend_schema(data, backend)

  if (is.null(frame)) {
    hit <- intersect(.nav_levels(x), names(schema))
    if (length(hit) != 1L) {
      .stop(
        paste0(
          "cannot infer the code %s from the data's columns ",
          "(found: %s); pass `frame=`"
        ),
        v$frame, if (length(hit) == 0L) "none" else .preview(hit)
      )
    }
    frame <- hit
  }
  .check_frame(x, frame, "frame")
  if (is.null(key)) key <- frame
  if (!.is_string(key) || !key %in% names(schema)) {
    .stop("the data has no column named `%s`; pass `key=`", key)
  }
  if (is.null(values)) {
    cand <- setdiff(names(schema), key)
    values <- cand[vapply(schema[cand], is.numeric, logical(1))]
    if (length(values) == 0L) {
      .stop("no numeric value columns found in `data`; specify `values=`")
    }
  } else if (!all(values %in% names(schema))) {
    .stop(
      "value column(s) not in `data`: %s",
      .preview(setdiff(values, names(schema)))
    )
  }

  # the factor per member of `frame`, resolved along the hierarchy ---------
  res <- scale_attributes(x, attribute,
    frame = frame, source = source,
    inherit = TRUE
  )
  uom <- unique(stats::na.omit(res$unit_of_measure))
  if (length(uom) == 0L) {
    .stop(
      "no `%s` value resolves for any %s at %s `%s`", attribute, v$unit,
      v$frame, frame
    )
  }
  if (length(uom) > 1L) {
    .stop(
      "`%s` is stored in several units of measure (%s); pass `source=`",
      attribute, paste(uom, collapse = ", ")
    )
  }
  parts <- .parse_uom(uom)
  kind <- unique(stats::na.omit(res$kind))
  if (identical(from_unit, parts$den) && identical(to_unit, parts$num)) {
    op <- "multiply"
  } else if (identical(from_unit, parts$num) &&
    identical(to_unit, parts$den)) {
    if (!identical(kind, "property")) {
      .stop(
        paste0(
          "`%s` converts %s -> %s only; the inverse is refused because it ",
          "is a %s, not a property (see SCALE_ATTRIBUTE_KINDS)"
        ),
        attribute, parts$den, parts$num, kind
      )
    }
    op <- "divide"
  } else {
    .stop(
      paste0(
        "`%s` is in %s and converts %s -> %s%s; got %s -> %s ",
        "(no unit-prefix arithmetic: convert kt to t first)"
      ),
      attribute, uom, parts$den, parts$num,
      if (identical(kind, "property")) " (or back)" else "",
      from_unit, to_unit
    )
  }

  out_cols <- c(attribute, paste0(attribute, ".origin_frame"))
  clash <- intersect(
    names(schema),
    c(out_cols, ".ms_factor", ".ms_origin_frame")
  )
  if (length(clash) > 0L) {
    .stop(
      "`data` already has column(s) %s; existing columns are never overwritten",
      .preview(clash)
    )
  }

  # every code must be a member, and must resolve (or na_action = "keep") --
  codes <- backend_distinct(data, key, backend)[[key]]
  codes <- unique(as.character(stats::na.omit(codes)))
  unknown <- setdiff(codes, res$unit)
  if (length(unknown) > 0L) {
    .stop(
      "code(s) in `data$%s` that are not %s of %s `%s`: %s",
      key, v$units, v$frame, frame, .preview(unknown)
    )
  }
  unresolved <- intersect(codes, res$unit[is.na(res$value)])
  if (length(unresolved) > 0L && na_action == "error") {
    .stop(
      paste0(
        "no `%s` value resolves for %s at %s `%s`; attach one with ",
        "attach_attributes_scale() or pass na_action = \"keep\""
      ),
      attribute, .preview(unresolved), v$frame, frame
    )
  }

  fac <- data.frame(res$unit,
    .ms_factor = res$value,
    .ms_origin_frame = res$origin_frame,
    stringsAsFactors = FALSE
  )
  names(fac)[1L] <- key
  joined <- dplyr::left_join(backend_lazy(data, backend), fac, by = key)
  joined <- if (op == "multiply") {
    dplyr::mutate(joined, dplyr::across(
      dplyr::all_of(values), ~ .x * .ms_factor
    ))
  } else {
    dplyr::mutate(joined, dplyr::across(
      dplyr::all_of(values), ~ .x / .ms_factor
    ))
  }
  joined <- dplyr::rename(joined,
    !!out_cols[1L] := .ms_factor,
    !!out_cols[2L] := .ms_origin_frame
  )
  backend_restore(joined, backend, collect = collect)
}

#' Split "num/den" into its two parts
#' @noRd
.parse_uom <- function(uom) {
  parts <- trimws(strsplit(uom, "/", fixed = TRUE)[[1L]])
  if (length(parts) != 2L || any(!nzchar(parts))) {
    .stop(paste0(
      "unit of measure \"%s\" is not of the form ",
      "\"<numerator>/<denominator>\" (e.g. \"GJ/t\")"
    ), uom)
  }
  list(num = parts[1L], den = parts[2L])
}
