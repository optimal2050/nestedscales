# carriers -- the shipped fuel / energy-carrier definition, a snapshot of
# energypal's carriers palette with the IPCC 2006 default factors and the
# alias tables attached, written as inst/scales/carriers.json.
#
#   source(file.path("data-raw", "carriers.R"))     # from the package root
#
# energypal's inst/extdata/palettes/carriers.yml stays the editable source of
# names, hierarchy, labels and aliases; this script reads it through
# energypal_table() and freezes it. data-raw/check_energypal.R, sourced at the
# end, fails when the definition and the palette disagree.
#
# WHAT BECOMES A FUEL
# -------------------
# group > carrier > fuel. The fuels are energypal's level-3 subtypes; the
# three carriers energypal declares without subtypes (Electricity, Heat,
# Other) become their own fuel, so every carrier is reachable from the
# atoms. Level-3 names are unique, so they key the scale directly.
#
# WHAT IS DELIBERATELY NOT HERE
# -----------------------------
# Colours (energypal's job), energypal's `_carbon_intensity` (labelled
# presentation-only in the yml), and a build date (the build must be
# deterministic so a second run is a no-op on inst/).

library(dplyr)
stopifnot(requireNamespace("energypal", quietly = TRUE))
suppressMessages(pkgload::load_all(".", quiet = TRUE))

# ---- the leaftable, straight from energypal -----------------------------
ct <- energypal::energypal_table("carriers", include_groups = TRUE)
FRAME_OF <- c("group", "carrier", "fuel")

leaf3 <- ct |>
  filter(level == 3L) |>
  transmute(fuel = name, carrier = parent)
leafless <- ct |>
  filter(level == 2L, !name %in% leaf3$carrier) |>
  transmute(fuel = name, carrier = name)
carrier_group <- ct |>
  filter(level == 2L) |>
  transmute(carrier = name, group = parent)

leaftable <- bind_rows(leaf3, leafless) |>
  left_join(carrier_group, by = "carrier") |>
  select(group, carrier, fuel) |>
  as.data.frame()

# keep energypal's file order at every frame (it is the legend order)
ord_group   <- ct$name[ct$level == 1L]
ord_carrier <- ct$name[ct$level == 2L]
leaftable <- leaftable[order(match(leaftable$group, ord_group),
                             match(leaftable$carrier, ord_carrier),
                             match(leaftable$fuel, ct$name)), , drop = FALSE]
rownames(leaftable) <- NULL

stopifnot(
  nrow(leaftable) == 71L,
  !anyNA(leaftable),
  !anyDuplicated(leaftable$fuel),
  length(unique(leaftable$group)) == 8L,
  length(unique(leaftable$carrier)) == 17L
)

# ---- labels: energypal's short/long labels per member --------------------
labels <- ct |>
  filter(!is.na(label_short) | !is.na(label_long)) |>
  transmute(frame = FRAME_OF[level], unit = name, label_short, label_long) |>
  as.data.frame()

spec <- energypal::energypal_spec("carriers")
palette_version <- as.character(spec$meta$version %||% NA_character_)

es0 <- scale_from_leaftable(
  leaftable,
  frames = FRAME_OF, key = "fuel",
  name = "carriers",
  desc = paste("Energy carriers: fuels and energy vectors with subtypes,",
               "from energypal's carriers palette (IPCC 2006 / IEA",
               "classifications)"),
  source = "energypal carriers.yml",
  labels = labels,
  energypal_version = as.character(utils::packageVersion("energypal")),
  palette_version = palette_version
)

# attribute inheritance walks the tree, so it must BE a tree
stopifnot(isTRUE(scale_nests(es0, "group", "carrier")),
          isTRUE(scale_nests(es0, "carrier", "fuel")))

# ---- attributes and aliases ---------------------------------------------
source(file.path("data-raw", "ipcc2006_fuel_defaults.R"))   # ipcc2006_fuel_defaults, ipcc_attr
source(file.path("data-raw", "aliases.R"))                  # alias_tbl

carriers <- es0 |>
  attach_attributes_scale(ipcc_attr) |>
  attach_aliases_scale(alias_tbl)

source(file.path("data-raw", "check_energypal.R"))          # stopifnot()s

print(carriers)
cat("\nfuels with an IPCC lhv:",
    sum(!is.na(scale_attributes(carriers, "lhv", frame = "fuel")$value)),
    "of", nrow(leaftable), "\n")

write_scale(carriers, file.path("inst", "scales", "carriers.json"),
            tables = "inline", overwrite = TRUE)
utils::write.csv(ipcc2006_fuel_defaults,
                 file.path("inst", "extdata", "ipcc2006_fuel_defaults.csv"),
                 row.names = FALSE, na = "")
cat("wrote inst/scales/carriers.json and inst/extdata/ipcc2006_fuel_defaults.csv\n")
