# Cross-language round trips, driven by tests/test_store_roundtrip.py.
#
#   Rscript roundtrip.R <repo root> write <dir>   R writes the reference stores
#   Rscript roundtrip.R <repo root> check <dir>   R opens stores Python wrote
#   Rscript roundtrip.R <repo root> defs <dir> <reference dir>
#                                                 R reads definitions Python
#                                                 wrote and compares each with
#                                                 the definition of the same
#                                                 name R wrote
#
# `check` and `defs` print one line per case: "OK <name>" or
# "FAIL <name>: <reason>".

args <- commandArgs(trailingOnly = TRUE)
pkgload::load_all(args[[1]], quiet = TRUE, export_all = FALSE)
mode <- args[[2]]
dir <- args[[3]]

lt <- scale_leaftable(scale_example())
res <- scale_from_leaftable(lt, frames = c("sector", "class", "group", "item"),
                            leaf = "item", name = "example",
                            residuals = list(item = "U6"))
single <- filter_scale(res, "sector", c("P", "S"))
prod <- scale_product(a = scale_example(), b = scale_example2())

d_single <- data.frame(
  item = rep(c("U1", "U2", "U3", "U4", "U5", "U6"), 2),
  year = rep(c(2020L, 2021L), each = 6),
  cap = c(1:6, 11:16) * 1.5
)
d_prod <- merge(data.frame(item = c("U1", "U2", "OTH")),
                data.frame(period = c("p1", "p3")))
d_prod$v <- seq_len(nrow(d_prod)) / 4

same_table <- function(a, b) {
  isTRUE(all.equal(as.data.frame(a), as.data.frame(b),
                   check.attributes = FALSE))
}

same_scale <- function(got, orig) {
  m1 <- S7::prop(got, "meta")
  m0 <- S7::prop(orig, "meta")
  checks <- c(
    frames = identical(scale_frames(got), scale_frames(orig)),
    leaf = identical(scale_leaf_column(got), scale_leaf_column(orig)),
    members = all(vapply(scale_frames(orig), function(f) {
      identical(scale_members(got, f), scale_members(orig, f))
    }, logical(1))),
    weights = identical(scale_weights(got), scale_weights(orig)),
    leaftable = same_table(scale_leaftable(got), scale_leaftable(orig)),
    name = identical(m1[["name"]], m0[["name"]]),
    residuals = identical(scale_residuals(got), scale_residuals(orig)),
    coverage = isTRUE(all.equal(scale_coverage(got), scale_coverage(orig))),
    parent_totals = isTRUE(all.equal(unlist(m1[["parent_totals"]]),
                                     unlist(m0[["parent_totals"]]))),
    id = identical(scale_id(got), scale_id(orig))
  )
  names(checks)[!checks]
}

# Every part of a definition: the tables, the whole of `meta` (a scale held
# in it reads back as its reference) and the identity.
same_definition <- function(got, orig) {
  checks <- c(
    class = identical(class(got), class(orig)),
    meta = isTRUE(all.equal(S7::prop(got, "meta"), S7::prop(orig, "meta"))),
    meta_names = identical(names(S7::prop(got, "meta")),
                           names(S7::prop(orig, "meta"))),
    attributes = same_table(scale_attributes(got), scale_attributes(orig)),
    aliases = same_table(scale_aliases(got), scale_aliases(orig)),
    labels = same_table(scale_labels(got), scale_labels(orig))
  )
  c(same_scale(got, orig), names(checks)[!checks])
}

same_data <- function(got, orig) {
  got <- as.data.frame(dplyr::collect(got))
  cols <- names(orig)
  got <- got[, cols]
  for (c in cols) if (is.factor(got[[c]])) got[[c]] <- as.character(got[[c]])
  o1 <- do.call(order, unname(as.list(got)))
  o0 <- do.call(order, unname(as.list(orig)))
  isTRUE(all.equal(got[o1, ], orig[o0, ], check.attributes = FALSE))
}

report <- function(name, bad) {
  cat(if (length(bad)) sprintf("FAIL %s: %s\n", name,
                               paste(bad, collapse = ", "))
      else sprintf("OK %s\n", name))
}

if (mode == "write") {
  write_scale_dataset(d_single, single, file.path(dir, "r_single"),
                      partitioning = "year", overwrite = TRUE)
  write_scale_dataset(d_prod, prod, file.path(dir, "r_product"), overwrite = TRUE)
} else if (mode == "defs") {
  ref <- args[[4]]
  for (f in sort(list.files(dir))) {
    bad <- tryCatch(
      same_definition(read_scale(file.path(dir, f)),
                      read_scale(file.path(ref, f))),
      error = function(e) conditionMessage(e)
    )
    report(f, bad)
  }
} else {
  for (case in list(list("py_single", single, d_single),
                    list("py_product", prod, d_prod))) {
    ds <- open_scale_dataset(file.path(dir, case[[1]]))
    bad <- character()
    if (scale_is_product(case[[2]])) {
      for (a in names(scale_axes(case[[2]]))) {
        miss <- same_scale(scale_axes(ds$scale, a), scale_axes(case[[2]], a))
        if (length(miss)) bad <- c(bad, paste0(a, ".", miss))
      }
      if (!identical(product_keys(ds$scale), product_keys(case[[2]]))) {
        bad <- c(bad, "keys")
      }
    } else {
      bad <- c(bad, same_scale(ds$scale, case[[2]]))
    }
    if (!same_data(ds$data, case[[3]])) bad <- c(bad, "data")
    report(case[[1]], bad)
  }
}
