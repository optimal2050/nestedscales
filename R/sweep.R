# =============================================================================
# Choosing k
# =============================================================================
# Nothing here picks k for you. It reports the two numbers people actually
# use -- within-cluster dispersion, which always falls as k rises, and the
# average silhouette, which does not -- and leaves the judgement where it
# belongs. An automatic "best k" would be a confident answer to a question
# that does not have one.
# =============================================================================

#' Cluster quality across a range of k
#'
#' @inheritParams cluster_scale
#' @param ks Values of `k` to try.
#' @param FUN The clustering function to sweep: [`cluster_scale()`] (default)
#'   or [`cluster_contiguous()`].
#' @param ... Passed to `FUN`.
#'
#' @return A data frame with one row per `k`: `k`, `within` (total
#'   within-cluster sum of distances to the cluster medoid), `silhouette`
#'   (average, `NA` at `k = 1`), and `smallest` (the size of the smallest
#'   cluster, which is often what rules a k out).
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(
#'   item = rep(scale_members(s), each = 4),
#'   t = rep(sprintf("t%d", 1:4), 7), v = as.numeric(seq_len(28))
#' )
#' cluster_sweep(d, s, ks = 2:4)
#' @export
cluster_sweep <- function(data, x, ks, frame = NULL, key = NULL, value = NULL,
                          distance = "euclidean", scale_members = FALSE,
                          FUN = cluster_scale, ...) {
  frame <- .resolve_frame(x, frame)
  members <- scale_members(x, frame)
  key <- key %||% .resolve_key(x, frame, names(as.data.frame(data)))
  d <- scale_distance(data, x,
    frame = frame, key = key, value = value,
    method = distance, scale_members = scale_members
  )
  dm <- as.matrix(d)

  rows <- lapply(ks, function(k) {
    cl <- FUN(data, x,
      k = k, frame = frame, key = key, value = value,
      distance = distance, scale_members = scale_members, ...
    )
    tab <- attr(cl, "clustering")
    g <- tab[[2L]]
    a <- match(g, unique(g))
    data.frame(
      k = k,
      within = .within_dispersion(dm, a),
      silhouette = .avg_silhouette(dm, a),
      smallest = min(tabulate(a)),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Total distance from each member to its cluster's medoid
#' @noRd
.within_dispersion <- function(dm, a) {
  sum(vapply(sort(unique(a)), function(g) {
    idx <- which(a == g)
    if (length(idx) == 1L) {
      return(0)
    }
    sub <- dm[idx, idx, drop = FALSE]
    min(rowSums(sub))
  }, numeric(1)))
}

#' Average silhouette width
#'
#' For each member: `b` is the smallest average distance to another cluster, `a`
#' the average distance within its own; the width is `(b - a) / max(a, b)`. A
#' singleton cluster has width 0 by the usual convention -- it has no within
#' distance to speak of, and calling that a perfect fit would flatter it.
#' @noRd
.avg_silhouette <- function(dm, a) {
  gs <- sort(unique(a))
  if (length(gs) < 2L) {
    return(NA_real_)
  }
  w <- vapply(seq_along(a), function(i) {
    own <- which(a == a[[i]])
    own <- setdiff(own, i)
    if (length(own) == 0L) {
      return(0)
    }
    ai <- mean(dm[i, own])
    bi <- min(vapply(setdiff(gs, a[[i]]), function(g) {
      mean(dm[i, which(a == g)])
    }, numeric(1)))
    if (max(ai, bi) == 0) {
      return(0)
    }
    (bi - ai) / max(ai, bi)
  }, numeric(1))
  mean(w)
}
