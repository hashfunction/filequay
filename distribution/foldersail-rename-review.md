# FolderSail 1.0.1 source rename review

Prepared on 2026-09-12, separately atop the owned-picker repair `a3f8f465df5ff5bb954c1016c137111a08648ee8`. This report covers the source rename and local verification. It does not qualify a renamed Windows package or provide renamed native screenshots.

## Changes

- Current application and shell display strings, splash label, final window titles, Git dialog title, startup errors and suggested CSV filename use FolderSail. All 49 locale resource sets retain their keys; 700 product-name values change without modifying other translations.
- Main managed assembly/apphost are `FolderSail.dll` and `FolderSail.exe`. App version is `1.0.1`; managed assembly/file and package versions are `1.0.1.0`. Process discovery, launch argument recognition, app-owned association recognition, trimming roots, packaged/installed payload checks, exact window expectations and cleanup paths follow those names.
- Current README, app links and source inventory generator use `https://foldersail.trieflow.com`, with `/privacy` and `/support`. Own package notices and icon notice use FolderSail. The current resource inventory changes only the renamed icon notice's SHA256, using the same CRLF convention as its previous row.
- Workflow and downloadable qualification metadata names are `FolderSail-Windows-<build kind>-qualification`; newly generated source archives and the owned temporary signed copy use FolderSail. The existing internal MSBuild `Files.App` project/package staging layout remains so the native dependency directory is unchanged. Public binaries remain absent from this workflow's artifact selection.

## Preserved contracts

The assigned Store identity remains `1659hashfunction.FileQuay`; publisher identity is not changed or inferred. This source still requires explicit owned identity/publisher packaging inputs rather than embedding a Store identity. Its disposable native qualification remains `Trieflow.FileQuay.Qualification` / `CN=FileQuay-CI-Qualification`. Application ID stays `App`; package identity/version, exact installed bytes, process package ownership, native module provenance and certificate cleanup checks retain their existing scope.

The registered/called `filequay:` protocol, `FilesMainWindow` persistence ID, `Software\Trieflow LLC\FileQuay\<package>\v1\AppInformation` registry path, `FileQuay-<package>-Instance` semaphore names, Git credential namespace, package LocalState, `OperationReceipts/v1.json` schema and `.filequay-original` recovery suffix stay unchanged. Existing user paths containing the old brand are data, not replacement targets. Internal namespaces, helper/flag names, source/build filenames, COM server identity and asset resource paths retain compatibility. Existing Files upstream attributions, SQLite/native dependency pins and licenses, icon pixel/vector assets, historical reviews, prior SPDX inventory and prior Windows screenshots remain unchanged.

The picker implementation and failure diagnostics from the preceding repair are byte-equivalent after line-ending normalization. The same actual Copy/Move, persisted receipt inspection, explicit export/cancel/replace recovery, clear-history, normal close and owned uninstall/cleanup predicates remain mandatory. Neither an instrumented build nor local tests substitute for the ordinary installed Consumer flow.

## Verification

- Regression before implementation: the new current-brand manifest test failed on the old default name/version; the renamed positive payload fixture failed because production required `FileQuay.exe`. Both pass after the source changes.
- 36 Python packaging tests pass, including a complete renamed self-contained payload, refusal of the old manifest executable even when a renamed payload exists, missing renamed managed DLL rejection, exact runtime/dependency asset checks and native license/hash fixtures.
- 30 production receipt tests pass, including a new fixed pre-rename v1 document loaded without rewriting its bytes. Append/reopen/export preserve the original record ID, original Unicode paths and totals. Existing cancellation, concurrency, corruption, recovery, substitution and protected-history tests remain passing.
- 20 isolated PowerShell test invocations pass: manifest, generated native adapter ABI/guard fixture, consumer observation/toolbar/workflow/diagnostics/picker scopes, installation ownership, managed PE build-kind classification, real local process-exit observation, record publication, runtime comparison and all six actual installer failure-path scenarios. The picker scope fixture still has 35 checks, including foreign broker and ambiguous filename refusal.
- 31 PowerShell scripts parse successfully. MSBuild property evaluation of the actual main project resolves `AssemblyName=FolderSail`, `RootNamespace=Files.App`, `Version=1.0.1`, `AssemblyVersion=FileVersion=1.0.1.0` and the retained icon resource.
- All 49 locale resource key/value sets were compared against the preceding commit; only intended product-name substitutions occurred. Changed text uses CRLF, and `git diff --check` passes.

Reproduction from the nested source root:

```sh
FILEQUAY_DOTNET="$PWD/.tools/dotnet-10.0.401/dotnet" python3 -m unittest discover -s tests/packaging -p 'test_*.py' -v
.tools/dotnet-10.0.401/dotnet test --project tests/Files.App.UnitTests/Files.App.UnitTests.csproj -c Release --no-restore
.tools/powershell-7.6.6/pwsh -NoProfile -File distribution/test-manifest.ps1
```

Run each `tests/packaging/test-*.ps1` in a fresh PowerShell process, with `FILEQUAY_DOTNET` set to that exact SDK; pass its absolute path as `-DotNet` to `test-consumer-adapter.ps1`. Run installer failure tests separately for InstallationAndCleanup, PreinstalledFramework, FailedAddRace, PackageChanged, ReportingFailure and AdapterFailure. Logs retained locally at `/private/tmp/foldersail-python-tests.log`, `/private/tmp/foldersail-unit-tests.log`, `/private/tmp/foldersail-powershell-tests.log` and `/private/tmp/foldersail-msbuild-properties.log`.

## Pending native evidence

This macOS check does not compile or execute the renamed WinUI application, test a Store upgrade, validate MSIX installation or claim consumer screenshots. After independent source review, run both native Windows matrix jobs on the exact committed/public source. Require the complete ordinary Consumer workflow, owned cleanup and actual FolderSail title/pixels; retain any failed picker evidence. No Store submission, site edit, parent release-status edit or public push was performed for this source change.
