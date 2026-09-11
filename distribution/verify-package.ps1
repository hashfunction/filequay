# Copyright (c) Trieflow LLC. Licensed under the MIT License.
param([string]$PackagePath, [string]$Identity, [string]$Publisher, [string]$OutputDirectory)
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
if ($manifest.Package.Identity.Name -ne $Identity -or $manifest.Package.Identity.Publisher -ne $Publisher) { throw 'Package identity/publisher differs from explicit build inputs.' }
if ($manifest.OuterXml -match 'packageManagement|windows.startupTask|windows.appExecutionAlias|windows.fileTypeAssociation|49306atecsolution') { throw 'Package contains an undeclared capability, registration or upstream identity.' }
if (@($manifest.SelectNodes("//*[local-name()='Protocol']")).Count -ne 1 -or @($manifest.SelectNodes("//*[local-name()='Protocol' and @Name='filequay']")).Count -ne 1) { throw 'Package must declare exactly the owned filequay activation protocol.' }
if ($manifest.Package.Properties.DisplayName -ne 'FileQuay' -or $manifest.Package.Properties.PublisherDisplayName -ne 'Trieflow LLC') { throw 'Package branding does not match FileQuay.' }
foreach ($required in @('FileQuay.exe', 'NOTICE.md', 'LICENSE-MIT', 'LICENSE-MPL')) {
    if (-not (Test-Path -LiteralPath (Join-Path $OutputDirectory $required))) { throw "Required package file missing: $required" }
}
$files = @(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File)
foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($OutputDirectory, $file.FullName)
    if ($relative -match '(^|[\\/])(Sentry[^\\/]*\.dll|SetFilesAsDefault\.reg|UnsetFilesAsDefault\.reg|Files\.App\.Launcher\.exe)$|Assets[\\/](AppTiles|FilesOpenDialog)[\\/]') { throw "Excluded upstream component packaged: $relative" }
    if ($file.Name -eq 'FileQuay.dll') {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
            if ($encoding.GetString($bytes) -match 'sentry\.secret|bingmapskey\.secret|githubclientid\.secret|https://files\.community/blog/posts|SetFilesAsDefault\.reg') { throw 'Application contains an excluded upstream service/default-handler input.' }
        }
    }
}
$files | ForEach-Object { [ordered]@{ path=[IO.Path]::GetRelativePath($OutputDirectory, $_.FullName); bytes=$_.Length; sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } } | ConvertTo-Json -Depth 4 | Set-Content ($OutputDirectory + '.files.json') -Encoding utf8NoBOM
[ordered]@{ makeappx=$makeappx.FullName; makeappx_version=$makeappx.VersionInfo.FileVersion; semantic_unpack_passed=$true; identity=$Identity; publisher=$Publisher; package_sha256=(Get-FileHash $PackagePath -Algorithm SHA256).Hash; installed=$false; wack_passed=$false; license_audit_complete=$false } | ConvertTo-Json | Set-Content ($OutputDirectory + '.validation.json') -Encoding utf8NoBOM
