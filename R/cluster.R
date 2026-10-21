# =============================================================================
# Clustering as scale construction
# =============================================================================
# A clustering assigns each unit of a frame to a group. That is exactly what a
# coarser frame IS, so the result here is not a bag of labels to be carried
# around and joined back by hand -- it is the scale itself, with a new frame
# added above the one that was clustered. Everything downstream then works
# without knowing a clustering happened: recasting to the clusters, shares
# within them, coverage, products, plots.
# =============================================================================

#' Cluster the units of a scale into a new frame
#'
#' Groups the units at `frame` by the similarity of their profiles and returns
#' the scale with those groups added as a new, coarser frame.
#'
#' @param data Long data: unit codes, one or more identifier columns saying
#'   which observation each row is, and a value column. A unit that is not
#'   observed over the same set as the others is an error rather than a hole.
#' @param x A `NestedScale`.
#' @param k Number of clusters.
#' @param frame Frame whose units are clustered. Defaults to the atom frame.
#' @param key,value Columns of `data`; inferred when unambiguous.
#' @param method `"pam"` (partitioning around medoids, via the cluster
#'   package), `"hclust"` ([stats::hclust]) or `"kmeans"` ([stats::kmeans]).
#'   `"pam"` and `"hclust"` work from the distance matrix, so they honour
#'   `distance=`; `"kmeans"` works on the raw profiles and ignores it.
#' @param distance A name from [`list_scale_distances()`].
#' @param scale_units Standardise each unit's profile before measuring;
#'   see [`scale_distance()`].
#' @param new_frame Name for the frame the clusters form.
#' @param labels How to name the clusters: a prefix (the default `"c"` gives
#'   `c01`, `c02`, ...), or `"medoid"` to name each cluster after its
#'   representative unit, which keeps the codes meaningful.
#' @param hclust_method Linkage for `method = "hclust"`.
#' @param seed Seed for `"kmeans"`, which starts from a random assignment.
#'   `NULL` leaves the session's stream alone.
#' @param ... Passed to the underlying algorithm.
#'
#' @return The scale, with `new_frame` inserted directly above `frame`. The
#'   assignment is also returned as the `"clustering"` attribute: a data frame
#'   of unit, cluster and (for medoid-based methods) whether the unit is its
#'   cluster's medoid.
#'
#' @details
#' The new frame goes directly above the clustered one, which is the only
#' position that is always true: the clusters are coarser than `frame` by
#' construction, but they need not nest inside any existing coarser frame, and
#' `nestedscales` does not require them to. Use
#' `scale_nests()` to ask whether a given pair happens to nest.
#'
#' @examples
#' s <- scale_example()
#' set.seed(1)
#' d <- data.frame(
#'   unit = rep(scale_units(s), each = 4),
#'   t = rep(sprintf("t%d", 1:4), 7),
#'   v = as.numeric(seq_len(28))
#' )
#' cl <- cluster_scale(d, s, k = 3)
#' scale_frames(cl)
#' head(attr(cl, "clustering"))
#' @export
cluster_scale <- function(data, x, k, frame = NULL, key = NULL, value = NULL,
                          method = c("pam", "hclust", "kmeans"),
                          distance = "euclidean", scale_units = FALSE,
                          new_frame = "cluster", labels = "c",
                          hclust_method = "ward.D2", seed = NULL, ...) {
  method <- match.arg(method)
  frame <- .resolve_frame(x, frame)
  units <- scale_units(x, frame)
  .check_k(k, length(units))
  .check_new_frame(x, new_frame)

  key <- key %||% .resolve_key(x, frame, names(as.data.frame(data)))
  m <- .feature_matrix(data, key = key, value = value, units = units)

  fit <- .cluster_fit(
    m, k, method, distance, scale_units, hclust_method,
    seed, data, x, frame, key, value, ...
  )

  .attach_cluster_frame(
    x, frame, new_frame, units, fit$assignment,
    fit$medoids, labels
  )
}

#' @noRd
.check_k <- function(k, n) {
  if (!is.numeric(k) || length(k) != 1L || is.na(k) || k < 1) {
    .stop("`k` must be a single positive number")
  }
  if (k > n) {
    .stop("`k` = %d is more than the %d unit(s) available to cluster", k, n)
  }
  invisible(TRUE)
}

#' @noRd
.check_new_frame <- function(x, new_frame) {
  if (!is.character(new_frame) || length(new_frame) != 1L ||
    !nzchar(new_frame)) {
    .stop("`new_frame` must be a single non-empty string")
  }
  if (new_frame %in% scale_frames(x)) {
    .stop(
      "`%s` is already a frame of this scale; pick another `new_frame`",
      new_frame
    )
  }
  invisible(TRUE)
}

