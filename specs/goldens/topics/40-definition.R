# Definition-file goldens: sourced by generate.R.
#
# R writes definitions under specs/goldens/definitions/ (single JSON files and
# bundle directories, schema version 2); definition.json describes what each
# must read back as. Bindings read every file, compare the description, and
# write the scale again to compare the header they produce with R's (the
# `nestedscales` version field excepted).
#
# specs/goldens/definitions_v1/ holds definitions of schema version 1, written
# by nestedscales 0.2.0. They are an input and are never regenerated;
# definition_v1.json describes what each reads back as.

def_dir <- file.path(out_dir, "definitions")
unlink(def_dir, recursive = TRUE)
dir.create(def_dir)

# a scale held in `meta` is written as a reference and reads back as one
meta_refs <- function(m) {
  Filter(function(z) is.list(z) && identical(names(z), "_scale"), m)
}

def_desc <- function(s) {
  m <- S7::prop(s, "meta")
  c(tables_desc(s), list(
    weights = vec(scale_weights(s)), default_weight = m[["default_weight"]],
    name = m[["name"]], desc = m[["desc"]],
    tokens = if (is.null(m[["tokens"]])) NULL else as.list(m[["tokens"]]),
    parent_name = m[["parent_name"]],
    coverage = num(m[["coverage"]]), parent_totals = num(m[["parent_totals"]]),
    residuals = if (is.null(m[["residuals"]])) NULL else
      lapply(m[["residuals"]], vec),
    refs = meta_refs(m),
    id = scale_id(s),
    leaftable = rows(scale_leaftable(s))
  ))
}

lt_ex <- scale_leaftable(scale_example())
defs <- list(
  list(file = "example.json", tables = "inline", scale = scale_example()),
  list(file = "fuels.json", tables = "inline", scale = build_a(fuels)),
  list(file = "labelled.json", tables = "inline",
       scale = attach_labels_scale(build_a(fuels_l), lb_new,
                                   variant = "short", default = "short")),
  list(file = "sample.json", tables = "inline",
       scale = filter_scale(
         scale_from_leaftable(lt_ex, frames = c("sector", "class", "group",
                                                "item"),
                              name = "example", residuals = list(item = "U6")),
         "sector", c("P", "S")
       )),
  list(file = "linked.json", tables = "inline",
       scale = scale_from_leaftable(scale_leaftable(scale_example2()),
                                    frames = c("era", "period"),
                                    name = "linked",
                                    based_on = scale_example())),
  list(file = "grid.scale", tables = "arrow",
       scale = scale_from_leaftable(grid, frames = c("m", "h"), leaf = "item",
                                    weights = "hours", name = "grid",
                                    tokens = c(m = "month", h = "hour"))),
  list(file = "tree.scale", tables = "csv", scale = build_a(fuels_tree)),
  list(file = "labelled.scale", tables = "csv", scale = build_a(fuels_tree_l))
)
dcases <- lapply(defs, function(d) {
  path <- write_scale(d$scale, file.path(def_dir, d$file), tables = d$tables)
  back <- read_scale(path)
  stopifnot(identical(scale_frames(back), scale_frames(d$scale)),
            identical(scale_id(back), scale_id(d$scale)))
  list(file = d$file, tables = d$tables, value = def_desc(back))
})

write_golden(dcases, "definition.json")

v1_dir <- file.path(out_dir, "definitions_v1")
v1cases <- lapply(sort(list.files(v1_dir)), function(f) {
  list(file = f, value = def_desc(read_scale(file.path(v1_dir, f))))
})

write_golden(v1cases, "definition_v1.json")
