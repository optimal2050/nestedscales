# =============================================================================
# NestedScale (S7 class) -- the dimension-agnostic core type
# =============================================================================
# A `NestedScale` is a nested partition of a set of atoms, in ANY dimension:
#
#   * `leaftable` -- flat enumeration of the atoms, with one column per frame
#                    in the hierarchy, a unique key column (named by `key`),
#                    and zero or more named weight columns
#   * `frames`    -- ordered character vector naming the hierarchy, COARSEST
#                    first (e.g. `c("section", "division", "class")`)
#   * `members`   -- named list giving the full ordered code vocabulary at each
#                    frame (e.g. `members$section = c("A", "B", ...)`)
#   * `key`       -- name of the atom key column (default `"unit"`)
#   * `attributes` -- long table of per-member physical attributes (a
#                    calorific value, a population density) keyed by
#                    `(frame, unit)`, so a value may sit on an atom OR on any
#                    coarser member; see R/attributes.R
#   * `aliases`   -- long table of alternative labels keyed by `(frame, unit)`;
#                    see R/aliases.R
#   * `meta`      -- small named list: `name`, `desc`, `weights`,
#                    `default_weight`, the sample bookkeeping triple
#                    (`coverage`, `parent_totals`, `parent_name`),
#                    `residuals`, `labels`, `source`
#
# Attributes are NOT weights: a weight says how big an atom is and drives
# aggregation; an attribute is a per-member factor consumed row by row by
# `convert_scale()`. The two tables are typed `class_any` with an empty-table
# default so that an object saved before they existed (which reads them as
# NULL) still validates; every accessor normalises NULL to the empty table.
#
# Anything derivable from these (parent/child tables, ancestry, shares, frame
# ranks, resolved attributes) is computed on demand. Nothing is cached on the
# object.
#
# Frames are *partitions of the atoms*, NOT necessarily a strict tree. Real
# hierarchies cross-cut, which is precisely why the atom layer exists and why
# conversion always routes through it. Test a given pair with `scale_nests()`.
#
# `timescales::Calendar` and `geoscales::Geoscale` are subclasses: they fix the
# key name, add their own invariants, and supply a dimension vocabulary through
# `scale_vocab()`.
# =============================================================================

