# Cluster the members of a scale under a contiguity constraint

Merges only members the constraint allows to be merged, so the resulting
groups are contiguous in order (an ordered scale) or connected in space
(an adjacency graph).

## Usage

``` r
cluster_contiguous(
  data,
  x,
  k,
  frame = NULL,
  key = NULL,
  value = NULL,
  distance = "euclidean",
  scale_members = FALSE,
  adjacency = "order",
  circular = FALSE,
  linkage = "average",
  new_frame = "cluster",
  labels = "c"
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

- distance:

  A name from
  [`list_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md).

- scale_members:

  Standardise each member's profile before measuring; see
  [`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md).

- adjacency:

  How members may be merged. `"order"` (the default) treats the members
  at `frame` as a sequence in member order and permits only neighbours –
  the clusters come out as consecutive blocks. Otherwise a two-column
  data frame or a square logical/0-1 matrix over the members, giving the
  pairs that may merge.

- circular:

  For `"order"`: treat the sequence as a loop, so the last member
  neighbours the first. Right for a yearly cycle, wrong for a
  trajectory.

- linkage:

  How the distance between two clusters is measured: `"average"`,
  `"complete"` or `"single"`.

- new_frame:

  Name for the frame the clusters form.

- labels:

  How to name the clusters: a prefix (the default `"c"` gives `c01`,
  `c02`, ...), or `"medoid"` to name each cluster after its
  representative member, which keeps the codes meaningful.

## Value

As
[`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md):
the scale with the cluster frame added, and the assignment in the
`"clustering"` attribute.

## Details

The constraint can make `k` unreachable: an adjacency graph with more
connected components than `k` cannot be merged below that number, and
the function stops with the count rather than returning something that
quietly violates the constraint.

## Examples

``` r
s <- scale_example()
d <- data.frame(
  item = rep(scale_members(s), each = 4),
  t = rep(sprintf("t%d", 1:4), 7), v = as.numeric(seq_len(28))
)
cl <- cluster_contiguous(d, s, k = 3)
attr(cl, "clustering")
#>   item cluster medoid
#> 1   U1     c01   TRUE
#> 2   U2     c01  FALSE
#> 3   U3     c02   TRUE
#> 4   U4     c02  FALSE
#> 5   U5     c03  FALSE
#> 6   U6     c03   TRUE
#> 7  OTH     c03  FALSE
```
