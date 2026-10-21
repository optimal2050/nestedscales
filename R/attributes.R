# =============================================================================
# Member attributes -- physical factors that live on the members of a scale
# =============================================================================
# One long table on the object, keyed by (frame, unit): a value may sit on an
# atom or on any coarser member. `scale_attributes()` resolves a value for
# every member of a frame by taking the member's own entry first and
# otherwise walking to the nearest coarser frame that holds one.
#
# Attributes are not weights (see R/scale-class.R) and are never recast;
# `convert_scale()` multiplies with them row by row. Each attribute name has
# a `kind`: a `property` is an invertible ratio (a calorific value, a
# density), a `factor` is one-way (an emission factor, a loss factor).
# =============================================================================

#' @include scale-class.R
NULL

.ATTR_COLS <- c(
  "frame", "unit", "attribute", "kind", "value", "lower", "upper",
  "unit_of_measure", "source", "note"
)

#' Kinds of attribute
#'
#' Every attribute name carries a kind, which [`convert_scale()`] consults:
#'
#' \describe{
#'   \item{`property`}{A physical property of the member, an invertible
#'     ratio: a calorific value in GJ/t converts tonnes to gigajoules and
#'     gigajoules back to tonnes; a density, a yield.}
#'   \item{`factor`}{A one-way multiplier: an emission factor in kg/TJ turns
#'     energy into CO2, and there is no physical sense in which CO2 turns
#'     back into energy; a loss factor, a tax rate.}
#' }
#'
#' @format A character vector of length 2.
#' @examples
#' SCALE_ATTRIBUTE_KINDS
#' @export
SCALE_ATTRIBUTE_KINDS <- c("property", "factor")

#' @noRd
.empty_attributes <- function() {
  data.frame(
    frame = character(), unit = character(), attribute = character(),
    kind = character(), value = numeric(), lower = numeric(),
    upper = numeric(), unit_of_measure = character(), source = character(),
    note = character(),
    stringsAsFactors = FALSE
  )
}

#' The attribute table, with NULL (an object saved before 0.2.0) as empty
#'
#' Read with `attr()`, not `S7::prop()`: an object saved under an earlier
#' class definition carries that definition with it, and `prop()` refuses a
#' property the embedded class does not know.
#' @noRd
.attr_table <- function(x) {
  attr(x, "attributes", exact = TRUE) %||% .empty_attributes()
}

#' Bring an object saved under an earlier class definition up to date
#'
#' An S7 object embeds its class. One saved before the `attributes` and
#' `aliases` properties existed validates and reads fine (the accessors
#' tolerate the missing attributes), but any WRITE -- `S7::prop<-`,
#' `S7::set_props()`, hence every rebuild -- is refused by the embedded
#' class. So the write paths call this first: it swaps in the current class
#' of the same name and package and fills the missing tables with empty
#' ones. A no-op for an up-to-date object.
#' @noRd
.upgrade_scale <- function(x) {
  cls <- attr(x, "S7_class", exact = TRUE)
  if (is.null(cls) ||
    all(c("attributes", "aliases") %in% names(cls@properties))) {
    return(x)
  }
  spec <- strsplit(class(x)[[1L]], "::", fixed = TRUE)[[1L]]
  current <- NULL
  if (length(spec) == 2L && isNamespaceLoaded(spec[[1L]])) {
    current <- get0(spec[[2L]],
      envir = asNamespace(spec[[1L]]), inherits = FALSE
    )
  }
  if (!inherits(current, "S7_class")) {
    .stop(paste0(
      "this %s was saved under an earlier class definition and its ",
      "package (%s) is not loaded, so it cannot be updated in place; ",
      "rebuild it from its leaftable"
    ), cls@name, if (length(spec) == 2L) spec[[1L]] else "unknown")
  }
  attr(x, "S7_class") <- current
  if (is.null(attr(x, "attributes", exact = TRUE))) {
    attr(x, "attributes") <- .empty_attributes()
  }
  if (is.null(attr(x, "aliases", exact = TRUE))) {
    attr(x, "aliases") <- .empty_aliases()
  }
  x
}

#' Every (frame, unit) pair the object currently has, as "frame\runit"
#' @noRd
.member_keys <- function(x) {
  members <- S7::prop(x, "members")
  unlist(lapply(names(members), function(f) {
    paste(f, members[[f]], sep = "\r")
  }), use.names = FALSE)
}

