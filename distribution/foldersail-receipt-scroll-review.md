# FolderSail stale receipt scroll provider

Run `34686746954`, attempt 1, used nested source
`63732166dae66f80980d8b7af73fd270f714b0f5` and public snapshot
`588f3741e5a6f67f27b4bad2cd63ed5ec7971e5a`. Instrumented
qualification passed. Consumer qualification failed before the native Save
picker, during `ScrollPattern.Scroll` on `ReceiptHistoryList`.

The retained receipt at
`/private/tmp/foldersail-34686746954-review/FolderSail-Windows-Consumer-qualification/Consumer/installation-result.json`
is 139,736 bytes, SHA-256
`149737cbd4b98364d9f537a387a62409174e364038fc1d58a454252c31abef12`.
Its actual exception is a PowerShell `MethodInvocationException` wrapping
`System.Windows.Automation.ElementNotAvailableException`, with the UIA message
that the target element is no longer available.

The actual sequence is Move card Expand at `10:00:49.9592241Z`, Collapse at
`10:00:50.1782004Z`, then Copy card ScrollDown at `10:00:50.7486219Z`. The last
input observation proves application PID 1896, main HWND 459052 and target popup
HWND 262700 are live, visible and owned; owner chain is `[262700,459052]`, the
popup is foreground, and the receipt list element is enabled and belongs to that
PID/window. The subsequent failure tree still contains the owned history list
and both Move/Copy list items. No package/application exit caused this exception.

The artifact contains only the startup `main-window.png`; it was viewed and shows
the actual Home window. There is no failure-time screenshot for this scroll.
The diagnosis relies on the retained exception, action trace and UI tree, without
substituting the startup screenshot for missing failure-time evidence.

## Source boundary and repair

`StatusCenter.xaml` uses a `ListView` over `OperationReceipts` and an Expander
item template with stable automation IDs for each source/destination detail.
`LoadReceiptsAsync` can clear/repopulate the bound collection. The evidence does
not identify which internal WinUI layout/provider event invalidated this specific
object; it does prove the scroll provider became unavailable. The former probe
retained both card objects across expansion/collapse, then reused a retained card
for every iteration of the scrolling loop. It had no stale-provider reacquisition.

The probe now retains only the two distinct observed title strings. Each scroll
iteration independently discovers the current owned `ReceiptHistoryList`, the
single exact `ReceiptDetailsExpander` with the same ID/title, and, when requested,
the exact source or destination detail within that card. It also rederives the
scroll ancestor from that current binding. Discovery continues to use the
unchanged retained-process, HWND, owner-chain, PID, uniqueness and bounded-tree
checks; broker discovery is not enabled for receipts.

Only an actual `ElementNotAvailableException`, either direct or within the bounded
eight-level exception chain, can retry this scroll/observation operation. Each
such observation consumes one of the original 16 attempts, records a bounded
`ReceiptScrollRequery` trace entry and waits the existing 100 ms cadence. The next
attempt observes visibility before sending another scroll. Exhaustion preserves
the last unavailable exception as the budget exception's inner cause. Unrelated
errors and ownership failures are propagated immediately.

Expand, Collapse, Invoke, Value and keyboard operations are outside this retry
loop. There is no replay of those actions, no repeat of Copy/Move, and no additional
workflow retry. Original 30-second expanded-detail observation waits remain.
The exact visible source/destination paths must still identify one distinct
persisted receipt ID, and the title must match that receipt's operation/result.
A title only identifies which card to inspect; it cannot confer receipt acceptance.

The native Save filename ValuePattern gate and diagnostics are unchanged, as are
product code, package/source/runtime bindings, normal close/uninstall and owned
fixture cleanup. Attempt 2 at the same original commit is coordinator-owned; this
repair did not dispatch another run or alter that attempt.

## Same-commit attempt 2: picker boundary reached

