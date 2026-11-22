# Ancestry between all frame pairs

Every `(coarser, finer)` code pair that shares at least one leaf, for
all frame pairs.

## Usage

``` r
scale_ancestry(x)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Value

A `data.frame` with columns `parent_frame`, `parent`, `child_frame`,
`child`.

## Details

Computed **leaf-mediated**, directly from the leaftable – deliberately
not as a transitive closure of
[`scale_family()`](https://optimal2050.github.io/nestedscales/r/reference/scale_family.md).
Closing a hierarchy that cross-cuts manufactures false relationships: in
the example scale, group `GB` straddles both sectors, so closing
`sector -> class -> group -> item` would wrongly report sector `P` as an
ancestor of member `U5`, which lies in sector `S`.

For frames that do not nest this relation is *overlap*, not containment
– test a given pair with
[`scale_nests()`](https://optimal2050.github.io/nestedscales/r/reference/scale_nests.md).

Frame columns are retained because codes are not unique across frames:
in the example, `"G1"` exists at both `class` and `group`, so a bare
`(parent, child)` pair would read as a self-loop.

## Examples

``` r
head(scale_ancestry(scale_example()))
#>   parent_frame parent child_frame child
#> 1       sector      P       class    G1
#> 2       sector      P       class    G2
#> 3       sector      P       group    G1
#> 4       sector      P       group    GB
#> 5       sector      P        item    U1
#> 6       sector      P        item    U2
```
