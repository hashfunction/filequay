# FileQuay installed-package qualification

`qualify-windows.ps1` builds with `FileQuayCIQualification=true`. This adds a probe
only to the instrumented CI executable and records that distinction in both build
and installation evidence. The final Store executable still requires its own
normal install/startup check; this run does not claim that check occurred.

The probe accepts only the exact package name `Trieflow.FileQuay.Qualification`,
publisher `CN=FileQuay-CI-Qualification`, and a fresh canonical GUID nonce. It runs
under the installed package identity and calls
`Server.AppInstanceMonitor.StartMonitor(Environment.ProcessId)` through the client
projection generated from `Files.App.Server.winmd`. It records the result/HRESULT,
holds its own process alive until released by the qualifier, and exits normally.
Ordinary startup remains separate and still must expose the main window and its
Status Center control while loading the root packaged CoreCLR.

The Windows installer verifies the activated client PID/path, exactly one server
under the installed package, the server's own packaged CoreCLR module, executable
and WinMD hashes, and server termination after the monitored client exits. The
natural-exit gate runs before forced cleanup. Bounded failures remain failures,
even if cleanup can subsequently terminate the owned processes. JSON, stdout,
stderr, available server diagnostics and module inventories are retained under
`artifacts/qualification`.

The manifest-to-archive verifier requires a Windows App Runtime framework
declaration because `WindowsAppSDKSelfContained=false`. Every declared framework
must have exactly one compatible supplied `.msix`/`.appx` whose own manifest has
the required Name, Publisher when declared, Version >= MinVersion, x64 or neutral
architecture, and Framework=true. Matching archives receive SHA-256 records.

`Test-CIInstallation.ps1` defaults to `-DependencyMode RequireClean`: any compatible
pre-existing registration fails before signing/installing. After installation,
the exact supplied framework tuple must be newly registered. An explicitly chosen
`AllowPreinstalled` run still validates every supplied artifact, but records only
dependency resolution against existing state, never proof of fresh framework
installation. The normal CI driver uses `RequireClean`.

Cleanup attempts all owned processes, package registration, both certificate
stores and the public certificate, retaining the original error and every cleanup
failure. Newly installed framework full names are recorded and retained until the
disposable runner is torn down. Such a run does not claim full environment cleanup.

The OOP server uses SDK-generated `Files.App.Server.runtimeconfig.json`.
`FileQuay.ServerRuntime.targets` corrects the hosted-DLL filename imposed by the
pinned C#/WinRT authoring targets before generation/publication; it does not create
a replacement runtimeconfig document. Existing exact .NET 10.0.12 runtime-pack
hash checks remain unchanged. The server registers its one manifest-declared
runtime class explicitly rather than discovering public classes by reflection.

Local qualification tests:

```text
python -m unittest discover -s tests/packaging -v
powershell -NoProfile -File tests/packaging/test-installation-helpers.ps1
powershell -NoProfile -File tests/packaging/test-installation-failures.ps1
powershell -NoProfile -File tests/packaging/test-installation-failures.ps1 -Scenario PreinstalledFramework
```

MSBuild tests require the pinned SDK and restored Microsoft.Windows.CsWinRT 2.2.0
authoring targets. `FILEQUAY_DOTNET` can select an isolated SDK host. The failure
replays use temporary archives and mocked native APIs; they do not install an app,
alter a certificate store, activate COM or open a window.

The SQLite provider remains an open shipping gate: the current
`SQLitePCLRaw.bundle_green` 2.1.11 resolves an affected native library. The
[reviewed advisory](https://github.com/advisories/GHSA-2m69-gcr7-jv3q) lists no patched
version of that legacy package and calls for SQLite >=3.50.2. A provider/native
distribution migration needs separate build, database compatibility and runtime
binary/source verification; this packaging repair does not suppress the warning.

### Attached-process exit evidence

Run34598100997 reached successful packaged StartMonitor activation and a client release receipt, then failed the combined exit condition. That report cannot distinguish timeout, nonzero exit, or an unavailable exit status. Qualification now retains each live client/server SafeHandle before release and records wait completion, numeric exit code and observation errors separately. Handles are disposed after owned-process cleanup. This preserves Windows exit information for PID-attached Process components; it does not make an otherwise failing process pass. See Microsoft's Process.WaitForExit documentation: https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.waitforexit?view=net-10.0 .

The actual-process regression attaches independently, disposes the launcher component, then verifies zero exit, exit7 and a live timeout. It runs both locally and on the Windows runner before the native app build. The exact installed-client/server retry remains authoritative; normal Store binary qualification is still pending.
