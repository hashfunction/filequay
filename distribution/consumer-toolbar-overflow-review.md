# FileQuay consumer toolbar overflow — run 34677146464

Base source: `26268dd81a59e6d0c7626dbd4441bd53f1167292`; public source `d1ffa7`.
This candidate repairs the observer's unsupported assumption that Paste is exposed while the toolbar overflow is closed. It does not establish a product clipboard defect or successful native Paste. The actual Consumer workflow remains pending a fresh Windows run.

## Native evidence

Retained Consumer receipt: `/private/tmp/filequay-34677146464-review/FileQuay-Windows-Consumer-qualification/Consumer/installation-result.json`, SHA-256 `8b88d5f91044f787be9e19aff17d7cb5c7bd0d8c984a72779a6efa3cc3ae6835`.
The actual isolated, source-generated IL-only adapter loaded and passed its evidence checks. The retained app PID was `5500`, main HWND `786546`.

| Observation, UTC 2026-09-12 | Clipboard evidence | Paste UIA observation |
| --- | --- | --- |
| Immediately after Copy Invoke at 06:16:18.7748 | Owner 0, sequence 0, no CF_HDROP | Absent, including hidden/disabled lookup |
| Destination at 06:16:19.654773 | Owner HWND 196990, PID 5500, sequence 8→8 stable, CF_HDROP available | Absent |
| Timeout at 06:16:50.243962 | Same owned clipboard HWND/PID, sequence 8→8 stable, CF_HDROP available | Absent |

Copy was invoked at 06:16:18.7616914; navigation began at 06:16:19.12298. The new diagnostic calls consume measurable time, so the previous run's 49 ms interval cannot be assumed here. Clipboard data became available and remained present throughout the destination wait. Neither an empty clipboard at failure nor navigation-induced loss is supported. These read-only format/owner queries do not prove the clipboard's exact file payload.

The property-resilient failure tree retains `ContextCommandBar` (class `ApplicationBar`), visible New, disabled Cut/Copy after destination navigation, and exactly one visible enabled `MoreButton`, name `More options`, class `Button`. Paste and every subsequent default command are absent. Unknown `ControlType.ProgrammaticName` did not discard the toolbar descendants. The owned 540-byte debug-log tail contains no Copy/clipboard error. The retained screenshot is the initial Home window, not a failure screenshot; it does not show the destination toolbar.

Production source places New, separator, Cut, Copy, Paste, Rename, Share, Delete and Properties in that order in the factory `AlwaysVisible` context (`src/Files.App/Data/Items/ToolbarSections.cs`). `Toolbar.xaml.cs` adds these to `ContextCommandBar.PrimaryCommands`; “AlwaysVisible” names a context, not a promise that every command fits on screen. `Toolbar.xaml` enables dynamic overflow through the view model. [Microsoft's Command bar documentation](https://learn.microsoft.com/en-us/windows/apps/design/controls/command-bar) describes moving primary commands into overflow when width is insufficient and opening it with More. The observed prefix plus More matches this source-backed overflow route. The unopened menu's actual Paste item and its enabled state were not captured; a fresh run must observe them.

The Instrumented job passed separately. The Consumer job failed at the first Paste wait and did not produce Copy/Move acceptance evidence. Owned process cleanup, fixture cleanup and app uninstall were verified, with no cleanup errors. Frameworks remain under the existing disposable-runner teardown policy; `full_environment_cleanup_verified` is false. This candidate does not relabel either result as full Consumer lifecycle success.

## Bounded observer change

Only the two Paste call sites use the new helper. Copy, Cut, navigation, product commands, clipboard code and the compiled adapter remain unchanged.

1. Prefer the existing uniquely visible and enabled exact `InnerNavigationToolbarPasteButton` selector.
2. If it is not exposed, observe the retained main window, its exact `ContextCommandBar` descendant and exactly one descendant `MoreButton` named `More options`. Require the observed classes, retained app PID, and main HWND. Existing lookup visibility/enabled filters remain active.
3. Invoke More once through the existing native foreground/window/process/element gates. The invocation sits outside retry polling, so a provider failure cannot toggle it again.
4. Retain a read-only `paste-overflow-opened` clipboard/control snapshot, reacquire the original exact visible enabled Paste, and invoke through the same input gates. Each observation stage retains the default 30-second bound. Missing, disabled, ambiguous or changed UI still fails and takes the existing bounded failure snapshot.

There is no clipboard mutation, synthetic Paste shortcut, arbitrary menu selection, window resize, added sleep, product hook or instrumented substitute. The exact file bytes, protected originals, Copy/Move receipts, visible receipt content, CSV destination decision/recovery, metadata clear, normal close and owned cleanup gates are unchanged. The new focused test is checked by the existing Windows qualification wrapper; artifact policy and workflow YAML are unchanged.

## Focused verification

Run from this source root:

```powershell
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-toolbar.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-workflow-diagnostics.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-workflow.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-observation.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-build-kind-acceptance.ps1
.tools/powershell-7.6.6/pwsh -NoLogo -NoProfile -File tests/packaging/test-consumer-adapter.ps1 -DotNet "$PWD/.tools/dotnet-10.0.401/dotnet"
```

- 19 toolbar cases pass, executing the production sequencing with scoped fixture providers: direct Paste, overflow reacquisition, missing/hidden/disabled/duplicate commands, missing/duplicate/renamed/wrong-class/hidden/disabled More, wrong toolbar class, foreign toolbar/button PID or window, foreground loss before and after More, and failed Invoke. The existing production ownership predicate is executed at the fixture action boundary; fixtures are not native Windows evidence.
- Replaying the prior production Paste expression in the same fixture passes the direct case and fails the overflow case with `Expected one owned workflow element 'InnerNavigationToolbarPasteButton'/''; observed 0.`
- 21 diagnostic cases and 44 independent file/receipt/CSV/ownership/cleanup boundary checks pass; Consumer observation and build-kind acceptance suites pass.
- 37 actual pinned source-generation, IL load, INPUT ABI, PE/identity rejection and read-only clipboard API checks pass. The adapter's production code is unchanged.
- `FILEQUAY_DOTNET="$PWD/.tools/dotnet-10.0.401/dotnet" python3 -m unittest discover -s tests/packaging`: 34 tests pass.
- PowerShell parsing, changed-file CRLF validation, and `git diff --check` pass. The consumer workflow body is byte-equivalent after normalizing only the two Paste call expressions; all subsequent acceptance checks remain identical.

Independent review and a fresh actual Windows Consumer run are next. No source push, package publication, website, branding or parent status edit was performed.
