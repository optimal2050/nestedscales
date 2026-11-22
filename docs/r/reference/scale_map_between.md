# Crosswalk between two scales through their shared leaves

The counterpart of
[`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md)
for two scales: leaves are matched on their codes, so a member of
`source` overlaps a member of `target` where they contain the same
leaves. Same columns as
[`scale_map()`](https://optimal2050.github.io/nestedscales/r/reference/scale_map.md),
with the two label columns named after the scales. Leaves of `source`
absent from `target` get an `NA` target (with a warning). A crosswalk
registered with
[`register_scale_map_between()`](https://optimal2050.github.io/nestedscales/r/reference/register_scale_map.md)
is returned as-is instead of being derived.

## Usage

``` r
scale_map_between(source, target, weight = NULL)
```

## Arguments

- source, target:

  Two named
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  objects whose leaf codes overlap.

- weight:

  Weight column of `source` for `w`; `NULL` uses its default weight, or
  weight 1 per leaf when it declares none.

## Value

A `data.frame` with columns `<from name>`, `<to name>`, `n_from`,
`n_overlap`, `w`, `w_from`.

## Examples

``` r
a <- scale_example()
b <- scale_from_leaftable(
  data.frame(
    big = c("X", "X", "Y", "Y", "Y", "Y", "Z"),
    item = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH")
  ),
  frames = c("big", "item"), name = "other"
)
scale_map_between(a, b)
#>   example other n_from n_overlap    w w_from
#> 1     OTH   OTH      1         1 1000   1000
#> 2      U1    U1      1         1  100    100
#> 3      U2    U2      1         1  200    200
#> 4      U3    U3      1         1  300    300
#> 5      U4    U4      1         1  400    400
#> 6      U5    U5      1         1  500    500
#> 7      U6    U6      1         1  600    600
```