#' Coerce user input to the attribute schema (optional columns filled)
#'
#' Membership is not checked here -- the validator does that.
#' @noRd
.as_attributes <- function(attributes, source = NULL, kind = NULL) {
  if (is.null(attributes)) {
    return(.empty_attributes())
  }
  if (!is.data.frame(attributes)) {
    .stop("`attributes` must be a data.frame")
  }
  attributes <- as.data.frame(attributes, stringsAsFactors = FALSE)
  for (arg in c("source", "kind")) {
    val <- get(arg)
    if (!is.null(val)) {
      if (!.is_string(val)) .stop("`%s` must be a single string", arg)
      if (arg %in% names(attributes)) {
        .stop("`attributes` already has a `%s` column; drop `%s=`", arg, arg)
      }
      attributes[[arg]] <- val
    }
  }
  for (opt in c("lower", "upper")) {
    if (!opt %in% names(attributes)) attributes[[opt]] <- NA_real_
  }
  if (!"note" %in% names(attributes)) attributes$note <- NA_character_
  missing_cols <- setdiff(.ATTR_COLS, names(attributes))
  if (length(missing_cols) > 0L) {
    .stop("`attributes` is missing column(s): %s", .preview(missing_cols))
  }
  extra <- setdiff(names(attributes), .ATTR_COLS)
  if (length(extra) > 0L) {
    .stop("`attributes` has unknown column(s): %s", .preview(extra))
  }
  out <- attributes[.ATTR_COLS]
  for (ch in c(
    "frame", "unit", "attribute", "kind", "unit_of_measure", "source", "note"
  )) {
    out[[ch]] <- as.character(out[[ch]])
  }
  for (nm in c("value", "lower", "upper")) {
    out[[nm]] <- as.numeric(out[[nm]])
  }
  rownames(out) <- NULL
  out
}

#' Validation of an attribute table against the members; a character vector
#' of problems, empty when fine
#' @noRd
.check_attributes_table <- function(at, frames, members, v) {
  errs <- character()
  if (!identical(names(at), .ATTR_COLS)) {
    return(sprintf(
      "`attributes` must have exactly the columns: %s",
      paste(.ATTR_COLS, collapse = ", ")
    ))
  }
  if (nrow(at) == 0L) {
    return(errs)
  }
  bad_frame <- unique(at$frame[!at$frame %in% frames])
  if (length(bad_frame) > 0L) {
    errs <- c(errs, sprintf(
      "`attributes` names %s(s) not in the object: %s", v$frame,
      .preview(bad_frame)
    ))
  }
  ok_frame <- at$frame %in% frames
  is_member <- rep(FALSE, nrow(at))
  is_member[ok_frame] <- mapply(
    function(f, u) u %in% members[[f]], at$frame[ok_frame],
    at$unit[ok_frame]
  )
  if (any(!is_member & ok_frame)) {
    bad <- unique(paste0(at$frame, "/", at$unit)[!is_member & ok_frame])
    errs <- c(errs, sprintf(
      "`attributes` names (%s/%s) pairs that are not members: %s",
      v$frame, v$unit, .preview(bad)
    ))
  }
  if (!is.numeric(at$value) || any(!is.finite(at$value))) {
    errs <- c(errs, "`attributes$value` must be finite numeric")
  }
  if (any(!is.na(at$lower) & !is.na(at$value) & at$lower > at$value) ||
    any(!is.na(at$upper) & !is.na(at$value) & at$upper < at$value)) {
    errs <- c(errs, "`attributes` must satisfy lower <= value <= upper")
  }
  for (nm in c("attribute", "kind", "unit_of_measure", "source")) {
    val <- at[[nm]]
    if (!is.character(val) || anyNA(val) || any(!nzchar(val))) {
      errs <- c(errs, sprintf("`attributes$%s` must be non-empty strings", nm))
    }
  }
  if (is.character(at$kind)) {
    bad_kind <- unique(at$kind[!at$kind %in% SCALE_ATTRIBUTE_KINDS])
    if (length(bad_kind) > 0L) {
      errs <- c(errs, sprintf(
        "`attributes$kind` must be one of %s; got: %s",
        paste(SCALE_ATTRIBUTE_KINDS, collapse = ", "), .preview(bad_kind)
      ))
    }
    kinds_per <- tapply(at$kind, at$attribute, function(k) length(unique(k)))
    mixed <- names(kinds_per)[kinds_per > 1L]
    if (length(mixed) > 0L) {
      errs <- c(errs, sprintf(
        "an attribute has one kind; these have several: %s", .preview(mixed)
      ))
    }
  }
  k <- paste(at$frame, at$unit, at$attribute, at$source, sep = "\r")
  if (anyDuplicated(k)) {
    dup <- unique(paste0(
      at$frame, "/", at$unit, ":", at$attribute, "@", at$source
    )[duplicated(k)])
    errs <- c(errs, sprintf(
      "`attributes` has duplicate (%s, %s, attribute, source) rows: %s",
      v$frame, v$unit, .preview(dup)
    ))
  }
  errs
}