#' NestedScale (S7 class)
#'
#' A nested discrete partition: a flat table of atoms plus the ordered
#' hierarchy of frames that groups them. The dimension is not named -- time and
#' space are the subclasses `Calendar` (timescales) and `Geoscale` (geoscales);
#' anything else (industries, income brackets, temperature regimes, technology
#' vintages) is declared directly.
#'
#' Construct with [`scale_from_leaftable()`].
#'
#' @param leaftable `data.frame` with a unique key column, one column per frame
#'   in `frames`, and zero or more numeric weight columns.
#' @param frames Ordered character vector of frame names (coarsest first); each
#'   must appear as a column of `leaftable`.
#' @param members Named list; `members[[f]]` is the full ordered set of codes
#'   present at frame `f`. Must equal the non-`NA` values of `leaftable[[f]]`
#'   as a set.
#' @param key Name of the atom key column (a single string, default `"unit"`).
#' @param meta Named list of attributes (`name`, `desc`, `weights`,
#'   `default_weight`, `residuals` (see [`scale_residuals()`]), `labels`,
#'   `source`, sample bookkeeping).
#' @param attributes Optional table of per-member physical attributes keyed
#'   by `(frame, unit)`; see [`attach_attributes_scale()`] for the columns.
#' @param aliases Optional table of alternative labels keyed by
#'   `(frame, unit)`; see [`attach_aliases_scale()`] for the columns.
#'
#' @return A `NestedScale` object.
#'
#' @seealso [`scale_from_leaftable()`], [`scale_frames()`], [`scale_units()`]
#' @examples
#' scale_example()
#' @keywords internal
NestedScale <- S7::new_class(
  "NestedScale",
  package = "nestedscales",
  properties = list(
    leaftable  = S7::new_property(S7::class_data.frame),
    frames     = S7::new_property(S7::class_character),
    members    = S7::new_property(S7::class_list),
    key        = S7::new_property(S7::class_character, default = "unit"),
    meta       = S7::new_property(S7::class_list, default = quote(list())),
    # `class_any`, not `class_data.frame`: an object saved before these
    # properties existed reads them as NULL, and a typed property would then
    # fail `S7::validate()` on every subset. The validator below treats NULL
    # as the empty table instead.
    attributes = S7::new_property(S7::class_any,
                                  default = quote(.empty_attributes())),
    aliases    = S7::new_property(S7::class_any,
                                  default = quote(.empty_aliases()))
  ),
  constructor = function(leaftable, frames, members, key = "unit",
                         meta = list(), attributes = NULL, aliases = NULL) {
    S7::new_object(
      S7::S7_object(),
      leaftable  = leaftable,
      frames     = frames,
      members    = members,
      key        = key,
      meta       = meta,
      attributes = attributes %||% .empty_attributes(),
      aliases    = aliases %||% .empty_aliases()
    )
  },
  validator = function(self) {
    errs <- character()

    leaftable <- S7::prop(self, "leaftable")
    frames <- S7::prop(self, "frames")
    members <- S7::prop(self, "members")
    key <- S7::prop(self, "key")
    meta <- S7::prop(self, "meta")
    attributes <- S7::prop(self, "attributes")
    aliases <- S7::prop(self, "aliases")

    # leaftable ---------------------------------------------------------------
    if (!is.data.frame(leaftable)) {
      return("`leaftable` must be a data.frame")
    }
    if (nrow(leaftable) == 0L) {
      errs <- c(errs, "`leaftable` must have at least one row")
    }

    # key ---------------------------------------------------------------------
    if (!is.character(key) || length(key) != 1L || is.na(key) ||
      !nzchar(key)) {
      return("`key` must be a single non-empty string")
    }
    if (!key %in% names(leaftable)) {
      errs <- c(errs, sprintf(
        "`leaftable` must have a `%s` column (the atom key)", key
      ))
    }

    # frames ------------------------------------------------------------------
    if (!is.character(frames) || length(frames) == 0L) {
      errs <- c(errs, "`frames` must be a non-empty character vector")
    } else if (anyDuplicated(frames)) {
      errs <- c(errs, "`frames` must be unique")
    } else {
      bad <- frames[!is_valid_frame(frames)]
      if (length(bad) > 0L) {
        errs <- c(errs, sprintf(
          "`frames` contains invalid names: %s", .preview(bad)
        ))
      }
      # The key name is allowed as the FINEST frame: there the frame column
      # *is* the key column, so nothing collides. As a coarser frame it would
      # clash with the key column, so it stays reserved there.
      clash <- intersect(frames, .RESERVED_COLS)
      if (key %in% frames && !identical(frames[length(frames)], key)) {
        clash <- c(clash, key)
      }
      if (length(clash) > 0L) {
        errs <- c(errs, sprintf(
          "`frames` may not use reserved names: %s", .preview(clash)
        ))
      }
      missing_cols <- setdiff(frames, names(leaftable))
      if (length(missing_cols) > 0L) {
        errs <- c(errs, sprintf(
          "`leaftable` missing frame columns: %s", .preview(missing_cols)
        ))
      }
    }

    # atom key values ---------------------------------------------------------
    if (key %in% names(leaftable)) {
      uid <- leaftable[[key]]
      if (!is.character(uid) || anyNA(uid) || any(!nzchar(uid))) {
        errs <- c(errs, sprintf(
          "`leaftable$%s` must be a non-empty character vector", key
        ))
      } else if (anyDuplicated(uid)) {
        dup <- unique(uid[duplicated(uid)])
        errs <- c(errs, sprintf(
          paste0(
            "`leaftable$%s` must be unique; duplicated: %s. ",
            "Parallel dimensions belong in separate NestedScale objects."
          ),
          key, .preview(dup)
        ))
      }
    }

    # members -----------------------------------------------------------------
    if (!is.list(members)) {
      errs <- c(errs, "`members` must be a list")
    } else if (length(errs) == 0L) {
      missing_mb <- setdiff(frames, names(members))
      if (length(missing_mb) > 0L) {
        errs <- c(errs, sprintf(
          "`members` missing entries for: %s", .preview(missing_mb)
        ))
      }
      for (f in intersect(frames, names(members))) {
        mb <- members[[f]]
        if (!is.character(mb) || length(mb) == 0L || anyNA(mb) ||
          any(!nzchar(mb)) || anyDuplicated(mb)) {
          errs <- c(errs, sprintf(
            "`members[[\"%s\"]]` must be a unique non-empty character vector",
            f
          ))
          next
        }
        seen <- unique(stats::na.omit(as.character(leaftable[[f]])))
        if (!setequal(seen, mb)) {
          errs <- c(errs, sprintf(
            paste0(
              "`members[[\"%s\"]]` must contain exactly the non-NA ",
              "values present in `leaftable$%s`"
            ), f, f
          ))
        }
      }
    }

    # attributes and aliases --------------------------------------------------
    # Checked against the members, so only once those are known to be sound.
    # NULL is the empty table (an object saved before these existed).
    if (length(errs) == 0L && is.list(members)) {
      v <- scale_vocab(self)
      if (!is.null(attributes)) {
        if (!is.data.frame(attributes)) {
          errs <- c(errs, "`attributes` must be a data.frame or NULL")
        } else {
          errs <- c(errs, .check_attributes_table(attributes, frames,
                                                  members, v))
        }
      }
      if (!is.null(aliases)) {
        if (!is.data.frame(aliases)) {
          errs <- c(errs, "`aliases` must be a data.frame or NULL")
        } else {
          errs <- c(errs, .check_aliases_table(aliases, frames, members, v))
        }
      }
    }

    # weights -----------------------------------------------------------------
    wts <- meta[["weights"]]
    if (!is.null(wts)) {
      if (!is.character(wts) || anyNA(wts)) {
        errs <- c(errs, "`meta$weights` must be a character vector")
      } else {
        for (w in wts) {
          if (!w %in% names(leaftable)) {
            errs <- c(errs, sprintf(
              "weight column `%s` not found in `leaftable`", w
            ))
            next
          }
          v <- leaftable[[w]]
          if (!is.numeric(v)) {
            errs <- c(errs, sprintf("weight column `%s` must be numeric", w))
          } else if (any(!is.finite(v) & !is.na(v))) {
            errs <- c(errs, sprintf("weight column `%s` must be finite", w))
          } else if (any(v < 0, na.rm = TRUE)) {
            errs <- c(errs, sprintf("weight column `%s` must be >= 0", w))
          } else if (isTRUE(sum(v, na.rm = TRUE) <= 0)) {
            errs <- c(errs, sprintf("weight column `%s` sums to zero", w))
          }
        }
        dw <- meta[["default_weight"]]
        if (!is.null(dw) && !(length(dw) == 1L && dw %in% wts)) {
          errs <- c(errs, "`meta$default_weight` must be one of `meta$weights`")
        }
      }
    }

    # residuals ---------------------------------------------------------------
    # Units that carry a real value but are not a destination for allocation:
    # non-regionalized GDP, non-allocable taxes, an "n.e.c." bucket. Declared
    # per frame because codes are not unique across frames.
    res <- meta[["residuals"]]
    if (!is.null(res)) {
      if (!is.list(res) || is.null(names(res)) || any(!nzchar(names(res)))) {
        errs <- c(errs, paste0(
          "`meta$residuals` must be a named list, one ",
          "entry per frame"
        ))
      } else {
        bad_fr <- setdiff(names(res), frames)
        if (length(bad_fr) > 0L) {
          errs <- c(errs, sprintf(
            "`meta$residuals` names frame(s) that are not frames: %s",
            .preview(bad_fr)
          ))
        }
        for (f in intersect(names(res), frames)) {
          codes <- res[[f]]
          if (!is.character(codes) || anyNA(codes)) {
            errs <- c(errs, sprintf(
              "`meta$residuals[[\"%s\"]]` must be a character vector", f
            ))
            next
          }
          unknown <- setdiff(codes, members[[f]])
          if (length(unknown) > 0L) {
            errs <- c(errs, sprintf(
              "`meta$residuals[[\"%s\"]]` names non-member(s): %s",
              f, .preview(unknown)
            ))
          }
        }
      }
    }

    # meta --------------------------------------------------------------------
    if (!is.list(meta)) {
      errs <- c(errs, "`meta` must be a list")
    }

    # Sample bookkeeping: coverage must be verifiable from the object itself.
    # `[[ ]]`, never `$`: `meta$coverage` would partial-match a subclass's
    # `coverage_class` field.
    if (is.list(meta) && !is.null(meta[["coverage"]])) {
      cov <- meta[["coverage"]]
      wts <- meta[["weights"]] %||% character()
      if (!is.numeric(cov) || is.null(names(cov)) ||
        !all(names(cov) %in% wts)) {
        errs <- c(errs, paste0(
          "`meta$coverage` must be a named numeric ",
          "over declared weights"
        ))
      } else if (!all(is.finite(cov)) || any(cov <= 0) || any(cov > 1)) {
        errs <- c(errs, "`meta$coverage` values must lie in (0, 1]")
      } else if (!is.null(meta[["parent_totals"]])) {
        pt <- meta[["parent_totals"]]
        for (w in intersect(names(cov), names(pt))) {
          got <- sum(leaftable[[w]], na.rm = TRUE) / pt[[w]]
          if (abs(got - cov[[w]]) > 1e-8) {
            errs <- c(errs, sprintf(
              "`meta$coverage[\"%s\"]` (%.6g) does not match the leaftable (%.6g)",
              w, cov[[w]], got
            ))
          }
        }
      }
      if (!is.null(meta[["parent_name"]]) &&
        !(is.character(meta[["parent_name"]]) &&
          length(meta[["parent_name"]]) == 1L &&
          nzchar(meta[["parent_name"]]))) {
        errs <- c(errs, "`meta$parent_name` must be a single non-empty string")
      }
    }

    if (length(errs) == 0L) NULL else errs
  }
)

