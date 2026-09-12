# FolderSail initial Windows qualification

Source baseline: Files v4.2.9, 99951c66928c4da714da8b1dd46039421182cbab.
Use Windows x64 with Visual Studio 2026/MSBuild and Windows SDK 26100 or newer,
matching the upstream Windows-2025/VS2026 workflow. The exact selected .NET SDK
is 10.0.401 with roll-forward disabled; the bundled .NET/Windows Desktop runtime
is the exact 10.0.12 security patch published 2026-09-08. The Windows App SDK is pinned 2.4.0.
The existing SDK reference is 10.0.26100.67-preview and language mode is preview;
these remain explicit qualification gates until a clean Windows restore/build
proves a compatible supported replacement. No installed Windows tool versions or
resolved NuGet transitive inventory are claimed from source inspection.

Removed the Satori.targets import: upstream downloaded an unpinned daily/latest
replacement CLR/JIT from files-community/Satori. FolderSail uses the official .NET
runtime selected by the SDK and project. No build must fetch that runtime fork.

Run distribution/check-prerequisites.ps1 on Windows. Configure the manifest with
.github/scripts/Configure-AppxManifest.ps1 -Identity <owned-name> -Publisher <owned-CN>.
Missing inputs must fail. Do not invoke upstream CD workflows or upstream service
substitution/signing scripts. Root provisions public committed source snapshots
and Windows CI; release signing/Store identity and installation tests are separate.

Portable receipt tests link the exact receipt source and shared enum files into
a net10.0 library without WinUI. This is deliberate: the macOS host cannot load
WinUI or build native Windows projects. The application consumes the same source;
Windows is required to qualify its XAML, dispatcher and actual operation boundary.

## Compiler compatibility repair

Actual Windows run 34578836224 failed CS9057: the Files.Core.SourceGenerator analyzer referenced Microsoft.CodeAnalysis 5.9.0.0 but SDK 10.0.102/MSBuild supplied compiler 5.0.0.0. The generator APIs compiled against exact Microsoft.CodeAnalysis.CSharp and Workspaces.Common 5.0.0. Microsoft.CodeAnalysis.Analyzers 5.0.0 is not published; the observed available compatible 5.3.0 is pinned explicitly. No NuGet version fallback is accepted as a lock. Existing RS1038 warnings about Workspaces/code-fix references in a compiler-extension assembly remain documented; a local generator build is not evidence of Windows application compilation. Both application and COM-server imports of the unpinned Satori runtime replacement were removed.

## Consumer runtime and COM-server packaging repair

The earlier Windows qualification runs 34584168249 and 34584734410 compiled the
application and passed 29 portable core tests plus MakeAppx semantic unpacking.
Their package inventory nevertheless lacked coreclr/hostfxr and the manifest's
`Files.App.Server/Files.App.Server.exe`. A successful build/unpack did not prove
that a clean consumer machine could launch either owned executable.

`FileQuay.Runtime.props` now makes only the app and COM server self-contained,
with apphosts and separate publish files. `TargetLatestRuntimePatch=true` plus
the locked SDK selects 10.0.12. Do not set `RuntimeFrameworkVersion` globally: an
actual cross-publish probe showed that it incorrectly applied 10.0.12 to
`Microsoft.Windows.SDK.NET.Ref`, which has a different version scheme. Restore
and build must use the same Release/x64/ReadyToRun inputs. Other solution projects
remain libraries and must not receive a blanket SelfContained override.

`FileQuay.Server.targets` publishes the COM server before `AssignTargetPaths`
and assembly resolution, cleans only its dedicated obj staging directory, and
adds every published file under the manifest's `Files.App.Server/` directory.
It preserves satellite subdirectories and stops if executable/runtimeconfig/deps
are absent. Server trimming is disabled: the COM server uses reflection-based
registration, and this task does not establish trimming compatibility.

The Windows App SDK remains an MSIX framework dependency. The .NET SelfContained
property does not remove that separate installation prerequisite. Package
inspection records the actual manifest dependencies; installation qualification
must install the matching architecture dependencies and exercise app/COM startup.
Runtime and Windows Desktop licenses are copied from the exact runtime packs.
They also need inclusion in the final resolved SPDX/license audit.

The payload verifier requires both manifest-owned executable paths, x64 native
hosts, included-framework 10.0.12 configurations, exact runtime-pack dependency
entries, every declared managed/native/resource dependency file, and notices.
It compares both sets of coreclr/clrjit/hostfxr/hostpolicy bytes with the exact
restored Microsoft.NETCore.App.Runtime.win-x64/10.0.12 pack, recording SHA256,
NuGet package SHA512 and native ProductVersion metadata. CoreCLR's ProductVersion
is a build-number string, so it cannot be parsed as runtime semantic version.
An unavailable reference pack fails verification. This is payload inspection;
it deliberately records startup, installation and WACK as unverified.

Run `python -m unittest discover -s tests/packaging` and
`pwsh -NoProfile -File tests/packaging/test-runtime-files.ps1` before packaging.
The Python staging tests invoke the exact production MSBuild target using a
labeled fixture publisher. A separate real SDK 10.0.401 probe cross-published two
minimal Windows executables on macOS, including both 10.0.12 runtime payloads and
notices; it is not a FolderSail build, an MSIX or Windows execution.

Primary references: [Microsoft self-contained Windows deployment](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps),
[.NET runtime patch selection](https://learn.microsoft.com/en-us/dotnet/core/deploying/runtime-patch-selection),
and the [official .NET 10 release feed](https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json).
