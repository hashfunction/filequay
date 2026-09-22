# FolderSail clear receipt scene and tooltip dismissal

Actual screenshot-only run `35705006718`, source `3336d39e096f90bb116035e6dd01bc21d320aeb7`, passed the repaired framework resolution, original payload checks and installed activation. It performed real Copy/Move operations, independently verified the expected file bytes and both persisted successful receipts, and produced one original 1920×1032 screenshot. Artifact **10684460638**, `FolderSail-real-product-screenshots`, remains unchanged under `/private/tmp/foldersail-capture-35705006718-review/artifact/`; its original log is `capture-job.log` in that review directory.

Original `01-folder-workspace.png` is 57819 bytes, SHA256 `7327a009b8fcb7c58a339533e10a9e9d98b14fd128bf752b40d50353f75e16b0`. Its matching JSON records exact owned PID 7840/HWND 328014 and identical before/after geometry/visibility. Visual inspection confirms real friendly demo paths and a floating file tooltip. Pixels were not changed.

The original receipt helper expanded and collapsed Move, then refused offscreen Copy at `08:31:56.899Z`, about 155 ms after the Collapse trace. The retained ancestor observations report all vertical view sizes 100% and no vertically scrollable container. The app source defines a 400px-wide/500px-maximum Status Center flyout containing expandable receipt cards (`NavigationToolbar.xaml`, `StatusCenter.xaml`). A layout transition is plausible; this run does not establish a provider defect or justify relaxing the original helper.

The capture scene now observes the two ordinary operation/result headers without expanding, collapsing or scrolling cards. Each visible title must uniquely match one of the independently validated persisted Copy/Move successes. The caption promises completed operations in local history, with no claim that paths are visible. The same actual file oracle, receipt history/path/time checks, native picker, CSV contents and preserved-original recovery checks remain. Original qualified helpers and their source binding are untouched.

Before each screen read, capture validates the original frame/content/ownership, moves the pointer once without clicking to its already hit-tested center, and then only polls readback and absence of visible owned UIA tooltips. Frame/content ownership is checked again before pixels. No repeated input is issued in the polling loop and no pixels are edited. The existing bounded read-only wait owns the dismissal deadline.

Focused tests pass:

- Production receipt scene joins exact headers and refuses missing, duplicate, wrong-title, failed-result, wrong-operation and duplicate-ID records.
- Production neutral-pointer helper is exercised with a native cursor seam and the real frame policy: one move on a valid owned frame, no move on a foreign frame, and refusal for wrong readback or a remaining tooltip.
- Existing frame geometry/occlusion refusals and script/helper integration pass; whitespace checks pass. No application build or broad qualification suite was repeated.

The failed run's owned process stop, uninstall, profile/demo/certificate/key/temp cleanup and native display restoration passed; normal UI close was not reached. A fresh full capture is required for receipt/export screens, CSV completion and normal-close verification. This is capture scene preparation, not additional consumer qualification.
