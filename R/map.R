# =============================================================================
# scale_map() -- the crosswalk through the atom layer
# =============================================================================
# Every conversion is `from -> ATOMS -> to`, collapsed into ONE table: one row
# per pair of overlapping units, carrying the counts and weights each rule
# needs. `recast_scale()` is a join against this table plus one grouped
# summarise, which is what lets the converters run unchanged over
# data.frame / data.table / arrow backends.
#
# Two shapes:
#   * within ONE scale -- `source`/`target` are frame names of `x`;
#   * across TWO scales -- `source`/`target` are NestedScale objects, matched on shared
#     atom keys.
#
# The ADAPTER SEAM is `scale_atom_pairs()`: a dimension supplies the atom-level
# (from, to, w) correspondence and everything downstream is shared. The `NestedScale`
# default reads it straight from the leaftable, which is already the atom
# enumeration. A dimension whose atom layer must be GENERATED rather than read
# -- time, where the atoms are a datetime grid that depends on the year --
# overrides this generic and may carry extra identifier columns (`year`)
# through `by=`; those ride the identifier-column contract from there on.
# =============================================================================

#' @include scale-class.R
NULL

#' @noRd
.MAP_REGISTRY <- new.env(parent = emptyenv())

#' Atom-level correspondence between two frames
#'
#' The seam a dimension package overrides when its atom layer is generated
#' rather than enumerated. Returns one row per atom (or per atom and extra
#' identifier, e.g. per grid instant and year).
#'
#' @param x A [`NestedScale`].
#' @param ... Method arguments: `source` and `target` (frame names of `x`), `weight`
#'   (a weight column, or `NULL` for the scale's default), and whatever else
#'   the dimension needs to generate its atoms -- `year` for a calendar.
#'
#' @return A `data.frame` with columns `source`, `target`, `w`, plus any extra
#'   identifier columns the dimension carries. The extra columns must be named
#'   in the `by` argument of the caller.
#'
#' @examples
#' head(scale_atom_pairs(scale_example(), "class", "group"))
#' @export
scale_atom_pairs <- S7::new_generic("scale_atom_pairs", "x")

S7::method(scale_atom_pairs, NestedScale) <- function(x, source, target, weight = NULL,
                                                ...) {
  leaves <- S7::prop(x, "leaftable")
  wcol <- .map_weight(x, weight)
  data.frame(
    source = as.character(leaves[[source]]),
    target = as.character(leaves[[target]]),
    w = if (is.null(wcol)) 1 else as.numeric(leaves[[wcol]]),
    stringsAsFactors = FALSE
  )
}

#' Crosswalk between two frames of a scale
#'
#' Materialises the `from -> atoms -> to` route as a table: one row per pair of
#' overlapping units with
#'
#' * `n_from` -- atoms in the `source` unit (its full set, before any target
#'   coverage is considered),
#' * `n_overlap` -- atoms the pair shares,
#' * `w` -- the weight of the overlap (summed atom weights, chosen weight
#'   column), the quantity `"weighted_mean"` aggregation uses,
#' * `w_from` -- the full weight of the `source` unit; `w / w_from` is the split
#'   share `"sum"` disaggregation uses.
#'
#' The two label columns are named by the frames; rows with an `NA` target
#' label are atoms `target` does not cover. A crosswalk registered with
#' [`register_scale_map()`] is returned as-is instead of being derived.
#'
#' @param x The [`NestedScale`] the frames belong to.
#' @param source,target Frame names of `x`.
#' @param weight Weight column for `w`. `NULL` uses the default weight; when
#'   the object declares no weights at all, every atom gets weight 1 (an equal
#'   split).
#' @param by Extra identifier columns carried through from
#'   [`scale_atom_pairs()`] (e.g. `"year"`).
#' @param ... Passed to [`scale_atom_pairs()`].
#'
#' @return A `data.frame` with columns `<from>`, `<to>` (`NA` = uncovered by
#'   `target`), `n_from`, `n_overlap`, `w`, `w_from`, plus any `by` columns.
#'
#' @seealso [`scale_map_between()`] for the map between two scales.
#' @examples
#' s <- scale_example()
#' scale_map(s, "class", "group")
#' scale_map(s, "sector", "class", weight = "count")
#' @export
scale_map <- function(x, source, target, weight = NULL, by = character(), ...) {
  if (S7::S7_inherits(source, NestedScale) || S7::S7_inherits(target, NestedScale)) {
    .stop(paste0(
      "`source` and `target` are frame names of `x`; for the map between two ",
      "scales use `scale_map_between()`"
    ))
  }
  .check_scale(x, "x")
  .check_frame(x, source, "source")
  .check_frame(x, target, "target")
  if (identical(source, target)) {
    v <- scale_vocab(x)
    .stop(paste0(
      "`source` and `target` are the same %s (\"%s\"); the map's ",
      "label columns are named by the %s"
    ), v$frame, source, v$frames)
  }

  reg <- .get_scale_map(source, target, .scale_name(x, require = FALSE))
  if (!is.null(reg)) {
    return(reg)
  }

  d <- scale_atom_pairs(x, source = source, target = target, weight = weight, ...)
  .finish_map(d, source, target, by = by)
}

