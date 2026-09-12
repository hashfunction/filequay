# FolderSail confirmed CSV result observation

Run **34707732569**, source `10e307e4a6e77776d5d6ddf97cd6e8cd60debc2f`,
passed actual Copy/Move, both persisted/visible receipts, filename replacement,
and native replacement confirmation. Its original Consumer installation receipt
is 172,636 bytes, SHA256
`549309e0401785c7e38bb42a0de35faf85401037b81349d9e39829cd2095f688`.
Original artifacts remain under `/private/tmp/foldersail-34707732569-review`.

The actual task-dialog Yes button has HWND 131864, distinct from dialog 131824
and picker 131660, PID 8868; the original owner/focus checks and sole Space
succeeded. Cancel preserved the previous CSV. The second app confirmation was
invoked once at 17:30:03 UTC. The final wait passed its independent CSV-row
oracle before failing to find `ReceiptStorageErrorBar`. No receipt-history
controls or result bar appear in the 145-node failure observation; the main
Status center button remains available. The visible similarly titled popup
contains the teaching-tip text, not receipt history.

`NavigationToolbar.xaml` puts StatusCenter inside the button's Flyout.
`StatusCenter.xaml` puts the result bar and receipt history inside that content.
The picker and app confirmation take focus away from the flyout. The harness
already reopens history after cancelling the export, but omitted that ordinary
step after confirming it. The cleanup complaint follows from retaining the
pre-export CSV inventory until both the real CSV and displayed recovery path
are verified; cleanup correctly refused changed, unregistered output.

The correction waits read-only for the exact confirmation to disappear, then
uses the existing guarded history opener once. The existing CSV, displayed
message/path, recovery bytes, original files, clear-history and cleanup checks
remain unchanged. Marketing's identical post-confirmation sequence receives
the same two-line correction, after its unedited scene-03 confirmation capture.
There is no export retry, direct history injection, product change or broader
selector allowance.

The new fixture retains the original 145 observation objects plus source/run
and original-receipt hashes (46,089 bytes, SHA256
`f0ba82f2a4c408e39ccafebd4f648ecaa562e85e55faff6f69a9b5763993fe09`).
It executes the actual consumer and marketing
post-confirmation caller statements and the production history opener, with
explicit UIA leaf simulations. Both original callers first reproduced the
closed-history failure. Each now passes five cases: closed/already-open
history, confirmation staying open, unavailable owned button, and selection
failure. Assertions preserve one confirmation input, wait-before-input,
conditional single reopening, and no replay after failure. This is sequence
verification, not a claim of native WinUI execution.

Focused verification:

- `tests/packaging/test-consumer-export-result.ps1`: both actual callers, ten cases.
- `tests/packaging/test-consumer-workflow.ps1`: 44 independent file, JSON, CSV,
  foreign-target, ownership and cleanup checks.
- `tests/packaging/test-consumer-picker-input.ps1`: 86 original filename,
  task-dialog, focus/input, confirmation and refusal checks.
- `git diff --check` passes. The new fixture runs in normal qualification
  before installation. No unrelated suite or full build was repeated.

Actual Windows recovery-message/path visibility and successful owned cleanup
still require the next native run. The original failed result is unchanged;
no consumer or marketing capture success is claimed.