#' Run one clustering and report assignment plus medoids
#' @noRd
.cluster_fit <- function(m, k, method, distance, scale_units, hclust_method,
                         seed, data, x, frame, key, value, ...) {
  k <- as.integer(k)
  if (method == "kmeans") {
    if (!is.null(seed)) withr_seed(seed)
    km <- stats::kmeans(m, centers = k, ...)
    return(list(
      assignment = as.integer(km$cluster),
      medoids = .medoids_from_centers(m, km$cluster, km$centers)
    ))
  }

  d <- scale_distance(data, x,
    frame = frame, key = key, value = value,
    method = distance, scale_units = scale_units
  )

  if (method == "pam") {
    if (!requireNamespace("cluster", quietly = TRUE)) {
      .stop(paste0(
        "method \"pam\" needs the cluster package; install it or ",
        "use method = \"hclust\""
      ))
    }
    p <- cluster::pam(d, k = k, diss = TRUE, ...)
    return(list(
      assignment = as.integer(p$clustering),
      medoids = as.character(p$medoids)
    ))
  }

  h <- stats::hclust(d, method = hclust_method, ...)
  a <- stats::cutree(h, k = k)
  list(
    assignment = as.integer(a),
    medoids = .medoids_from_dist(d, a)
  )
}

#' Seed the RNG for the calling function only: the caller's `.Random.seed` is
#' put back when that function exits.
#' @noRd
withr_seed <- function(seed, envir = parent.frame()) {
  old <- if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
    get(".Random.seed", globalenv(), inherits = FALSE)
  }
  restore <- if (is.null(old)) {
    quote(rm(".Random.seed", envir = globalenv()))
  } else {
    bquote(assign(".Random.seed", .(old), envir = globalenv()))
  }
  do.call(on.exit, list(restore, add = TRUE), envir = envir)
  set.seed(seed)
  invisible(NULL)
}

#' The unit closest to its cluster's centre
#' @noRd
.medoids_from_centers <- function(m, assignment, centers) {
  vapply(sort(unique(assignment)), function(g) {
    idx <- which(assignment == g)
    dd <- sqrt(rowSums((m[idx, , drop = FALSE] -
      rep(centers[g, ], each = length(idx)))^2))
    rownames(m)[idx][which.min(dd)]
  }, character(1))
}

#' The unit with the smallest total distance to its cluster-mates
#' @noRd
.medoids_from_dist <- function(d, assignment) {
  mm <- as.matrix(d)
  vapply(sort(unique(assignment)), function(g) {
    idx <- which(assignment == g)
    sub <- mm[idx, idx, drop = FALSE]
    rownames(mm)[idx][which.min(rowSums(sub))]
  }, character(1))
}

#' Insert the cluster frame into the scale
#' @noRd
.attach_cluster_frame <- function(x, frame, new_frame, units, assignment,
                                  medoids, labels) {
  k <- length(unique(assignment))
  code <- if (identical(labels, "medoid")) {
    if (is.null(medoids)) {
      .stop("this method reports no medoids; use a prefix for `labels`")
    }
    medoids[assignment]
  } else {
    sprintf(
      paste0(labels, "%0", max(2L, nchar(as.character(k))), "d"),
      assignment
    )
  }
  names(code) <- units

  lt <- scale_leaftable(x)
  fr <- scale_frames(x)
  lt[[new_frame]] <- unname(code[as.character(lt[[frame]])])

  at <- scale_rank(x, frame)
  new_frames <- append(fr, new_frame, after = at - 1L)

  meta <- S7::prop(x, "meta")
  members <- S7::prop(x, "members")
  members[[new_frame]] <- unique(stats::na.omit(as.character(lt[[new_frame]])))
  members <- members[new_frames]
  # the rows are unchanged, so the concrete class, its payload and every
  # meta field survive as they are
  out <- .reconstruct(x, lt, new_frames, members, meta)

  tab <- data.frame(
    unit = units, cluster = unname(code),
    stringsAsFactors = FALSE
  )
  names(tab)[1L] <- frame
  names(tab)[2L] <- new_frame
  if (!is.null(medoids)) {
    tab$medoid <- tab[[frame]] %in% medoids
  }
  attr(out, "clustering") <- tab
  out
}

#' The representative unit of each cluster
#'
#' The medoid is an ACTUAL unit, not an average of units, which is what makes
#' it usable as a representative period or a representative region: a model
#' built on medoids is built on things that really happened.
#'
#' @param x A scale returned by [`cluster_scale()`].
#' @param frame The cluster frame; defaults to the one the clustering added.
#'
#' @return A data frame of cluster and its representative unit.
#'
#' @examples
#' s <- scale_example()
#' d <- data.frame(
#'   unit = rep(scale_units(s), each = 4),
#'   t = rep(sprintf("t%d", 1:4), 7), v = as.numeric(seq_len(28))
#' )
#' cluster_medoids(cluster_scale(d, s, k = 3))
#' @export
cluster_medoids <- function(x, frame = NULL) {
  tab <- attr(x, "clustering")
  if (is.null(tab)) {
    .stop(paste0(
      "this scale carries no clustering; `cluster_medoids()` ",
      "reads the result of `cluster_scale()`"
    ))
  }
  if (!"medoid" %in% names(tab)) {
    .stop("this clustering reported no medoids")
  }
  cl <- setdiff(names(tab), c("medoid"))
  out <- tab[tab$medoid, cl, drop = FALSE]
  names(out) <- c("unit", "cluster")[seq_along(cl)]
  out <- out[, c(2L, 1L), drop = FALSE]
  names(out) <- c("cluster", "representative")
  rownames(out) <- NULL
  out[order(out$cluster), , drop = FALSE]
}
