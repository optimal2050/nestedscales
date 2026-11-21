# =============================================================================
# Distances between the members of a scale
# =============================================================================
# Every distance here is either delegated to `stats::dist()` or written from
# its textbook definition -- `1 - cor` for correlation, `1 - cosine` for
# cosine -- so the package carries no borrowed implementation. Anything more
# specialised (dynamic time warping, shape-based distances) belongs in a user
# registration rather than a dependency: `register_scale_distance()` takes a
# function and the rest of the package works with it unchanged.
# =============================================================================

#' Built-in distances
#'
#' \describe{
#'   \item{`euclidean`, `manhattan`, `maximum`}{Straight to
#'     [stats::dist()]. Compare members by the LEVEL of their profiles.}
#'   \item{`correlation`}{`1 - cor(t(x))`, Pearson. Compares SHAPE: two members
#'     that rise and fall together are close however different their
#'     magnitudes, which is what you usually want when grouping load or
#'     generation profiles.}
#'   \item{`spearman`}{The same on ranks -- shape, robust to outliers.}
#'   \item{`cosine`}{`1 - cosine similarity`. Shape again, but sensitive to
#'     sign and not centred, so a member that is uniformly positive is close to
#'     every other such member.}
#' }
#'
#' @format A character vector.
#' @returns A character vector of the six built-in distance names accepted by
#'   the `method` argument of [scale_distance()]; [list_scale_distances()] adds
#'   any registered with [register_scale_distance()].
#' @examples
#' SCALE_DISTANCES
#' @export
SCALE_DISTANCES <- c(
  "euclidean", "manhattan", "maximum", "correlation",
  "spearman", "cosine"
)

#' @noRd
.DISTANCE_REGISTRY <- new.env(parent = emptyenv())

#' @noRd
.dist_builtin <- function(m, method) {
  switch(method,
    euclidean = stats::dist(m, method = "euclidean"),
    manhattan = stats::dist(m, method = "manhattan"),
    maximum = stats::dist(m, method = "maximum"),
    correlation = .dist_from_similarity(
      stats::cor(t(m), use = "everything", method = "pearson")
    ),
    spearman = .dist_from_similarity(
      stats::cor(t(m), use = "everything", method = "spearman")
    ),
    cosine = .dist_from_similarity(.cosine_similarity(m)),
    .stop("unknown distance `%s`; see SCALE_DISTANCES", method)
  )
}

#' Similarity on the -1..1 scale to a distance on 0..2
#'
#' A constant profile has zero variance and undefined correlation; such a member
#' is defined here to be maximally distant from everything (including another
#' constant member), because "flat" says nothing about shape and grouping two
#' flat members together on that basis would be an artefact.
#' @noRd
.dist_from_similarity <- function(s) {
  s[!is.finite(s)] <- -1
  d <- 1 - s
  diag(d) <- 0
  stats::as.dist(d)
}

#' @noRd
.cosine_similarity <- function(m) {
  n <- sqrt(rowSums(m^2))
  n[n == 0] <- NA_real_
  s <- (m / n) %*% t(m / n)
  s
}

#' Register a distance
#'
#' The built-ins cover level and shape; anything else -- dynamic time warping,
#' a domain-specific dissimilarity, a precomputed matrix -- is registered here
#' and then usable by name everywhere in the package.
#'
#' @param name Name to register under.
#' @param fn A function of the member-by-feature matrix returning a
#'   [stats::dist] object (or a square matrix) over its rows.
#'
#' @return Invisibly, `name`.
#'
#' @examples
#' register_scale_distance("first_diff", function(m) {
#'   stats::dist(t(apply(m, 1, diff)))
#' })
#' "first_diff" %in% list_scale_distances()
#' clear_scale_distances("first_diff")
#' @export
register_scale_distance <- function(name, fn) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
    !nzchar(name)) {
    .stop("`name` must be a single non-empty string")
  }
  if (!is.function(fn)) .stop("`fn` must be a function of a matrix")
  assign(name, fn, envir = .DISTANCE_REGISTRY)
  invisible(name)
}

