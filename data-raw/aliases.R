# alias_tbl -- energypal's `_aliases` plus model commodity codes, as the
# alias table of the `carriers` definition.
#
# Sourced by data-raw/carriers.R, which supplies `ct` (energypal's carriers
# table) and `es0`. data-raw/commodity_aliases.csv is the editable list of
# commodity codes; only its `mapped` rows are attached.
#
# Defines: alias_tbl.

library(dplyr)
stopifnot(exists("ct"), exists("es0"))

FRAME_OF <- c("group", "carrier", "fuel")

# ---- energypal aliases (one `;`-joined string per entry) -----------------
ep <- ct |>
  filter(!is.na(aliases), nzchar(aliases)) |>
  transmute(frame = FRAME_OF[level], unit = name, aliases)
ep_long <- do.call(rbind, lapply(seq_len(nrow(ep)), function(i) {
  data.frame(
    frame = ep$frame[i], unit = ep$unit[i],
    alias = trimws(strsplit(ep$aliases[i], ";", fixed = TRUE)[[1L]]),
    source = "energypal",
    stringsAsFactors = FALSE
  )
}))
ep_long <- ep_long[nzchar(ep_long$alias), , drop = FALSE]

# ---- commodity codes -------------------------------------------------------
cm <- utils::read.csv(file.path("data-raw", "commodity_aliases.csv"),
                      stringsAsFactors = FALSE, check.names = FALSE,
                      na.strings = c("", "NA"))
stopifnot(all(cm$status %in% c("mapped", "review", "unmapped")),
          all(!is.na(cm$frame[cm$status == "mapped"])))
cm_ok <- cm |>
  filter(status == "mapped") |>
  transmute(frame, unit, alias, source = "commodity") |>
  as.data.frame()

alias_tbl <- bind_rows(ep_long, cm_ok) |>
  distinct() |>
  as.data.frame()
rownames(alias_tbl) <- NULL

# every alias row must name a member (the class validates this again)
members <- S7::prop(es0, "members")
ok <- mapply(function(f, u) u %in% members[[f]], alias_tbl$frame,
             alias_tbl$unit)
if (!all(ok)) {
  stop("alias rows name members that do not exist: ",
       paste(paste0(alias_tbl$frame, "/", alias_tbl$unit)[!ok],
             collapse = ", "), call. = FALSE)
}

cat("aliases:", sum(alias_tbl$source == "energypal"), "energypal +",
    sum(alias_tbl$source == "commodity"), "commodity;",
    sum(cm$status == "review"), "commodity code(s) awaiting a ruling:",
    paste(cm$alias[cm$status == "review"], collapse = ", "), "\n")