# Dimension vocabulary ---------------------------------------------------------

#' The dimension vocabulary of a scale
#'
#' Engine messages are written once and interpolated with the words of the
#' dimension at hand, so a `Calendar` flowing through the shared engine still
#' errors in the language of time ("timeframe", "timeslice") and a `Geoscale`
#' in the language of space ("geoframe", "region"). Subclasses supply their own
#' method; the `NestedScale` default is the neutral vocabulary.
#'
#' @param x A [`NestedScale`].
#' @param ... Passed to methods.
#'
#' @return A named list with elements `object`, `frame`, `frames`, `unit`,
#'   `units`, `atoms`, and optionally `register_rule` and `register_map`: the
#'   calls that error messages suggest for registering a value column's rule
#'   or an explicit crosswalk, when the dimension package offers its own
#'   (`"register_geoscale_rule()"`).
#'
#' @examples
#' scale_vocab(scale_example())
#' @export
scale_vocab <- S7::new_generic("scale_vocab", "x")

S7::method(scale_vocab, NestedScale) <- function(x, ...) {
  list(
    object = "NestedScale", frame = "frame", frames = "frames",
    unit = "unit", units = "units", atoms = "atoms"
  )
}

# Accessors --------------------------------------------------------------------

#' Frame rank
#'
#' Position of a frame in the hierarchy: 1 is the coarsest.
#'
#' @param x A [`NestedScale`].
#' @param frame Character vector of frame names.
#'
#' @return An integer vector of ranks; `NA` for names that are not frames of
#'   `x`.
#'
#' @examples
#' s <- scale_example()
#' scale_rank(s, c("group", "unit"))
#' @export
scale_rank <- function(x, frame) {
  .check_scale(x)
  frames <- S7::prop(x, "frames")
  r <- match(frame, frames)
  # The key is finer than every frame when it is the atom level, so it ranks
  # one past the last. Without this the direction test in the recast pipeline
  # compares against NA.
  key <- S7::prop(x, "key")
  r[is.na(r) & frame == key] <- length(frames) + 1L
  r
}

