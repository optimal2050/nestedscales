# Validate frame names

A frame name must be a non-empty, non-`NA` string that is a
syntactically valid R name (so it can be used as a data.frame column
without quoting).

## Usage

``` r
is_valid_frame(x)
```

## Arguments

- x:

  Character vector of candidate frame names.

## Value

A logical vector the same length as `x`.

## Examples

``` r
is_valid_frame(c("industry", "reg32", "", "2bad"))
#> [1]  TRUE  TRUE FALSE FALSE
```
