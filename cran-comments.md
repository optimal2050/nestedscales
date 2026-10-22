## Resubmission

This is a resubmission. In this version (0.2.0) I have:

* added `\value` to `SCALE_DISTANCES.Rd` and `SCALE_RULES.Rd`, describing the
  class and meaning of each exported constant, as requested. Every other
  exported topic documents its value, including the new
  `SCALE_ATTRIBUTE_KINDS.Rd`.

The version also contains development made while the package was under
review, listed in NEWS.md: member attributes and aliases, conversion with
them, language-neutral definition files with a catalogue of shipped
definitions, and a public backend layer (`backend_*`) for packages built on
this one. Argument names were harmonised (`source`/`target` instead of
`from`/`to`). The package has not been on CRAN, so no released code depends on
the old names.

The previous resubmission (0.1.1) made Arrow IPC storage fall back to
uncompressed files when the requested compression codec is unavailable.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

The package is pure R with no compiled code and no system requirements.

## Test environments

* Windows 11, R 4.6.1 and R 4.5.3 (local, `--as-cran`)
* win-builder, R-devel
