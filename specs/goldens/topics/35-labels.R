# Label, identity and tree goldens: sourced by generate.R after
# 30-attributes.R, whose helpers and fuel scale it shares.
#
# A `table` case is one call (a table, or a character vector for
# `scale_label()`); a `scale` case is the scale after its steps, described
# with its label table; a `print` case records the printed scale, its
# identity and the rows of `scale_tree()`.

acalls <- list()

fuels_lb <- data.frame(
  frame   = c("carrier", "carrier", "carrier", "fuel", "group", "carrier"),
  member  = c("Coal", "Oil", NA, "Diesel", "Bio", "Coal"),
  variant = c("name", "name", "name", "name", "name", "short"),
  label   = c("Hard and brown coal", "Crude and products", "Energy carrier",
              "Diesel oil", "Biogenic", "coal"),
  stringsAsFactors = FALSE
)
fuels_l <- fuels
fuels_l$labels <- fuels_lb

pcase <- function(base, steps = list()) {
  s <- apply_steps(build_a(base), steps)
  acalls[[length(acalls) + 1L]] <<- list(
    kind = "print", scale = construct_a(base), steps = enc_steps(steps),
    error = FALSE,
    value = list(
      id = scale_id(s),
      format = format(s),
      print = vec(utils::capture.output(print(s))),
      tree = rows(as.data.frame(unclass(scale_tree(s)))),
      tree_lines = vec(utils::capture.output(print(scale_tree(s), ascii = TRUE)))
    )
  )
}

# reading ----------------------------------------------------------------------

acase("scale_labels", fuels_l)
acase("scale_labels", fuels_l, frame = "carrier")
acase("scale_labels", fuels_l, variant = "short")
acase("scale_labels", fuels_l, frame = "carrier", variant = c("name", "short"))
acase("scale_labels", fuels_l, frame = "phase")
acase("scale_labels", fuels_l, frame = "nope")
acase("scale_labels", fuels)

acase("scale_label", fuels_l, members = c("Oil", "Coal", "Gas", NA),
      frame = "carrier")
acase("scale_label", fuels_l, members = c("Oil", "Coal", "Gas", NA),
      frame = "carrier", variant = "short")
acase("scale_label", fuels_l, members = "Diesel", frame = "fuel")
acase("scale_label", fuels_l, members = c("solid", NA), frame = "phase")
acase("scale_label", fuels_l, members = "Coal", frame = "carrier",
      variant = "nope")
acase("scale_label", fuels_l, members = "Coal", frame = "nope")
acase("scale_label", fuels, members = c("Coal", NA), frame = "carrier")
acase("scale_label", fuels, members = "Coal", frame = "carrier",
      variant = "anything")

# attaching --------------------------------------------------------------------

lb_new <- data.frame(frame = "phase", member = c("solid", "gas", NA),
                     label = c("Solid", "Gaseous", "Phase"),
                     stringsAsFactors = FALSE)
scase(fuels, list(step("attach_labels_scale", labels = lb_new)))
scase(fuels, list(step("attach_labels_scale", labels = lb_new,
                       variant = "en")))
scase(fuels_l, list(step("attach_labels_scale", labels = lb_new,
                         variant = "short", default = "short")))
scase(fuels_l, list(step("attach_labels_scale", labels = lb_new,
                         default = "nope")))
scase(fuels_l, list(step("attach_labels_scale", labels = fuels_lb[1:3, ])))
scase(fuels_l, list(step("attach_labels_scale",
                         labels = transform(fuels_lb[1:3, ], label = "x"),
                         overwrite = TRUE)))
scase(fuels_l, list(step("attach_labels_scale", labels = fuels_lb[1:2, ],
                         variant = "name")))
scase(fuels, list(step("attach_labels_scale",
                       labels = data.frame(frame = "phase", member = "plasma",
                                           label = "Plasma"))))
scase(fuels, list(step("attach_labels_scale",
                       labels = data.frame(frame = "nope", member = "solid",
                                           label = "Solid"))))
scase(fuels, list(step("attach_labels_scale",
                       labels = data.frame(frame = "phase", member = "solid",
                                           label = ""))))
scase(fuels, list(step("attach_labels_scale",
                       labels = rbind(lb_new[1, ], lb_new[1, ]))))
scase(fuels, list(step("attach_labels_scale",
                       labels = data.frame(frame = "phase", member = "solid"))))
scase(fuels, list(step("attach_labels_scale",
                       labels = data.frame(frame = "phase", member = "solid",
                                           label = "Solid", note = "x"))))
scase(fuels, list(step("attach_labels_scale", labels = lb_new,
                       variant = "")))

acase("scale_label", fuels_l, members = c("solid", "liquid", NA),
      frame = "phase",
      steps = list(step("attach_labels_scale", labels = lb_new,
                        variant = "short", default = "short")))
acase("scale_label", fuels_l, members = c("Coal", "Oil"), frame = "carrier",
      steps = list(step("attach_labels_scale", labels = lb_new,
                        variant = "short", default = "short")))

# the label table travels through filter / prune -------------------------------

scase(fuels_l, list(step("filter_scale", "group", "Fossil")))
scase(fuels_l, list(step("filter_scale", "carrier", "Electricity")))
scase(fuels_l, list(step("filter_scale", "carrier", "Electricity",
                         drop_empty_frames = TRUE)))
fuels_tree_l <- fuels_tree
fuels_tree_l$labels <- fuels_lb
scase(fuels_tree_l, list(step("prune_scale", "carrier")))
scase(fuels_tree_l, list(step("prune_scale", "group")))

# join -------------------------------------------------------------------------

d_carrier <- data.frame(carrier = c("Oil", "Coal", "Gas", "Oil"),
                        v = c(1, 2, 3, 4), stringsAsFactors = FALSE)
acase("join_scale", fuels_l, data = d_carrier, labels = TRUE)
acase("join_scale", fuels_l, data = d_carrier, labels = "short")
acase("join_scale", fuels_l, data = d_carrier, labels = FALSE)
acase("join_scale", fuels_l, data = d_carrier, labels = "nope")
acase("join_scale", fuels_l, data = d_carrier, labels = TRUE,
      attach = "group", as_factor = FALSE)
acase("join_scale", fuels, data = d_carrier, labels = TRUE)
acase("join_scale", fuels_l,
      data = data.frame(carrier = "Oil", fuels.label = "x"), labels = TRUE)

# print, identity, tree ----------------------------------------------------------

pcase(fuels)
pcase(fuels_l)
pcase(fuels_tree_l)
pcase(fuels_l, list(step("filter_scale", "group", "Fossil")))
pcase(fuels_l, list(step("attach_labels_scale", labels = lb_new,
                         variant = "short", default = "short")))

write_golden(acalls, "labels.json")