#' Crosswalk between two scales through their shared atoms
#'
#' The counterpart of [`scale_map()`] for two scales: atoms are matched on
#' their keys, so a unit of `source` overlaps a unit of `target` where they contain
#' the same atoms. Same columns as [`scale_map()`], with the two label columns
#' named after the scales. Atoms of `source` absent from `target` get an `NA` target
#' (with a warning). A crosswalk registered with
#' [`register_scale_map_between()`] is returned as-is instead of being derived.
#'
#' @param source,target Two named [`NestedScale`] objects whose atom keys overlap.
#' @param weight Weight column of `source` for `w`; `NULL` uses its default
#'   weight, or weight 1 per atom when it declares none.
#'
#' @return A `data.frame` with columns `<from name>`, `<to name>`, `n_from`,
#'   `n_overlap`, `w`, `w_from`.
#'
#' @examples
#' a <- scale_example()
#' b <- scale_from_leaftable(
#'   data.frame(
#'     big = c("X", "X", "Y", "Y", "Y", "Y", "Z"),
#'     unit = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH")
#'   ),
#'   frames = c("big", "unit"), name = "other"
#' )
#' scale_map_between(a, b)
#' @export
scale_map_between <- function(source, target, weight = NULL) {
  .check_scale(source, "source")
  .check_scale(target, "target")
  from_nm <- .scale_name(source, arg = "source")
  to_nm <- .scale_name(target, arg = "target")
  if (identical(from_nm, to_nm)) {
    .stop(
      paste0(
        "`source` and `target` have the same name (\"%s\"); the map's ",
        "label columns are named by the scales -- rename one"
      ),
      from_nm
    )
  }
  reg <- .get_scale_map(from_nm, to_nm)
  if (!is.null(reg)) {
    return(reg)
  }

  kf <- scale_key(source)
  kt <- scale_key(target)
  lf <- S7::prop(source, "leaftable")
  lt <- S7::prop(target, "leaftable")
  shared <- intersect(lf[[kf]], lt[[kt]])
  if (length(shared) == 0L) {
    keys <- if (identical(kf, kt)) sprintf("`%s` keys", kf) else "keys"
    hint <- scale_vocab(source)$register_map %||% "register_scale_map_between()"
    .stop(
      paste0(
        "the atom layers of \"%s\" and \"%s\" share no %s; ",
        "register an explicit crosswalk with %s"
      ),
      from_nm, to_nm, keys, hint
    )
  }
  n_miss <- sum(!lf[[kf]] %in% shared)
  if (n_miss > 0L) {
    .warn(paste0(
      "%d atom(s) of \"%s\" have no counterpart in \"%s\"; their ",
      "share is uncovered (NA target)"
    ), n_miss, from_nm, to_nm)
  }
  wcol <- .map_weight(source, weight)
  d <- data.frame(
    source = lf[[kf]],
    target = ifelse(lf[[kf]] %in% shared, lf[[kf]], NA_character_),
    w = if (is.null(wcol)) 1 else as.numeric(lf[[wcol]]),
    stringsAsFactors = FALSE
  )
  .finish_map(d, from_nm, to_nm)
}

#' Chosen weight column, or NULL for the unweighted (equal) fallback
#' @noRd
.map_weight <- function(x, weight) {
  if (length(scale_weights(x)) == 0L && is.null(weight)) {
    return(NULL)
  }
  .resolve_weight(x, weight)
}

#' Aggregate an atom frame of from/to/w (plus any `by` columns) into the map
#' schema
#' @noRd
.finish_map <- function(d, from_lab, to_lab, by = character()) {
  miss <- setdiff(c("source", "target", "w", by), names(d))
  if (length(miss) > 0L) {
    .stop("the atom correspondence is missing column(s): %s", .preview(miss))
  }
  d <- d[!is.na(d$source), , drop = FALSE]
  if (nrow(d) == 0L) {
    .stop("no atoms carry a code at `source`; the map would be empty")
  }
  d$w[is.na(d$w)] <- 0
  grp <- c(by, "source", "target")
  map <- d |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grp))) |>
    dplyr::summarise(
      n_overlap = dplyr::n(), w = sum(.data$w),
      .groups = "drop_last"
    ) |>
    dplyr::mutate(
      n_from = sum(.data$n_overlap),
      w_from = sum(.data$w)
    ) |>
    dplyr::ungroup() |>
    as.data.frame()
  ord <- do.call(order, c(map[c(by, "source", "target")], list(na.last = TRUE)))
  map <- map[ord, c(by, "source", "target", "n_from", "n_overlap", "w", "w_from"),
    drop = FALSE
  ]
  rownames(map) <- NULL
  names(map)[names(map) == "source"] <- from_lab
  names(map)[names(map) == "target"] <- to_lab
  map
}

# Registry ---------------------------------------------------------------------

