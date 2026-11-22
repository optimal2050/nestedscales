# Subset a NestedScale by member

Keeps only the leaves belonging to `member` at `frame`, and rebuilds the
member vocabularies accordingly.

## Usage

``` r
filter_scale(x, frame, member, drop_empty_frames = FALSE)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  Frame that `member` belongs to.

- member:

  Character vector of codes to keep.

- drop_empty_frames:

  Drop frames left with no codes at all.

## Value

A
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Details

A genuine subset is a SAMPLE and is book-kept as one: `meta$coverage`
records, per weight column, the kept fraction of the ROOT parent's total
(so filters compose against the original object), `meta$parent_totals`
stores those root totals (making the coverage claim verifiable by the
validator), `meta$parent_name` records the parent, and `meta$name` is
mangled to `"parent[frame:codes]"` so a sample never impersonates its
parent in the crosswalk registry or in
[`join_scale()`](https://optimal2050.github.io/nestedscales/r/reference/join_scale.md)
column names. A filter that keeps every leaf is a true no-op. Read the
fraction back with
[`scale_coverage()`](https://optimal2050.github.io/nestedscales/r/reference/scale_coverage.md).

## Examples

``` r
s <- scale_example()
p <- filter_scale(s, "sector", "P")
p
#> NestedScale: example[sector:P]
#> Description: Synthetic example: reused code, non-nesting frame pair, and an unassigned leaf 
#> Frames (4, coarsest first):
#>   - sector (1)
#>     - class (2)
#>       - group (2)
#>         - item (4)
#> Leaves: 4
#> Weights: size, count (default: size)
scale_coverage(p)
#>      size     count 
#> 0.3225806 0.6666667 
```
