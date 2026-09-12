# Copyright (c) Trieflow LLC. Licensed under the MIT License.
param([string]$PackagePath, [string]$Identity, [string]$Publisher, [string]$OutputDirectory,
      [ValidateSet('Qualification','Store')][string]$IdentityMode='Qualification',
      [ValidateSet('Consumer','Instrumented')][string]$BuildKind='Consumer')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Package validation requires Windows.' }
if (-not $PackagePath -or -not $Identity -or -not $Publisher -or -not $OutputDirectory) { throw 'PackagePath, Identity, Publisher and a fresh OutputDirectory are required.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Validation output directory must not already exist.' }
$makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" | Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
if (-not $makeappx) { throw 'MakeAppx from the Windows SDK is required.' }
# MakeAppx has no validate subcommand. Unpack without /nv performs its documented semantic checks.
& $makeappx.FullName unpack /p $PackagePath /d $OutputDirectory /v
if ($LASTEXITCODE -ne 0) { throw "MakeAppx validation/unpack failed: $LASTEXITCODE" }
[xml]$manifest = Get-Content -LiteralPath (Join-Path $OutputDirectory 'AppxManifest.xml') -Raw
. (Join-Path $PSScriptRoot '../.github/scripts/PackageIdentity.Helpers.ps1')
Assert-FolderSailPackageIdentity $manifest $IdentityMode $BuildKind
if ($manifest.Package.Identity.Name -ne $Identity -or $manifest.Package.Identity.Publisher -ne $Publisher) { throw 'Package identity/publisher differs from explicit build inputs.' }
if ($manifest.OuterXml -match 'packageManagement|windows.startupTask|windows.appExecutionAlias|windows.fileTypeAssociation|49306atecsolution') { throw 'Package contains an undeclared capability, registration or upstream identity.' }
if (@($manifest.SelectNodes("//*[local-name()='Protocol']")).Count -ne 1 -or @($manifest.SelectNodes("//*[local-name()='Protocol' and @Name='filequay']")).Count -ne 1) { throw 'Package must declare exactly the owned filequay activation protocol.' }
foreach ($required in @('FolderSail.exe', 'NOTICE.md', 'LICENSE-MIT', 'LICENSE-MPL')) {
    if (-not (Test-Path -LiteralPath (Join-Path $OutputDirectory $required))) { throw "Required package file missing: $required" }
}
[xml]$runtimePolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'FileQuay.Runtime.props') -Raw
$runtimeVersion = [string]$runtimePolicy.Project.PropertyGroup.FileQuayRuntimeVersion
$payloadJson = & python (Join-Path $PSScriptRoot 'verify-package-payload.py') --package-root $OutputDirectory --runtime-version $runtimeVersion --dependency-directory (Join-Path (Split-Path $PackagePath -Parent) 'Dependencies/x64')
if ($LASTEXITCODE -ne 0) { throw "Package payload is incomplete: $payloadJson" }
$payload = ($payloadJson -join "`n") | ConvertFrom-Json
$assetsPath = Join-Path $PSScriptRoot '../src/Files.App/obj/project.assets.json'
if (-not (Test-Path -LiteralPath $assetsPath -PathType Leaf)) { throw 'Restored application assets are required to verify the exact runtime-pack bytes.' }
$assets = Get-Content -LiteralPath $assetsPath -Raw | ConvertFrom-Json
$packageFolders = @($assets.packageFolders.PSObject.Properties.Name)
. (Join-Path $PSScriptRoot 'verify-runtime-files.ps1')
$runtimeBinaries = @(Test-FileQuayRuntimeFiles -PackageRoot $OutputDirectory -RuntimeVersion $runtimeVersion -PackageFolders $packageFolders)
$files = @(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File)
foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($OutputDirectory, $file.FullName)
    if ($relative -match '(^|[\\/])(Sentry[^\\/]*\.dll|SetFilesAsDefault\.reg|UnsetFilesAsDefault\.reg|Files\.App\.Launcher\.exe)$|Assets[\\/](AppTiles|FilesOpenDialog)[\\/]') { throw "Excluded upstream component packaged: $relative" }
    if ($file.Name -eq 'FolderSail.dll') {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
            if ($encoding.GetString($bytes) -match 'sentry\.secret|bingmapskey\.secret|githubclientid\.secret|https://files\.community/blog/posts|SetFilesAsDefault\.reg') { throw 'Application contains an excluded upstream service/default-handler input.' }
        }
    }
}
$files | ForEach-Object { [ordered]@{ path=[IO.Path]::GetRelativePath($OutputDirectory, $_.FullName); bytes=$_.Length; sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } } | ConvertTo-Json -Depth 4 | Set-Content ($OutputDirectory + '.files.json') -Encoding utf8NoBOM
[ordered]@{ makeappx=$makeappx.FullName; makeappx_version=$makeappx.VersionInfo.FileVersion; semantic_unpack_passed=$true; payload_inspection=$payload; runtime_binaries=$runtimeBinaries; runtime_startup_verified=$false; identity=$Identity; publisher=$Publisher; identity_mode=$IdentityMode; package_sha256=(Get-FileHash $PackagePath -Algorithm SHA256).Hash; installed=$false; wack_passed=$false; license_audit_complete=$false } | ConvertTo-Json -Depth 8 | Set-Content ($OutputDirectory + '.validation.json') -Encoding utf8NoBOM
