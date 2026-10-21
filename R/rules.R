# =============================================================================
# Aggregation rule registry
# =============================================================================
# A package-level environment mapping a parameter name to the rule used when
# recasting it, plus an optional weight column. `recast_scale()` consults the
# registry when the caller does not pass `rule=`; an explicit argument always
# wins. A column with neither an explicit rule nor a registry entry is an
# ERROR -- there is deliberately no fallback (ruling 2026-08-13).
#
# Entries are SCOPED so the dimension packages cannot collide: a rule for
# "load" in the time dimension is a different statement from a rule for "load"
# in space (time renormalises by duration, space simply adds up). A scoped
# lookup falls back to the unscoped entry, so a rule that holds in every
# dimension can still be registered once.
# =============================================================================

#' Supported aggregation rules
#'
#' Each rule defines behaviour in **both** directions. Direction is taken from
#' the frame ranks, so aggregation and disaggregation are one operation:
#'
#' \describe{
#'   \item{`sum`}{Up: sum. Down: split proportionally to the weight.
#'     For extensive quantities (capacity, demand, area, population).}
#'   \item{`weighted_mean`}{Up: weight-weighted mean. Down: copy unchanged.
#'     For intensive quantities (efficiency, price, capacity factor).}
#'   \item{`mean`}{Up: unweighted mean. Down: copy unchanged.}
#'   \item{`copy`}{Up: the common value, erroring if it is not constant.
#'     Down: copy unchanged. For scale-invariant scalars.}
#'   \item{`sd`}{Up: standard deviation over the atoms (aggregation only;
#'     going down it degenerates to `NA` for single-atom groups).}
#'   \item{`share`}{Share within parent: each source unit's value divided by
#'     the total over its parent group. Unlike every other rule the result
#'     stays keyed at the **source** frame -- the recast target (or
#'     `parent=`) names the parent -- so it cannot be mixed with other rules
#'     in one call (the two share rules mix freely, being one computation).
#'     For building distribution keys and normalised profiles; requires
#'     `from` to nest within the parent.}
#'   \item{`logshare`}{The same computation as `share` -- the values ARE
#'     shares -- but figures draw it on a fixed log10 percent scale
#'     (0.01%..100%), where `share` gets a fixed linear 0..1 scale.}
#' }
#'
#' @format A character vector of length 7.
#' @examples
#' SCALE_RULES
#' @export
SCALE_RULES <- c(
  "sum", "weighted_mean", "mean", "copy", "sd", "share",
  "logshare"
)

#' The share rules, which are one computation under two display intents
#' @noRd
.SHARE_RULES <- c("share", "logshare")

#' @noRd
.RULE_REGISTRY <- new.env(parent = emptyenv())

#' Registry key for a (scope, param) pair
#' @noRd
.rule_key <- function(param, scope = NULL) {
  if (is.null(scope) || !nzchar(scope)) param else paste0(scope, ":", param)
}

#' Register how a parameter should be recast
#'
#' Records the rule (and optionally the weight) to use for a named value
#' column, so callers of [`recast_scale()`] need not repeat it. Downstream
#' packages register their own parameter maps at load time.
#'
#' @param param Name of the value column.
#' @param rule One of [`SCALE_RULES`].
#' @param weight Optional weight column name used by `sum` (down) and
#'   `weighted_mean` (up). `NULL` means the scale's default weight.
#' @param scope Optional dimension namespace (e.g. `"calendar"`,
#'   `"geoscale"`). `NULL` registers the rule for every dimension.
#'
#' @return Invisibly, the registered entry.
#'
#' @examples
#' register_scale_rule("capacity", "sum")
#' register_scale_rule("eff", "weighted_mean", weight = "count")
#' get_scale_rule("eff")
#' clear_scale_rules(c("capacity", "eff"))
#' @export
register_scale_rule <- function(param, rule, weight = NULL, scope = NULL) {
  if (!is.character(param) || length(param) != 1L || is.na(param) ||
    !nzchar(param)) {
    .stop("`param` must be a single non-empty string")
  }
  rule <- match.arg(rule, SCALE_RULES)
  if (!is.null(weight) && (!is.character(weight) || length(weight) != 1L)) {
    .stop("`weight` must be a single string or NULL")
  }
  if (!is.null(scope) && (!is.character(scope) || length(scope) != 1L)) {
    .stop("`scope` must be a single string or NULL")
  }
  entry <- list(rule = rule, weight = weight, scope = scope)
  assign(.rule_key(param, scope), entry, envir = .RULE_REGISTRY)
  invisible(entry)
}

#' Look up a registered rule
#'
#' A scoped lookup prefers the entry registered for that scope and falls back
#' to an unscoped one.
#'
#' @param param Name of the value column.
#' @param scope Optional dimension namespace.
#'
#' @return A list with elements `rule`, `weight` and `scope`, or `NULL` if
#'   `param` has not been registered.
#'
#' @examples
#' register_scale_rule("demand", "sum")
#' get_scale_rule("demand")
#' get_scale_rule("not_registered")
#' clear_scale_rules("demand")
#' @export
get_scale_rule <- function(param, scope = NULL) {
  if (!is.character(param) || length(param) != 1L) {
    return(NULL)
  }
  for (k in unique(c(.rule_key(param, scope), param))) {
    if (exists(k, envir = .RULE_REGISTRY, inherits = FALSE)) {
      return(get(k, envir = .RULE_REGISTRY, inherits = FALSE))
    }
  }
  NULL
}

