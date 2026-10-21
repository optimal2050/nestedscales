# =============================================================================
# Load hooks
# =============================================================================

.onLoad <- function(libname, pkgname) {
  # Required for S7 methods on generics owned by other packages (here base's
  # `print`/`format`/`summary`). An S7 object is NOT S4-backed -- `isS4()` on a
  # NestedScale is FALSE and the object carries a plain character class attribute --
  # so the methods S7 defines against another package's generic are not
  # visible until they are registered here. Without this call, `print(s)`
  # falls through to the default and dumps the raw properties.
  S7::methods_register()

  # `S7::method(print, ...) <-` leaves a local `print` binding in this
  # namespace, so the NAMESPACE `S3method(print, summary_Scale)` entry
  # registers against that shim instead of base's print -- invisible to
  # dispatch from user code. Register the plain-S3 class explicitly.
  registerS3method("print", "summary_Scale", print.summary_Scale,
    envir = baseenv()
  )
  registerS3method("print", "summary_ScaleProduct",
    print.summary_ScaleProduct,
    envir = baseenv()
  )
  registerS3method("print", "scale_dataset", print.scale_dataset,
    envir = baseenv()
  )

  # The shipped definitions (inst/scales/), so `read_scale("carriers")`
  # resolves with nothing else attached. Dimension packages do the same for
  # theirs in their own .onLoad().
  d <- system.file("scales", package = pkgname)
  if (nzchar(d)) register_scale_dir(d, package = pkgname)

  invisible()
}
