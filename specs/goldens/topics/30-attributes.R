# Attribute / alias / conversion goldens: sourced by generate.R.
#
# The scale is the 9-fuel example of the test fixtures (reused code, a
# cross-cutting `phase`, attributes at three levels), rebuilt from the golden:
# the leaftable, attribute and alias tables travel column-wise with types.
# A case may apply `steps` (attach_*, filter_scale, ...) before the call.

fuels_lt <- data.frame(
  group   = c("Fossil", "Fossil", "Fossil", "Fossil", "Fossil",
              "Bio", "Bio", "Bio", "Power"),
  phase   = c("solid", "solid", "liquid", "liquid", "gas",
              "solid", "liquid", "gas", NA),
  carrier = c("Coal", "Coal", "Oil", "Oil", "Gas",
              "Biomass", "Biomass", "Biomass", "Electricity"),
  fuel    = c("Anthracite", "Lignite", "Diesel", "Gasoline", "NaturalGas",
              "Wood", "Biodiesel", "Biogas", "Electricity"),
  stringsAsFactors = FALSE
)
fuels_at <- data.frame(
  frame     = c("fuel", "fuel", "carrier", "group", "fuel", "carrier"),
  unit      = c("Anthracite", "Lignite", "Oil", "Bio", "Anthracite", "Gas"),
  attribute = c("lhv", "lhv", "lhv", "lhv", "ef_co2", "ef_co2"),
  kind      = c(rep("property", 4L), "factor", "factor"),
  value     = c(26.7, 11.9, 42.5, 15.0, 98300, 56100),
  lower     = c(21.6, 5.5, 40.0, 7.9, 94600, 54300),
  upper     = c(32.2, 21.6, 45.0, 31.0, 101000, 58300),
  unit_of_measure = c("GJ/t", "GJ/t", "GJ/t", "GJ/t", "kg/TJ", "kg/TJ"),
  source    = "example",
  stringsAsFactors = FALSE
)
fuels_al <- data.frame(
  frame  = c("fuel", "carrier", "fuel", "carrier", "carrier"),
  unit   = c("Anthracite", "Coal", "Electricity", "Electricity", "Electricity"),
  alias  = c("hard coal", "coal", "elc", "elc", "power"),
  source = "example",
  stringsAsFactors = FALSE
)
fuels <- list(build = "scale_from_leaftable", leaftable = fuels_lt,
              frames = c("group", "phase", "carrier", "fuel"), key = "fuel",
              name = "fuels", attributes = fuels_at, aliases = fuels_al)
fuels_tree <- fuels
fuels_tree$leaftable$phase <- NULL
fuels_tree$frames <- c("group", "carrier", "fuel")
fuels_tree$name <- "tree"

build_a <- function(spec) {
  args <- list(spec$leaftable, frames = spec$frames, key = spec$key,
               name = spec$name)
  if (!is.null(spec$attributes)) args$attributes <- spec$attributes
  if (!is.null(spec$aliases)) args$aliases <- spec$aliases
  do.call(scale_from_leaftable, args)
}
construct_a <- function(spec) {
  out <- construct(spec)
  if (!is.null(spec$attributes)) out$attributes <- tab(spec$attributes)
  if (!is.null(spec$aliases)) out$aliases <- tab(spec$aliases)
  out
}
enc_args <- function(args) {
  lapply(args, function(a) if (is.data.frame(a)) tab(a) else a)
}
enc_steps <- function(steps) {
  lapply(steps, function(st) list(fn = st$fn, args = enc_args(st$args)))
}
apply_steps <- function(s, steps) {
  for (st in steps) s <- do.call(st$fn, c(list(s), st$args))
  s
}
tables_desc <- function(s) list(
  frames = vec(scale_frames(s)), key = scale_key(s),
  members = lapply(S7::prop(s, "members"), vec),
  attributes = rows(scale_attributes(s)), aliases = rows(scale_aliases(s))
)

acalls <- list()
acase <- function(fn, base, ..., data = NULL, steps = list()) {
  args <- list(...)
  r <- with_warnings({
    s <- apply_steps(build_a(base), steps)
    pos <- if (is.null(data)) list(s) else list(data, s)
    do.call(fn, c(pos, args))
  })
  acalls[[length(acalls) + 1L]] <<- c(
    list(kind = "table", fn = fn, scale = construct_a(base),
         steps = enc_steps(steps), data = if (!is.null(data)) tab(data),
         args = enc_args(args)),
    r
  )
}
scase <- function(base, steps) {
  r <- withCallingHandlers(
    try_call(apply_steps(build_a(base), steps)),
    warning = function(cnd) invokeRestart("muffleWarning")
  )
  if (!r$error) r$value <- tables_desc(r$value)
  acalls[[length(acalls) + 1L]] <<- c(
    list(kind = "scale", scale = construct_a(base), steps = enc_steps(steps)), r
  )
}

# stored and resolved attributes ----------------------------------------------

acase("scale_attributes", fuels)
acase("scale_attributes", fuels, attribute = "lhv")
acase("scale_attributes", fuels, attribute = "lhv", frame = "fuel")
acase("scale_attributes", fuels, attribute = "lhv", frame = "carrier")
acase("scale_attributes", fuels, attribute = "ef_co2", frame = "fuel")
acase("scale_attributes", fuels, frame = "fuel")
acase("scale_attributes", fuels, frame = "fuel", inherit = FALSE)
acase("scale_attributes", fuels, frame = "group")
acase("scale_attributes", fuels, attribute = "lhv", frame = "fuel",
      source = "example")
acase("scale_attributes", fuels, attribute = "density")
acase("scale_attributes", fuels, source = "nope")
acase("scale_attributes", fuels, attribute = "lhv", frame = "phase")

