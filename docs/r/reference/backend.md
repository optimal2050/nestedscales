# Backends: the table types the verbs accept

The conversion verbs run on a `data.frame`, a tibble, a `data.table`, a
dtplyr lazy table or an arrow Dataset/Table/query, and return results in
the caller's type; lazy inputs stay lazy unless collected. These
functions are that contract, exposed so a dimension package built on
nestedscales can accept the same inputs as the core verbs.

## Usage

``` r
backend_of(data, arg = "data")

backend_is_lazy(backend)

backend_schema(data, backend = NULL)

backend_lazy(data, backend = NULL)

backend_pull(table)

backend_restore(table, backend, collect = NULL)

backend_bind_rows(
  parts,
  use_dt = requireNamespace("data.table", quietly = TRUE)
)
```

## Arguments

- data:

  A data object on any supported backend.

- arg:

  Argument name used in the error message.

- backend:

  A backend name from `backend_of()`; `NULL` resolves it from `data`.

- table:

  A query or table.

- collect:

  Force materialisation of a lazy result.

- parts:

  List of data frames.

- use_dt:

  Use
  [`data.table::rbindlist()`](https://rdrr.io/pkg/data.table/man/rbindlist.html).
  Defaults to whether data.table is installed; an explicit value makes
  both branches testable.

## Value

`backend_of()` a single string naming the backend; `backend_is_lazy()` a
logical; `backend_schema()` a zero-row `data.frame`; `backend_lazy()`
`data`, wrapped where the backend needs it; `backend_pull()` a
`data.frame`; `backend_restore()` the result in the input's class;
`backend_bind_rows()` one data frame, or `NULL` when every part is
empty.

## Details

- `backend_of()` names the backend of `data`, and errors on an
  unsupported input – the one place that message is written.

- `backend_is_lazy()` says whether a backend produces queries.

- `backend_schema()` describes the columns without scanning the data.

- `backend_lazy()` lifts `data` into a dplyr-compatible carrier for a
  pipeline (a `data.table` becomes a dtplyr step when dtplyr is
  installed).

- `backend_pull()` materialises a query or table as a `data.frame`.

- `backend_restore()` returns a pipeline result in the caller's type.

- `backend_bind_rows()` binds chunk results into one frame.

## Examples

``` r
d <- data.frame(item = c("U1", "U2", "U2"), v = 1:3)
backend_of(d)
#> [1] "data.frame"
backend_is_lazy(backend_of(d))
#> [1] FALSE
backend_schema(d)
#> [1] item v   
#> <0 rows> (or 0-length row.names)
```
