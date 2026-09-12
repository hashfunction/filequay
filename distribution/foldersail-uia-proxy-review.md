# FolderSail native Win32 UIA proxy preflight

2026-09-12. Candidate based on nested source `58f98181497ad10538bd0a252dab6b6a438ad5f6` (the separate receipt-scroll repair). Windows behavior remains pending independent dispatch; this is a client-host correction and diagnostic, with no product binary or consumer acceptance change.

## Observed failure

Run `34686746954`, attempt 2, public source `588f3741e5a6f67f27b4bad2cd63ed5ec7971e5a`, reached the owned Save As dialog after actual Copy/Move receipt validation. The filename was the unique native `Edit` / ID `1001` under `FileNameControlHost`, with the expected `FolderSail-receipts` text. Dialog HWND `66112` belonged to broker PID `5436`; owner chain `[66112,327762]` ended at retained app PID `1556`. The screenshot was inspected. Discovery now works.

The actual filename and native Save/Cancel Buttons all exposed `ControlType.Pane`, with unsupported Value/Invoke patterns. The filename was enabled, visible and focused. The client was PowerShell `7.6.5`, .NET `10.0.11`, with UIAutomationClient/Types/Provider `10.0.0.0` under `C:\Program Files\PowerShell\7`. Its loaded-assembly list did not contain UIAutomationClientSideProviders. That proves neither absence of the file on disk nor the reason automatic loading failed.

Receipt: `/private/tmp/foldersail-34686746954-attempt2-review/Consumer/installation-result.json`, 217587 bytes, SHA-256 `85ca61d9ccc83dcb9de766717b26cad3b7063c371ae1c240d5547a08fa76c0c3`. Screenshot: the adjacent `consumer-save-picker-failure.png`. Only the small metadata artifact was downloaded.

## Source-backed correction

Microsoft documents that standard Win32 controls need client-side proxies for full UIA semantics; without a proxy, only basic HWND properties are available. The public `ClientSettings.RegisterClientSideProviderAssembly` API registers a provider table in the calling client process. Exact .NET WPF `v10.0.11` source establishes the matching-version default assembly and its native Edit/Button provider entries:

