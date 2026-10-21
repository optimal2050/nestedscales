# =========================================================================== #
# Backend-contract harness.
#
# The contract (R/backend.R): the same pipeline runs on every supported input;
# eager classes come back as themselves, lazy inputs stay lazy unless
# collect = TRUE. Mirrors the harness in timescales and geoscales.
# =========================================================================== #

.bk_all <- c("data.frame", "tibble", "data.table", "dtplyr", "arrow")

.bk_installed <- function(bk) {
  switch(bk,
    "data.frame" = TRUE,
    "tibble"     = requireNamespace("tibble", quietly = TRUE),
    "data.table" = requireNamespace("data.table", quietly = TRUE),
    "dtplyr"     = requireNamespace("dtplyr", quietly = TRUE) &&
                   requireNamespace("data.table", quietly = TRUE),
    "arrow"      = requireNamespace("arrow", quietly = TRUE),
    FALSE)
}

.bk_lazy <- function(bk) bk %in% c("dtplyr", "arrow")

# Backends the current tier sweeps: the lazy engines join at `full`.
test_backends <- function(tier_gate = TRUE) {
  bks <- Filter(.bk_installed, .bk_all)
  if (tier_gate &&
    .tier_levels[[scales_test_tier()]] < .tier_levels[["full"]]) {
    bks <- setdiff(bks, c("dtplyr", "arrow"))
  }
  bks
}

as_backend <- function(df, bk) {
  df <- as.data.frame(df)
  switch(bk,
    "data.frame" = df,
    "tibble"     = tibble::as_tibble(df),
    "data.table" = data.table::as.data.table(df),
    "dtplyr"     = dtplyr::lazy_dt(data.table::as.data.table(df)),
    "arrow"      = arrow::arrow_table(df),
    stop("unknown backend: ", bk)
  )
}

# What class must an EAGER result (or a collected lazy one) have?
.bk_expect_class <- function(out, bk, collected = FALSE) {
  switch(bk,
    "data.frame" = is.data.frame(out) && !inherits(out, "tbl_df") &&
      !inherits(out, "data.table"),
    "tibble" = inherits(out, "tbl_df"),
    "data.table" = inherits(out, "data.table"),
    # backend_restore: collected dtplyr -> data.table,
    # collected arrow -> whatever collect() returns (a data.frame)
    "dtplyr" = if (collected) {
      inherits(out, "data.table")
    } else {
      inherits(out, "dtplyr_step")
    },
    "arrow" = if (collected) {
      is.data.frame(out)
    } else {
      !is.data.frame(out)
    },
    FALSE
  )
}

.bk_sort <- function(d, key_cols) {
  d <- as.data.frame(d)
  keys <- intersect(key_cols, names(d))
  if (length(keys)) d <- d[do.call(order, d[keys]), , drop = FALSE]
  rownames(d) <- NULL
  d
}

# The one contract statement.
#
#   make_call : function(x, collect = NULL) -> the verb's result on `x`
#   input     : plain data.frame the reference is computed from
#   key_cols  : columns to sort on before comparing
#   value_cols: value columns whose NA rows a LAZY result may omit (the
#               observed-groups asymmetry); NULL = lazy == eager
expect_backend_contract <- function(input, make_call, key_cols,
                                    value_cols = NULL,
                                    backends = test_backends()) {
  ref <- .bk_sort(make_call(input), key_cols)
  cmp_cols <- names(ref)
  ref_lazy <- if (is.null(value_cols)) {
    ref
  } else {
    .bk_sort(
      ref[stats::complete.cases(ref[value_cols]), , drop = FALSE],
      key_cols
    )
  }

  for (bk in backends) {
    x <- as_backend(input, bk)
    out <- make_call(x)
    if (.bk_lazy(bk)) {
      expect_true(.bk_expect_class(out, bk),
        label = sprintf("[%s] result stays lazy", bk)
      )
      got <- .bk_sort(dplyr::collect(out), key_cols)
      expect_equal(got[intersect(cmp_cols, names(got))],
        ref_lazy[intersect(cmp_cols, names(got))],
        ignore_attr = TRUE,
        label = sprintf("[%s] collected values", bk)
      )
      out2 <- make_call(x, collect = TRUE)
      expect_true(.bk_expect_class(out2, bk, collected = TRUE),
        label = sprintf("[%s] collect=TRUE materialises", bk)
      )
    } else {
      expect_true(.bk_expect_class(out, bk),
        label = sprintf("[%s] class restored", bk)
      )
      expect_equal(.bk_sort(out, key_cols)[cmp_cols], ref[cmp_cols],
        ignore_attr = TRUE,
        label = sprintf("[%s] values", bk)
      )
      out2 <- make_call(x, collect = TRUE) # no-op on an eager backend
      expect_equal(.bk_sort(out2, key_cols)[cmp_cols], ref[cmp_cols],
        ignore_attr = TRUE,
        label = sprintf("[%s] collect=TRUE is a no-op", bk)
      )
    }
  }
  invisible(ref)
}

# The rejection branch, stated once per entry point.
expect_backend_rejects <- function(make_call) {
  expect_error(make_call(list(a = 1)), "data\\.frame, tibble, data\\.table")
}
