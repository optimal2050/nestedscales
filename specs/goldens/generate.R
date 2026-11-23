# Generate the cross-language golden cases from the R package SOURCE.
#
# Run from the repository root:
#   Rscript specs/goldens/generate.R
#
# Every binding replays these files and must reproduce them. Each case carries
# its own construction arguments so a binding rebuilds the exact same scale.
# Row order of tables is not part of the contract (R sorts in the session
# locale); bindings compare rows as sets.

pkgload::load_all(".", quiet = TRUE, export_all = FALSE)

out_dir <- file.path("specs", "goldens")
vec <- function(x) I(as.character(x))
num <- function(x) if (is.null(x)) NULL else as.list(x)
rows <- function(df) {
  if (nrow(df) == 0L) return(I(list()))
  lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
}
verdict <- function(v, attr_name = "offenders") {
  a <- attr(v, attr_name)
  list(
    ok = isTRUE(v),
    offenders = if (attr_name == "offenders") vec(a %||% character()) else NULL,
    sizes = if (attr_name == "sizes" && !is.null(a)) as.list(a) else NULL
  )
}
try_call <- function(expr) {
  tryCatch(list(error = FALSE, value = expr),
           error = function(e) list(error = TRUE, message = conditionMessage(e)))
}

build <- function(spec) {
  if (spec$build == "scale_from_leaftable") {
    scale_from_leaftable(spec$leaftable, frames = spec$frames,
                         leaf = spec$leaf, name = spec$name)
  } else {
    get(spec$build)()
  }
}
construct <- function(spec) list(
  build = spec$build,
  leaftable = if (!is.null(spec$leaftable)) as.list(spec$leaftable),
  frames = if (!is.null(spec$frames)) vec(spec$frames),
  leaf = spec$leaf, name = spec$name
)

grid <- expand.grid(m = c("m1", "m2"), h = c("h1", "h2", "h3"),
                    stringsAsFactors = FALSE)
grid$item <- paste(grid$m, grid$h, sep = "_")
grid$hours <- c(31, 28, 31, 28, 31, 28)

cases <- list(
  example = list(build = "scale_example"),
  example2 = list(build = "scale_example2"),
  grid = list(build = "scale_from_leaftable", leaftable = grid,
              frames = c("m", "h"), leaf = "item", name = "grid")
)

one_case <- function(spec) {
  s <- build(spec)
  fr <- scale_frames(s)
  nav <- unique(c(fr, scale_leaf_frame(s)))
  pairs <- expand.grid(a = fr, b = fr, stringsAsFactors = FALSE)
  pairs <- pairs[pairs$a != pairs$b, ]

  nav_calls <- list()
  for (fn in c("scale_children", "scale_parents",
               "scale_descendants", "scale_ancestors")) {
    for (f in nav) {
      for (u in scale_members(s, f)) {
        r <- try_call(get(fn)(s, f, u))
        if (!r$error && is.data.frame(r$value)) r$value <- rows(r$value)
        if (!r$error && is.character(r$value)) r$value <- vec(r$value)
        nav_calls[[length(nav_calls) + 1L]] <- c(
          list(fn = fn, frame = f, member = u), r
        )
      }
    }
  }

  uniform <- list()
  for (f in fr) {
    for (w in c(list(NULL), as.list(scale_weights(s)))) {
      uniform[[length(uniform) + 1L]] <- c(
        list(frame = f, weight = w),
        verdict(scale_is_uniform(s, f, weight = w), "sizes")
      )
    }
  }

  list(
    construct = construct(spec),
    frames = vec(fr),
    leaf = scale_leaf_column(s),
    leaf_frame = scale_leaf_frame(s),
    id = scale_id(s),
    format = format(s),
    print = vec(utils::capture.output(print(s))),
    summary = vec(utils::capture.output(print(summary(s)))),
    tree = rows(as.data.frame(unclass(scale_tree(s)))),
    tree_lines = vec(utils::capture.output(print(scale_tree(s), ascii = TRUE))),
    weights = vec(scale_weights(s)),
    coverage = num(scale_coverage(s)),
    rank = lapply(stats::setNames(nm = unique(c(fr, scale_leaf_column(s), "nope"))),
                  function(f) scale_rank(s, f)),
    members = lapply(stats::setNames(nm = nav), function(f) vec(scale_members(s, f))),
    family = rows(scale_family(s)),
    ancestry = rows(scale_ancestry(s)),
    nests = lapply(seq_len(nrow(pairs)), function(i) c(
      list(parent = pairs$a[i], child = pairs$b[i]),
      verdict(scale_nests(s, pairs$a[i], pairs$b[i]))
    )),
    crosses = lapply(seq_len(nrow(pairs)), function(i) c(
      list(a = pairs$a[i], b = pairs$b[i]),
      verdict(scale_crosses(s, pairs$a[i], pairs$b[i]))
    )),
    uniform = uniform,
    nav = nav_calls
  )
}

