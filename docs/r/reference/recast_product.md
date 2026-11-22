# Recast data indexed by a product of scales

**\[experimental\]** This feature may change or be removed in a later
version.

Converts one or more axes of a product in a single call. Axes named in
`target` are converted; axes left out pass through untouched.

## Usage

``` r
recast_product(
  data,
  x,
  target,
  values = NULL,
  rules = NULL,
  weights = NULL,
  na_action = c("drop", "error", "keep"),
  collect = NULL
)
```

## Arguments

- data:

  The data, in any supported backend, carrying one key column per axis
  (see
  [`product_keys()`](https://optimal2050.github.io/nestedscales/r/reference/product_keys.md))
  plus the value columns.

- x:

  A
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md).

- target:

  Named list or character vector, one entry per axis to convert: either
  a frame name of that axis's scale, or another
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  to convert into. Axes omitted pass through unchanged.

- values:

  Value columns to convert. Default: all numeric columns that are not
  key columns. Numeric identifiers (a year) must be excluded explicitly.

- rules:

  Rule per value column and axis: a scalar for everything, or a named
  list whose entries are scalars or vectors named by axis, e.g.
  `list(load = c(time = "weighted_mean", space = "sum"))`. `NULL`
  (default) resolves each column on each axis through that dimension's
  own scope in the rule registry – which is where an intensive/extensive
  asymmetry between dimensions belongs.

- weights:

  Weight column per axis, e.g. `c(space = "pop")`; scalar applies to
  every axis.

- na_action:

  Passed to each axis's pass.

- collect:

  For lazy inputs: materialise (`TRUE`) or return the query.

## Value

The recast data in the input's class, keyed by the converted axes'
target members.

## Details

Execution is a sequence of ordinary single-axis
[`recast_scale()`](https://optimal2050.github.io/nestedscales/r/reference/recast_scale.md)
calls – see the file comment in `R/product-recast.R` for why that is
exactly equivalent to a joint recast for every supported rule, and why
the joint crosswalk is never built. The passes are ordered so the axis
that reduces the data most runs first.

A per-axis `"sd"` is refused because it is order-dependent; a scalar
`"sd"` means the pooled sd over all product leaves in a target block,
which is well defined and is computed without materialising the product.
`"share"` is not defined across a product, because it changes which axis
the result is keyed by.

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
d <- merge(
  data.frame(item = c("U1", "U2", "U3", "U4", "U5", "U6")),
  data.frame(period = c("p1", "p2", "p3", "p4"))
)
d$cap <- seq_len(nrow(d))

# aggregate both axes at once
recast_product(d, p, target = list(a = "sector", b = "era"), rules = "sum")
#>   era sector cap
#> 1  E1      P  44
#> 2  E2      P 140
#> 3  E1      S  34
#> 4  E2      S  82

# different rules per axis
recast_product(d, p,
  target = list(a = "sector", b = "era"),
  rules = list(cap = c(a = "sum", b = "weighted_mean"))
)
#>   era sector cap
#> 1  E1      P  28
#> 2  E2      P  74
#> 3  E1      S  20
#> 4  E2      S  43
```
