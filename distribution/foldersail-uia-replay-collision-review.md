# UIA replay assembly identity

Both jobs in run 34697326490 (public source
16d39154c6b2894c60c6772c619856b263962b4d) passed 43 Python packaging tests,
the repaired 17-scenario receipt collision replay, and 24 proxy identity/result
policy cases. Instrumented failed at 13:48:41Z and Consumer at 13:49:08Z in
test-uia-proxy.ps1:109: the real Microsoft ClientSettings type has no fixture
Calls field. Neither job reached the new packaged SDK gate or application
build/install. This is a harness failure, not a native product or SDK result.

The original failed log is /private/tmp/foldersail-34697326490-failed.log;
Consumer metadata is /private/tmp/foldersail-34697326490-review. The artifact
sizes were 7,940 bytes (Instrumented) and 10,979 bytes (Consumer).

## Concrete reproductions and repair

Preloading an independently emitted System.Windows.Automation.ClientSettings
class reproduced the exact Calls-property failure locally. The test now retains
the Assembly returned by LoadFromStream, obtains ClientSettings from that exact
assembly, and uses that Type for counters and the direct PowerShell-call replay.
The original production C# shim still compiles against the supplied client
assembly; its source/hash/reference/NoInlining and failure evidence checks stay
unchanged. The real dynamic-frame failure, typed-caller recovery, original
exception retention and three binding-drift refusals still execute.

An audit of remaining fake types reproduced four further collisions before any
fixture changes:

- Proxy fixture: ValuePattern.Current missing.
- Picker input: ValuePattern.Current missing.
- Picker scope: AutomationElement.Roots missing.
- Picker diagnostics: AutomationProperty.LookupById missing.

Each now defines a unique replay namespace and changes only bracketed UIA type
references in its in-memory production script. The original action, selector,
policy and observation logic is executed with the same scenario assertions.
No production helper, C# source, package, UI input or ownership gate is modified.
The sole fake Microsoft-named client class remains necessary for the compiled
public API shim test, with all observations explicitly assembly-bound.

Every affected test preloads the colliding Microsoft-qualified types. On Windows
these come from the real PSHOME UIAutomationClient/UIAutomationTypes assemblies.
On this non-Windows host they come from a separate emitted assembly, allowing
reliable collision regression without claiming native UIA behavior.

## Fresh verification

Using .tools/powershell-7.6.6/pwsh with TMPDIR=/private/tmp, the affected tests pass:

- test-uia-proxy.ps1: 24 policy cases, actual compiled exception/stack replay and
  all three exact caller-binding refusals.
- test-uia-proxy-fixture.ps1: 23 policy cases, missing-host-provider refusal, actual
  pinned SDK/lock/source fixture build and post-build byte mutation rejection.
- test-consumer-picker-input.ps1: 25 sequencing/refusal cases.
- test-consumer-picker-scope.ps1: all 39 discovery and selector cases.
- test-consumer-picker-diagnostics.ps1: 59 observation/refusal cases.
- test-consumer-receipt-scroll.ps1: all 17 existing collision scenarios.

For the fixture build, FILEQUAY_DOTNET points to
$PWD/.tools/dotnet-10.0.401/dotnet. The original sources with a colliding preload
failed before their repairs; the corrected versions pass with preload retained.
The local emitted-class branch is not a Windows lifecycle result. Fresh native
Windows qualification, including the stable SDK package gate and full Consumer
workflow, remains required.
