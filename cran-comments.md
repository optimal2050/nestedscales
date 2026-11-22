## Update

This is an update of 'nestedscales' from 0.2.0 to 0.3.0. It answers the
request to correct the check problems of 0.2.0 before 2026-12-11.

* The ERROR on the r-devel Linux flavors came from one test that matched the
  wording of an 'S7' error message; the wording changed in 'S7' 1.0.0. The
  test no longer depends on it.
* 'S7' 1.0.0 also keeps the class of an object under another attribute. The
  package now reads it through `S7::S7_class()`. It is tested with 'S7'
  1.0.0 and with 'S7' 0.2.2.

Other changes, listed in NEWS.md:

* A change of vocabulary, with renamed functions and arguments and no
  aliases for the old names. No package on CRAN depends on 'nestedscales'.
* The example data files that were shipped under `inst/` are removed; the
  package ships no data.
* Two helper functions are no longer exported, and five features are marked
  experimental in their help pages.
* New: display labels for members and frames, `scale_id()`, `scale_tree()`,
  an experimental link between a data table and a scale, and the two classes
  are exported.

## R CMD check results

0 errors | 0 warnings | 0 notes

The package is pure R with no compiled code and no system requirements.

## Test environments

* Windows 11, R 4.6.2 (local, `--as-cran`)
* win-builder, R-devel
* R-hub: linux (R-devel), ubuntu-release

On R-hub macos-arm64 (R-devel) the check did not start: the suggested
package 'arrow' has no binary there and its source build failed while
configuring its C++ library, before 'nestedscales' was checked.
