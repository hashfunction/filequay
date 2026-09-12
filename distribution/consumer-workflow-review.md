# FileQuay consumer workflow implementation review

The consumer installation qualifier now requires actual Copy → Move → receipt
inspection → CSV destination cancellation/confirmation/recovery → metadata clear
within the already verified installed process. It does not use a CI app entry
point, call product view models, populate receipt history, or replace file
operations with fixture writes. The generated inputs and independent validation
remain outside the application.

The source changes are confined to qualification helpers, five additional
CsWin32 API declarations, existing acceptance/installer wiring, focused fixtures
and documentation. Product UI, workflow YAML, consumer close behavior, strict
framework installation, installation identity, instrumented COM qualification,
unsigned input rehashing and exact app/certificate cleanup are preserved.

## Evidence

- RED: the new boundary fixture failed because its implementation was absent;
  the new acceptance mutation failed because the old consumer acceptance ignored
  missing workflow evidence.
- GREEN: 44 independent workflow checks passed using real generated files,
  independent JSON and CSV readers, byte/hash mutations, duplicate/missing rows,
  wrong paths/results/times, foreign UI observations, an actual filesystem link,
  changed ownership and cleanup-before-process-stop refusal.
- All 34 existing Python packaging tests passed with the pinned .NET 10.0.401 SDK.
  An initial invocation selected the machine's unrelated .NET 8 SDK; rerunning
  with the repository tool path resolved those SDK-selection failures.
- Existing PowerShell registration/cleanup, build-kind acceptance, UI evidence,
  exclusive publication, actual managed metadata and actual process fixtures
  passed. All five installer failure scenarios retained primary, cleanup and
  evidence/reporting failures as required.
- The affected CsWin32 project built successfully with zero errors. The native
  adapter compiled against that actual generated assembly. This is compilation
  evidence; no Win32 input, native picker or installed WinUI workflow was executed
  on macOS.

## Review boundaries for the Windows run

The save picker must expose a live native owner chain back to the retained main
HWND. A different process is observed through its own retained handle, without
granting permission to terminate that process. Every input action checks the
target's actual native window, UIA ancestor/process, visibility, enabled state
and exact foreground again. Dynamic WinUI popup windows are bound from observed
native ancestors, never selected solely by a control ID or title.

Receipt details may require bounded scrolling in their visible owned container;
the workflow does not resize or alter product UI. A missing native picker owner,
ambiguous selector, inaccessible detail, unsupported UIA pattern, malformed
receipt, CSV mismatch or changed protected file remains a qualification failure.
The first Windows run must establish these actual provider behaviors.

After the retained app stops, fixture cleanup validates every remaining allowed
file before deleting any entry. Unexpected files, changed bytes, marker changes
or reparse points preserve the fixture and fail cleanup. No raw fixture payload,
full app profile, package archive or native binary is added to public artifacts.

Run `34609580070` remains the earlier installation/consumer-window and
instrumented COM baseline. It is not evidence that this newly added interactive
workflow has passed. Root review and a fresh Windows run remain pending.
