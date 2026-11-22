# Write a scale as a definition file, and read one back

A definition is a header (JSON, the stored form; YAML on request) plus
tables. A small scale fits in **one file** with every table inline; a
large one is a **bundle** directory holding `scale.json` and its tables
as Arrow IPC files (or CSV when arrow is not installed). Either form is
language-neutral: the header is plain JSON and the tables are Arrow or
CSV with their column types recorded.

## Usage

``` r
write_scale(
  x,
  path,
  format = c("json", "yaml"),
  tables = c("auto", "inline", "arrow", "csv"),
  overwrite = FALSE
)

read_scale(path, package = NULL, class = c("stored", "core"))
```

## Arguments

- x:

  A
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

- path:

  A file (`.json`, `.yaml`, `.yml`) or a bundle directory; for
  `read_scale()` also a catalogue id.

- format:

  Header format: `"json"` (default) or `"yaml"`. A single-file `path`
  fixes it by its extension.

- tables:

  Where the tables go: `"auto"` (inline when the tables hold at most
  1000 rows in all, else `"arrow"` when arrow is installed, else
  `"csv"`), `"inline"`, `"arrow"` or `"csv"`. A single file can only
  inline.

- overwrite:

  Replace a definition already at `path`.

- package:

  For a catalogue id: the package whose definition to take when several
  packages ship the same id.

- class:

  `"stored"` (default) returns the class recorded in the header;
  `"core"` the plain
  [`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md).

## Value

`write_scale()` returns `path`, invisibly. `read_scale()` returns the
scale.

## Details

`path` ending in `.json`, `.yaml` or `.yml` writes a single file; any
other `path` is a bundle directory. A bundle is only ever written into
an empty directory or over a bundle written before (`overwrite = TRUE`);
nothing else in a directory is touched.

`read_scale()` takes a file, a bundle directory, or the id of a shipped
definition (see
[`scale_catalog()`](https://optimal2050.github.io/nestedscales/r/reference/scale_catalog.md)).
The scale comes back as the class it was written from when that class is
registered (see
[`register_scale_class()`](https://optimal2050.github.io/nestedscales/r/reference/scale_payload_io.md));
`class = "core"` asks for the plain
[`NestedScale`](https://optimal2050.github.io/nestedscales/r/reference/NestedScale.md)
instead, dropping any payload.

## Round trips

An arrow bundle reads back identical. A JSON or YAML header carries
numbers at 15 significant digits, so an inline table reads back equal
([`all.equal()`](https://rdrr.io/r/base/all.equal.html)), not
necessarily identical, for arbitrary doubles.

## Examples

``` r
s <- scale_example()
f <- file.path(tempdir(), "example.json")
write_scale(s, f, overwrite = TRUE)
back <- read_scale(f)
identical(scale_frames(back), scale_frames(s))
#> [1] TRUE
all.equal(scale_leaftable(back), scale_leaftable(s))
#> [1] TRUE

# a bundle, with the tables as files
if (requireNamespace("arrow", quietly = TRUE)) {
  d <- file.path(tempdir(), "example.scale")
  write_scale(s, d, tables = "arrow", overwrite = TRUE)
  list.files(d)
  identical(scale_leaftable(read_scale(d)), scale_leaftable(s))
}
#> Warning: write_feather(version = 2) has been superseded by write_ipc_file().
#> Warning: 'arrow::read_feather' is deprecated.
#> Use 'read_ipc_file' instead.
#> See help("Deprecated")
#> [1] TRUE
```
