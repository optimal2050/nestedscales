# Built-in distances

**\[experimental\]** This feature may change or be removed in a later
version.

- `euclidean`, `manhattan`, `maximum`:

  Straight to [`stats::dist()`](https://rdrr.io/r/stats/dist.html).
  Compare members by the LEVEL of their profiles.

- `correlation`:

  `1 - cor(t(x))`, Pearson. Compares SHAPE: two members that rise and
  fall together are close however different their magnitudes, which is
  what you usually want when grouping load or generation profiles.

- `spearman`:

  The same on ranks – shape, robust to outliers.

- `cosine`:

  `1 - cosine similarity`. Shape again, but sensitive to sign and not
  centred, so a member that is uniformly positive is close to every
  other such member.

## Usage

``` r
SCALE_DISTANCES
```

## Format

A character vector.

## Value

A character vector of the six built-in distance names accepted by the
`method` argument of
[`scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/scale_distance.md);
[`list_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md)
adds any registered with
[`register_scale_distance()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md).

## Examples

``` r
SCALE_DISTANCES
#> [1] "euclidean"   "manhattan"   "maximum"     "correlation" "spearman"   
#> [6] "cosine"     
```
