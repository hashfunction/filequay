# SQLite dependency qualification

FileQuay's application and `tests/Files.SQLiteQualification` import the same
`FileQuay.SQLite.props`. It retains Microsoft.Data.Sqlite.Core **10.0.2** and
replaces retired SQLitePCLRaw.bundle_green 2.1.11 with exact
SQLitePCLRaw.config.e_sqlite3 **3.0.5** and native SQLite **3.53.4**. Raw core and
the provider resolve to 3.0.5. Both existing `Batteries_V2.Init()` calls remain.
The app and SQL host have generated NuGet lock files; use locked restore during
qualification. No existing database is migrated or rewritten by this change.

[The advisory](https://github.com/advisories/GHSA-2m69-gcr7-jv3q) identifies
SQLite before 3.50.2 as affected. Its June 18, 2026 "no patched version" field
predates later packages. Green itself still ends at 2.1.11; the current
[upstream 3.0.5 bundle](https://www.nuget.org/packages/SQLitePCLRaw.bundle_e_sqlite3/3.0.5)
uses native package ID `SQLite`, which is the explicitly pinned selection here.

## Evidence and source

`sqlite-dependencies.lock.json` pins five NuGet archives, their NuGet content
hashes, the exact Windows managed/native asset paths and SHA-256 hashes, the
native version/source ID, and the corresponding source-archive URLs/hashes.
NuGet's content hash is read from resolved assets; it is distinct from the
signed archive's hash. `verify-sqlite-assets.py` requires the exact Windows graph
and matching cache bytes. When supplied a package root, it also requires one
copy of each pinned DLL at the package root, its exact bytes, all original
notices and the matching dependency record. It never claims native execution.

The original Apache-2.0 license and NOTICE from the pinned raw source, SQLite's
public-domain declaration from the native package, and this dependency record
are included under `Licenses/SQLite` in output. Native version 3.53.4/source ID
`bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc` match the
[official release](https://sqlite.org/releaselog/3_53_4.html). The full source's
`manifest.uuid` and the amalgamation's published SHA3-256 were independently
checked. Preserve these source archives in release evidence using the exact
URLs/hashes; no floating Git tag or unverified replacement is accepted.

**Vendor native-build provenance remains open.** The public NuGet package
contains no native build recipe, and its compiler/flags-to-binary chain was not
reproduced. Corresponding-source identity and file hashes do not close that
separate gate. The package is not cleared for Store release by these checks.

## ReadyToRun byte preservation

The four managed SQLite assemblies remain IL and are JIT compiled so their
NuGet hashes can be checked in the package. Ordinary R2R uses the documented
exclusion list. In pinned SDK 10.0.401, composite R2R explicitly ignores that
list. The narrow `PreserveFileQuaySQLiteAssemblyBytes` target therefore marks
only these four resolved files `ReferenceOnly` before the R2R preparation
step. They remain available as compiler references without being rewritten.
Other application assemblies retain the existing R2R policy.

This behavior was verified against the
[exact SDK task source](https://github.com/dotnet/sdk/blob/v10.0.401/src/Tasks/Microsoft.NET.Build.Tasks/PrepareForReadyToRunCompilation.cs)
and a real composite-R2R publication: the documented list alone changed bytes;
the scoped metadata preserved all four input hashes and the resulting SQL
host passed. Requalify this hook when changing SDK versions, and enforce the
final Windows file hashes rather than assuming the hook still works.

## Commands

Use the pinned SDK and an isolated NuGet cache. The existing app restore needs
its Windows prerequisites and exact vendor-input bootstrap.

```powershell
dotnet restore src/Files.App/Files.App.csproj --locked-mode -p:Platform=x64 -p:Configuration=Release -p:EnableWindowsTargeting=true -p:PublishReadyToRun=true
dotnet restore tests/Files.SQLiteQualification/Files.SQLiteQualification.csproj --locked-mode
# Execute on Windows; real Windows-specific provider and native library.
dotnet run --project tests/Files.SQLiteQualification/Files.SQLiteQualification.csproj -f net10.0-windows10.0.26100.0 -c Release -r win-x64 --no-restore
python distribution/verify-sqlite-assets.py --assets src/Files.App/obj/project.assets.json --package-cache <NuGet-global-packages> --package-root <extracted-main-package> --output <sqlite-assets.json>
dotnet list tests/Files.SQLiteQualification/Files.SQLiteQualification.csproj package --vulnerable --include-transitive --format json --no-restore
```

On macOS arm64, run the SQL host with `-f net10.0` and no Windows RID. It uses
only owned temporary fixtures and deletes them after closing connections.
The host fails on an unexpected native version, source ID, module path or DLL
hash, then checks the application's actual SQL (embedded from the two detector
source files), Unicode values, parameter binding, asynchronous reads, managed
callbacks, rollback, read-only refusal, copied WAL/integrity and malformed-file
handling. Its JSON lists all 33 checks and the executed native module/hash.
It is not a WinUI/WinRT or complete cloud-detector test.

Cross-publication on macOS to `net10.0-windows10.0.26100.0/win-x64` selects the
Windows-specific managed provider and verifies all five output hashes/notices.
It cannot establish successful Windows loading or app installation. Run the
same checks on the installed package's provider path, then the existing normal
startup, interaction and COM qualification.

## Current limits

The application restore and exact selected SQLite graph passed locally with no
NU190 audit entries. The SQL host's vulnerability query reported no vulnerable
packages. The full app's `dotnet list package --vulnerable` command on macOS
reported `Sequence contains no matching element`, including with an explicit
framework; that is an audit-tool failure, not a clean full-app report. Repeat
that audit on Windows. No Windows app, installed package, ARM64 device or Store
success is inferred from local tests. Existing cloud-database copy consistency
while another process writes the source is a separate behavior not changed by
this dependency migration.