#' @rdname register_scale_distance
#' @export
get_scale_distance <- function(name) {
  if (!is.character(name) || length(name) != 1L) {
    return(NULL)
  }
  if (!exists(name, envir = .DISTANCE_REGISTRY, inherits = FALSE)) {
    return(NULL)
  }
  get(name, envir = .DISTANCE_REGISTRY, inherits = FALSE)
}

#' @rdname register_scale_distance
#' @export
list_scale_distances <- function() {
  sort(unique(c(
    SCALE_DISTANCES,
    ls(envir = .DISTANCE_REGISTRY, all.names = FALSE)
  )))
}

#' @rdname register_scale_distance
#' @param name Distances to remove; `NULL` clears every registered one.
#'   Built-ins cannot be removed.
#' @export
clear_scale_distances <- function(name = NULL) {
  present <- ls(envir = .DISTANCE_REGISTRY, all.names = TRUE)
  drop <- if (is.null(name)) present else intersect(name, present)
  if (length(drop) > 0L) rm(list = drop, envir = .DISTANCE_REGISTRY)
  invisible(NULL)
}

#' Distance between the members of a scale
#'
#' Reshapes long, member-keyed data into a member-by-observation matrix and
#' measures the distance between its rows.
#'
#' @param data Long data: a column of member codes, one or more identifier
#'   columns saying which observation each row is, and a value column.
#' @param x A `NestedScale`.
#' @param frame Frame whose members are compared. Defaults to the leaf frame.
#' @param key Column of `data` holding the member codes. Defaults to `frame`
#'   when present, else the scale's leaf column.
#' @param value Value column; inferred when unambiguous.
#' @param method A name from [`list_scale_distances()`].
#' @param scale_members Standardise each member's profile to mean 0, sd 1 before
#'   measuring. Turns a level distance into a shape distance; has no effect on
#'   `"correlation"`, which already ignores level.
#'
#' @return A [stats::dist] object over the frame's members, in member order.
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(
#'   item = rep(scale_members(s), each = 3),
#'   t = rep(sprintf("t%d", 1:3), 7), v = as.numeric(seq_len(21))
#' )
#' round(scale_distance(d, s, method = "correlation"), 2)
#' @export
scale_distance <- function(data, x, frame = NULL, key = NULL, value = NULL,
                           method = "euclidean", scale_members = FALSE) {
  frame <- .resolve_frame(x, frame)
  key <- key %||% .resolve_key(x, frame, names(as.data.frame(data)))
  members <- scale_members(x, frame)

  m <- .feature_matrix(data, key = key, value = value, members = members)
  if (isTRUE(scale_members)) {
    m <- t(apply(m, 1, function(z) {
      s <- stats::sd(z)
      if (!is.finite(s) || s == 0) {
        return(z - mean(z))
      }
      (z - mean(z)) / s
    }))
  }

  fn <- get_scale_distance(method)
  d <- if (!is.null(fn)) fn(m) else .dist_builtin(m, method)
  if (!inherits(d, "dist")) d <- stats::as.dist(as.matrix(d))
  if (attr(d, "Size") != length(members)) {
    .stop(
      paste0("distance `%s` returned %d rows for %d members"),
      method, attr(d, "Size"), length(members)
    )
  }
  attr(d, "Labels") <- members
  d
}

#' @noRd
.resolve_frame <- function(x, frame) {
  if (!is.null(frame)) {
    return(frame)
  }
  .leaf_frame(x)
}

#' @noRd
.resolve_key <- function(x, frame, cols) {
  if (frame %in% cols) {
    return(frame)
  }
  k <- scale_leaf_column(x)
  if (k %in% cols) {
    return(k)
  }
  .stop(
    "the data has neither a `%s` nor a `%s` column; pass `key=`",
    frame, k
  )
}
