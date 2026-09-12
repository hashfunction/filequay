# FileQuay consumer Paste diagnosis — run 34675008189

Base source: `418b8bab28a22d315d3f5c117a90a96e71247044`; public source `40ba9d5f`.
This is an evidence-only candidate. The actual Windows Copy/Paste workflow remains unqualified pending the next native run.

## Established evidence

The isolated IL-only qualification adapter passed in run 34675008189. The consumer navigated to the exact generated source directory, selected the generated `résumé,原稿.txt` item, and invoked `InnerNavigationToolbarCopyButton`. Its trace records Copy at 05:25:29.369 UTC and the subsequent Ctrl+L at 05:25:29.418 UTC. Navigation to the owned `copy` directory was independently read back. The enabled/visible Paste lookup returned zero matches until it failed. The destination still contained only `protected.txt`; all owned fixture/process/package/trust cleanup passed.

Retained evidence: `/private/tmp/filequay-34675008189-review/Consumer/installation-result.json`, SHA-256 `435ec6396832afe32f4a9850eefbb582b31eb8f6f7e9598eac8d7e71be7d5838`.

Zero matches did not distinguish a disabled, offscreen, or absent Paste element. `Find-FileQuayWorkflowElements` filters disabled and offscreen elements unless `IncludeHidden` is supplied. The failure tree contained 92 records and three `ControlType.ProgrammaticName` property errors. Its old traversal read all node properties before enqueuing children, so each of those errors discarded an entire subtree. Absence of toolbar IDs from that incomplete tree is not evidence that the application removed them.

Production source review:

- `src/Files.App/Data/Items/ToolbarSections.cs`: default Cut/Copy/Paste entries belong to `AlwaysVisible`, which `Toolbar.GetActiveToolbarContexts` always includes. The toolbar can overflow; current evidence does not establish that it did.
- `src/Files.App/Actions/FileSystem/PasteItemAction.cs`: Paste executability depends on `App.AppModel.IsPasteEnabled` and the current page type. `ModifiableCommand` delegates this property and its automation ID to the base Paste command.
- `src/Files.App/Data/Models/AppModel.cs`: the clipboard content-change handler enables Paste when the data package exposes StorageItems or Bitmap; exceptions set it false.
- `src/Files.App/Helpers/TransferHelpers.cs`: Copy asynchronously resolves selected storage items before `Clipboard.SetContent`. Returning from UI Automation Invoke does not prove completion of that asynchronous work. The mutable context and navigation boundary merit observation, but the trace alone does not prove a race or a clipboard failure.
- `src/Files.App/UserControls/NavigationToolbar.xaml.cs`: path submission awaits navigation and then focuses the active pane. A visible omnibar text box in the failed tree alone does not prove a focus defect.

The selected item's accessible name ended in `, Folder`, although the generated fixture is independently checked as a regular file. Its underlying production item classification was not recorded; this candidate does not infer it from that label.

## Candidate

The input order, selectors, waits, and assertions are unchanged. In particular, no clipboard-completion gate, extra sleep, alternative Paste action, product bypass, or acceptance exception was added.

1. The failure-only UI traversal now reads each non-identity property independently and still visits children when a control type/name cannot be read. Process identity must be readable and match the owned scope before a subtree is included. Unknown control types retain their raw value and property error. The combined failure tree remains bounded to 160 nodes and depth 8, with 1,024-character diagnostic fields.
2. Read-only `ClipboardObservation` trace entries run before Copy/Cut, immediately after each Invoke, after destination navigation, and on failure. They record the exact Copy/Cut/Paste/omnibar IDs including disabled/offscreen state, native clipboard owner HWND/PID, sequence before/after, and CF_HDROP format availability. Errors are metadata, never success evidence. Existing retained-process/window/foreground checks surround native clipboard observation; all existing input ownership checks remain intact.
3. The three new clipboard queries use centrally pinned CsWin32 `0.3.298` through the isolated qualification adapter. Their declarations also join the customer CsWin32 input list to retain the existing reviewed-subset check. Customer ReadyToRun/composite settings and application command logic are unchanged. No clipboard is opened, read for payload, emptied, or written. [Microsoft's clipboard API reference](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-functions) distinguishes these owner/sequence/availability queries from payload and mutation APIs.
4. On failure, the owned package's `LocalState/debug.log` contributes at most its last 32 KiB to the existing JSON receipt, with byte length/offset and truncation metadata. Ancestors and the log must be regular, non-reparse paths. Read failures are recorded separately. This uses the existing app logger's location; no product logging was added.
5. The diagnostic regression runs in `distribution/qualify-windows.ps1`. The workflow YAML and artifact paths are unchanged; the extra observations live in the existing metadata receipt.

Observation has execution cost. Trace timestamps bracket that work; a green run with observation alone would not establish which hypothesized timing issue caused the prior failure. Clipboard format/owner metadata also does not prove the clipboard contains the fixture's exact file. The actual Paste, independent destination bytes/protected originals, two persisted/UI receipts, CSV preservation/recovery, metadata clear, normal close, uninstall and cleanup checks remain the acceptance evidence.

## Verification

The regression was also run against an isolated copy retaining the original all-at-once property read. It failed with `An unknown control type discarded the toolbar descendants.` The corrected actual helper passes 21 cases: unknown control type, disabled/offscreen Paste, individual property failure, foreign/unreadable PID, child-provider failure, depth/node/field limits, cross-window remaining budget, stage/error metadata, receipt JSON round-trip, bounded end-relative log reads, and link refusal. Its UI providers are test fixtures; they are not Windows UI execution evidence.

Commands run from the source root:

```powershell
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-workflow-diagnostics.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-workflow.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-adapter.ps1 -DotNet "$PWD/.tools/dotnet-10.0.401/dotnet"
```

- Diagnostic helper: 21 checks passed.
- Independent file/JSON/CSV/foreign-target/cleanup workflow: 44 checks passed.
- Actual pinned source generation, adapter IL load, native INPUT ABI, PE/identity rejection: 37 checks passed, including absence of clipboard payload/mutation APIs.
- Python packaging: all 34 passed with `FILEQUAY_DOTNET="$PWD/.tools/dotnet-10.0.401/dotnet" python3 -m unittest discover -s tests/packaging`.
- Consumer observation, build-kind acceptance, installation helpers, and qualification-record publication suites passed.
- All six actual installer failure fixtures passed: normal owned failure, preinstalled framework, failed-Add race, package mutation, reporting failure and adapter failure.
- The consumer workflow body compares exactly to the base after removing only the new observation/log calls. PowerShell parsing, CRLF validation and `git diff --check` passed.

Windows native clipboard/UI behavior and the full consumer workflow are pending independent review and dispatch. No production Copy/Paste defect has been asserted or repaired in this candidate. No public push, snapshot, website or status update was performed.
