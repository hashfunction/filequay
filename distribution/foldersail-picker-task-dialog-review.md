# Native replacement task dialog — 2026-09-12

Windows run `34705590423`, public source
`29a524deecbab5a319aed76db775244682b6c7c2`, passed actual Copy/Move operations,
persisted/visible receipts, one native filename replacement, three read-only
filename observations ending at the exact full owned CSV path, and one Save
Space action. Consumer qualification then timed out waiting for native/app
export confirmation. It did not reach accepted CSV export or normal close.

The original Consumer `installation-result.json` is 160,403 bytes with SHA256
`65128eb40241c7a68579b97226bafba60d2795c62458648264f8de03b0512d58`.
Its owned PickerHost process `1732` exposed a distinct dialog `66288`, title
`Confirm Save As`, class `#32770`. The content was exactly:

```text
receipts.csv already exists.
Do you want to replace it?
```

The Yes control was `CommandButton_6`, `CCPushButton`, ControlType.Button,
visible, enabled and keyboard-focusable. No was `CommandButton_7` of the same
class and type and held keyboard focus. Discovery queried only `6`; the later
button predicate allowed only the `Button` class. That exact mismatch prevented
the handler from reaching either focus or input for this dialog.

The original observation's `hwnd` field is the **scope HWND**, not the control's
`NativeWindowHandle`. Neither Yes's native handle nor its provider-pattern
support was captured. The six original scoped node values and provenance are
retained in `tests/packaging/fixtures/picker-task-dialog-34705590423.json`, a
derived metadata excerpt with SHA256
`05c367981cde514a0284414dbbdd923745db06011f1e14c813bfd95c1dc06ac0`.
The private original receipt is preserved separately; no build-log excerpt is
published by this change.

The candidate adds only the observed task-dialog route. It requires the same
retained picker PID, a distinct owned dialog, exact root PID/HWND/title/class/
type, full previously verified filename, exact content text and No sibling, and
a unique retained Yes UIA runtime identity. These checks run before input and
again during the existing bounded focus observation. The original owner chain,
foreground, enabled/visible state and exact final native input guards remain.
The existing `6`/`Button` route is retained.

Before focus, the new route records original button properties and provider
metadata, including the separately observed native control handle. Zero,
unavailable, changed, or dialog-equal control handles refuse before Yes input.
The dialog HWND is never substituted. If the exact native control exists, the
original helper requests focus once, observes it without replay, and sends only
one ordinary Space after the unchanged C# native focus/owner checks. No
InvokePattern, mouse-click fallback, dialog-level focus allowance or new native
API was introduced.

The original CSV bytes are checked before native Yes and again at the app's
confirmation. The app must still display the exact full destination path before
its explicit transaction decision. Cancel, committed CSV/recovery, metadata
clear, normal-close and cleanup acceptance remain unchanged. Marketing remains
in its separate prior commit and unbound.

Validation:

- The original-observation replay first failed with `No observation:
  selected-file snapshot and explicit export confirmation` instead of reaching
  the guarded button boundary. It now records an unavailable native HWND and
  refuses before Yes focus/input, as required by the missing original fact.
- The actual production picker PowerShell sequence passed **86 checks**,
  including 39 added task-dialog cases: exact scalar route, missing/dialog-equal
  HWND, wrong root/content/No/PID/owner/path, duplicate/replaced UIA identity,
  absent runtime identity, unsupported class/context, delayed/absent focus, changed native HWND, native
  refusal without replay, and wrong full app confirmation. Nonzero control
  handles in these tests are explicitly scalar fixtures, not Windows evidence.
- Existing native Space **16**, native Unicode **16**, generated CsWin32 IL/
  native ABI adapter **41**, scope/filename selector **22+39**, picker diagnostic
  **59**, workflow file boundaries **44**, and observation checks passed.
  The generated adapter was compiled with the pinned local .NET 10.0.401.
- The existing qualification script already invokes the expanded picker suite;
  no workflow or product code changes were needed.

Actual Windows remains pending. If the task-dialog provider supplies no distinct
native control HWND, the next run will fail with precise provider evidence and
without Yes input. That would require a separately evidenced normal UI route;
this candidate does not claim that unsupported boundary is solved.
