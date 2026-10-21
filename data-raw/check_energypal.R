# The `carriers` definition must match energypal's carriers palette, which
# is the editable source of its names, hierarchy and aliases. Sourced at the
# end of data-raw/carriers.R with `ct` (energypal's table) and `carriers`
# in scope; every check is a stopifnot(), so a drift fails the build rather
# than shipping a stale snapshot. (A test cannot do this: energypal is not a
# dependency of nestedscales.)

stopifnot(exists("ct"), exists("carriers"))

leaf3 <- ct$name[ct$level == 3L]
leafless <- ct$name[ct$level == 2L & !ct$name %in% ct$parent[ct$level == 3L]]
stopifnot(
  setequal(scale_units(carriers), c(leaf3, leafless)),
  setequal(scale_units(carriers, "carrier"), ct$name[ct$level == 2L]),
  setequal(scale_units(carriers, "group"), ct$name[ct$level == 1L])
)

# parent links
fam <- scale_family(carriers, "carrier", "fuel")
ep <- ct[ct$level == 3L, c("parent", "name")]
got <- fam[fam$child %in% ep$name, c("parent", "child")]
stopifnot(identical(got$parent[match(ep$name, got$child)], ep$parent))
fam2 <- scale_family(carriers, "group", "carrier")
ep2 <- ct[ct$level == 2L, c("parent", "name")]
stopifnot(identical(fam2$parent[match(ep2$name, fam2$child)], ep2$parent))

# every energypal alias is present under source "energypal"
al <- scale_aliases(carriers, source = "energypal")
has <- ct[!is.na(ct$aliases), ]
for (i in seq_len(nrow(has))) {
  want <- trimws(strsplit(has$aliases[i], ";", fixed = TRUE)[[1L]])
  frame <- c("group", "carrier", "fuel")[has$level[i]]
  got <- al$alias[al$frame == frame & al$unit == has$name[i]]
  stopifnot(all(want %in% got))
}

# the palette version that was snapshotted
spec <- energypal::energypal_spec("carriers")
stopifnot(identical(S7::prop(carriers, "meta")[["palette_version"]],
                    as.character(spec$meta$version)))
cat("energypal consistency: OK\n")