#' List registered rules
#'
#' @param scope Optional dimension namespace; `NULL` lists every entry.
#'
#' @return A `data.frame` with columns `param`, `rule`, `weight` and `scope`.
#'
#' @examples
#' register_scale_rule("invcost", "weighted_mean", weight = "size")
#' list_scale_rules()
#' clear_scale_rules("invcost")
#' @export
list_scale_rules <- function(scope = NULL) {
  nms <- sort(ls(envir = .RULE_REGISTRY, all.names = FALSE))
  entries <- lapply(nms, function(k) {
    get(k, envir = .RULE_REGISTRY, inherits = FALSE)
  })
  keep <- if (is.null(scope)) {
    rep(TRUE, length(nms))
  } else {
    vapply(entries, function(e) identical(e$scope, scope), logical(1))
  }
  nms <- nms[keep]
  entries <- entries[keep]
  if (length(nms) == 0L) {
    return(data.frame(
      param = character(), rule = character(),
      weight = character(), scope = character(),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    param = sub("^[^:]*:", "", nms),
    rule = vapply(entries, function(e) e$rule, character(1)),
    weight = vapply(
      entries, function(e) e$weight %||% NA_character_,
      character(1)
    ),
    scope = vapply(
      entries, function(e) e$scope %||% NA_character_,
      character(1)
    ),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Clear the rule registry
#'
#' Mainly useful in tests.
#'
#' @param name Optional character vector of parameter names to remove. `NULL`
#'   (default) clears everything in `scope`.
#' @param scope Optional dimension namespace.
#'
#' @return Invisibly `NULL`.
#'
#' @examples
#' register_scale_rule("tmp_param", "sum")
#' clear_scale_rules("tmp_param")
#' @export
clear_scale_rules <- function(name = NULL, scope = NULL) {
  if (is.null(name)) {
    if (is.null(scope)) {
      rm(
        list = ls(envir = .RULE_REGISTRY, all.names = TRUE),
        envir = .RULE_REGISTRY
      )
      return(invisible(NULL))
    }
    present <- grep(paste0("^", scope, ":"),
      ls(envir = .RULE_REGISTRY, all.names = TRUE),
      value = TRUE
    )
  } else {
    present <- intersect(
      vapply(name, .rule_key, character(1), scope = scope),
      ls(envir = .RULE_REGISTRY, all.names = TRUE)
    )
  }
  if (length(present) > 0L) rm(list = present, envir = .RULE_REGISTRY)
  invisible(NULL)
}

# Resolution -------------------------------------------------------------------

#' Resolve the per-column rules for a recast
#'
#' `rule` and `weight` may each be a single value (applied to every column) or
#' a named vector, one entry per value column. Columns with neither an
#' explicit rule nor a registry entry are an error.
#'
#' @param values Character vector of value column names.
#' @param rule Scalar or named character vector, or `NULL`.
#' @param weight Scalar or named character vector, or `NULL`.
#' @param scope Dimension namespace used for registry lookups.
#' @return A named list, one entry per value column, each `list(rule, weight)`.
#' @noRd
.rules_for <- function(values, rule = NULL, weight = NULL, scope = NULL,
                       hint = "register_scale_rule()") {
  .per_column <- function(x, what) {
    if (is.null(x)) {
      return(stats::setNames(
        vector("list", length(values)),
        values
      ))
    }
    if (length(x) == 1L && is.null(names(x))) {
      return(stats::setNames(rep(list(unname(x)), length(values)), values))
    }
    if (is.null(names(x))) {
      .stop(paste0(
        "`%s` must be a single value or a NAMED vector with one ",
        "entry per value column"
      ), what)
    }
    unknown <- setdiff(names(x), values)
    if (length(unknown) > 0L) {
      .stop(
        "`%s` names columns that are not value columns: %s",
        what, .preview(unknown)
      )
    }
    out <- stats::setNames(vector("list", length(values)), values)
    for (v in names(x)) out[[v]] <- unname(x[[v]])
    out
  }

  rules <- .per_column(rule, "rule")
  weights <- .per_column(weight, "weight")

  out <- stats::setNames(vector("list", length(values)), values)
  missing <- character()
  for (v in values) {
    r <- rules[[v]]
    w <- weights[[v]]
    if (is.null(r)) {
      entry <- get_scale_rule(v, scope = scope)
      if (is.null(entry)) {
        missing <- c(missing, v)
        next
      }
      r <- entry$rule
      if (is.null(w)) w <- entry$weight
    }
    r <- match.arg(r, SCALE_RULES)
    out[[v]] <- list(rule = r, weight = w)
  }
  if (length(missing) > 0L) {
    .stop(paste0(
      "no aggregation rule for value column(s): %s. Pass `rule=` ",
      "or register one with `%s`."
    ), .preview(missing), hint)
  }
  out
}