#' Frames of a NestedScale
#'
#' The hierarchy names, ordered coarsest first. The last entry is the atom
#' frame whenever one frame enumerates the atoms; when none does -- a
#' `Calendar`'s atoms are combinations of its frames -- the key column is the
#' atom level instead.
#'
#' @param x A [`NestedScale`].
#' @param finest Return only the finest (atom) frame.
#'
#' @return A character vector of frame names, or a single name when
#'   `finest = TRUE`.
#'
#' @examples
#' s <- scale_example()
#' scale_frames(s)
#' scale_frames(s, finest = TRUE)
#' @export
scale_frames <- function(x, finest = FALSE) {
  .check_scale(x)
  f <- S7::prop(x, "frames")
  if (isTRUE(finest)) f[length(f)] else f
}

#' Units of a NestedScale
#'
#' The code vocabulary at one frame, in canonical order.
#'
#' @param x A [`NestedScale`].
#' @param frame A single frame name; defaults to the finest frame (the atoms).
#'
#' @return A character vector of unit codes.
#'
#' @examples
#' s <- scale_example()
#' scale_units(s)
#' scale_units(s, "group")
#' @export
scale_units <- function(x, frame = NULL) {
  .check_scale(x)
  if (is.null(frame)) frame <- .atom_level(x)
  .check_frame(x, frame)
  if (identical(frame, S7::prop(x, "key")) &&
    !frame %in% S7::prop(x, "frames")) {
    return(unique(as.character(S7::prop(x, "leaftable")[[frame]])))
  }
  S7::prop(x, "members")[[frame]]
}

#' The level at which a scale enumerates its atoms
#'
#' The finest frame when one code of it sits on each leaftable row, and the
#' key column otherwise. A [`NestedScale`] built from a nested hierarchy is the
#' first kind; a timescales `Calendar` is the second, because its timeslices
#' are combinations of its frames rather than codes of any one of them.
#'
#' Needed by the dimension packages: it is the `frame` to pass to
#' [`join_scale()`] or [`recast_scale()`] for data keyed at the atoms.
#'
#' @param x A [`NestedScale`].
#' @return A single string -- a frame name, or the key.
#' @examples
#' scale_atom_level(scale_example())
#' @export
scale_atom_level <- function(x) {
  .check_scale(x)
  .atom_level(x)
}

#' The level at which the leaftable enumerates atoms
#'
#' Usually the finest frame, which is how `scale_example()` and `Geoscale` are
#' built: there the finest frame has one code per leaftable row. A `Calendar`
#' is not like that -- its atoms are combinations of its frames
#' (`d365_h24` has 8760 timeslices over YDAY x HOUR, and the irregular
#' `m12_md365` has 365 over MONTH x MDAY, which is not even a full product) --
#' so no frame enumerates them and the KEY column does.
#'
#' Decided this way rather than having the dimension packages declare an
#' atom-level frame (so `calendar_timeframes()` would return
#' `YDAY, HOUR, timeslice`). That alternative fits this package untouched and
#' is worth reconsidering, but it changes the public output of a released
#' package and reaches into every consumer that reads `@timeframes`, energyRt
#' included. Declined on blast radius, not on merit.
#' @noRd
.atom_level <- function(x) {
  frames <- S7::prop(x, "frames")
  finest <- frames[length(frames)]
  n <- length(S7::prop(x, "members")[[finest]])
  if (!is.null(n) && n == nrow(S7::prop(x, "leaftable"))) {
    finest
  } else {
    S7::prop(x, "key")
  }
}

#' The levels the navigation verbs step through: the frames, plus the key as
#' the finest level when the key is the atom level.
#' @noRd
.nav_levels <- function(x) {
  fr <- S7::prop(x, "frames")
  at <- .atom_level(x)
  if (at %in% fr) fr else c(fr, at)
}

#' The atom key column name
#'
#' @param x A [`NestedScale`].
#' @return A single string.
#' @examples
#' scale_key(scale_example())
#' @export
scale_key <- function(x) {
  .check_scale(x)
  S7::prop(x, "key")
}

