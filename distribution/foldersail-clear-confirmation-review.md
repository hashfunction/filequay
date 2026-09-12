# Clear receipts confirmation selector

Candidate follows `ecde6139db8ee69f469e6ae37382ed12949a532a`.
Run `34710948563` reached the final clear-history confirmation after completing
Copy, Move, both distinct visible/persisted receipts, CSV cancellation preserving
the previous file, and confirmed CSV export with displayed recovery path.
It did not repeat the scroll refusal: there are no ReceiptScrollContainerRefusal
records in this run.

Original Consumer receipt is retained at
`/private/tmp/foldersail-34710948563-review/Consumer/installation-result.json`:
185240 bytes, SHA256
`62a780fdc75d7ddf0ee3798a2c15528e93e666ae951b0755e2318e037447a013`.
The source fixture preserves the complete 160-node failure observation and the
original Clear invocation as an explicitly labeled extract, with receipt hash
and source/run identity. Fixture bytes are pinned in the test and preserved by
`.gitattributes`; the original receipt is unchanged.

The exact localized `Clear receipts` confirmation appears as ClassName `Popup`,
ControlType `Window`, enabled and on screen, PID8740. It contains an enabled
PrimaryButton named `Clear receipts`, CloseButton named `Cancel`, and the exact
metadata-only content:

> Clear local receipt history? Files, live operations and preserved corrupt-history evidence are unaffected.

`StatusCenter.ClearReceipts_Click` constructs a WinUI ContentDialog with those
title, content and button resources and a Cancel default. Its UI Automation peer
is the observed Popup Window. The harness instead required UIA ClassName
`ContentDialog`, so it rejected the actual dialog before sending confirmation.
The repair replaces only that class predicate and adds the exact observed Window
control type. Exact localized title, uniqueness, scoped descendant selection,
metadata-only text, final native ownership/foreground/input checks and all later
file/JSON/CSV/cleanup gates remain unchanged. No additional action or retry is
introduced. Marketing capture has no clear-history step and needs no parallel edit.

The actual CSV was 1023 bytes, SHA256
`f3781a3a43578372f5e242816785d98c511576a6bca5a889b43813b215d75939`.
The displayed preserved-original path was registered and its 57 original bytes
were independently verified. Fixture/process cleanup, uninstall and trust removal
passed. Clear-history and normal-close acceptance remained false; no complete
consumer, Store or marketing success is inferred.

## Focused verification

The new test extracts and executes the actual consumer clear caller, retaining
the production unique-element reader, action helper and ownership predicate.
Only UIA/Win32 leaves are fixture providers; this is not Windows acceptance.
The unchanged selector first failed with the exact original missing-confirmation
error. After the repair all 13 scenarios pass: original Popup/Window, wrong class,
role, title, duplicate popup, hidden/disabled/foreign popup, incorrect metadata
text, missing/duplicate primary control, changed foreground and changed owner.
Every refusal sends zero confirmation inputs; the opener and successful
confirmation are each sent once.

```sh
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-clear-confirmation.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-receipt-scroll.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-export-result.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-workflow.ps1
```

All passed: 13 new clear-caller, 21 scroll, 10 consumer/marketing export-result
scenarios and 44 independent workflow boundary checks. The standard Windows
qualification invokes the new test beside the existing consumer tests.
Red/green logs are `/private/tmp/foldersail-clear-confirmation-{red,green}.log`;
other focused logs use `/private/tmp/foldersail-clear-*-tests.log`.
`git diff --check` passed. Fresh Windows confirmation, persisted empty history,
unchanged protected/export/recovery files and full normal-close lifecycle remain
required by the existing gates.
