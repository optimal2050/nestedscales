# A second small example NestedScale

A different dimension from
[`scale_example()`](https://optimal2050.github.io/nestedscales/r/reference/scale_example.md),
for the examples that need two axes. Two frames, four leaves, its own
leaf column (`period`) and a weight – deliberately well behaved, so the
awkwardness in an example stays on the other axis.

## Usage

``` r
scale_example2()
```

## Value

A
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
with 4 leaves and frames `era`/`period`.

## Examples

``` r
scale_example2()
#> NestedScale: example2
#> Description: Synthetic second dimension, for product examples 
#> Frames (2, coarsest first):
#>   - era (2)
#>     - period (4)
#> Leaves: 4
#> Weights: span (default: span)
scale_product(a = scale_example(), b = scale_example2())
#> ScaleProduct: <unnamed> 
#> Axes (2):
#>   a : NestedScale 'example'  sector/class/group/item  leaves 7  key: item
#>   b : NestedScale 'example2'  era/period  leaves 4  key: period
#> Leaves: 7 x 4 = 28  (not materialised)
```