#' The leaftable of a NestedScale
#'
#' The one-row-per-atom table the scale is built on, as a plain `data.frame` --
#' the exported accessor to prefer over reaching for `x@leaftable`.
#' `as.data.frame()` and `ggplot2::fortify()` on a NestedScale are equivalent, so
#' `ggplot(s) + geom_*()` pipelines work directly.
#'
#' @param x A [`NestedScale`].
#' @param row.names,optional Ignored (S3 signature compatibility).
#' @param ... Ignored.
#' @return A `data.frame`: one row per atom, with the frame columns plus any
#'   weight columns.
#' @examples
#' head(scale_leaftable(scale_example()))
#' head(as.data.frame(scale_example()))
#' @export
scale_leaftable <- function(x) {
  .check_scale(x)
  S7::prop(x, "leaftable")
}

#' @rdname scale_leaftable
#' @method as.data.frame NestedScale
as.data.frame.NestedScale <- function(x, row.names = NULL, optional = FALSE, ...) {
  scale_leaftable(x)
}

S7::method(as.data.frame, NestedScale) <- as.data.frame.NestedScale

#' @rdname scale_leaftable
#' @export
`as.data.frame.nestedscales::NestedScale` <- as.data.frame.NestedScale

#' Weight columns of a NestedScale
#'
#' @param x A [`NestedScale`].
#'
#' @return A character vector of weight column names (possibly empty).
#'
#' @examples
#' scale_weights(scale_example())
#' @export
scale_weights <- function(x) {
  .check_scale(x)
  S7::prop(x, "meta")[["weights"]] %||% character()
}

#' Subset a subclass's per-atom payload
#'
#' The seam a dimension package overrides when it carries per-atom data
#' alongside the leaftable -- geoscales' `Geoscale` and its geometry. Called
#' whenever the engine rebuilds an object from a row subset, with the kept row
#' indices. The `NestedScale` default has no payload and returns `x` unchanged.
#'
#' @param x A [`NestedScale`].
#' @param ... Method arguments: `i`, the integer vector of kept leaftable row
#'   indices.
#'
#' @return `x`, with any payload subset to the kept rows.
#'
#' @examples
#' identical(
#'   scale_payload_slice(scale_example(), 1:3),
#'   scale_example()
#' )
#' @export
scale_payload_slice <- S7::new_generic("scale_payload_slice", "x")

S7::method(scale_payload_slice, NestedScale) <- function(x, i, ...) x

#' Collapse a subclass's per-atom payload
#'
#' The companion of [`scale_payload_slice()`] for the rebuilds that MERGE
#' atoms rather than keep a subset of them -- [`prune_scale()`], which makes
#' a coarser frame the new atom layer. Called with `map`, an integer vector
#' with one entry per row of the OLD leaftable giving the index of the NEW
#' row that atom was merged into, or `NA` for an atom that was dropped.
#'
#' The `NestedScale` default returns `x` unchanged, which is right for a
#' payload keyed by member codes (the core's own attribute and alias tables
#' are re-keyed by the engine itself). A subclass whose payload is positional
#' -- one geometry per leaftable row -- must override it and merge its
#' payload by `map`; if it does not, its own validator rejects the length
#' mismatch, so the failure is loud rather than a silently misaligned
#' payload.
#'
#' @param x A [`NestedScale`].
#' @param ... Method arguments: `map`, the integer vector described above.
#'
#' @return `x`, with any payload merged to the new rows.
#'
#' @examples
#' identical(
#'   scale_payload_collapse(scale_example(), c(1L, 1L, 2L, 2L, 3L, 3L, NA)),
#'   scale_example()
#' )
#' @export
scale_payload_collapse <- S7::new_generic("scale_payload_collapse", "x")

S7::method(scale_payload_collapse, NestedScale) <- function(x, map, ...) x

#' An alias property for a subclass
#'
#' Builds a getter/setter property that reads and writes an inherited property
#' under a different name -- how timescales' `Calendar` keeps `@timeframes` and
#' geoscales' `Geoscale` keeps `@geoframes` working over the inherited
#' `@frames`, so no existing code has to change when they become subclasses.
#'
#' The setter is a no-op on `NULL`. S7's generated constructor writes every
#' dynamic property once with `NULL` before the real values are set, so a
#' setter that forwards `NULL` makes the class impossible to construct.
#'
#' @param name Name of the inherited property to alias.
#'
#' @return An S7 property.
#'
#' @examples
#' Aliased <- S7::new_class("Aliased",
#'   parent = scale_class(),
#'   properties = list(levels = scale_alias_property("frames"))
#' )
#' a <- Aliased(
#'   leaftable = scale_leaftable(scale_example()),
#'   frames = scale_frames(scale_example()),
#'   members = S7::prop(scale_example(), "members")
#' )
#' a@levels
#' @export
scale_alias_property <- function(name) {
  force(name)
  S7::new_property(
    getter = function(self) S7::prop(self, name),
    setter = function(self, value) {
      if (is.null(value)) {
        return(self)
      }
      S7::prop(self, name) <- value
      self
    }
  )
}

