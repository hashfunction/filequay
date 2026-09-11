# FileQuay initial Windows qualification

Source baseline: Files v4.2.9, 99951c66928c4da714da8b1dd46039421182cbab.
Use Windows x64 with Visual Studio 2026/MSBuild and Windows SDK 26100 or newer,
matching the upstream Windows-2025/VS2026 workflow. The exact selected .NET SDK
is 10.0.102 with roll-forward disabled. The Windows App SDK is pinned 2.4.0.
The existing SDK reference is 10.0.26100.67-preview and language mode is preview;
these remain explicit qualification gates until a clean Windows restore/build
proves a compatible supported replacement. No installed Windows tool versions or
resolved NuGet transitive inventory are claimed from source inspection.

Removed the Satori.targets import: upstream downloaded an unpinned daily/latest
replacement CLR/JIT from files-community/Satori. FileQuay uses the official .NET
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
