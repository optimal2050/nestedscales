# ipcc2006_fuel_defaults -- the IPCC 2006 Vol. 2 Ch. 1 default tables in long
# form, and the attribute rows that enter the `carriers` definition.
#
# Sourced by data-raw/carriers.R, which supplies `es0` (the scale the mapping
# is validated against). The transcribed CSVs under data-raw/ipcc2006 are the
# source of truth; see the README there.
#
# Defines: ipcc2006_fuel_defaults (the table written to inst/extdata),
#          ipcc_attr (rows to attach).

library(dplyr)
stopifnot(exists("es0"))

ipcc_dir <- file.path("data-raw", "ipcc2006")
ncv <- utils::read.csv(file.path(ipcc_dir, "table1-2_ncv.csv"),
                       stringsAsFactors = FALSE, check.names = FALSE)
ef  <- utils::read.csv(file.path(ipcc_dir, "table1-4_ef_co2.csv"),
                       stringsAsFactors = FALSE, check.names = FALSE)
map <- utils::read.csv(file.path(ipcc_dir, "ipcc_to_energypal.csv"),
                       stringsAsFactors = FALSE, check.names = FALSE,
                       na.strings = c("", "NA"))

# ---- transcription checks -------------------------------------------------
# Pin the row count once the maintainer has checked the transcription
# against the PDF; a changed count means a changed table, which is a review.
EXPECT_ROWS <- 53L
stopifnot(
  identical(ncv$ipcc_fuel, ef$ipcc_fuel),
  nrow(ncv) == EXPECT_ROWS,
  !anyDuplicated(ncv$ipcc_fuel),
  all(is.na(ncv$ncv) |
        (ncv$ncv_lower <= ncv$ncv & ncv$ncv <= ncv$ncv_upper)),
  all(ef$ef_lower <= ef$ef_co2 & ef$ef_co2 <= ef$ef_upper),
  sum(is.na(ncv$ncv)) == 1L,                       # Industrial Wastes only
  ncv$ipcc_fuel[is.na(ncv$ncv)] == "Industrial Wastes"
)

# ---- mapping checks -------------------------------------------------------
stopifnot(
  setequal(map$ipcc_fuel, ncv$ipcc_fuel),
  !anyDuplicated(map$ipcc_fuel),
  all(map$status %in% c("mapped", "review", "unmapped")),
  is.logical(map$primary),
  all(!is.na(map$frame[map$status == "mapped"])),
  all(is.na(map$frame[map$status == "unmapped"])),
  all(!map$primary[map$status != "mapped"])
)
members <- S7::prop(es0, "members")
placed <- map[!is.na(map$frame), , drop = FALSE]
is_member <- mapply(function(f, u) f %in% names(members) && u %in% members[[f]],
                    placed$frame, placed$unit)
if (!all(is_member)) {
  stop("ipcc_to_energypal.csv names members that do not exist: ",
       paste(paste0(placed$frame, "/", placed$unit)[!is_member],
             collapse = ", "), call. = FALSE)
}
prim <- map[map$status == "mapped" & map$primary, , drop = FALSE]
if (anyDuplicated(paste(prim$frame, prim$unit))) {
  stop("more than one primary IPCC fuel for: ",
       paste(unique(paste0(prim$frame, "/", prim$unit)[
         duplicated(paste(prim$frame, prim$unit))]), collapse = ", "),
       call. = FALSE)
}

# ---- the long table -------------------------------------------------------
# lhv is a physical property (invertible); the CO2 factor is one-way.
ipcc2006_fuel_defaults <- bind_rows(
  ncv |>
    transmute(ipcc_fuel, attribute = "lhv", kind = "property", value = ncv,
              lower = ncv_lower, upper = ncv_upper,
              unit_of_measure = "GJ/t", table = "1.2"),
  ef |>
    transmute(ipcc_fuel, attribute = "ef_co2", kind = "factor", value = ef_co2,
              lower = ef_lower, upper = ef_upper,
              unit_of_measure = "kg/TJ", table = "1.4")
) |>
  mutate(source = "IPCC2006") |>
  left_join(map |>
              select(ipcc_fuel, frame, unit, mapping_status = status, primary),
            by = "ipcc_fuel") |>
  arrange(match(ipcc_fuel, ncv$ipcc_fuel), match(attribute, c("lhv", "ef_co2"))) |>
  as.data.frame()
rownames(ipcc2006_fuel_defaults) <- NULL

# ---- rows that enter the definition's attribute table --------------------
ipcc_attr <- ipcc2006_fuel_defaults |>
  filter(mapping_status == "mapped", primary, !is.na(value)) |>
  transmute(frame, unit, attribute, kind, value, lower, upper,
            unit_of_measure, source, note = ipcc_fuel) |>
  as.data.frame()

cat("IPCC 2006:", nrow(ipcc2006_fuel_defaults), "rows;",
    sum(map$status == "mapped"), "mapped /",
    sum(map$status == "review"), "review /",
    sum(map$status == "unmapped"), "unmapped fuels;",
    nrow(ipcc_attr), "attribute rows attached\n")
