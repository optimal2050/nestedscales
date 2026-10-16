# Recast goldens: sourced by specs/goldens/generate.R (shares its helpers).
#
# Each call records the function, the scale, the data (column-wise with types),
# the arguments, and the result with every warning. `ordered` says whether the
# row order is part of the contract (completed results are; the atom
# projection and an uncompleted crosswalk are not).

tab <- function(df) list(
  columns = lapply(df, function(c) if (is.character(c)) vec(c) else I(as.numeric(c))),
  types = lapply(df, function(c) if (is.character(c)) "string" else "double")
)

build_r <- function(spec) {
  if (spec$build == "scale_from_leaftable") {
    args <- list(spec$leaftable, frames = spec$frames, key = spec$key,
                 name = spec$name)
    if (!is.null(spec$residuals)) args$residuals <- spec$residuals
    do.call(scale_from_leaftable, args)
  } else {
    get(spec$build)()
  }
}
construct_r <- function(spec) {
  out <- construct(spec)
  if (!is.null(spec$residuals)) {
    out$residuals <- lapply(spec$residuals, vec)
  }
  out
}

calls <- list()
call <- function(fn, scale, data, ..., ordered = TRUE) {
  args <- list(...)
  run_args <- args
  if (!is.null(args$to_scale)) {
    run_args$to <- build_r(args$to_scale)
    run_args$to_scale <- NULL
    args$to_scale <- construct_r(args$to_scale)
  }
  if (!is.null(args$map)) args$map <- tab(args$map)
  s <- if (is.null(scale)) NULL else build_r(scale)
  pos <- if (is.null(s)) list(data) else list(data, s)
  r <- with_warnings(do.call(fn, c(pos, run_args)))
  calls[[length(calls) + 1L]] <<- c(
    list(fn = fn, scale = if (!is.null(scale)) construct_r(scale),
         data = tab(data), args = args, ordered = ordered),
    r
  )
}

# Scales -----------------------------------------------------------------------

ex <- list(build = "scale_example")
lt_ex <- scale_leaftable(scale_example())
ex_res <- list(build = "scale_from_leaftable", leaftable = lt_ex,
               frames = c("sector", "class", "group", "unit"), key = "unit",
               name = "example", residuals = list(unit = "U6"))
ex_dead <- ex_res
ex_dead$residuals <- list(unit = c("U5", "U6"))
noweights <- list(build = "scale_from_leaftable",
                  leaftable = data.frame(grp = c("A", "A", "B"),
                                         unit = c("u1", "u2", "u3")),
                  frames = c("grp", "unit"), key = "unit", name = "noweights")
other <- list(build = "scale_from_leaftable",
              leaftable = data.frame(big = c("X", "X", "Y", "Y", "Y", "Y", "Z"),
                                     unit = c("U1", "U2", "U3", "U4", "U5", "U6",
                                              "OTH"),
                                     size = c(1, 2, 3, 4, 5, 6, 7)),
              frames = c("big", "unit"), key = "unit", name = "other")

# Data -------------------------------------------------------------------------

U <- c("U1", "U2", "U3", "U4", "U5", "U6", "OTH")
d_unit <- data.frame(unit = U, cap = c(1, 2, 3, 4, 5, 6, 7),
                     eff = c(.5, .6, .7, .8, .9, 1, .4))
d_unit6 <- d_unit[1:6, ]
d_panel <- rbind(cbind(d_unit, year = 2020),
                 cbind(transform(d_unit, cap = cap * 10), year = 2021))
d_na <- d_unit
d_na$cap[2] <- NA
d_partial <- data.frame(unit = "U1", value = 1)
d_partial_panel <- data.frame(unit = c("U1", "U2", "U1"),
                              year = c(2020, 2020, 2021), value = c(1, 2, 5))
d_unknown <- rbind(d_unit, data.frame(unit = "ZZ", cap = 9, eff = .1))
d_none <- data.frame(unit = c("ZZ", "YY"), cap = c(1, 2))
d_sector <- data.frame(sector = c("P", "S"), cap = c(10, 20), eff = c(.5, .7))
d_class <- data.frame(class = c("G1", "G2", "S1"), cap = c(3, 7, 11),
                      eff = c(.5, .6, .7))