#' Units that are residuals
#'
#' A residual carries a real value but is not a destination for allocation:
#' non-regionalized GDP, taxes that belong to no industry, an "n.e.c." bucket.
#' It aggregates upward like any other unit -- that is the point, it is what
#' makes the parent total reconcile -- but [`recast_scale()`] never splits a
#' coarse figure INTO one.
#'
#' Declare them when building the scale, per frame, because codes are not
#' unique across frames:
#' `scale_from_leaftable(..., residuals = list(unit = "DE_XR"))`.
#'
#' @param x A [`NestedScale`].
#' @param frame A single frame name for just that frame's residuals, or
#'   `NULL` for the whole named list.
#'
#' @return A character vector of unit codes, or the named list over frames.
#'   Empty when the scale declares none.
#'
#' @examples
#' s <- scale_example()
#' scale_residuals(s) # none declared
#'
#' lf <- scale_leaftable(s)
#' r <- scale_from_leaftable(
#'   lf,
#'   frames = scale_frames(s), key = "unit",
#'   weights = scale_weights(s), name = "with_residual",
#'   residuals = list(unit = "OTH")
#' )
#' scale_residuals(r, "unit")
#' @export
scale_residuals <- function(x, frame = NULL) {
  .check_scale(x)
  res <- S7::prop(x, "meta")[["residuals"]]
  if (is.null(res)) {
    return(if (is.null(frame)) list() else character())
  }
  if (is.null(frame)) {
    return(res)
  }
  .check_frame(x, frame)
  res[[frame]] %||% character()
}

#' @noRd
.check_scale <- function(x, arg = "x") {
  if (!S7::S7_inherits(x, NestedScale)) {
    # A product is the near miss worth naming: it holds scales but is not one,
    # and its per-atom table is the thing a caller must ask for deliberately.
    if (S7::S7_inherits(x, ScaleProduct)) {
      .stop(paste0(
        "`%s` is a ScaleProduct, not a single NestedScale. Its atoms ",
        "are not materialised -- use `scale_axes()` for the ",
        "component scales, or `product_atoms()` to build the ",
        "grid."
      ), arg)
    }
    .stop("`%s` must be a NestedScale object", arg)
  }
  invisible(TRUE)
}

#' Resolve a frame name against a NestedScale
#'
#' @param x A [`NestedScale`].
#' @param frame A single frame name.
#' @param arg Argument name used in the error message.
#' @noRd
.check_frame <- function(x, frame, arg = NULL) {
  f <- S7::prop(x, "frames")
  v <- scale_vocab(x)
  if (is.null(arg)) arg <- v$frame
  if (is.null(frame) || length(frame) != 1L || is.na(frame)) {
    .stop(
      "`%s` must be a single %s name; one of: %s",
      arg, v$frame, paste(f, collapse = ", ")
    )
  }
  if (!frame %in% c(f, S7::prop(x, "key"))) {
    .stop(
      "`%s` = \"%s\" is not a %s of this %s; one of: %s",
      arg, frame, v$frame, v$object,
      paste(unique(c(f, S7::prop(x, "key"))), collapse = ", ")
    )
  }
  invisible(frame)
}

#' Resolve the weight column to use
#' @noRd
.resolve_weight <- function(x, weight = NULL) {
  wts <- scale_weights(x)
  if (is.null(weight)) {
    weight <- S7::prop(x, "meta")[["default_weight"]] %||%
      (if (length(wts) > 0L) wts[[1L]] else NULL)
  }
  if (is.null(weight)) {
    .stop(paste0(
      "no weight column available; declare one via ",
      "`meta$weights` or pass `weight=`"
    ))
  }
  if (!weight %in% wts) {
    .stop(
      "`weight` = \"%s\" is not a weight column; one of: %s",
      weight, if (length(wts)) paste(wts, collapse = ", ") else "<none>"
    )
  }
  weight
}

# Format / print ---------------------------------------------------------------

S7::method(format, NestedScale) <- function(x, ...) {
  sprintf(
    "<NestedScale[%s] atoms=%d>",
    paste(S7::prop(x, "frames"), collapse = "/"),
    nrow(S7::prop(x, "leaftable"))
  )
}

#' @method print NestedScale
print.NestedScale <- function(x, ...) {
  meta <- S7::prop(x, "meta")
  f <- S7::prop(x, "frames")
  mb <- S7::prop(x, "members")
  lf <- S7::prop(x, "leaftable")
  v <- scale_vocab(x)

  name <- meta[["name"]] %||% ""
  cat(v$object, ": ", if (nzchar(name)) name else "<unnamed>", "\n", sep = "")
  if (!is.null(meta[["desc"]]) && nzchar(meta[["desc"]])) {
    cat("Description:", meta[["desc"]], "\n")
  }

  cat(toupper(substring(v$frames, 1, 1)), substring(v$frames, 2),
    " (", length(f), ", coarsest first):\n",
    sep = ""
  )
  for (i in seq_along(f)) {
    l <- f[i]
    n_code <- length(mb[[l]])
    n_na <- sum(is.na(lf[[l]]))
    cat("  ", strrep("  ", i - 1L), "- ", l, " (", n_code, ")",
      if (n_na > 0L) sprintf("  [%d %s unassigned]", n_na, v$unit) else "",
      "\n",
      sep = ""
    )
  }
  cat("Atoms: ", nrow(lf), "\n", sep = "")

  wts <- scale_weights(x)
  if (length(wts) > 0L) {
    dw <- meta[["default_weight"]] %||% wts[[1L]]
    cat("Weights: ", paste(wts, collapse = ", "),
      " (default: ", dw, ")\n",
      sep = ""
    )
  }
  at <- .attr_table(x)
  if (nrow(at) > 0L) {
    per_frame <- table(factor(at$frame, levels = f))
    per_frame <- per_frame[per_frame > 0L]
    cat("Attributes: ", paste(unique(at$attribute), collapse = ", "),
      " (sources: ", paste(unique(at$source), collapse = ", "), ") -- ",
      paste(sprintf("%d at %s", as.integer(per_frame), names(per_frame)),
        collapse = ", "
      ),
      "\n",
      sep = ""
    )
  }
  al <- .alias_table(x)
  if (nrow(al) > 0L) {
    cat("Aliases: ", nrow(al), " (", paste(unique(al$source), collapse = ", "),
      ")\n",
      sep = ""
    )
  }
  if (!is.null(meta[["source"]])) cat("Source: ", meta[["source"]], "\n", sep = "")
  invisible(x)
}