oil_b <- data.frame(frame = "carrier", unit = "Oil", attribute = "lhv",
                    kind = "property", value = 43, unit_of_measure = "GJ/t",
                    stringsAsFactors = FALSE)
attach_b <- step("attach_attributes_scale", attributes = oil_b, source = "b")
acase("scale_attributes", fuels, attribute = "lhv", frame = "fuel",
      steps = list(attach_b))
acase("scale_attributes", fuels, attribute = "lhv", frame = "fuel",
      source = "b", steps = list(attach_b))
acase("scale_attributes", fuels, attribute = "lhv", steps = list(attach_b))
acase("scale_attributes", fuels,
      steps = list(step("attach_attributes_scale", attributes = fuels_at[1L, ])))
acase("scale_attributes", fuels,
      steps = list(step("attach_attributes_scale",
                        attributes = transform(oil_b, kind = "ratio"),
                        source = "b")))
acase("scale_attributes", fuels,
      steps = list(step("attach_attributes_scale",
                        attributes = transform(oil_b, unit = "Olive"),
                        source = "b")))
acase("scale_attributes", fuels,
      steps = list(step("attach_attributes_scale",
                        attributes = transform(oil_b, kind = "factor"),
                        source = "b")))

# aliases and matching ---------------------------------------------------------

acase("scale_aliases", fuels)
acase("scale_aliases", fuels, frame = "carrier")
acase("scale_match", fuels,
      labels = c("anthracite", "hard coal", "ELC", "power", "Coal", "nope",
                 " Gas "))
acase("scale_match", fuels, labels = c("elc", "Electricity"), frame = "fuel")
acase("scale_match", fuels, labels = "coal", frame = "fuel")
acase("scale_match", fuels, labels = "coal", frame = "nope")

# conversion -------------------------------------------------------------------

d_conv <- data.frame(fuel = c("Anthracite", "Diesel", "Wood"),
                     t = c(1000, 2, 3), stringsAsFactors = FALSE)
acase("convert_scale", fuels, data = d_conv, attribute = "lhv",
      from_unit = "t", to_unit = "GJ")
acase("convert_scale", fuels, data = d_conv, attribute = "lhv",
      from_unit = "GJ", to_unit = "t")
acase("convert_scale", fuels, data = d_conv, attribute = "lhv",
      from_unit = "t", to_unit = "GJ", values = "t", key = "fuel",
      frame = "fuel")
d_gas <- data.frame(fuel = c("Anthracite", "NaturalGas"), t = c(1, 1),
                    stringsAsFactors = FALSE)
acase("convert_scale", fuels, data = d_gas, attribute = "lhv",
      from_unit = "t", to_unit = "GJ")
acase("convert_scale", fuels, data = d_gas, attribute = "lhv",
      from_unit = "t", to_unit = "GJ", na_action = "keep")
acase("convert_scale", fuels, data = data.frame(fuel = "Anthracite", tj = 2),
      attribute = "ef_co2", from_unit = "TJ", to_unit = "kg")
acase("convert_scale", fuels, data = data.frame(fuel = "Anthracite", kg = 2),
      attribute = "ef_co2", from_unit = "kg", to_unit = "TJ")
acase("convert_scale", fuels, data = d_conv, attribute = "lhv",
      from_unit = "kt", to_unit = "GJ")
acase("convert_scale", fuels, data = data.frame(fuel = "Unobtainium", t = 1),
      attribute = "lhv", from_unit = "t", to_unit = "GJ")
acase("convert_scale", fuels,
      data = data.frame(carrier = c("Oil", "Biomass"), t = c(1, 1)),
      attribute = "lhv", from_unit = "t", to_unit = "GJ")
acase("convert_scale", fuels, data = data.frame(code = "Oil", t = 1),
      attribute = "lhv", from_unit = "t", to_unit = "GJ", frame = "carrier",
      key = "code")
acase("convert_scale", fuels,
      data = data.frame(fuel = "Anthracite", t = 1, lhv = 0),
      attribute = "lhv", from_unit = "t", to_unit = "GJ")
acase("convert_scale", fuels, data = data.frame(x = "Anthracite", t = 1),
      attribute = "lhv", from_unit = "t", to_unit = "GJ")
acase("convert_scale", fuels, data = d_conv, attribute = "ef_co2",
      from_unit = "TJ", to_unit = "kg", source = "nope")
acase("convert_scale", fuels, data = d_conv, attribute = "lhv",
      from_unit = "t", to_unit = "GJ", steps = list(attach_b))
acase("convert_scale", fuels, data = d_conv, attribute = "lhv",
      from_unit = "t", to_unit = "GJ", source = "b", steps = list(attach_b))

# the tables travel through filter / prune / attach --------------------------

scase(fuels, list(step("filter_scale", "group", "Fossil")))
scase(fuels, list(step("filter_scale", "carrier", "Electricity")))
scase(fuels, list(step("filter_scale", "fuel", c("Diesel", "Wood"))))
scase(fuels_tree, list(step("prune_scale", "carrier")))
scase(fuels_tree, list(step("prune_scale", "group")))
scase(fuels, list(step(
  "attach_aliases_scale",
  aliases = data.frame(frame = "fuel", unit = "Diesel", alias = "DSL"),
  source = "b"
)))
scase(fuels, list(step(
  "attach_aliases_scale",
  aliases = data.frame(frame = "fuel", unit = "Anthracite", alias = "hard coal"),
  source = "example"
)))
scase(fuels, list(step(
  "attach_aliases_scale",
  aliases = data.frame(frame = "fuel", unit = "Olive", alias = "x"),
  source = "b"
)))

write_golden(acalls, "attributes.json")
