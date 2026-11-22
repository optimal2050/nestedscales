# Distance between the members of a scale

**\[experimental\]** This feature may change or be removed in a later
version.

Reshapes long, member-keyed data into a member-by-observation matrix and
measures the distance between its rows.

## Usage

``` r
scale_distance(
  data,
  x,
  frame = NULL,
  key = NULL,
  value = NULL,
  method = "euclidean",
  scale_members = FALSE
)
```

## Arguments

- data:

  Long data: a column of member codes, one or more identifier columns
  saying which observation each row is, and a value column.

- x:

  A `NestedScale`.

- frame:

  Frame whose members are compared. Defaults to the leaf frame.

- key:

  Column of `data` holding the member codes. Defaults to `frame` when
  present, else the scale's leaf column.

- value:

  Value column; inferred when unambiguous.

- method:

  A name from
  [`list_scale_distances()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_distance.md).

- scale_members:

  Standardise each member's profile to mean 0, sd 1 before measuring.
  Turns a level distance into a shape distance; has no effect on
  `"correlation"`, which already ignores level.

## Value

A [stats::dist](https://rdrr.io/r/stats/dist.html) object over the
frame's members, in member order.

## Examples

``` r
s <- scale_example()
d <- data.frame(
  item = rep(scale_members(s), each = 3),
  t = rep(sprintf("t%d", 1:3), 7), v = as.numeric(seq_len(21))
)
round(scale_distance(d, s, method = "correlation"), 2)
#>     U1 U2 U3 U4 U5 U6
#> U2   0               
#> U3   0  0            
#> U4   0  0  0         
#> U5   0  0  0  0      
#> U6   0  0  0  0  0   
#> OTH  0  0  0  0  0  0
```
