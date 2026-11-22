# Frame rank

Position of a frame in the hierarchy: 1 is the coarsest.

## Usage

``` r
scale_rank(x, frame)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- frame:

  Character vector of frame names.

## Value

An integer vector of ranks; `NA` for names that are not frames of `x`.

## Examples

``` r
s <- scale_example()
scale_rank(s, c("group", "item"))
#> [1] 3 4
```
