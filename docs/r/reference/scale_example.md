# A small example NestedScale

A synthetic 3-frame hierarchy used in examples and tests. It
deliberately reproduces three awkward features of real classification
tables:

## Usage

``` r
scale_example()
```

## Value

A
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
with 7 leaves and frames `sector`/`class`/`group`/`item`.

## Details

- a code (`"G1"`) reused at more than one frame, so bare codes are
  ambiguous and every lookup must name its frame;

- a non-nesting pair of frames – group `"GB"` draws members from two
  different classes, so `class` and `group` do not form a tree;

- a member (`"OTH"`) with no code at any coarser frame (partial
  coverage).

## Examples

``` r
s <- scale_example()
s
#> NestedScale: example
#> Description: Synthetic example: reused code, non-nesting frame pair, and an unassigned leaf 
#> Frames (4, coarsest first):
#>   - sector (2)  [1 member unassigned]
#>     - class (3)  [1 member unassigned]
#>       - group (3)  [1 member unassigned]
#>         - item (7)
#> Leaves: 7
#> Weights: size, count (default: size)
scale_nests(s, "class", "group") # FALSE - they cross-cut
#> [1] FALSE
#> attr(,"offenders")
#> [1] "GB"
```
