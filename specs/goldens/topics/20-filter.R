# Filter / prune / share / join / array goldens: sourced by generate.R.
#
# A scale-valued case is a chain of steps applied to a base scale; its result
# is the whole scale (frames, members, the sample bookkeeping, the leaftable).

scale_desc <- function(s) {
  m <- S7::prop(s, "meta")
  list(
    frames = vec(scale_frames(s)), key = scale_key(s),
    members = lapply(S7::prop(s, "members"), vec),
    name = m[["name"]], parent_name = m[["parent_name"]],
    coverage = num(m[["coverage"]]), parent_totals = num(m[["parent_totals"]]),
    weights = vec(scale_weights(s)), default_weight = m[["default_weight"]],
    leaftable = rows(scale_leaftable(s))
  )
}

fcalls <- list()
steps_case <- function(base, steps) {
  r <- withCallingHandlers(
    try_call({
      s <- build_r(base)
      for (st in steps) s <- do.call(st$fn, c(list(s), st$args))
      s
    }),
    warning = function(cnd) invokeRestart("muffleWarning")
  )
  if (!r$error) r$value <- scale_desc(r$value)
  fcalls[[length(fcalls) + 1L]] <<- c(
    list(kind = "scale", scale = construct_r(base), steps = steps), r
  )
}
step <- function(fn, ...) list(fn = fn, args = list(...))
table_case <- function(fn, base, data = NULL, ...) {
  args <- list(...)
  s <- build_r(base)
  pos <- if (is.null(data)) list(s) else list(data, s)
  r <- with_warnings(do.call(fn, c(pos, args)))
  fcalls[[length(fcalls) + 1L]] <<- c(
    list(kind = "table", fn = fn, scale = construct_r(base),
         data = if (!is.null(data)) tab(data), args = args),
    r
  )
}

# filter / prune ---------------------------------------------------------------

steps_case(ex, list(step("filter_scale", "sector", "P")))
steps_case(ex, list(step("filter_scale", "class", c("G1", "S1"))))
steps_case(ex, list(step("filter_scale", "group", "GB")))
steps_case(ex, list(step("filter_scale", "unit", U)))
steps_case(ex, list(step("filter_scale", "sector", "P"),
                    step("filter_scale", "class", "G1")))
steps_case(ex, list(step("filter_scale", "unit", "OTH")))
steps_case(ex, list(step("filter_scale", "unit", "OTH", drop_empty_frames = TRUE)))
steps_case(ex, list(step("filter_scale", "sector", "Q")))
steps_case(ex, list(step("filter_scale", "unit",
                         c("U1", "U2", "U3", "U4", "U5", "U6"))))
for (f in c("sector", "class", "group", "unit")) {
  steps_case(ex, list(step("prune_scale", f)))
}
steps_case(ex, list(step("filter_scale", "sector", "S"),
                    step("prune_scale", "class")))
steps_case(noweights, list(step("prune_scale", "grp")))
steps_case(ex_res, list(step("filter_scale", "class", "S1")))

# share / join / array ---------------------------------------------------------

for (f in c("class", "group", "unit")) {
  for (w in list(NULL, "count")) {
    table_case("scale_share", ex, frame = f, weight = w)
    table_case("scale_share", ex, frame = f, weight = w, within = "sector")
  }
}
table_case("scale_share", ex, frame = "unit", within = "group")

d_join <- data.frame(class = c("G1", "G2", "S1", "G1"), v = c(1, 2, 3, 4))
table_case("join_scale", ex, d_join)
table_case("join_scale", ex, d_join, attach = TRUE)
table_case("join_scale", ex, d_join, attach = "sector", as_factor = FALSE)
table_case("join_scale", ex, d_join, meta = TRUE)
table_case("join_scale", ex, d_join, attach = TRUE, meta = TRUE, weight = "count")
table_case("join_scale", ex, d_group, attach = TRUE)
table_case("join_scale", ex, rbind(d_join, data.frame(class = "ZZ", v = 9)))
table_case("join_scale", ex, data.frame(class = "ZZ", v = 9))
table_case("join_scale", ex, data.frame(class = "G1", example = "x"),
           attach = "sector")
table_case("join_scale", ex, data.frame(example = c("G1", "S1"), v = 1:2),
           frame = "class", attach = TRUE)
table_case("join_scale", ex, d_unit, attach = "group")
table_case("join_scale", ex, d_unit, frame = "unit", attach = "nope")
table_case("join_scale", noweights, d_nw, meta = TRUE)

write_golden(fcalls, "filter.json")