#' Attach physical attributes to a scale
#'
#' Appends rows to the object's attribute table. A row names the member it
#' belongs to (`frame`, `unit`), the attribute (`attribute`, e.g. `"lhv"`),
#' its `kind` (see [`SCALE_ATTRIBUTE_KINDS`]), its `value`, an optional
#' `lower`/`upper` range, the physical `unit_of_measure` (`"GJ/t"`,
#' `"kg/TJ"`), the `source` the figure was taken from and an optional `note`.
#' Values can be attached at **any** frame: a calorific value for a whole
#' carrier is inherited by every fuel under it that has no value of its own
#' (see [`scale_attributes()`]).
#'
#' Existing rows are never overwritten: a row whose `(frame, unit,
#' attribute, source)` already exists is an error. Attach a second source
#' under its own `source` name and choose between them with `source=` when
#' reading.
#'
#' @param x A [`NestedScale`].
#' @param attributes A `data.frame` with columns `frame`, `unit`,
#'   `attribute`, `value`, `unit_of_measure`, and optionally `lower`,
#'   `upper`, `note`; `kind` and `source` as columns or through the
#'   arguments.
#' @param source Optional single string filled into the `source` column
#'   when `attributes` has none.
#' @param kind Optional single string filled into the `kind` column when
#'   `attributes` has none.
#'
#' @return The scale with the rows appended.
#'
#' @examples
#' s <- scale_example()
#' s2 <- attach_attributes_scale(
#'   s,
#'   data.frame(frame = "class", unit = c("G1", "G2", "S1"),
#'              attribute = "density", value = c(10, 20, 5),
#'              unit_of_measure = "t/m3"),
#'   source = "survey", kind = "property"
#' )
#' scale_attributes(s2, "density", frame = "unit")
#' @export
attach_attributes_scale <- function(x, attributes, source = NULL,
                                    kind = NULL) {
  .check_scale(x)
  x <- .upgrade_scale(x)
  new <- .as_attributes(attributes, source = source, kind = kind)
  old <- .attr_table(x)
  k_old <- paste(old$frame, old$unit, old$attribute, old$source, sep = "\r")
  k_new <- paste(new$frame, new$unit, new$attribute, new$source, sep = "\r")
  clash <- intersect(k_new, k_old)
  if (length(clash) > 0L) {
    hit <- new[k_new %in% clash, , drop = FALSE]
    .stop(
      paste0(
        "attribute row(s) already present (never overwritten): %s; ",
        "attach under another `source`"
      ),
      .preview(paste0(
        hit$frame, "/", hit$unit, ":", hit$attribute, "@", hit$source
      ))
    )
  }
  out <- rbind(old, new)
  rownames(out) <- NULL
  S7::prop(x, "attributes") <- out # validated by the class
  x
}

#' Read attributes, resolved along the hierarchy
#'
#' With `frame = NULL`, returns the stored attribute table (filtered by
#' `attribute` and `source`). With a `frame`, returns one row per member of
#' that frame per attribute, **resolved**: a member's own value when it has
#' one, otherwise the value of its nearest ancestor that has one, walking
#' coarser frames one at a time. The row reports where the value came from
#' in `origin_frame`/`origin_unit`; a member with no value anywhere gets an
#' `NA` row.
#'
#' Two situations are errors rather than guesses:
#'
#' * the walk reaches a frame where the member has **several** ancestors
#'   (the frames cross-cut) and at least one of them holds the attribute --
#'   "inheritance is ambiguous";
#' * several `source`s publish the attribute for the same member and
#'   `source` is `NULL` -- pass `source=` to choose.
#'
#' @param x A [`NestedScale`].
#' @param attribute Character vector of attribute names; `NULL` for all.
#' @param frame Frame whose members to resolve for; `NULL` returns the
#'   stored table unresolved.
#' @param source Restrict to one source (or several). `NULL` uses whatever
#'   is stored and errors on a conflict.
#' @param inherit Walk to coarser frames for members without a value of
#'   their own (default `TRUE`). `FALSE` reports stored values only.
#'
#' @return A `data.frame` with the attribute columns (`frame`, `unit`,
#'   `attribute`, `kind`, `value`, `lower`, `upper`, `unit_of_measure`,
#'   `source`, `note`), plus `origin_frame` and `origin_unit` when `frame`
#'   is given.
#'
#' @examples
#' s <- attach_attributes_scale(
#'   scale_example(),
#'   data.frame(frame = c("sector", "class"), unit = c("P", "S1"),
#'              attribute = "density", value = c(10, 5),
#'              unit_of_measure = "t/m3"),
#'   source = "survey", kind = "property"
#' )
#' scale_attributes(s)                           # stored rows
#' scale_attributes(s, "density", frame = "unit") # resolved per atom
#' @export
scale_attributes <- function(x, attribute = NULL, frame = NULL,
                             source = NULL, inherit = TRUE) {
  .check_scale(x)
  at <- .attr_table(x)
  if (!is.null(attribute)) {
    if (!is.character(attribute)) .stop("`attribute` must be character")
    unknown <- setdiff(attribute, at$attribute)
    if (length(unknown) > 0L) {
      .stop(
        "attribute(s) not stored on this %s: %s (stored: %s)",
        scale_vocab(x)$object, .preview(unknown),
        if (nrow(at)) paste(unique(at$attribute), collapse = ", ") else "<none>"
      )
    }
    at <- at[at$attribute %in% attribute, , drop = FALSE]
  }
  if (!is.null(source)) {
    if (!is.character(source)) .stop("`source` must be character")
    unknown <- setdiff(source, at$source)
    if (length(unknown) > 0L) {
      .stop("source(s) not stored on this %s: %s", scale_vocab(x)$object,
            .preview(unknown))
    }
    at <- at[at$source %in% source, , drop = FALSE]
  }
  if (is.null(frame)) {
    rownames(at) <- NULL
    return(at)
  }
  .check_frame(x, frame)
  .resolve_attributes(x, at, frame, inherit = isTRUE(inherit))
}

