# FileQuay native save picker diagnostic — run 34679139214

Base source: `b0d4a56e3b589172b089ee412b8a2f68ffbc7153`; public source
`688017e`. This is a failure-evidence change, not a product repair or native
consumer acceptance claim. Independent review and a fresh Windows run are next.

## Observed failure

The retained Consumer receipt is
`/private/tmp/filequay-34679139214-review/Consumer/installation-result.json`.
The actual consumer process was PID 7864, main HWND 393584. Both Paste actions
completed after the reviewed toolbar overflow change. The observer then verified
exact Copy/Move file states, two distinct persisted receipts and both matching
visible receipt cards. This workflow covers Copy/Move and receipt export/clear;
it does not claim a generic rename or preview exercise.

At `2026-09-12T07:01:13.6646225Z`, the exact enabled `ReceiptExportButton` was
invoked in the owned Status Center HWND 1049182, with native owner chain
`1049182 → 393584` and PID 7864. The existing 30-second wait then found zero
eligible owned elements with automation ID `1001`. Its failure tree contained
134 nodes, all under the disabled main window `move - FileQuay`; there was no
picker root and no tree-observation error. The clipboard diagnostic also found
that the main window was no longer the eligible foreground target. The only
retained PNG is startup `Home - FileQuay`, not the picker or failure state.

`StatusCenter.ExportReceipts_Click` uses the real
`Windows.Storage.Pickers.FileSavePicker`, initializes it with
`MainWindow.Instance.WindowHandle`, and awaits `PickSaveFileAsync`. Product
source alone does not prove its actual runtime automation ID, UIA top-level
shape, native owner chain or provider visibility. The retained evidence cannot
distinguish a missing `1001` control from exclusion by the observer's desktop
UIA scope discovery. The selector and ownership policy therefore remain intact.

The run failed before CSV destination/cancel/recovery/clear checks and normal
close acceptance. Owned process cleanup, fixture cleanup, app uninstall and
trust removal passed with no cleanup errors or residual application packages.
Framework retention follows the existing disposable-runner policy;
`full_environment_cleanup_verified` remains false.

## Bounded observation change

Only a timeout/failure at the existing save-picker lookup invokes the new
read-only helper. The original error is always rethrown. Other failures continue
through the existing diagnostic/cleanup paths.

The helper obtains the current native foreground HWND directly through the
already source-verified `ConsumerInput.Observe`, avoiding dependence on desktop
UIA discovery for this diagnostic. It records the retained main/foreground
HWND, PID and bounded native owner chain. If that foreground has no native owner
chain to the retained live main window, it returns numeric exclusion evidence
without reading its UI text, tree, process details or pixels.

For an owned foreground, it retains an independent exact process handle and
rechecks process/window liveness, PID, main identity, foreground identity and
the native owner chain before observation and after each tree. The diagnostic
may observe disabled UI; it cannot authorize input. It observes at most 128
desktop UIA roots, reading only their native handles unless a root identifies
this already proved foreground. This records whether the owned foreground was
missing from desktop UIA, reported offscreen, or had inconsistent UIA PID.
Unrelated roots contribute only aggregate counts; their names/text are not read.

Direct foreground Control View and Raw View trees each retain at most 80 nodes,
depth 8, with fields/errors capped at 1024 characters. The existing resilient
traversal requires the exact target PID for every node. A changing ownership
observation removes partial UI trees, retains numeric identity/error metadata
and disposes the diagnostic process handle. No broker is terminated by this
helper. No new native API, product assembly or adapter source is introduced.

If exact visible UIA HWND/PID and native foreground ownership remain proved,
the helper copies actual screen pixels into `consumer-save-picker-failure.png`.
It requires the whole rounded capture rectangle to fit the observed virtual
desktop, at most 8192 pixels per dimension / 33554432 pixels, and checks stable
window bounds and ownership around the actual `CopyFromScreen`. There is no
foreground activation, resizing, pixel editing, synthetic picker or input.
Output uses exclusive creation; PNG bytes are capped at 33554432, with hash,
size, desktop and capture bounds retained. Failure to capture is secondary and
does not discard already verified tree observations. The existing metadata/PNG
artifact glob already includes the new file; no binary upload change is needed.

## Verification

The initial new boundary fixture failed because the production helper did not
exist. The final suite runs real production predicates, traversal and export
failure handling with scoped platform adapters. No fixture is native UI proof.

- 40 new checks pass: exact owned foreground, unowned exclusion without content
  access, wrong/invalid retained process, changed/lost ownership, UIA PID
  mismatch, disabled observations, missing properties/descendants, Control/Raw
  node budgets, desktop root budget, absent/zero native handle, offscreen scope,
  capture bounds, secondary capture errors, partial identity retention, and
  original missing-element error preservation.
- Existing diagnostics: 21 checks; toolbar: 19 checks; independent file/receipt/
  CSV/ownership/cleanup validators: 44 checks; Consumer observation and distinct
  build-kind acceptance suites pass.
- Packaging Python suite: 34 tests pass.
- Actual pinned native adapter source generation, IL loading, Windows INPUT ABI
  and exact PE/source/API identity checks: 37 pass. Adapter source is unchanged.
- Changed PowerShell files parse; changed text files use CRLF; `git diff --check`
  passes. The existing workflow body is byte-equivalent after normalizing only
  the failure catch and diagnostic output-directory transport. Product source,
  native adapter, input/owner predicates and file/receipt/CSV helpers are unchanged.

Commands use the installed local PowerShell
`.tools/powershell-7.6.6/pwsh` and `.tools/dotnet-10.0.401/dotnet`. Logs:
`/private/tmp/filequay-picker-diagnostic-tests.log`,
`/private/tmp/filequay-picker-diagnostic-final.log`,
`/private/tmp/filequay-picker-packaging-tests.log`, and
`/private/tmp/filequay-picker-adapter-tests.log`.

The local host cannot execute the real Windows picker or screen copy. The next
Windows run must supply actual foreground identity, desktop-scope result and
owned picker tree/pixels (or explicit ownership rejection). No selector/product
fix, public push, parent status, website, branding or Store change was made.