S7::method(print, NestedScale) <- print.NestedScale

# Dispatch on the fully-qualified S7 class name: `class()` reports
# `nestedscales::NestedScale` first, and that is the registration base-R `print()`
# finds before falling through to `print.S7_object`.
#' @export
`print.nestedscales::NestedScale` <- print.NestedScale

# Summary ----------------------------------------------------------------------

#' Summarize a NestedScale
#'
#' Complements [print()] with the quantitative view: per-weight totals and
#' coverage, and the adjacent-frame nesting table. Returns a `"summary_Scale"`
#' object (a list) with its own print method.
#'
#' @param object A [`NestedScale`].
#' @param x A `"summary_Scale"` object (the print method's argument).
#' @param ... Ignored.
#' @return `summary()` returns a list of class `"summary_Scale"`: `name`,
#'   `desc`, `frames` (named member counts), `unassigned` (named NA-atom
#'   counts), `n_atoms`, `weights`, `weight_totals`, `default_weight`,
#'   `coverage` (see [scale_coverage()]), `sampled`, `parent_name`, `nesting`
#'   (adjacent-pair table with offender counts, see [scale_nests()]),
#'   `attributes` (a `data.frame` of row counts by `attribute`, `frame` and
#'   `source`), `aliases` (counts by `source`), `source`, `vocab`.
#' @examples
#' summary(scale_example())
#' @method summary NestedScale
summary.NestedScale <- function(object, ...) {
  meta <- S7::prop(object, "meta")
  lt <- S7::prop(object, "leaftable")
  fr <- S7::prop(object, "frames")
  wts <- scale_weights(object)
  cov <- scale_coverage(object)
  at <- .attr_table(object)
  al <- .alias_table(object)

  attr_counts <- if (nrow(at) > 0L) {
    cnt <- as.data.frame(
      table(
        attribute = at$attribute, frame = factor(at$frame, levels = fr),
        source = at$source
      ),
      stringsAsFactors = FALSE
    )
    names(cnt)[4L] <- "n"
    cnt <- cnt[cnt$n > 0L, , drop = FALSE]
    rownames(cnt) <- NULL
    cnt
  } else {
    data.frame(
      attribute = character(), frame = character(), source = character(),
      n = integer(), stringsAsFactors = FALSE
    )
  }
  alias_counts <- if (nrow(al) > 0L) {
    cnt <- as.data.frame(table(source = al$source), stringsAsFactors = FALSE)
    names(cnt)[2L] <- "n"
    cnt
  } else {
    data.frame(source = character(), n = integer(), stringsAsFactors = FALSE)
  }

  nesting <- NULL
  if (length(fr) > 1L) {
    nesting <- do.call(rbind, lapply(seq_len(length(fr) - 1L), function(i) {
      ok <- scale_nests(object, fr[i], fr[i + 1L])
      data.frame(
        parent = fr[i], child = fr[i + 1L],
        nests = isTRUE(ok),
        n_offenders = length(attr(ok, "offenders")),
        stringsAsFactors = FALSE
      )
    }))
  }

  out <- list(
    name = meta[["name"]] %||% "",
    desc = meta[["desc"]] %||% "",
    frames = vapply(S7::prop(object, "members")[fr], length, integer(1)),
    unassigned = vapply(fr, function(l) sum(is.na(lt[[l]])), integer(1)),
    n_atoms = nrow(lt),
    weights = wts,
    weight_totals = if (length(wts)) {
      colSums(as.data.frame(lt)[, wts, drop = FALSE], na.rm = TRUE)
    } else {
      numeric(0)
    },
    default_weight = meta[["default_weight"]],
    coverage = cov,
    sampled = any(cov < 1),
    parent_name = meta[["parent_name"]],
    nesting = nesting,
    attributes = attr_counts,
    aliases = alias_counts,
    source = meta[["source"]],
    vocab = scale_vocab(object)
  )
  class(out) <- "summary_Scale"
  out
}

