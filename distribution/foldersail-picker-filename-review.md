# Native filename delivery after the observed picker mismatch

Original Windows run 34703681708, attempt 1, used public source
`3ddacc0626983062f9fac81881562183a907d77d` (local `ff1b54cf`).
The original Consumer installation receipt is 162,193 bytes, SHA-256
`4d388c72135f9d214fde9f9b4c41389abd8402cd1fba915a7dbd9495aa57ded9`.
The Instrumented job passed; its 6,026-byte original receipt has SHA-256
`37030973eb549c10f846c6e7b39454427f280dabaec3480eae09aeb5215b3612`.

Consumer Copy, Move and both persisted/visible operation receipts passed. The
picker filename ValuePattern readback exactly matched the owned fixture CSV.
Save focus now demonstrably converged from false to true after one SetFocus
request: picker HWND 66162/PID 7320, button HWND 66194, app HWND 328072/PID 9132.
One native Space followed. The app's visible export confirmation then named
`C:\Users\runneradmin\Documents\FolderSail-receipts.csv`, its default filename,
instead of the selected fixture path. The exact confirmation gate refused;
its PrimaryButton was never invoked. Cleanup, uninstall and trust removal
passed; the Consumer workflow and assigned Store export did not.

The product directly displays the `StorageFile.Path` returned by
`PickSaveFileAsync`. The matching Microsoft WPF WindowsEditBox Value provider
sets text with WM_SETTEXT; successful property readback therefore did not prove
that PickerHost returned that path. The precise internal PickerHost behavior
is not established. Primary source:
[Microsoft WPF v10.0.11 WindowsEditBox](https://raw.githubusercontent.com/dotnet/wpf/v10.0.11/src/Microsoft.DotNet.Wpf/src/UIAutomation/UIAutomationClientSideProviders/MS/Internal/AutomationProxies/WindowsEditBox.cs).

This candidate changes only the qualification driver. It focuses the exact
owned native Edit control, observes that one focus request for at most twenty
reads, then uses one native SendInput array: Ctrl+A down/up followed by Unicode
down/up pairs. The compiled adapter rechecks retained process, owner chain,
foreground, native HWND and GetGUIThreadInfo focus immediately before input.
Text is bounded to 1,024 UTF-16 code units and rejects control characters and
unpaired surrogates. Partial input fails without replay. The clipboard remains
untouched, preserving the app-owned file-drop data from the actual Copy/Move.
Unicode input uses Microsoft's documented
[KEYBDINPUT contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-keybdinput).

The text readback observes queued input processing for at most twenty reads,
retaining each original value; identity and read-only changes still fail
immediately. No input is retried. The original exact app-confirmation path,
existing-file hash, replacement, CSV content and recovery-file checks remain.
The filename test runs on the real generated CsWin32 qualification adapter;
no customer application code or package identity changes.

Local verification reproduced failures before the new method and before
asynchronous readback handling. Afterward, the actual compiled adapter passed
16 Unicode and 16 Space OS-boundary cases; the production PowerShell picker
flow passed 47 cases, including focus drift, delayed readback, wrong returned
path and no replay after failure. The actual locked CsWin32 generator, IL
loader, native structure layout and rejection suite passed 41 checks. All
66 packaging Python tests passed with the pinned .NET 10.0.401 SDK.
These are local driver and ABI results, not a successful Windows picker run.
