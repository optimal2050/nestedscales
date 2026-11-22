# Cluster the members of a scale into a new frame

Groups the members at `frame` by the similarity of their profiles and
returns the scale with those groups added as a new, coarser frame.

## Usage

``` r
cluster_scale(
  data,
  x,
  k,
  frame = NULL,
  key = NULL,
  value = NULL,
  method = c("pam", "hclust", "kmeans"),
  distance = "euclidean",
  scale_members = FALSE,
  new_frame = "cluster",
  labels = "c",
  hclust_method = "ward.D2",
  seed = NULL,
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

- k:

  Number of clusters.

- frame:

  Frame whose members are clustered. Defaults to the leaf frame.

- key, value:

  Columns of `data`; inferred when unambiguous.

- method:

  `"pam"` (partitioning around medoids, via the cluster package),
  `"hclust"` ([stats::hclust](https://rdrr.io/r/stats/hclust.html)) or
  `"kmeans"` ([stats::kmeans](https://rdrr.io/r/stats/kmeans.html)).
  `"pam"` and `"hclust"` work from the distance matrix, so they honour
  `distance=`; `"kmeans"` works on the raw profiles and ignores it.

- distance:

  A name from
  [`list_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md).

- scale_members:

  Standardise each member's profile before measuring; see
  [`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md).

- new_frame:

  Name for the frame the clusters form.

- labels:

  How to name the clusters: a prefix (the default `"c"` gives `c01`,
  `c02`, ...), or `"medoid"` to name each cluster after its
  representative member, which keeps the codes meaningful.

- hclust_method:

  Linkage for `method = "hclust"`.

- seed:

  Seed for `"kmeans"`, which starts from a random assignment. `NULL`
  leaves the session's stream alone.

- ...:

  Passed to the underlying algorithm.

## Value

The scale, with `new_frame` inserted directly above `frame`. The
assignment is also returned as the `"clustering"` attribute: a data
frame of member, cluster and (for medoid-based methods) whether the
member is its cluster's medoid.

## Details

The new frame goes directly above the clustered one, which is the only
position that is always true: the clusters are coarser than `frame` by
construction, but they need not nest inside any existing coarser frame,
and `nestedscales` does not require them to. Use
[`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md)
to ask whether a given pair happens to nest.

## Examples

``` r
s <- scale_example()
set.seed(1)
d <- data.frame(
  item = rep(scale_members(s), each = 4),
  t = rep(sprintf("t%d", 1:4), 7),
  v = as.numeric(seq_len(28))
)
cl <- cluster_scale(d, s, k = 3)
scale_frames(cl)
#> [1] "sector"  "class"   "group"   "cluster" "item"   
head(attr(cl, "clustering"))
#>   item cluster medoid
#> 1   U1     c01  FALSE
#> 2   U2     c01   TRUE
#> 3   U3     c01  FALSE
#> 4   U4     c02   TRUE
#> 5   U5     c02  FALSE
#> 6   U6     c03  FALSE
```