S7::method(summary, NestedScale) <- summary.NestedScale

#' @rdname summary.NestedScale
#' @export
`summary.nestedscales::NestedScale` <- summary.NestedScale

#' @rdname summary.NestedScale
#' @export
#' @method print summary_Scale
print.summary_Scale <- function(x, ...) {
  v <- x$vocab %||% list(object = "NestedScale", frames = "frames", units = "units")
  cat("<summary of ", v$object,
    if (nzchar(x$name)) paste0(" '", x$name, "'"), ">\n",
    sep = ""
  )
  if (nzchar(x$desc)) cat("  desc:          ", x$desc, "\n", sep = "")
  cat("  ", format(paste0(v$frames, ":"), width = 16),
    paste(sprintf("%s (%d)", names(x$frames), x$frames), collapse = " / "),
    "\n",
    sep = ""
  )
  cat("  atoms:          ", x$n_atoms, "\n", sep = "")
  if (any(x$unassigned > 0)) {
    ua <- x$unassigned[x$unassigned > 0]
    cat("  unassigned:     ",
      paste(sprintf("%s (%d)", names(ua), ua), collapse = ", "),
      "\n",
      sep = ""
    )
  }
  if (length(x$weights)) {
    cat("  weight totals:  ",
      paste(
        sprintf(
          "%s = %s", names(x$weight_totals),
          format(x$weight_totals, big.mark = ",", digits = 6)
        ),
        collapse = ", "
      ),
      if (!is.null(x$default_weight)) {
        paste0("  (default: ", x$default_weight, ")")
      },
      "\n",
      sep = ""
    )
  }
  if (isTRUE(x$sampled)) {
    cat("  SAMPLED:        ",
      paste(sprintf("%s %.1f%%", names(x$coverage), 100 * x$coverage),
        collapse = ", "
      ),
      if (!is.null(x$parent_name) && nzchar(x$parent_name)) {
        paste0(" of '", x$parent_name, "'")
      },
      "\n",
      sep = ""
    )
  }
  if (!is.null(x$nesting)) {
    for (i in seq_len(nrow(x$nesting))) {
      r <- x$nesting[i, ]
      cat("  nesting:        ", r$parent, " > ", r$child, ": ",
        if (r$nests) {
          "nested"
        } else {
          paste0("CROSS-CUTTING (", r$n_offenders, " offender(s))")
        },
        "\n",
        sep = ""
      )
    }
  }
  if (!is.null(x$attributes) && nrow(x$attributes) > 0L) {
    for (i in seq_len(nrow(x$attributes))) {
      r <- x$attributes[i, ]
      cat("  attributes:     ", r$attribute, " at ", r$frame, ": ", r$n,
        " (", r$source, ")\n",
        sep = ""
      )
    }
  }
  if (!is.null(x$aliases) && nrow(x$aliases) > 0L) {
    cat("  aliases:        ",
      paste(sprintf("%s (%d)", x$aliases$source, x$aliases$n),
        collapse = ", "
      ),
      "\n",
      sep = ""
    )
  }
  if (!is.null(x$source)) cat("  source:         ", x$source, "\n", sep = "")
  invisible(x)
}

# Other base generics ----------------------------------------------------------

#' @rdname scale_frames
#' @method names NestedScale
names.NestedScale <- function(x) scale_frames(x)

S7::method(names, NestedScale) <- names.NestedScale

#' @export
`names.nestedscales::NestedScale` <- names.NestedScale

#' Is this a scale, or a product of scales?
#'
#' The classes themselves are not exported (the package's surface is its
#' functions), so these are how calling code asks. Build a scale with
#' [`scale_from_leaftable()`] and a product with [`scale_product()`].
#'
#' Named with the object prefix rather than `is_scale()`, which `ggplot2`
#' already exports.
#'
#' @param x Any object.
#' @return A single `TRUE` or `FALSE`. A product is NOT a scale: it holds
#'   several and materialises no atoms of its own.
#' @examples
#' scale_is(scale_example())
#' scale_is(data.frame(unit = "U1"))
#' scale_is_product(scale_product(a = scale_example(), b = scale_example2()))
#' @export
scale_is <- function(x) {
  S7::S7_inherits(x, NestedScale)
}

#' @rdname scale_is
#' @export
scale_is_product <- function(x) {
  S7::S7_inherits(x, ScaleProduct)
}

#' The scale classes, for subclassing and dispatch
#'
#' The classes are not exported under their own names (the package's surface
#' is its functions), so these return them. Needed to build a subclass
#' (`S7::new_class(..., parent = scale_class())`, which is what
#' [`scale_alias_property()`] is for) or to register an S7 method against one.
#' To merely ask what an object is, use [`scale_is()`].
#'
#' @return The S7 class object.
#' @examples
#' scale_class()
#' S7::S7_inherits(scale_example(), scale_class())
#' @export
scale_class <- function() {
  NestedScale
}

#' @rdname scale_class
#' @export
scale_product_class <- function() {
  ScaleProduct
}

#' The rule-registration call to suggest in errors for a scale
#' @noRd
.rule_hint <- function(x) scale_vocab(x)$register_rule %||% "register_scale_rule()"
