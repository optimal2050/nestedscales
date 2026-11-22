# Shipped scale definitions

Packages ship scale definitions as files (see
[`write_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md))
and register the directory holding them; `scale_catalog()` lists what
every registered directory holds and
[`read_scale()`](https://optimal2050.github.io/nestedscales/r/reference/write_scale.md)
takes an id from it. nestedscales itself ships no definitions.

## Usage

``` r
register_scale_dir(path, package = NULL)

list_scale_dirs()

clear_scale_dirs()

scale_catalog()
```

## Arguments

- path:

  A directory of definition files or bundles.

- package:

  The package registering it; `NULL` for a directory registered by hand
  (listed under `package = NA`).

## Value

`scale_catalog()` a `data.frame` with one row per definition: `id`,
`name`, `kind` (the class, without its package prefix), `leaf` (the name
of the leaf column), `frames` (joined by `/`), `n_leaves`, `package`,
`path`. `register_scale_dir()` the registry key, invisibly;
`list_scale_dirs()` a `data.frame` with `package` and `path`;
`clear_scale_dirs()` `NULL`, invisibly.

## Details

`register_scale_dir()` is what a dimension package calls in its
`.onLoad()`:
`register_scale_dir(system.file("scales", package = pkgname), package = pkgname)`.

## Examples

``` r
scale_catalog()
#> [1] id       name     kind     leaf     frames   n_leaves package  path    
#> <0 rows> (or 0-length row.names)
```
