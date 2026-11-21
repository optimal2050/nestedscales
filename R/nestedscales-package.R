#' nestedscales: Nested Scales and Multi-Dimensional Indexes for Modeling
#'
#' A multi-level discrete representation of a data dimension, for modeling,
#' data processing and visualization. A nested scale is a flat table of leaves
#' plus the frames that group them; every frame nests in the leaves, and frames
#' may nest in or overlay each other. The package defines the transition rules
#' between levels (sum, weighted mean, mean, copy, sd, share) and the
#' operations on them: conversion of data between resolutions, labelling,
#' subsetting, combination of several scales into a product index, and
#' construction of new frames by clustering.
#'
#' Time and space live in dimension packages built on this one, designed for
#' optimization and simulation models where labeled time slices and regions
#' are the index sets:
#' [timescales](https://github.com/optimal2050/timescales)' `Calendar` and
#' [geoscales](https://github.com/optimal2050/geoscales)' `Geoscale` are
#' subclasses of `NestedScale`, so every verb here accepts them. Any other
#' dimension -- industries, income brackets, temperature regimes, technology
#' vintages -- is declared directly with [`scale_from_leaftable()`].
#' `vignette("nestedscales", package = "nestedscales")` introduces the
#' functions; the
#' [package website](https://optimal2050.github.io/nestedscales/) includes a
#' roadmap of what is available and what is planned.
#'
#' A clustering is treated as scale construction: [`cluster_scale()`] returns
#' the scale with a new coarser frame inserted above the one clustered, so
#' recasting to clusters, within-cluster shares, coverage and products all work
#' with no special casing. [`scale_distance()`] and its registry supply the
#' metrics, [`cluster_contiguous()`] the order- and adjacency-constrained
#' variants, and [`cluster_sweep()`] reports quality across `k` without
#' choosing one for you.
#'
#' @keywords internal
#' @importFrom rlang .data :=
"_PACKAGE"
