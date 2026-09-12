# Capture candidate review — 2026-09-12

Prepared on the `abc9648e971f022aaeab386dce4b98a238725837` consumer filename
repair. Only new marketing-specific source, fixtures, documentation and the
separate manual workflow are added. No product, packaging, original consumer
helper, source-publication validator or existing Windows workflow was edited.

The approved composition is implemented: original Inbox files, actual Copy and
Move receipts with one expanded path detail, and actual export confirmation.
The CSV commit/recovery, normal window close, owned process cleanup and uninstall
must finish after the screenshots. Raw PNGs retain exact qualified package and
capture-source provenance. The existing qualification's filename/input helper
is loaded from the future exact qualified commit, so capture cannot silently use
an older ValuePattern-only filename route.

`binding.json` remains `qualified: null`. Direct execution of the binding command
failed with `Capture needs a reviewed successful Store package binding`, before
creating a GitHub output file, downloading artifacts or attempting installation.
There are no Windows marketing screenshots or completed marketing receipts.

Fresh focused validation:

- `python3 -m unittest discover -s distribution/marketing -p 'test_*.py' -v`:
  **18 tests passed**. Includes the original Store archive/lifecycle verifier
  fixture replay and refusal of each mutated original receipt, package and source
  publication input. Native binaries, publication network and original Git are
  explicit seams in that test; their real acceptance is not claimed.
- Six PowerShell scripts passed: `test_capture_frame.ps1`,
  `test_capture_display.ps1`, `test_capture_lifecycle.ps1`,
  `test_capture_complete.ps1`, `test_capture_native.ps1`, and
  `test_capture_integration.ps1`. They include actual C# compilation, real script
  loading, existing-output preservation, real retained temporary child-process
  cleanup, and a late-server refusal. Scalar ownership/display fixtures are not
  represented as Windows observations.
- The completion policy test first failed with its missing production helper;
  it passes with exact scenes, CSV, close, source and cleanup checks. A new
  non-finite required-bounds case failed before the NaN/Infinity refusal and
  passed afterward. The original protected file and seal mutation fixtures
  preserve changed content instead of deleting it.
- The standalone workflow YAML parsed locally. No application build, artifact
  download, dispatch, push, Store mutation or site publication was performed.

Review/Windows follow-up: bind the exact original successful assigned-Store
package and all four artifact IDs; review that committed binding, then dispatch
the separate capture workflow. Receipt viewport composition, current native
picker delivery and removal of the fresh Appx profile by uninstall are still
actual Windows boundaries. A failure preserves metadata and prevents a complete
capture receipt. PNG/caption publication remains a separate review step.
