# Definition-file goldens: sourced by generate.R.
#
# R writes definitions under specs/goldens/definitions/ (single JSON files and
# bundle directories); definition.json describes what each must read back as.
# Bindings read every file, compare the description, and write the scale again
# to compare the header they produce with R's (the `nestedscales` version
# field excepted).

def_dir <- file.path(out_dir, "definitions")
unlink(def_dir, recursive = TRUE)
dir.create(def_dir)

def_desc <- function(s) {
  m <- S7::prop(s, "meta")
  c(tables_desc(s), list(
    weights = vec(scale_weights(s)), default_weight = m[["default_weight"]],
    name = m[["name"]], desc = m[["desc"]],
    tokens = if (is.null(m[["tokens"]])) NULL else as.list(m[["tokens"]]),
    leaftable = rows(scale_leaftable(s))
  ))
}

defs <- list(
  list(file = "example.json", tables = "inline", scale = scale_example()),
  list(file = "fuels.json", tables = "inline", scale = build_a(fuels)),
  list(file = "grid.scale", tables = "arrow",
       scale = scale_from_leaftable(grid, frames = c("m", "h"), key = "unit",
                                    weights = "hours", name = "grid",
                                    tokens = c(m = "month", h = "hour"))),
  list(file = "tree.scale", tables = "csv", scale = build_a(fuels_tree))
)
dcases <- lapply(defs, function(d) {
  path <- write_scale(d$scale, file.path(def_dir, d$file), tables = d$tables)
  back <- read_scale(path)
  stopifnot(identical(scale_frames(back), scale_frames(d$scale)))
  list(file = d$file, tables = d$tables, value = def_desc(d$scale))
})

write_golden(dcases, "definition.json")
