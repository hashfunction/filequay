# FileQuay qualification adapter loading review

Windows run `34672454037` failed before the first consumer workflow action.
`ConsumerWorkflow.Ui.ps1` loaded the published `Files.App.CsWin32.dll` into
PowerShell. That DLL was a component of the customer's `FileQuay.r2r.dll`
composite image. CoreCLR terminated the host after comparing the composite's
`Microsoft.VisualBasic.Core` MVID with PowerShell's already loaded assembly:
`c585b51a-08cf-45ea-b303-c0eb61c6d047` versus
`5cde5ad0-c294-4106-9b95-5387bb893667`. The native termination bypassed PowerShell
catch/finally. The primary log is `/private/tmp/filequay-34672454037-failed.log`,
lines 2146–2148. This establishes a qualification-host loading defect; it does
not establish a product file-operation failure or success.

## Candidate

The baseline is source `b93c3ad18eb55fe6a597764aaab93f668c5f0ba4`.
`tests/Files.Qualification.Native` compiles the unchanged
`ConsumerWorkflow.Native.cs` together with its nine explicitly requested native
APIs and the generator's dependency closure. The requests must match the
adapter's actual calls and already exist in the customer CsWin32 inputs.
Generation uses the central `Microsoft.Windows.CsWin32` 0.3.298 pin, linked
customer `NativeMethods.json`, and the same build-task generation mode. The
committed NuGet lock includes transitive metadata/documentation inputs.

The project has no customer project or runtime reference. It targets the
repository's .NET framework version, emits the distinct
`FileQuay.Qualification.Native` identity and explicitly disables ReadyToRun,
composite publication and self-contained output for this helper alone.
Qualification builds it into a fresh work directory with the exact global SDK
and locked restore. It checks the resolved generator pin, hashes source inputs
before/after the build and rejects unexpected output DLLs.

Before CLR loading, the loader reads the actual PE metadata and requires ILOnly,
an empty managed-native directory, the exact helper identity/type and only
System framework references. It loads the same inspected byte array, preventing
replacement between inspection and loading. Existing helper identity/type
collisions are rejected. A retained assembly object and SHA256 bind the input
adapter used by the workflow to the installation record.

Consumer initialization now occurs before certificate creation, trust import,
signing or package installation. Consumer acceptance additionally requires
successful adapter preflight. The instrumented COM path is unchanged. Customer
composite ReadyToRun settings, native input ownership/foreground assertions,
Copy/Move/JSON/CSV validation, timeouts, normal-close requirements, uninstall and
fixture cleanup are unchanged. No workflow YAML or artifact payload expansion
is included; the adapter build lives outside uploaded metadata paths.

## Verification

- RED: the adapter fixture failed without its helper. The new actual-installer
  AdapterFailure case failed because no early adapter initialization occurred.
- GREEN: 28 adapter checks pass with a real locked source-generation build and
  actual IL load. They inspect the public adapter/generated API methods and
  INPUT ABI; reject managed-native-header and IL-flag mutations, a foreign
  AssemblyRef, malformed PE, wrong identity, duplicate load and changed binding.
- The actual installer AdapterFailure fixture records failure and an unchanged
  unsigned package while proving zero certificate/trust/install mutations.
  All five prior installer failure scenarios still pass.
- All 44 independent consumer workflow checks and 34 Python packaging tests pass.
  Existing registration/cleanup, build-kind acceptance (including missing-adapter
  refusal), consumer observation, exclusive publication, real managed metadata
  and actual process exit/cleanup fixtures pass. PowerShell AST parsing passes.
- macOS validation used the pinned .NET 10.0.401 and PowerShell 7.6.6 tools. One
  existing metadata-test invocation initially selected the machine's .NET 8;
  selecting the pinned SDK for that subprocess resolved the environment error.

No Windows native input was executed locally. Independent review and a fresh
Windows installed consumer run are still required to prove Copy/Move, receipt,
CSV, picker ownership and final cleanup behavior. No public push or release
status change was made by this candidate.
