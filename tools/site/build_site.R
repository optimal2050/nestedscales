# =========================================================================== #
# build_site.R -- the R and Python documentation as one site.
#
# Usage (from the repository root):
#   Rscript tools/site/build_site.R
#
#   docs/index.html  landing page (tools/site/index.html)
#   docs/r/          pkgdown site (_pkgdown.yml: destination docs/r)
#   docs/python/     MkDocs site (python/mkdocs.yml, written by
#                    tools/site/python_reference.py)
#
# The Python site needs the binding's virtual environment with the `docs`
# extra: python/.venv, `pip install -e "python[docs]"`.
# =========================================================================== #

py <- normalizePath(file.path("python", ".venv",
                              if (.Platform$OS.type == "windows") "Scripts/python.exe"
                              else "bin/python"), mustWork = TRUE)

unlink("docs", recursive = TRUE)
dir.create("docs")

pkgdown::build_site(".", preview = FALSE, install = TRUE)

run <- function(args, wd = ".") {
  old <- setwd(wd)
  on.exit(setwd(old))
  status <- system2(py, args)
  if (!identical(status, 0L)) stop("failed: python ", paste(args, collapse = " "))
}
run("tools/site/python_reference.py")
run(c("-m", "mkdocs", "build", "--clean", "--quiet"), wd = "python")

file.copy(file.path("tools", "site", "index.html"), file.path("docs", "index.html"),
          overwrite = TRUE)
file.create(file.path("docs", ".nojekyll"))
cat("site written to docs/: r/, python/, index.html\n")
