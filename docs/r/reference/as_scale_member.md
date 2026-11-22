# Codes bound to a scale

**\[experimental\]** This feature may change or be removed in a later
version.

`as_scale_member()` marks a vector of codes as belonging to one frame of
one scale; it is what
[`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)
puts in a column. The result is a character vector of class
`scale_member` that carries the scale's name, its
[`scale_id()`](https://optimal2050.github.io/nestedscales/r/reference/scale_id.md)
and the frame. `is_scale_member()` tests for it. Experimental, with the
rest of the data link; see
[`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md).

## Usage

``` r
as_scale_member(x, scale, frame)

is_scale_member(x)
```

## Arguments

- x:

  A vector of codes; for `is_scale_member()`, any object.

- scale:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  the codes belong to.

- frame:

  The frame the codes are at.

## Value

`as_scale_member()` a `scale_member` vector as long as `x`;
`is_scale_member()` a single logical.

## Details

Combining two such vectors (binding rows, joining) works when they are
on the same scale and frame and is an error otherwise. Combined with a
plain character vector the result stays bound, the plain codes being
taken on trust; the verbs check codes against the scale when they use
them.

## See also

[`bind_scale()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md),
[`scale_link()`](https://optimal2050.github.io/nestedscales/r/reference/bind_scale.md)

## Examples

``` r
s <- scale_example()
u <- as_scale_member(c("P", "S", "P"), s, "sector")
u
#> <scale_member<'example' [c24a3e23], sector>[3]>
#> [1] P S P
is_scale_member(u)
#> [1] TRUE
as.character(u)
#> [1] "P" "S" "P"
```