d_group <- data.frame(group = c("G1", "GB", "GC"), cap = c(3, 12, 6),
                      eff = c(.5, .6, .7))
d_copy_ok <- data.frame(unit = U[1:6], k = c(1, 1, 2, 2, 3, 3))
d_copy_bad <- data.frame(unit = U[1:6], k = c(1, 2, 2, 2, 3, 3))
d_nw <- data.frame(grp = c("A", "B"), cap = c(10, 20))

RULES <- c("sum", "mean", "weighted_mean", "copy", "sd")
CV <- c("cap", "eff")

# recast_scale: up -------------------------------------------------------------

for (r in RULES) {
  for (to in c("class", "sector", "group")) {
    for (na in c("drop", "keep", "error")) {
      call("recast_scale", ex, d_unit, from = "unit", to = to, rule = r,
           values = CV, na_action = na)
    }
    call("recast_scale", ex, d_unit6, from = "unit", to = to, rule = r,
         values = CV)
    call("recast_scale", ex, d_panel, from = "unit", to = to, rule = r,
         values = CV)
    call("recast_scale", ex, d_na, from = "unit", to = to, rule = r,
         values = CV)
    call("recast_scale", ex, d_partial, from = "unit", to = to, rule = r)
    call("recast_scale", ex, d_partial_panel, from = "unit", to = to, rule = r,
         values = "value")
  }
  for (w in c("count", "size")) {
    call("recast_scale", ex, d_unit, from = "unit", to = "class", rule = r,
         values = CV, weight = w)
  }
}
call("recast_scale", ex, d_copy_ok, from = "unit", to = "class", rule = "copy")
call("recast_scale", ex, d_copy_bad, from = "unit", to = "class", rule = "copy")
call("recast_scale", ex, d_unit, from = "unit", to = "class",
     rule = list(cap = "sum", eff = "weighted_mean"),
     weight = list(cap = "size", eff = "count"))
call("recast_scale", ex, d_partial, from = "unit", to = "class", rule = "sum",
     missing_sources = "ignore")
call("recast_scale", ex, d_partial, from = "unit", to = "class", rule = "sum",
     diagnostics = "off")
call("recast_scale", ex, d_unknown, from = "unit", to = "class", rule = "sum",
     values = CV)
call("recast_scale", ex, d_none, from = "unit", to = "class", rule = "sum")
call("recast_scale", ex, d_unit, to = "class", rule = "sum", values = CV)
call("recast_scale", ex, d_unit, from = "unit", to = "class", values = CV)

# recast_scale: down and across -------------------------------------------------

down <- list(
  list(d_sector, "sector", c("unit", "class", "group")),
  list(d_class, "class", c("unit", "group", "sector")),
  list(d_group, "group", c("class", "unit"))
)
for (dn in down) {
  for (to in dn[[3]]) {
    for (r in RULES) {
      for (na in c("drop", "keep")) {
        call("recast_scale", ex, dn[[1]], from = dn[[2]], to = to, rule = r,
             na_action = na)
      }
    }
    call("recast_scale", ex, dn[[1]], from = dn[[2]], to = to, rule = "sum",
         weight = "count")
  }
}

# residuals --------------------------------------------------------------------

call("recast_scale", ex_res, d_class, from = "class", to = "unit", rule = "sum")
call("recast_scale", ex_res, d_class, from = "class", to = "unit", rule = "sum",
     weight = "count")
call("recast_scale", ex_res, d_sector, from = "sector", to = "unit", rule = "sum")
call("recast_scale", ex_res, d_unit6, from = "unit", to = "class", rule = "sum")
call("recast_scale", ex_dead, d_class, from = "class", to = "unit", rule = "sum")

# share ------------------------------------------------------------------------

for (na in c("drop", "keep", "error")) {
  call("recast_scale", ex, d_unit, from = "unit", to = "sector", rule = "share",
       values = CV, na_action = na)
}
call("recast_scale", ex, d_unit6, from = "unit", to = "unit", rule = "share",
     values = CV)
call("recast_scale", ex, d_unit6, from = "unit", to = "unit", rule = "share",
     values = CV, parent = "class")
