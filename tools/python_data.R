# Vendor the shipped definitions into the Python binding.
#
#   Rscript tools/python_data.R        # from the repository root
#
# The Python binding reads the same files R ships under inst/scales/ and
# inst/extdata/; this copies them verbatim into python/src/nestedscales/data/
# so `nestedscales.read_scale("carriers")` resolves without R installed.
# Run after data-raw/carriers.R; python/tests/test_definition.py checks the
# copy is identical to the R one.

src_scales <- list.files(file.path("inst", "scales"), full.names = TRUE)
src_extra <- list.files(file.path("inst", "extdata"), full.names = TRUE)
dst <- file.path("python", "src", "nestedscales", "data")
dir.create(dst, showWarnings = FALSE, recursive = TRUE)
for (f in c(src_scales, src_extra)) {
  file.copy(f, file.path(dst, basename(f)), overwrite = TRUE)
  cat("copied", basename(f), "\n")
}
