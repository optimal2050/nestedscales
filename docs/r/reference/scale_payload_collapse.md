# Collapse a subclass's per-leaf payload

The companion of
[`scale_payload_slice()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_slice.md)
for the rebuilds that MERGE leaves rather than keep a subset of them –
[`prune_scale()`](https://optimal2050.github.io/nestedscales/r/reference/prune_scale.md),
which makes a coarser frame the new leaf layer. Called with `map`, an
integer vector with one entry per row of the OLD leaftable giving the
index of the NEW row that leaf was merged into, or `NA` for a leaf that
was dropped.

## Usage

``` r
scale_payload_collapse(x, ...)
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- ...:

  Method arguments: `map`, the integer vector described above.

## Value

`x`, with any payload merged to the new rows.

## Details

The `NestedScale` default returns `x` unchanged, which is right for a
payload keyed by member codes (the core's own attribute and alias tables
are re-keyed by the engine itself). A subclass whose payload is
positional – one geometry per leaftable row – must override it and merge
its payload by `map`; if it does not, its own validator rejects the
length mismatch, so the failure is loud rather than a silently
misaligned payload.

## Examples

``` r
identical(
  scale_payload_collapse(scale_example(), c(1L, 1L, 2L, 2L, 3L, 3L, NA)),
  scale_example()
)
#> [1] TRUE
```
