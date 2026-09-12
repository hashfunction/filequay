# FolderSail UIA fixture companion preload

Run 34698388236 used public source `b6b13047db752787ebc56e7c0738b3c9c4739a9c`. Both jobs failed in the harness before application build, SQLite native execution, package validation, or installation. Instrumented stopped at 14:10:48 UTC and Consumer at 14:12:07 UTC on 2026-09-12. The exact primary error was `Expected independently loaded UIA collision type: AutomationProperty`, from `tests/packaging/uia-replay-collision.ps1:18`, called at the beginning of `test-consumer-picker-diagnostics.ps1`.

The original logs show all 43 Python packaging checks, the 17 receipt-scroll scenarios, proxy policy 24 cases, compiled registration stack/binding regression, Win32 fixture 23 cases and locked fixture build, and general consumer diagnostics 21 cases passing first. Actual Consumer `uia-proxy-preflight.json` records `passed: true`, `cleanup_errors: []`, and no error. The two small artifacts contain prerequisite/TRX metadata and that preflight receipt; neither contains a new application installation result. This run is not evidence of a product or stable SDK runtime failure.

The collision helper explicitly loaded only the host's `UIAutomationClient.dll`, then required `AutomationProperty` to be discoverable through PowerShell's type lookup. Microsoft documents that `AutomationProperty` is defined in the separate `UIAutomationTypes.dll`: https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.automationproperty?view=windowsdesktop-10.0. The matching WPF source is https://github.com/dotnet/wpf/blob/v10.0.11/src/Microsoft.DotNet.Wpf/src/UIAutomation/UIAutomationTypes/System/Windows/Automation/AutomationProperty.cs. Loading Client alone does not force its lazy companion into type discovery.

The fresh-process regression executes the real helper's Windows branch and actual PowerShell type lookup. Only the host file-loading boundary is doubled: client and property types are emitted into separate exact-named assemblies only when their corresponding file is requested. Before correction, it reproduces the exact missing `AutomationProperty` error. After correction, both exact host files load once and all four types resolve to their expected assembly. The helper now explicitly loads `UIAutomationTypes.dll` from the same `$PSHOME` before Client. Failure messages also retain the unresolved or actual assembly identity. It adds no alternate search location and does not catch import failures.

Local validation with `.tools/powershell-7.6.6/pwsh -NoProfile -File`:

- `tests/packaging/test-uia-replay-preload.ps1`: red on original helper, green after correction.
- `tests/packaging/test-consumer-picker-diagnostics.ps1`: 59 checks passed.
- `tests/packaging/test-consumer-picker-scope.ps1`: 39 checks passed.
- `tests/packaging/test-consumer-picker-input.ps1`: 25 checks passed.
- `tests/packaging/test-uia-proxy.ps1`: 24 policy checks, compiled exception/stack replay, and three caller-binding refusals passed.
- `tests/packaging/test-uia-proxy-fixture.ps1`: 23 checks, missing-host-provider refusal, actual locked build, and post-build mutation refusal passed, using `FILEQUAY_DOTNET=$PWD/.tools/dotnet-10.0.401/dotnet`.
- `tests/packaging/test-consumer-receipt-scroll.ps1`: 17 scenarios passed.

The new replay runs as its own checked PowerShell process in qualification. Production registration, native adapter, UI actions, file/CSV oracles, ownership and cleanup predicates are unchanged. A fresh Windows application run remains required. Store/source integration is preserved separately in a named Git stash and is not part of this repair.
