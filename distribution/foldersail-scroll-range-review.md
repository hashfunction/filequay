# FolderSail receipt scroll state convergence

Windows run `34693226019`, source snapshot
`6254c7d041bb2de7534ccfa63619eea159684d64` (local `ca032cbd`), passed
Instrumented qualification and failed Consumer qualification before the Save
picker. The previous native Save/Space correction was not exercised by this run.

The actual Consumer installation receipt is 150,593 bytes, SHA-256
`cfb3bc0876dd68d886e507eff6ccc3f3a9c145d3771874a1808ed1aefb9a7dad`, retained under
`/private/tmp/foldersail-34693226019-review/FolderSail-Windows-Consumer-qualification/Consumer`.
Copy and Move completed with the original 84-byte Unicode file, protected
sentinels and two persisted successful receipts. The Move receipt expanded at
12:30:30.2180750Z and collapsed at 12:30:31.0669917Z. The first ScrollDown on
`ReceiptHistoryList` at 12:30:31.3231437Z threw a PowerShell
`MethodInvocationException` wrapping `System.InvalidOperationException` from
`UiaCoreApi.CheckError` during `ScrollPattern.Scroll`.

The input observation retained live application PID 1200, main HWND 786456,
popup HWND 393786, owner chain `[393786,786456]`, the exact foreground popup and
an enabled, visible owned receipt list. The later failure tree still contained
the enabled visible `ListView` with that automation ID. No scroll range or
failure-time screenshot was captured. The only PNG was viewed and shows the
earlier Home window; it is not evidence of the later scrolling state.

Microsoft's public [ScrollViewerAutomationPeer implementation](https://github.com/microsoft/microsoft-ui-xaml/blob/6d4e2040ea8f5a2bd8130cf24d3e23985f8f8ba3/dxaml/xcp/dxaml/lib/ScrollViewerAutomationPeer_Partial.cpp#L105)
returns `UIA_E_INVALIDOPERATION` if a requested axis is no longer scrollable.
Its vertical availability depends on current extent and viewport. A layout
change after collapse is consistent with the observed sequence; the artifact
does not prove the exact range transition or internal WinUI cause. This source
reference explains the public provider behavior, not a claimed reconstruction
of the installed Microsoft runtime binary.

## Bounded probe change

Each actual scroll records both axes' scrollable state, percentage and view size
before and after the call, plus its completed or failed outcome. A failed
post-call range query is recorded separately and cannot replace the original
call exception. The original ScrollDown trace remains the input intent; the
new `ReceiptScrollAttempt.outcome` explicitly distinguishes failed calls.

Only a typed `InvalidOperationException` raised inside the actual Scroll call
enables read-only convergence. Discovery, ownership checks and range-query
failures cannot enable it. The next observations reacquire the exact owned list
and the same requested card/detail, check the original popup PID/HWND/owner and
foreground, and accept only a genuinely visible detail. After this failure,
that visibility operation never sends another Scroll or another UI action.
Persistent invisibility or changed ownership fails with the original complete
exception retained as the inner cause. Unavailable providers still use the
existing bounded reacquisition policy; they cannot re-enable input after the
typed scroll failure.

Both the existing 16-attempt maximum and a 30-second elapsed deadline apply.
The fixture can shorten that deadline, never extend it. A result observed after
the deadline cannot return accepted. Receipt Expand/Collapse, Copy/Move,
persisted and visible path matching, CSV decisions/recovery, native picker,
normal close, uninstall and owned cleanup remain unchanged.

## Verification

The production scroll/reader/action fixture first failed with the actual typed
exception on the old code. It now passes 14 scenarios. It imports the actual
owned list metadata, PID/HWND/owner state and exception from the compact
`receipt-scroll-invalid-operation-34693226019.json` fixture. The simulated
scrollable-to-nonscrollable range change is explicitly labelled as test data,
not represented as a range observed in the Windows run.

Coverage includes exact two receipt IDs/paths after one failed Scroll, no
action replay, before/after range mutation, foreign foreground, never-visible
state, failure while reading the later range, actual elapsed deadline refusal,
existing stale-provider budget, duplicate cards/IDs, wrong paths and nonreplayed
Expand/Collapse. Existing picker input, picker scope, diagnostics, file/receipt,
observation and toolbar regressions also pass. All 36 Python packaging tests
pass. Changed PowerShell files parse and `git diff --check` passes.

Commands (nested source):

```text
.tools/powershell-7.6.6/pwsh -NoProfile -File tests/packaging/test-consumer-receipt-scroll.ps1
TMPDIR=/private/tmp FILEQUAY_DOTNET=<source>/.tools/dotnet-10.0.401/dotnet python3 -m unittest discover -s tests/packaging -v
```

Logs: `/private/tmp/foldersail-scroll-range-{red,regressions,python}.log`.
This is local fixture evidence. Fresh Windows Consumer qualification remains
required, including the as-yet unexercised native Save/Space change. Actual
cleanup in run 34693226019 succeeded: owned process and fixture removal,
uninstall and trust removal, with no residual packages or cleanup/evidence
errors. This repair does not claim Consumer acceptance or Store readiness.

The unfinished Store/source work remains isolated in the named git stash
`FolderSail assigned Store export WIP before 34693226019 diagnosis`; its five
downloaded source archives remain under `/private/tmp/foldersail-corresponding-source`.
