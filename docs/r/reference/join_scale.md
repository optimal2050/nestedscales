# Attach scale labels and memberships to a dataset

Adds a code column named after the scale, and optionally the codes of
coarser frames (`"<name>.<frame>"`), the display names of the codes
(`"<name>.label"`) and the member's share and weight (`"<name>.share"`,
`"<name>.weight"`).

## Usage

``` r
join_scale(
  data,
  x,
  key = NULL,
  frame = NULL,
  attach = NULL,
  meta = FALSE,
  weight = NULL,
  as_factor = TRUE,
  collect = NULL,
  diagnostics = c("auto", "on", "off"),
  labels = NULL
)
```

## Arguments

- data:

  The data, in any supported backend, with a column of member codes.

- x:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  to attach.

- key:

  Name of the code column in `data`. Inferred from the scale's name, the
  keyed frame, or the scale's leaf column.

- frame:

  The frame the codes in `key` are at. `NULL` (default) is inferred as
  the single frame name appearing among the data's columns.

- attach:

  Coarser frames whose codes to attach as new columns: `TRUE` for all of
  them, a character vector to choose, `NULL`/`FALSE` for none.

- meta:

  Attach the member's `share` and `weight` at the keyed frame.

- weight:

  Weight column used for `meta`. `NULL` uses the default.

- as_factor:

  Return attached membership columns as factors with the frame's full
  vocabulary as levels (so empty groups still plot).

- collect:

  For lazy inputs: materialise (`TRUE`) or return the query.

- diagnostics:

  Whether to run the checks that read the data (no matching codes; codes
  that are not members). `"auto"` (default) runs them on eager inputs
  and skips them on arrow/dtplyr, which makes this verb zero-scan there;
  `"on"`/`"off"` force the choice.

- labels:

  Attach the display names of the keyed codes as `"<name>.label"`:
  `TRUE` for the default variant, a string to name one, `NULL`/`FALSE`
  (default) for none. See
  [`attach_labels_scale()`](https://optimal2050.github.io/nestedscales/r/reference/attach_labels_scale.md).

## Value

`data` with the attached columns, in its own class.

## Details

Existing columns are never overwritten – a collision is an error.

## Examples

``` r
s <- scale_example()
d <- data.frame(class = c("G1", "G2", "S1"), v = 1:3)
join_scale(d, s, attach = TRUE)
#>   class v example.sector example
#> 1    G1 1              P      G1
#> 2    G2 2              P      G2
#> 3    S1 3              S      S1
join_scale(d, s, attach = "sector")
#>   class v example.sector example
#> 1    G1 1              P      G1
#> 2    G2 2              P      G2
#> 3    S1 3              S      S1
join_scale(d, s, meta = TRUE)
#>   class v example.weight example.share example
#> 1    G1 1            300     0.1428571      G1
#> 2    G2 2            700     0.3333333      G2
#> 3    S1 3           1100     0.5238095      S1
```