#' Register / look up a direct crosswalk
#'
#' A registered map short-circuits the atom-layer derivation in
#' [`scale_map()`] or [`scale_map_between()`] (and thereby [`recast_scale()`])
#' for one pair of resolutions -- for cases where the exact correspondence is
#' known (hand-audited crosswalks, official concordance tables).
#'
#' `register_scale_map()` and `get_scale_map()` handle a pair of frames of one
#' scale; the map is scoped to that scale, so the same frame pair in two
#' different scales does not collide. `register_scale_map_between()` and
#' `get_scale_map_between()` handle a pair of scales.
#'
#' @param x The [`NestedScale`] the frames belong to, or its name.
#' @param source,target For the within-scale functions, frame names of `x`. For the
#'   `_between` functions, two [`NestedScale`] objects or their names.
#' @param map A `data.frame` shaped like a [`scale_map()`] result: the two
#'   label columns named after the frames (or scales), plus `n_from`,
#'   `n_overlap`, `w` and `w_from`. `NULL` removes a previously registered map.
#'
#' @return Invisibly, the registry key. The `get_` functions return the
#'   registered map (or `NULL`); `list_scale_maps()` a `data.frame` of registry
#'   keys.
#'
#' @examples
#' s <- scale_example()
#' fake <- data.frame(
#'   class = "G1", group = "GC", n_from = 1L,
#'   n_overlap = 1L, w = 1, w_from = 1
#' )
#' register_scale_map(s, "class", "group", fake)
#' list_scale_maps()
#' get_scale_map(s, "class", "group")
#' register_scale_map(s, "class", "group", NULL) # remove
#' clear_scale_maps()
#' @export
register_scale_map <- function(x, source, target, map) {
  .register_map(
    .map_name_of(x, "x"), .frame_label(source, "source"), .frame_label(target, "target"),
    map
  )
}

#' @rdname register_scale_map
#' @export
register_scale_map_between <- function(source, target, map) {
  .register_map("", .map_name_of(source, "source"), .map_name_of(target, "target"), map)
}

#' @noRd
.register_map <- function(scope, from_nm, to_nm, map) {
  key <- paste0(scope, if (nzchar(scope)) ":", from_nm, "->", to_nm)
  if (is.null(map)) {
    if (exists(key, envir = .MAP_REGISTRY, inherits = FALSE)) {
      rm(list = key, envir = .MAP_REGISTRY)
    }
    return(invisible(key))
  }
  if (!is.data.frame(map)) {
    .stop("`map` must be a data.frame (see `scale_map()`) or NULL")
  }
  need <- c(from_nm, to_nm, "n_from", "n_overlap", "w", "w_from")
  miss <- setdiff(need, names(map))
  if (length(miss) > 0L) {
    .stop("`map` is missing column(s): %s", .preview(miss))
  }
  assign(key, as.data.frame(map), envir = .MAP_REGISTRY)
  invisible(key)
}

#' A NestedScale's name, or a name given directly
#' @noRd
.map_name_of <- function(z, arg) {
  if (is.character(z) && length(z) == 1L && nzchar(z)) {
    return(z)
  }
  .check_scale(z, arg)
  .scale_name(z, arg = arg)
}

#' A frame name: one non-empty string
#' @noRd
.frame_label <- function(z, arg) {
  if (!is.character(z) || length(z) != 1L || is.na(z) || !nzchar(z)) {
    .stop("`%s` must be a single frame name", arg)
  }
  z
}

#' @noRd
.get_scale_map <- function(from_nm, to_nm, scope = "") {
  for (key in unique(c(
    paste0(scope, if (nzchar(scope)) ":", from_nm, "->", to_nm),
    paste0(from_nm, "->", to_nm)
  ))) {
    if (exists(key, envir = .MAP_REGISTRY, inherits = FALSE)) {
      return(get(key, envir = .MAP_REGISTRY, inherits = FALSE))
    }
  }
  NULL
}

#' @rdname register_scale_map
#' @export
get_scale_map <- function(x, source, target) {
  .get_scale_map(.frame_label(source, "source"), .frame_label(target, "target"),
    scope = .map_name_of(x, "x")
  )
}

#' @rdname register_scale_map
#' @export
get_scale_map_between <- function(source, target) {
  .get_scale_map(.map_name_of(source, "source"), .map_name_of(target, "target"))
}

#' @rdname register_scale_map
#' @export
list_scale_maps <- function() {
  keys <- sort(ls(envir = .MAP_REGISTRY, all.names = TRUE))
  data.frame(key = keys, stringsAsFactors = FALSE)
}

#' Clear the registered crosswalks
#'
#' Mainly useful in tests.
#'
#' @param name Registry keys to remove (as listed by [`list_scale_maps()`]);
#'   `NULL` (default) clears every registered crosswalk.
#'
#' @examples
#' clear_scale_maps()
#' @return Invisibly `NULL`.
#' @export
clear_scale_maps <- function(name = NULL) {
  present <- ls(envir = .MAP_REGISTRY, all.names = TRUE)
  drop <- if (is.null(name)) present else intersect(name, present)
  if (length(drop) > 0L) rm(list = drop, envir = .MAP_REGISTRY)
  invisible(NULL)
}
