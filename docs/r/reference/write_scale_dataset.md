# Write data and the scales that index it to one folder

**\[experimental\]** This feature may change or be removed in a later
version.

The data is written as a hive-partitioned Arrow IPC dataset and the
scales travel with it, so
[`open_scale_dataset()`](https://optimal2050.github.io/nestedscales/r/reference/open_scale_dataset.md)
gives back both and the result can be recast without re-declaring
anything. Each scale is stored as the definition
[`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
writes, so its attributes and aliases travel too.

## Usage

``` r
write_scale_dataset(
  data,
  x,
  path,
  partitioning = NULL,
  compression = "zstd",
  overwrite = FALSE
)
```

## Arguments

- data:

  The table to write, in any supported backend.

- x:

  The
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
  or
  [`ScaleProduct`](https://optimal2050.github.io/nestedscales/r/reference/ScaleProduct.md)
  the data is indexed by.

- path:

  Directory to create. It must not already contain a store unless
  `overwrite = TRUE`.

- partitioning:

  Columns to partition the data by (hive style). `NULL` (default) picks
  nothing; a good choice is a low-cardinality identifier such as a year,
  which lets a filtered read skip whole files.

- compression:

  Codec for the IPC files, e.g. `"zstd"` (default), `"lz4"` or
  `"uncompressed"`. If the codec is unavailable in the installed Arrow
  build, the files are written uncompressed with a warning.

- overwrite:

  Replace an existing store at `path`.

## Value

`path`, invisibly.

## Examples

``` r
p <- scale_product(a = scale_example(), b = scale_example2())
d <- merge(
  data.frame(item = c("U1", "U2")),
  data.frame(period = c("p1", "p2"))
)
d$v <- 1:4
dir <- file.path(tempdir(), "store")
if (requireNamespace("arrow", quietly = TRUE)) {
  write_scale_dataset(d, p, dir, overwrite = TRUE)
  ds <- open_scale_dataset(dir)
  ds
}
#> Warning: write_feather(version = 2) has been superseded by write_ipc_file().
#> Warning: write_feather(version = 2) has been superseded by write_ipc_file().
#> Warning: `format = "feather"` is deprecated; use `format = "ipc"` instead.
#> Warning: 'arrow::read_feather' is deprecated.
#> Use 'read_ipc_file' instead.
#> See help("Deprecated")
#> Warning: 'arrow::read_feather' is deprecated.
#> Use 'read_ipc_file' instead.
#> See help("Deprecated")
#> Warning: `format = "feather"` is deprecated; use `format = "ipc"` instead.
#> <scale_dataset> C:\Users\admin\AppData\Local\Temp\RtmpaYWn4w/store 
#>   rows:  4
#>   files: 1 (1 KB)
#>   scale: product over a x b
```
