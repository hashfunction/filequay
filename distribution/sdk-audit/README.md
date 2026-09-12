# FolderSail release Windows projection

FolderSail now pins `Microsoft.Windows.SDK.NET.Ref` **10.0.26100.70**. The previous
10.0.26100.67-preview package points to Microsoft's pre-release SDK license.
The selected release points to the release SDK license, whose Distributable Code
terms refer to the official redist list. That list expressly covers this package's
`lib/net8.0/Microsoft.Windows.SDK.NET.dll` and `WinRT.Runtime.dll` when distributed
as part of a program, subject to those terms. This does not label the projection
as MIT or grant rights beyond the Microsoft terms.

Primary records: [release terms](https://aka.ms/WinSDKLicenseURL),
[redist list](https://learn.microsoft.com/en-us/legal/windows-sdk/redist), and
[Microsoft's projection/runtime distinction](https://github.com/microsoft/WindowsAppSDK/discussions/4368).
`windows-sdk-release.json` records exact original archive and retrieved terms
lengths/SHA-256, immutable version URLs, module hashes and the comparison result.
The changing license/redist URLs are dated observations, not immutable archives.

## Compatibility evidence

Both packages target net8.0. WinRT.Runtime.dll and WinRT.SourceGenerator.dll are
byte-identical. The SDK projection assembly changes from 10.0.26100.59 to
10.0.26100.69; its informational version identifies the same projection source
commit `9488666cdb6ac39f750be188c48d59a9f682549c`. The net6.0 package 10.0.26100.69
was not selected because it changes WinRT.Runtime assembly identity to 2.1.0.0.
The chosen net8.0 package retains 2.2.0.0.

The executable metadata comparison retains all 121,216 inspected public/protected
signatures and adds 522. It decodes type, method and field signatures; it does not
compare every custom attribute, generic constraint or implementation. No native
Windows compatibility claim follows from these static results.

```powershell
./distribution/sdk-audit/compare-api.ps1 -BeforeArchive <original-preview.nupkg> -AfterArchive <original-release.nupkg>
```

The comparison checks both original archive SHA-256 values before reading their
PE metadata. It does not load or execute their managed code. Both original
archives remain in the local audit cache outside the repository.

## Required native evidence

The ordinary qualification pipeline now verifies the exact restored release
NuGet archive and the actual packaged FolderSail.deps.json after SDK unpacking,
writing windows-sdk-package.json. Preview, other release, missing/conflicting
runtime packs and mismatched projection/runtime assembly records fail. The final
Store exporter must use this same source-and-package validation on the retained
MSIX, in addition to all source, package and installed lifecycle gates.

No current native run or earlier qualification is reclassified. A fresh build,
Consumer and Instrumented installed workflows, and the later assigned Store
lifecycle remain required. No UI, identity or input/cleanup policy changes.

## Local verification

The initial pin regression failed against 10.0.26100.67-preview before the change.
Focused Python tests exercise the actual source pin and shared package validator,
including preview/stale source and package mismatches. The real original NuGet
archives are also checked by the metadata comparison. These are local checks;
Windows compilation and installed execution remain pending.

Verified on 2026-09-12: all 43 Python packaging tests pass using the repository's
.NET 10.0.401 on PATH; seven are the focused SDK tests. The first broader run
used the host's .NET 8 and failed five unrelated SDK-resolution fixtures, then
passed after selecting the pinned runtime. The committed PE comparison reproduced
121,216 retained signatures and 522 additions. The production CLI accepted the
exact original 10,639,646-byte NuGet archive with synthetic deps metadata in a
local fixture, and refused altered archive bytes and preview metadata without
writing a receipt. Synthetic metadata is not installed package evidence.