The coordinator's second attempt completed with a different, later failure.
Only the 335,936-byte metadata artifact `10296635574` was downloaded; the package
was not downloaded again. Metadata is under
`/private/tmp/foldersail-34686746954-attempt2-review/`, and its failed log is
`/private/tmp/foldersail-34686746954-attempt2-failed.log`.
The 217,587-byte installation receipt has SHA-256
`85ca61d9ccc83dcb9de766717b26cad3b7063c371ae1c240d5547a08fa76c0c3`.

This unchanged original source passed one ScrollDown at `10:18:37.0992630Z` and
both visible receipt ID/path checks, confirming the first attempt's scroll
failure was intermittent. It then reached the owned Save As picker and timed out
specifically on **unsupported ValuePattern**. The exact filename Edit `1001`
under `FileNameControlHost` was visible, enabled and focused; its native HWND was
66228 in broker PID 5436. `TryGetCurrentPattern(Value)` returned false with no
pattern, and the availability property reported unsupported. This is not a
null-pattern or read-only interpretation failure. Save/Cancel Win32 buttons also
reported no supported Invoke pattern. The observations do not yet establish why
the client/provider exposes that state.

The native picker HWND 66112 belonged to the live broker, with retained app PID
1556, main HWND 327762 and owner chain `[66112,327762]`; the main window was
modal-disabled. The new failure screenshot was viewed and shows the real Save As
window with `FolderSail-receipts` selected. Client metadata records PowerShell
7.6.5, .NET 10.0.11 and UIAutomationClient/Types/Provider 10.0 loaded from the
PowerShell 7 installation. No picker implementation or acceptance gate was changed
based on this observation. It remains the next distinct unresolved boundary.

## Verification

The new fixture executes the production receipt reader, unique selector, scroll
loop, action dispatch and ownership predicate. The fixture runs before packaging in the Windows qualification entrypoint.
Only UIA/native observation and sleep providers are doubled. Its scroll provider invalidates the prior UI object
generation and throws the same wrapped unavailable exception through a real .NET
method invocation. Returning the old retained card again is rejected by the
fixture provider. Local fixture output is not Windows application evidence.

- RED: the existing production `ScrollPattern.Scroll` call failed with the wrapped
  unavailable provider exception at `ConsumerWorkflow.Ui.ps1:158`.
- GREEN: exact two receipt IDs and paths survive fresh-list/card queries; the
  successful scenario uses two scroll calls and exactly one Expand/Collapse per
  receipt, with one retained requery diagnostic.
- Negative cases: 16 consecutive unavailable scrolls retain the original cause
  and fail at the unchanged budget; an unrelated exception whose message mentions
  ElementNotAvailable is not retried; changed foreground blocks the second scroll;
  duplicate card, changed paths and duplicate persisted ID fail; unavailable
  Expand or Collapse is never replayed.
- **Nine production scroll/receipt scenarios passed.**
- **36 packaging Python tests passed.** All **21 isolated PowerShell fixture
  invocations passed**, including all six installation-failure scenarios, the
  exact picker scope/diagnostic tests, native adapter build/ABI tests, independent
  receipt/file verification and manifest checks. **32 PowerShell files parsed.**
- `git diff --check` passed; all changed text files use CRLF as required by the
  nested repository instructions. Native Windows application execution is pending.

Logs: `/private/tmp/foldersail-receipt-scroll-{red,green,python,powershell}.log`.
PowerShell runtime: `.tools/powershell-7.6.6/pwsh` under this nested source;
.NET SDK: `.tools/dotnet-10.0.401/dotnet`. Each fixture uses a fresh PowerShell
process; `FILEQUAY_DOTNET` is set to the absolute SDK path, and the native adapter
fixture receives the same path via `-DotNet`.

Native Windows qualification remains required. This is a bounded probe repair,
not a claim that scrolling now passes natively or that the unresolved picker
provider boundary is fixed. No push, workflow dispatch, Store, site or parent
status change was made.
