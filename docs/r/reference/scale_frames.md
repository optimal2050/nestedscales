# Frames of a NestedScale

The hierarchy names, ordered coarsest first. The last entry is the leaf
frame whenever one frame enumerates the leaves; when none does – a
`Calendar`'s leaves are combinations of its frames – the leaf column
identifies them instead.

## Usage

``` r
scale_frames(x, finest = FALSE)

# S3 method for class 'NestedScale'
names(x)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- finest:

  Return only the finest (leaf) frame.

## Value

A character vector of frame names, or a single name when
`finest = TRUE`.

## Examples

``` r
s <- scale_example()
scale_frames(s)
#> [1] "sector" "class"  "group"  "item"  
scale_frames(s, finest = TRUE)
#> [1] "item"
```