- [Client-side providers](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-clientsideprovider)
- [RegisterClientSideProviderAssembly](https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.clientsettings.registerclientsideproviderassembly?view=windowsdesktop-10.0)
- [ProxyManager v10.0.11](https://github.com/dotnet/wpf/blob/v10.0.11/src/Microsoft.DotNet.Wpf/src/UIAutomation/UIAutomationClient/MS/Internal/Automation/ProxyManager.cs)
- [Standard provider table v10.0.11](https://github.com/dotnet/wpf/blob/v10.0.11/src/Microsoft.DotNet.Wpf/src/UIAutomation/UIAutomationClientSideProviders/MS/Internal/AutomationProxies/Main.cs)

The candidate permits only `UIAutomationClientSideProviders.dll` beside the loaded UIAutomationClient in the exact current `$PSHOME`. Both files must be regular, bounded, have no reparse ancestors, remain hash-stable, have assembly version `10.0.0.0`, neutral culture, Microsoft token `31bf3856ad364e35`, valid Microsoft Authenticode signatures, and Microsoft company metadata. The actual file/hash/signature and host version are recorded. Missing files fail before fixture build or registration. There is no alternate directory/version/GAC scan or dependency download. Registration uses the framework's own `UIAutomationClientsideProviders` spelling, including the lower-case namespace component required for its public table lookup.

A separate pure-BCL fixture DLL, generated with existing locked CsWin32 `0.3.298` and SDK `10.0.401`, creates real standard Win32 Edit/Button controls in a fresh same-host PowerShell STA child. No UIA server provider is supplied by the fixture. The child is bound to its retained handle, executable, PID, nonce, and exact HWNDs. The parent records loaded provider identities before registration, then registers before creating/querying fresh fixture HWNDs so cached HWND-only fallback objects do not obscure the support check. It records actual fresh control support, rechecks ownership, visibility, enabled state and foreground before actions, requires actual typed editable ValuePattern and InvokePattern, writes one nonce value, reads it back, and invokes once. The child independently reads native Edit text and its actual button notification, then destroys its window and exits. Acceptance requires exactly one invocation, the exact native value, no timeout/error, exit zero and no residual HWND. The fixture times out after 30 seconds; parent readiness/exit/cleanup waits are bounded. Failure cleanup targets only the retained child and records any forced termination or secondary error. Fixture binaries are never uploaded.

The diagnostic has `consumer_acceptance:false`. Consumer qualification repeats the live preflight in its own installer host before certificate/trust/package mutation; it cannot inherit success merely from an earlier diagnostic file. Existing installed source/package/module checks, owned native picker selection, Value/Invoke action gates, exact persisted receipt/CSV validation, normal app close, uninstall and cleanup are unchanged. No workaround keys or fabricated provider support were added.

## Short Windows dispatch and limits

Workflow `windows.yml` accepts `uia_proxy_diagnostic_only=true`. That selects only the ten-minute `Native Win32 UIA proxy diagnostic` job on the exact existing `windows-2025-vs2026` image and current `pwsh` host; both app build jobs are skipped. It uses the existing pinned checkout/setup-dotnet actions. Artifact `FolderSail-Win32-UIA-proxy-diagnostic` contains only `uia-proxy-preflight.json`. With the default false input, Consumer also runs this preflight before vendor restoration and the expensive application build.

Root should inspect `proxy.proxy_file`, the verified `proxy.client`/`proxy.proxy`, `loaded_providers_before_registration`/`after`, and the independent `fixture.result`, exit and cleanup fields. A passing fixture establishes only this client's standard Win32 provider support. The actual FolderSail Save picker and complete consumer flow still must pass on Windows.

If the exact PSHOME provider is absent, the candidate records the path and fails. The source-backed alternative is a dedicated OS Windows PowerShell 5.1/.NET Framework picker client, whose proxy table belongs to that process, as already used for Wave's UIA host. That would need its own exact OS assembly/process provenance, the same real Win32 fixture, bounded IPC and owner rechecks around the actual picker Value/Invoke actions. It is not an automatic fallback and is not implemented here. There is no claim yet about why this PS7 host failed automatic proxy loading.

## Local verification and review

- Existing packaging suite: 36 tests passed with the local pinned SDK.
- 24 isolated PowerShell invocations passed, including all seven installer failure scenarios, existing input/receipt/picker/module/runtime/manifest checks, and the new proxy tests.
- New tests include 22 identity/native-result cases, 23 ready/control-semantic cases, the actual missing-current-host loader boundary, the production locked fixture build, and post-build file mutation rejection.
- All 38 PowerShell scripts parsed. Final changed fixture tests and parse were rerun after review adjustments.
- Working text is CRLF; C# uses repository tab indentation. Product source, existing picker/action gates, immutable Store identity, branding, source notices and runtime dependencies were not changed.

Local tools: `.tools/powershell-7.6.6/pwsh` and `.tools/dotnet-10.0.401/dotnet` under this nested source repository. Logs: `/private/tmp/foldersail-uia-proxy-research/{python-tests,powershell-tests,fixture-final-tests,parse}.log`. An initial unconfigured Python run selected the system .NET 8 SDK and failed five SDK-resolution checks; rerunning with `FILEQUAY_DOTNET` set to the already-installed exact 10.0.401 SDK passed all 36. The native fixture builds locally, but Win32 execution/registration cannot be claimed from macOS.

Root independent review and explicit Windows dispatch remain required. No push, workflow dispatch, Store action, site change or parent status edit was performed.

## Exact Windows token correction

Diagnostic run34689919450 reached identity inspection on Windows before any
fixture registration or input. Both assemblies are present under the current
PSHOME, Microsoft Authenticode signatures Valid, version10.0.0.0. The actual
UIAutomationClient is signed with strong-name token31bf3856ad364e35; the actual
UIAutomationClientSideProviders uses tokenb77a5c561934e089. The initial candidate
incorrectly required the client token for both assemblies.

The assertion now requires the exact observed token for each assembly role.
Path, file/version/hash, neutral culture, company and Microsoft Authenticode
requirements are unchanged. No alternate assembly is accepted. The production
regression failed before this correction and now passes24 cases, including both
swapped-token refusals. The previous22-case fixture had repeated the incorrect
same-token assumption; it has been corrected to use the actual distinct values.
A fresh short Windows diagnostic must still establish registration and actions.

Retained actual files: UIAutomationClient407336 bytes, SHA-256
be8e03688f1c1158b6a1a9b091ca864d9e7f338390537d71a1080f8a454bb2e4;
UIAutomationClientSideProviders857896 bytes, SHA-256
c60be0bba0652ff58fb38db1b0535e4bb9f6bd8bf035e56d89b7d87690963f19.
The complete metadata receipt is retained under
/private/tmp/foldersail-34689919450-review/FolderSail-Win32-UIA-proxy-diagnostic.

## Registration exception trace (diagnostics only)

Run `34690270201`, public source
`32ca2fefa9b9ffae4753b54cd9d822042d5dcd31` (local `7fb62256`), passed both
exact assembly identity checks with the same hashes/sizes recorded above. Host
PowerShell 7.6.5 reports .NET 10.0.11. The loaded-provider list was empty before
registration. The original public registration call threw a wrapped
NullReferenceException; `registered:false`, `passed:false`, and
`consumer_acceptance:false` remained correct. No fixture child was started and
cleanup errors are empty. The 4,066-byte receipt SHA-256 is
`4bbe621a2e194cb94624fe9f7fe1ebbb41d952416d4017ecb8cea09460e83421`.
The actual receipt retains only the outer exception's
Message, so it does not establish the failing framework method or stack frame.

The exact WPF v10.0.11 `ProxyManager.LoadDefaultProxies` source linked above
walks caller frames and dereferences `MethodBase.ReflectedType.Assembly` without
a null check (lines 309–315). A PowerShell dynamic method can lack that reflected
type, making this a plausible explanation. It is not yet a proven diagnosis of
this actual run. No typed shim, alternate assembly, framework-private mutation,
retry, or provider fallback is introduced in this diagnostic candidate.

`Register-FileQuayUiaProxy` now records the unchanged public API route and exact
assembly-name argument. If that call fails, it captures the original ErrorRecord
before the outer preflight reduces it to its Message: full Exception.ToString
(up to 32,768 characters), script stack (8,192), error ID (1,024), and up to eight
inner exceptions with type/HResult/message (4,096)/stack (16,384). Each bounded
text reports its original length and explicit truncation; chain truncation is
also explicit. A trace formatting error is recorded separately (4,096-character
bound), and the original registration refusal is rethrown. There is one call,
no replay, and no change to original Win32 fixture, ownership, input, cleanup, or
consumer acceptance requirements.

Inspect `proxy.registration_exception.exception_text.text` and
`proxy.registration_exception.chain` in the next short diagnostic artifact. Only
if the actual stack confirms the default-loader dynamic-frame defect should a
source-owned compiled, non-inlined typed caller of the same public API be tested
in a subsequent fresh host. A process that already attempted default registration
must not be treated as an equivalent fresh first-call test.

The existing `test-uia-proxy.ps1` now executes the production registration
boundary with a deliberately failing compiled C# public-API double. Its real
inner NullReference stack and PowerShell stack survive JSON; an oversized deep
exception verifies bounds; a diagnostic ToString failure preserves the primary
refusal with exactly one call per attempt. It reuses a read-only already loaded
host assembly only for this loader-boundary replay and does not load a foreign
provider. All original 24 identity/result cases also pass. Additional focused
checks: 23 real-pattern policy cases, absent-host refusal, production locked
Win32 fixture build/hash-tamper refusal using `.tools/dotnet-10.0.401/dotnet`, and
the actual installer `ProxyFailure` scenario. No native registration/UI success
is claimed from local macOS verification.
