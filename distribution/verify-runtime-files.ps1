# Copyright (c) Trieflow LLC. Licensed under the MIT License.
function Test-FileQuayRuntimeFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$RuntimeVersion,
        [Parameter(Mandatory)][string[]]$PackageFolders
    )
    $packId = 'Microsoft.NETCore.App.Runtime.win-x64'
    $pack = $null
    foreach ($folder in $PackageFolders) {
        $candidate = Join-Path $folder ($packId.ToLowerInvariant() + '/' + $RuntimeVersion)
        if (Test-Path -LiteralPath $candidate -PathType Container) { $pack = $candidate; break }
    }
    if (-not $pack) { throw "Restored runtime pack is unavailable: $packId/$RuntimeVersion. Restore the exact package before verification." }
    $packageHashPath = Join-Path $pack ($packId.ToLowerInvariant() + '.' + $RuntimeVersion + '.nupkg.sha512')
    if (-not (Test-Path -LiteralPath $packageHashPath -PathType Leaf)) { throw "Restored runtime package hash is unavailable: $packageHashPath" }
    $packageHash = (Get-Content -LiteralPath $packageHashPath -Raw).Trim()
    foreach ($directory in @('', 'Files.App.Server')) {
        foreach ($name in @('coreclr.dll', 'clrjit.dll', 'hostfxr.dll', 'hostpolicy.dll')) {
            $relative = if ($directory) { $directory + '/' + $name } else { $name }
            $binaryPath = Join-Path $PackageRoot $relative
            $referencePath = Join-Path $pack ('runtimes/win-x64/native/' + $name)
            if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) { throw "Required runtime binary is missing: $relative" }
            if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) { throw "Restored runtime pack binary is missing: $referencePath" }
            $actualHash = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash
            $expectedHash = (Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) { throw "Packaged runtime $relative differs from the restored runtime pack $packId/$RuntimeVersion." }
            # CoreCLR product resources use a build-number format, not the runtime's semantic version.
            [ordered]@{
                path = $relative
                product_version = (Get-Item -LiteralPath $binaryPath).VersionInfo.ProductVersion
                sha256 = $actualHash
                runtime_pack = $packId
                runtime_pack_version = $RuntimeVersion
                runtime_pack_sha256 = $expectedHash
                runtime_pack_nupkg_sha512 = $packageHash
            }
        }
    }
}