#' Resolve one attribute table at one frame (the inheritance walk)
#' @noRd
.resolve_attributes <- function(x, at, frame, inherit) {
  frames <- S7::prop(x, "frames")
  units <- scale_units(x, frame)
  attrs <- unique(at$attribute)
  v <- scale_vocab(x)
  rank <- match(frame, frames)
  coarser <- if (is.na(rank)) rev(frames) else rev(frames[seq_len(rank - 1L)])

  anc <- NULL
  if (inherit && length(coarser) > 0L) {
    anc <- .ancestry_to(x, frame)
  }

  key_at <- paste(at$frame, at$unit, at$attribute, sep = "\r")

  pick <- function(a, u) {
    hit <- at[key_at == paste(frame, u, a, sep = "\r"), , drop = FALSE]
    origin <- c(frame, u)
    if (nrow(hit) == 0L && inherit) {
      for (cf in coarser) {
        parents <- unique(anc$parent[anc$parent_frame == cf & anc$child == u])
        if (length(parents) == 0L) next
        cand <- at[at$attribute == a & at$frame == cf &
          at$unit %in% parents, , drop = FALSE]
        if (nrow(cand) == 0L) next
        if (length(parents) > 1L) {
          .stop(
            paste0(
              "inheritance of `%s` is ambiguous for `%s` at %s `%s`: it ",
              "spans %s at %s `%s`, which holds the attribute; store a ",
              "value at `%s` or pass a nesting %s"
            ),
            a, u, v$frame, frame, .preview(parents, 5L), v$frame, cf, frame,
            v$frame
          )
        }
        hit <- cand
        origin <- c(cf, parents)
        break
      }
    }
    if (nrow(hit) > 1L) {
      .stop(
        paste0(
          "`%s` for `%s` at %s `%s` is published by several sources (%s); ",
          "pass `source=`"
        ),
        a, origin[2L], v$frame, origin[1L],
        paste(unique(hit$source), collapse = ", ")
      )
    }
    if (nrow(hit) == 0L) {
      hit <- data.frame(
        frame = frame, unit = u, attribute = a, kind = NA_character_,
        value = NA_real_, lower = NA_real_, upper = NA_real_,
        unit_of_measure = NA_character_, source = NA_character_,
        note = NA_character_, stringsAsFactors = FALSE
      )
      origin <- c(NA_character_, NA_character_)
    } else {
      hit$frame <- frame
      hit$unit <- u
    }
    hit$origin_frame <- origin[1L]
    hit$origin_unit <- origin[2L]
    hit
  }

  rows <- list()
  for (a in attrs) {
    for (u in units) rows[[length(rows) + 1L]] <- pick(a, u)
  }
  if (length(rows) == 0L) {
    out <- .empty_attributes()
    out$origin_frame <- character()
    out$origin_unit <- character()
    return(out)
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Ancestry rows whose child frame is `frame` -- including the key level,
#' which `scale_ancestry()` does not list when the key is the atom level
#' @noRd
.ancestry_to <- function(x, frame) {
  frames <- S7::prop(x, "frames")
  if (frame %in% frames) {
    anc <- scale_ancestry(x)
    return(anc[anc$child_frame == frame, , drop = FALSE])
  }
  leaves <- S7::prop(x, "leaftable")
  parts <- lapply(frames, function(f) {
    d <- unique(data.frame(
      parent_frame = f, parent = as.character(leaves[[f]]),
      child_frame = frame, child = as.character(leaves[[frame]]),
      stringsAsFactors = FALSE
    ))
    d[!is.na(d$parent), , drop = FALSE]
  })
  do.call(rbind, parts)
}