call("recast_scale", ex, d_unit6, from = "unit", to = "sector", rule = "share",
     values = CV, parent = "class")
call("recast_scale", ex, d_panel, from = "unit", to = "class", rule = "logshare",
     values = CV, na_action = "keep")
call("recast_scale", ex, d_group, from = "group", to = "sector", rule = "share")
call("recast_scale", ex, d_class, from = "class", to = "sector", rule = "share",
     weight = "size")
call("recast_scale", ex, d_unit, from = "unit", to = "class",
     rule = list(cap = "share", eff = "sum"))
call("recast_scale", ex, d_unit, from = "unit", to = "class", rule = "sum",
     values = CV, parent = "sector")

# no weights, cross-object -----------------------------------------------------

call("recast_scale", noweights, d_nw, from = "grp", to = "unit", rule = "sum")
call("recast_scale", noweights, d_nw, from = "grp", to = "unit", rule = "copy")
call("recast_scale", ex, d_unit, from = "unit", to_scale = other, rule = "sum",
     values = CV)
call("recast_scale", ex, d_class, from = "class", to_scale = other, rule = "sum")

# recast_crosswalk -------------------------------------------------------------

cw <- data.frame(month = c("m01", "m02"), quarter = "Q1",
                 n_from = c(31, 28), n_overlap = c(31, 28))
d_month <- data.frame(month = c("m01", "m02"), energy = c(310, 280),
                      price = c(10, 20))
call("recast_crosswalk", NULL, d_month, map = cw, from = "month", to = "quarter",
     rule = list(energy = "sum", price = "weighted_mean"), ordered = FALSE)
call("recast_crosswalk", NULL, d_month, map = cw, from = "month", to = "quarter",
     rule = list(energy = "sum", price = "weighted_mean"),
     targets = c("Q1", "Q2", NA))
cw_w <- transform(cw, w = c(1, 3), w_from = c(1, 3))
call("recast_crosswalk", NULL, d_month, map = cw_w, from = "month",
     to = "quarter", rule = "sum", ordered = FALSE)
cw_y <- rbind(cbind(cw, year = 2020), cbind(transform(cw, quarter = "Q2"),
                                            year = 2021))
d_month_y <- rbind(cbind(d_month, year = 2020), cbind(d_month, year = 2021))
call("recast_crosswalk", NULL, d_month_y, map = cw_y, from = "month",
     to = "quarter", values = c("energy", "price"), rule = "sum", by = "year",
     ordered = FALSE)
call("recast_crosswalk", NULL, d_month[1, ], map = cw, from = "month",
     to = "quarter", rule = "sum", ordered = FALSE)
call("recast_crosswalk", NULL, d_month, map = cw, from = "month", to = "quarter",
     rule = "share", ordered = FALSE)

# the atom halves --------------------------------------------------------------

call("recast_to_atoms", ex, d_sector, from = "sector", rule = "sum",
     weight = "size", ordered = FALSE)
call("recast_to_atoms", ex, d_class, from = "class",
     rule = list(cap = "sum", eff = "weighted_mean"), ordered = FALSE)
call("recast_to_atoms", ex, d_group, from = "group", rule = "sum",
     attach_weight = FALSE, ordered = FALSE)
call("recast_to_atoms", ex, d_unit, from = "unit", rule = "sum", values = CV,
     ordered = FALSE)
for (r in RULES) {
  for (na_rm in c(FALSE, TRUE)) {
    call("recast_from_atoms", ex, d_na, to = "class", rule = r, values = CV,
         na_rm = na_rm)
  }
  for (na in c("drop", "keep", "error")) {
    call("recast_from_atoms", ex, d_panel, to = "sector", rule = r,
         values = CV, na_action = na)
  }
}
atoms <- recast_to_atoms(d_class, scale_example(), from = "class",
                         rule = list(cap = "sum", eff = "weighted_mean"))
call("recast_from_atoms", ex, atoms, to = "class",
     rule = list(cap = "sum", eff = "weighted_mean"))
call("recast_from_atoms", ex, d_partial, to = "class", rule = "sum")

write_golden(calls, "recast.json")