write_golden <- function(x, file) {
  jsonlite::write_json(
    list(generated_by = paste("nestedscales", packageVersion("nestedscales")),
         cases = x),
    file.path(out_dir, file),
    auto_unbox = TRUE, digits = NA, null = "null", na = "null", pretty = TRUE
  )
  cat("wrote", file.path(out_dir, file), "\n")
}

write_golden(lapply(cases, one_case), "navigation.json")

# Maps -------------------------------------------------------------------------

with_warnings <- function(expr) {
  w <- character()
  r <- withCallingHandlers(
    try_call(expr),
    warning = function(cnd) {
      w <<- c(w, conditionMessage(cnd))
      invokeRestart("muffleWarning")
    }
  )
  if (!r$error) {
    r$value <- if (is.data.frame(r$value)) rows(r$value) else vec(r$value)
  }
  c(r, list(warnings = vec(w)))
}

map_cases <- c(cases, list(
  noweights = list(
    build = "scale_from_leaftable",
    leaftable = data.frame(grp = c("A", "A", "B"), item = c("u1", "u2", "u3")),
    frames = c("grp", "item"), leaf = "item", name = "noweights"
  )
))
within <- lapply(map_cases, function(spec) {
  s <- build(spec)
  fr <- scale_frames(s)
  calls <- list()
  for (a in fr) for (b in fr) {
    if (a == b) next
    for (w in c(list(NULL), as.list(scale_weights(s)))) {
      calls[[length(calls) + 1L]] <- c(
        list(source = a, target = b, weight = w),
        with_warnings(scale_map(s, a, b, weight = w))
      )
    }
  }
  list(construct = construct(spec), calls = calls)
})

other <- list(
  build = "scale_from_leaftable",
  leaftable = data.frame(big = c("X", "X", "Y", "Y", "Y", "Y", "Z"),
                         item = c("U1", "U2", "U3", "U4", "U5", "U6", "OTH"),
                         size = c(1, 2, 3, 4, 5, 6, 7)),
  frames = c("big", "item"), leaf = "item", name = "other"
)
partial <- list(
  build = "scale_from_leaftable",
  leaftable = data.frame(top = c("T1", "T1", "T2"), item = c("U1", "U3", "U9")),
  frames = c("top", "item"), leaf = "item", name = "partial"
)
disjoint <- list(
  build = "scale_from_leaftable",
  leaftable = data.frame(grp = c("A", "B"), item = c("z1", "z2")),
  frames = c("grp", "item"), leaf = "item", name = "disjoint"
)
specs <- list(example = list(build = "scale_example"), other = other,
              partial = partial, disjoint = disjoint)
pairs_between <- list(
  c("example", "other", NA), c("example", "other", "count"),
  c("other", "example", NA), c("example", "partial", NA),
  c("partial", "example", NA), c("example", "disjoint", NA)
)
between <- lapply(pairs_between, function(p) {
  w <- if (is.na(p[3])) NULL else p[3]
  c(
    list(source = construct(specs[[p[1]]]), target = construct(specs[[p[2]]]),
         weight = w),
    with_warnings(scale_map_between(build(specs[[p[1]]]), build(specs[[p[2]]]),
                                    weight = w))
  )
})

write_golden(list(within = within, between = between), "maps.json")

# Topic scripts share the helpers above ----------------------------------------

for (f in sort(list.files(file.path(out_dir, "topics"), pattern = "[.]R$",
                          full.names = TRUE))) {
  source(f, local = TRUE)
}
