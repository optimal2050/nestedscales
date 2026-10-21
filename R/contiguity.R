# =============================================================================
# Constrained clustering
# =============================================================================
# Unconstrained clustering will happily group January with July because they
# look alike, or two regions on opposite sides of a continent because their
# wind profiles correlate. Sometimes that is exactly right. Often the result
# has to respect a structure the data does not know about:
#
#   * ORDER, for an ordered scale -- clusters must be contiguous blocks, so
#     the coarser frame is a genuine sequence of periods and a model built on
#     it can still talk about "the next one";
#   * ADJACENCY, for a spatial scale -- clusters must be connected, so a
#     region is a region rather than a scattering.
#
# Both are the same algorithm: agglomerative merging restricted to pairs the
# constraint permits. It is written out here rather than delegated, because
# `stats::hclust()` has no notion of a forbidden merge.
# =============================================================================

#' Cluster the units of a scale under a contiguity constraint
#'
#' Merges only units the constraint allows to be merged, so the resulting
#' groups are contiguous in order (an ordered scale) or connected in space (an
#' adjacency graph).
#'
#' @inheritParams cluster_scale
#' @param adjacency How units may be merged. `"order"` (the default) treats
#'   the units at `frame` as a sequence in member order and permits only
#'   neighbours -- the clusters come out as consecutive blocks. Otherwise a
#'   two-column data frame or a square logical/0-1 matrix over the units,
#'   giving the pairs that may merge.
#' @param circular For `"order"`: treat the sequence as a loop, so the last
#'   unit neighbours the first. Right for a yearly cycle, wrong for a
#'   trajectory.
#' @param linkage How the distance between two clusters is measured:
#'   `"average"`, `"complete"` or `"single"`.
#'
#' @return As [`cluster_scale()`]: the scale with the cluster frame added, and
#'   the assignment in the `"clustering"` attribute.
#'
#' @details
#' The constraint can make `k` unreachable: an adjacency graph with more
#' connected components than `k` cannot be merged below that number, and the
#' function stops with the count rather than returning something that quietly
#' violates the constraint.
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(
#'   unit = rep(scale_units(s), each = 4),
#'   t = rep(sprintf("t%d", 1:4), 7), v = as.numeric(seq_len(28))
#' )
#' cl <- cluster_contiguous(d, s, k = 3)
#' attr(cl, "clustering")
#' @export
cluster_contiguous <- function(data, x, k, frame = NULL, key = NULL,
                               value = NULL, distance = "euclidean",
                               scale_units = FALSE, adjacency = "order",
                               circular = FALSE, linkage = "average",
                               new_frame = "cluster", labels = "c") {
  linkage <- match.arg(linkage, c("average", "complete", "single"))
  frame <- .resolve_frame(x, frame)
  units <- scale_units(x, frame)
  .check_k(k, length(units))
  .check_new_frame(x, new_frame)

  key <- key %||% .resolve_key(x, frame, names(as.data.frame(data)))
  d <- scale_distance(data, x,
    frame = frame, key = key, value = value,
    method = distance, scale_units = scale_units
  )

  adj <- .adjacency_matrix(adjacency, units, circular)
  fit <- .agglomerate(as.matrix(d), adj, k = as.integer(k), linkage = linkage)

  .attach_cluster_frame(
    x, frame, new_frame, units, fit$assignment,
    .medoids_from_dist(d, fit$assignment), labels
  )
}

#' Normalise the adjacency specification into a logical matrix
#' @noRd
.adjacency_matrix <- function(adjacency, units, circular) {
  n <- length(units)
  a <- matrix(FALSE, n, n, dimnames = list(units, units))

  if (identical(adjacency, "order")) {
    if (n > 1L) {
      i <- seq_len(n - 1L)
      a[cbind(i, i + 1L)] <- TRUE
      a[cbind(i + 1L, i)] <- TRUE
      if (isTRUE(circular)) {
        a[1L, n] <- TRUE
        a[n, 1L] <- TRUE
      }
    }
    return(a)
  }

  if (is.data.frame(adjacency) || is.matrix(adjacency) &&
    ncol(adjacency) == 2L && !is.logical(adjacency) &&
    !is.numeric(adjacency)) {
    pairs <- as.data.frame(adjacency)
    if (ncol(pairs) < 2L) {
      .stop("`adjacency` must have two columns of unit codes")
    }
    source <- match(as.character(pairs[[1L]]), units)
    target <- match(as.character(pairs[[2L]]), units)
    bad <- unique(c(
      as.character(pairs[[1L]])[is.na(source)],
      as.character(pairs[[2L]])[is.na(target)]
    ))
    if (length(bad) > 0L) {
      .stop(
        "`adjacency` names unit(s) that are not at this frame: %s",
        .preview(bad)
      )
    }
    ok <- !is.na(source) & !is.na(target)
    a[cbind(source[ok], target[ok])] <- TRUE
    a[cbind(target[ok], source[ok])] <- TRUE
    return(a)
  }

  if (is.matrix(adjacency)) {
    if (!identical(dim(adjacency), c(n, n))) {
      .stop(
        "`adjacency` is %s but this frame has %d units",
        paste(dim(adjacency), collapse = " x "), n
      )
    }
    a[] <- adjacency != 0
    a <- a | t(a)
    diag(a) <- FALSE
    dimnames(a) <- list(units, units)
    return(a)
  }

  .stop(paste0(
    "`adjacency` must be \"order\", a two-column data frame of ",
    "unit pairs, or a square matrix over the units"
  ))
}

#' Constrained agglomerative merging
#'
#' Repeatedly merges the closest PERMITTED pair. Cluster distance is the
#' average, complete or single linkage over the member pairs, recomputed from
#' the original distances rather than updated by a recurrence, which keeps the
#' code obviously correct at the cost of speed the sizes here do not need.
#' @noRd
.agglomerate <- function(dm, adj, k, linkage) {
  n <- nrow(dm)
  members <- as.list(seq_len(n))
  active <- rep(TRUE, n)

  link <- switch(linkage,
    average = mean,
    complete = max,
    single = min
  )

  repeat {
    live <- which(active)
    if (length(live) <= k) break

    best <- NULL
    best_d <- Inf
    for (ii in seq_along(live)) {
      for (jj in seq_len(ii - 1L)) {
        i <- live[[ii]]
        j <- live[[jj]]
        mi <- members[[i]]
        mj <- members[[j]]
        if (!any(adj[mi, mj, drop = FALSE])) next
        dij <- link(dm[mi, mj, drop = FALSE])
        if (dij < best_d) {
          best_d <- dij
          best <- c(i, j)
        }
      }
    }
    if (is.null(best)) {
      comp <- length(live)
      .stop(paste0(
        "the constraint allows no further merges at %d cluster(s), ",
        "so k = %d is unreachable: the units fall into %d group(s) ",
        "that cannot be joined"
      ), comp, k, comp)
    }
    i <- best[[1L]]
    j <- best[[2L]]
    members[[i]] <- c(members[[i]], members[[j]])
    active[[j]] <- FALSE
  }

  assignment <- integer(n)
  for (g in seq_along(which(active))) {
    assignment[members[[which(active)[[g]]]]] <- g
  }
  # number the clusters in the order their first member appears, so an
  # order-constrained result reads as a sequence
  first <- vapply(
    sort(unique(assignment)),
    function(g) min(which(assignment == g)), integer(1)
  )
  assignment <- match(assignment, order(first))
  list(assignment = assignment)
}
