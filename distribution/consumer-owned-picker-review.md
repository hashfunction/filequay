# FileQuay owned save-picker discovery — run 34682410941

Base source: `3f8018d934559d343e8c26c98db934e2c0ce4b9c`. This repair changes the
consumer observer's candidate discovery and exact filename selector, with no
product or acceptance change. Fresh actual Windows qualification remains pending.

## Retained native evidence

Receipt: `/private/tmp/filequay-34682410941-review/FileQuay-Windows-Consumer-qualification/Consumer/installation-result.json`,
SHA-256 `4fc27d44ede4aba3c3413a9f0bbbd3dcef6c2d4533a6088d9d44c8175eb9f4c1`.
The main window was HWND 262620/PID 7272. The actual foreground Save As picker
was HWND 66112/broker PID 7760, with native owner chain `[66112,262620]` and the
main window disabled. Its retained unedited 625×480 PNG was viewed directly;
SHA-256 `e867fc0461215876806b60af1ce8f5e97cd43cfc4e9e0abe0c65b959c82fbdef`.

Desktop UIA Children enumeration observed four roots, with no property errors
and no matching picker. The direct FromHandle control/raw trees instead expose
the Save As root, FileNameControlHost/AppControlHost, and enabled visible filename
ID 1001/class Edit. Both trees also expose a second enabled visible ID 1001 for
`Address: Documents`, class ToolbarWindow32. The observed filename ControlType is
Pane, so assuming ControlType.Edit would be incorrect.

## Focused repair

The scope collector preserves the 128-root budget and adds only the actual native
foreground HWND whose owner chain reaches the retained live main window. Broker
candidates still require explicit AllowBroker. It deduplicates exact native HWNDs,
checks native/UIA PID and handle agreement, retains the exact broker process once
under the existing eight-handle budget, and rechecks retained handles, process
liveness, owner chain, visibility and native/UIA identity before returning a
scope. A foreground change during discovery rejects that candidate. No foreign
foreground UI is read and no process-name discovery, broad scan or cleanup exists.
The disabled main window remains observable while its owned modal picker is active.

Filename selection is scoped to the unique observed FileNameControlHost with
AppControlHost class in a distinct owned picker. Its unique descendant 1001 must
have class Edit and a supported writable ValuePattern. This excludes the actual
address-bar collision without changing control-type semantics or using keyboard/
coordinate fallbacks. Existing input-time ownership checks still run before
ValuePattern/Save invocation. Original timeout/failure diagnostics remain intact.

Copy/Move file predicates, persisted/visible receipt checks, CSV destination,
overwrite/cancel/recovery/clear, normal close, owned cleanup and uninstall gates
are unchanged. Successful local replay is not completed consumer qualification.

## Verification

- The new real production-scope replay first failed on the exact missing
  foreground case; it passes after repair. The fixture models the actual native
  numbers/tree shape and runs production functions without native user input.
- 35 focused checks pass: absent/duplicate desktop roots, foreign foreground,
  explicit broker opt-in, process retention/budgets, expired/invalid/changed
  native and UIA ownership, filename ID collision/outside-host/duplicates,
  class/host/PID/HWND changes and unsupported/read-only/failing ValuePattern.
- All seven separately launched consumer PowerShell fixtures pass, including
  40 picker diagnostics, 19 toolbar, 21 diagnostic and 44 file/receipt boundary
  checks, consumer observation, and actual generated native adapter verification.
- All 34 Python packaging tests pass with exact .NET SDK 10.0.401. Initial local
  invocations selected the host SDK or multiple dotnet paths; rerunning with
  FILEQUAY_DOTNET and the adapter's explicit -DotNet path resolved this without
  changing production tool selection.
- Changed scripts parse, changed text is CRLF, and git diff --check passes.
  Existing native input, diagnostic collection, file/receipt predicates and
  package installer are unchanged.

Logs: `/private/tmp/filequay-picker-scope-red.log`,
`/private/tmp/filequay-picker-scope-python-sdk401.log`, and
`/private/tmp/filequay-picker-scope-powershell-sdk401.log`. Local .NET and
PowerShell are this source's `.tools/dotnet-10.0.401/dotnet` and
`.tools/powershell-7.6.6/pwsh`.

No push, Store/site action, branding change or fresh native success is claimed.
