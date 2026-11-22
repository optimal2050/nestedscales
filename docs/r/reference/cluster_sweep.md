# Cluster quality across a range of k

Cluster quality across a range of k

## Usage

``` r
cluster_sweep(
  data,
  x,
  ks,
  frame = NULL,
  key = NULL,
  value = NULL,
  distance = "euclidean",
  scale_members = FALSE,
  FUN = cluster_scale,
  ...
)
```

## Arguments

- data:

  Long data: member codes, one or more identifier columns saying which
  observation each row is, and a value column. A member that is not
  observed over the same set as the others is an error rather than a
  hole.

- x:

  A `NestedScale`.

- ks:

  Values of `k` to try.

- frame:

  Frame whose members are clustered. Defaults to the leaf frame.

- key, value:

  Columns of `data`; inferred when unambiguous.

- distance:

  A name from
  [`list_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md).

- scale_members:

  Standardise each member's profile before measuring; see
  [`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md).

- FUN:

  The clustering function to sweep:
  [`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md)
  (default) or
  [`cluster_contiguous()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_contiguous.md).

- ...:

  Passed to `FUN`.

## Value

A data frame with one row per `k`: `k`, `within` (total within-cluster
sum of distances to the cluster medoid), `silhouette` (average, `NA` at
`k = 1`), and `smallest` (the size of the smallest cluster, which is
often what rules a k out).

## Examples

``` r
s <- scale_example()
d <- data.frame(
  item = rep(scale_members(s), each = 4),
  t = rep(sprintf("t%d", 1:4), 7), v = as.numeric(seq_len(28))
)
cluster_sweep(d, s, ks = 2:4)
#>   k within silhouette smallest
#> 1 2     48  0.5147392        3
#> 2 3     32  0.4197279        2
#> 3 4     24  0.2387755        1
```
