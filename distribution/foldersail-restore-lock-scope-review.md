# FolderSail solution restore lock-file scope

The first available original checkpoint from run `34729579948`, public source `a41c2f2d20dc08658df96f3592bd048a9d7ad4e0`, identifies the source writer before Store export. Instrumented job `103649771674` passed. Its `after-build` observation at 01:16:47 UTC and `after-installation` observation at 01:17:35 UTC have the same eleven untracked files, no tracked diff, no truncation and no diagnostic errors:

- `src/Files.App.BackgroundTasks/packages.lock.json`
- `src/Files.App.Controls/packages.lock.json`
- `src/Files.App.CsWin32/packages.lock.json`
- `src/Files.App.Server/packages.lock.json`
- `src/Files.App.Storage/packages.lock.json`
- `src/Files.Core.SourceGenerator/packages.lock.json`
- `src/Files.Core.Storage/packages.lock.json`
- `src/Files.Shared/packages.lock.json`
- `tests/Files.App.UITests/packages.lock.json`
- `tests/Files.App.UnitTests/packages.lock.json`
- `tests/Files.InteractionTests/packages.lock.json`

The original log remains `/private/tmp/foldersail-34729579948-review/job-103649771674.log`. Monitoring stopped after this decisive checkpoint; no final qualification or export is claimed for that run.

Both source build entry points passed `RestorePackagesWithLockFile=true` globally to solution Restore, which opts every referenced PackageReference project into writing a lock. Removing only that global argument leaves the existing app/SQLite scoped declaration and native/Win32 fixture declarations unchanged. All four tracked lock files remain unchanged. No ignored paths, generated-file deletion, dependency/version edits, UI behavior or final source-clean gate changes are introduced.

[Microsoft's NuGet documentation](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files#enabling-the-lock-file) documents project-root generation when opted in and continued use of an existing lock even without the command-line property. It also explains that a referenced library's lock does not determine the consuming application's resolved closure.

Focused local verification with the pinned `.tools/dotnet-10.0.401/dotnet` SDK:

- The real NuGet/MSBuild regression first reproduced unowned library lock creation with both original production solution-restore command lines. The repaired commands pass.
- The fixture imports the original `FileQuay.SQLite.props` opt-in into an application referencing a library, using a tiny offline owned NuGet feed and no native compilation. An existing application lock stays byte-for-byte identical and resolves 1.0.1 after a lower matching 1.0.0 becomes available; the unlocked library resolves 1.0.0 without creating a source lock. Only the fixture disables unrelated ReadyToRun acquisition.
- Actual MSBuild `-getProperty:RestorePackagesWithLockFile` returns `true` for `Files.App`, `Files.SQLiteQualification`, `Files.Qualification.Native`, and `Files.Qualification.Win32Controls`; their original tracked locks are unchanged.
- All six exporter cases pass, including exact clean-source refusal, lifecycle/package/source checks and bounded diagnostics. Whitespace verification passes.

Fresh native qualification and final export remain required. The observed transient Store input refusal from run `34727745434` has no inferred UI repair; its unchanged guard now retains rejected state if it recurs.
