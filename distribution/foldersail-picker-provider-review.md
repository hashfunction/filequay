# FolderSail native picker provider diagnostics

Prepared 2026-09-12 against source `0efc8f50f8f81371c60e1965360536e9c4d1adf5`, after actual Windows run `34685016295`. This is a diagnostic-only candidate; the ordinary installed Consumer workflow remains unqualified.

## Observed failure

The retained `Consumer/consumer-save-picker-failure.png` was viewed before changing source. It shows the actual Save As dialog, Documents folder, selected `FolderSail-receipts` filename and CSV type. `installation-result.json` records owned foreground HWND `66114`, broker PID `8864`, retained app PID `4904`, disabled main HWND `262446`, and owner chain `[66114,262446]`. The actual filename is automation ID `1001`, native class `Edit`, below `FileNameControlHost`; the other ID `1001` is an address toolbar and is not the filename.

Both the 56-node control view and 65-node raw view expose the filename as `ControlType.Pane`, focused but not keyboard-focusable. The native Save button also appears as a Pane. The consumer progresses through actual Copy/Move and visible receipt checks, then fails while waiting for the editable filename before setting the CSV path. The compound exception was `Native filename field is not the observed editable ValuePattern control.` No pattern result, null/read-only distinction, provider description or UIA client assembly identities were retained. These observations do not prove a ValuePattern workaround or a product defect.

The instrumented matrix job passed independently. Consumer failed: normal close was not requested, normal exit was not verified, owned process and fixture cleanup were verified, and `cleanup_errors` was empty. These cleanup outcomes do not grant Consumer acceptance.

## Bounded change

The same filename gate now distinguishes identity/class mismatch, unsupported ValuePattern, null returned pattern and read-only pattern. Provider-thrown exceptions retain their existing propagation. Evaluation order and accepted conditions are unchanged.

Only the existing failed-picker observation enables extra reads. Within its same 80-node/depth-8 budget per view, exact class/ID pairs for filename, filename host, Save and Cancel gain current HWND/framework information, Value/Invoke availability properties and actual `TryGetCurrentPattern` support/null/type results. An available ValuePattern additionally reports its read-only state and bounded current value. Every string/error remains limited to 1,024 characters. Foreign or changed element PIDs are rejected, the retained native owner/foreground checks still bracket tree capture, and all failures remain secondary diagnostics.

Provider-description lookup uses the documented `UIA_ProviderDescriptionPropertyId` 30107 through the public managed lookup. If the loaded managed client does not register that property, the receipt explicitly records `client_property_registered=false`; it does not manufacture a property, register a proxy or infer a description. NotSupported, null, false and property-query failures remain distinct.

The receipt records only already-loaded assemblies named UIAutomationClient, UIAutomationTypes, UIAutomationProvider or UIAutomationClientSideProviders, capped at 16 entries, with full identity, path and module ID, plus PowerShell/.NET versions. No assemblies are explicitly loaded, providers registered or application input sent by this observation. The original package/source/module ownership, Copy/Move/receipt/export/recovery/clear/close/uninstall predicates and real screenshot capture remain unchanged.

Microsoft's [managed ProxyManager implementation](https://github.com/dotnet/wpf/blob/main/src/Microsoft.DotNet.Wpf/src/UIAutomation/UIAutomationClient/MS/Internal/Automation/ProxyManager.cs) attempts default proxy loading once and can fall back after provider creation fails. That is a hypothesis consistent with generic native controls, not a diagnosis of this runner. The [property identifier documentation](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-automation-element-propids) and [managed lookup API](https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.automationproperty.lookupbyid) establish the diagnostic query's public interface. Actual proxy availability remains unresolved until the next native receipt.

## Local verification

- New tests failed before production changes: provider observation was absent, and distinct filename failures were concealed by the same exception.
- 59 production-boundary picker diagnostic checks pass. Coverage includes unsupported/null/read-only/writable results; NotSupported/null/unregistered properties; secondary errors; exact IDs/classes; foreign/changing PIDs; node/text/assembly budgets; exclusion of unrelated assembly paths; and receipt JSON serialization at the real depth.
- 39 production scope/filename selector checks pass, retaining all prior wrong host, duplicate filename, address bar, foreign HWND/PID, unsupported/read-only/null provider and broker-change refusals.
- All 20 isolated PowerShell invocations pass, including manifest, real generated native adapter, workflow observation/input policy, installer ownership and all six installer failure scenarios. 36 Python packaging and 30 production receipt tests pass. All 31 PowerShell files parse. The final null-property distinction was then rechecked with the 59-case fixture.
- Changed text files use CRLF; `git diff --check` passes. No full native WinUI build or Windows run is claimed from macOS.

Reproduction uses `.tools/powershell-7.6.6/pwsh` and `.tools/dotnet-10.0.401/dotnet` under this source root. Set `FILEQUAY_DOTNET` to that absolute SDK for Python and PowerShell fixtures, and pass it as `-DotNet` to `test-consumer-adapter.ps1`. Run PowerShell fixtures separately; run `distribution/test-manifest.ps1` and all six installation-failure scenarios. Logs: `/private/tmp/foldersail-provider-{python,powershell,manifest,unit,green}.log`; the failing regression logs are `/private/tmp/foldersail-provider-red.log` and `/private/tmp/foldersail-gate-red.log`.

Independent root review and a fresh exact-source native Windows run are pending. No push, Store, website, parent status or product runtime changes were made.
