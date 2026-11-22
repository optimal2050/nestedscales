# The dimension vocabulary of a scale

Engine messages are written once and interpolated with the words of the
dimension at hand, so a `Calendar` flowing through the shared engine
still errors in the language of time ("timeframe", "timeslice") and a
`Geoscale` in the language of space ("geoframe", "region"). Subclasses
supply their own method; the `NestedScale` default is the neutral
vocabulary.

## Usage

``` r
scale_vocab(x, ...)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- ...:

  Passed to methods.

## Value

A named list with elements `object`, `frame`, `frames`, `member`,
`members`, `leaves`, and optionally `register_rule` and `register_map`:
the calls that error messages suggest for registering a value column's
rule or an explicit crosswalk, when the dimension package offers its own
(`"register_geoscale_rule()"`).

## Examples

``` r
scale_vocab(scale_example())
#> $object
#> [1] "NestedScale"
#> 
#> $frame
#> [1] "frame"
#> 
#> $frames
#> [1] "frames"
#> 
#> $member
#> [1] "member"
#> 
#> $members
#> [1] "members"
#> 
#> $leaves
#> [1] "leaves"
#> 
```
