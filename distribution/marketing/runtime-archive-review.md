# FolderSail capture Runtime archive hash repair

Screenshot-only run `35701462462`, source `42ac57d7fed1e3bb04c02f409aeee0874e956d8a`, passed capture tests and all original app package/lifecycle verification. It failed before app installation or pixels at `prepare_capture.py:62`: `Original Runtime NuGet bytes differ`. The code compared the whole signed NuGet ZIP's SHA512 with `packages.lock.json`'s `contentHash`.

NuGet defines those differently. Its [PackageArchiveReader](https://source.dot.net/NuGet.Packaging/PackageArchiveReader.cs.html) calls the [signed-archive content hashing implementation](https://source.dot.net/NuGet.Packaging/Signing/Archive/SignedPackageArchiveUtility.cs.html), which computes the package content excluding the signing entry. An unsigned archive can share its whole-file hash with its content hash; that assumption is invalid for the actual signed Windows App Runtime package.

The existing Runtime 2.4.0 archive was checked with the actual NuGet reader bundled with SDK 10.0.401, `NuGet.Packaging, Version=7.9.0.0`. `GetContentHash` returns exactly the qualified application lock's value:

`ioljT2/zivSWb6Hc375VPrRrauE5O49OccruHQFI23NdwGERCFBgCr1qCYhFciTxAX9hOMkJeAx0/Wo6Z5y6eg==`

The signed ZIP is 164053946 bytes, SHA256 `93f48b096416ab7b908ea30690bba47de8264cd2f22dd7b0ad97187a86d00120`, whole-file SHA512:

`esr1+QzXU0mA0yCUO8rnQ7ok4dUpTFiFTaRbZgDic/UMFrhrNd09CBiUYaO/M0z7FDon7wqa1CFoMBsPn9QHJQ==`

Anonymous HTTPS streaming readback of the current fixed NuGet URL matched those bytes/hashes exactly. No duplicate archive was retained. The local Python trust bundle initially refused TLS; system curl then verified TLS with its system trust store, without disabling certificate verification, credentials or redirects.

`runtime-archive.json` now records this explicit reviewed archive pin, the distinct qualified content hash, reader observation and public readback. Capture requires the fixed package/version/URL and original lock hash to agree, checks the downloaded archive's exact size/SHA256, uses the correct whole-file SHA512 in the existing extractor, then rechecks archive bytes. The existing exact framework member hash and manifest identity/dependency checks remain unchanged. No app binary, original qualified binding or native input/lifecycle gate changed, and no new hash parser/runtime tool is added.

Focused verification:

- The production preparation regression first reproduced the original SHA512 refusal, then passed with separate content and archive hashes. Four mutations reject changed content hash, archive SHA256, archive SHA512, or original framework member hash before writing the framework output.
- All four preparation/extraction tests pass, including existing malformed ZIP and duplicate/foreign archive guards.
- The actual production `prepare_framework` completed using the existing real signed archive and original qualified Store MSIX/receipt. It extracted `tools/MSIX/win10-x64/Microsoft.WindowsAppRuntime.2.msix`, 46787781 bytes, SHA256 `a3ce5b76713133dfd3b378e81c43a89954c664fcd70fd0c070e409ed3de03ebf`, and passed the original framework identity/dependency matcher. Only the network read was replaced with the already independently verified same archive stream for this local replay.
- Whitespace checks pass. No application rebuild or broad test suite was repeated.

Original failure and proof files remain under `/private/tmp/foldersail-capture-35701462462-review/`: `capture-job.log`, `runtime-content-hash.json`, `runtime-public-readback.json`, and `framework-replay/framework-verification.json`. The replay retains the original extracted framework; the app MSIX is a read-only hardlink to the independently verified original.

A fresh actual Windows screenshot-only run remains required. No image or successful capture/cleanup is claimed from the failed run. The already qualified/submitted Store app package is unchanged.
