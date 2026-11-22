# The representative member of each cluster

The medoid is an ACTUAL member, not an average of members, which is what
makes it usable as a representative period or a representative region: a
model built on medoids is built on things that really happened.

## Usage

``` r
cluster_medoids(x, frame = NULL)
```

## Arguments

- x:

  A scale returned by
  [`cluster_scale()`](https://optimal2050.github.io/nestedscales/r/reference/cluster_scale.md).

- frame:

  The cluster frame; defaults to the one the clustering added.

## Value

A data frame of cluster and its representative member.

## Examples

``` r
s <- scale_example()
d <- data.frame(
  item = rep(scale_members(s), each = 4),
  t = rep(sprintf("t%d", 1:4), 7), v = as.numeric(seq_len(28))
)
cluster_medoids(cluster_scale(d, s, k = 3))
#>   cluster representative
#> 1     c01             U2
#> 2     c02             U4
#> 3     c03            OTH
```
