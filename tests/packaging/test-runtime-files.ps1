# Copyright (c) Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../distribution/verify-runtime-files.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('FileQuay-runtime-test-' + [Guid]::NewGuid().ToString('N'))
function Assert-Rejected([scriptblock]$Action, [string]$Expected) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if (-not $caught -or $caught -notlike ('*' + $Expected + '*')) { throw "Expected rejection containing '$Expected', observed '$caught'." }
}
try {
    $cache = Join-Path $temporary 'nuget'
    $package = Join-Path $temporary 'package'
    $pack = Join-Path $cache 'microsoft.netcore.app.runtime.win-x64/10.0.12'
    $reference = Join-Path $pack 'runtimes/win-x64/native'
    foreach ($directory in @($reference, $package, (Join-Path $package 'Files.App.Server'))) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    # Labeled fixture bytes test comparison behavior; they are not native executables.
    [IO.File]::WriteAllText((Join-Path $pack 'microsoft.netcore.app.runtime.win-x64.10.0.12.nupkg.sha512'), 'fixture-package-hash')
    foreach ($name in @('coreclr.dll', 'clrjit.dll', 'hostfxr.dll', 'hostpolicy.dll')) {
        [IO.File]::WriteAllText((Join-Path $reference $name), ('runtime fixture: ' + $name))
        Copy-Item -LiteralPath (Join-Path $reference $name) -Destination $package
        Copy-Item -LiteralPath (Join-Path $reference $name) -Destination (Join-Path $package 'Files.App.Server')
    }
    $matching = @(Test-FileQuayRuntimeFiles -PackageRoot $package -RuntimeVersion '10.0.12' -PackageFolders @($cache))
    if ($matching.Count -ne 8) { throw "Expected eight checked runtime binaries, observed $($matching.Count)." }
    foreach ($item in $matching) {
        if ($item.sha256 -ne $item.runtime_pack_sha256 -or $item.runtime_pack_version -ne '10.0.12') { throw 'Runtime verification evidence is incomplete.' }
    }
    [IO.File]::WriteAllText((Join-Path $package 'Files.App.Server/coreclr.dll'), 'a different runtime patch')
    Assert-Rejected { Test-FileQuayRuntimeFiles -PackageRoot $package -RuntimeVersion '10.0.12' -PackageFolders @($cache) } 'differs from the restored runtime pack'
    Copy-Item -LiteralPath (Join-Path $reference 'coreclr.dll') -Destination (Join-Path $package 'Files.App.Server/coreclr.dll') -Force
    Remove-Item -LiteralPath (Join-Path $package 'hostfxr.dll')
    Assert-Rejected { Test-FileQuayRuntimeFiles -PackageRoot $package -RuntimeVersion '10.0.12' -PackageFolders @($cache) } 'Required runtime binary is missing'
    Assert-Rejected { Test-FileQuayRuntimeFiles -PackageRoot $package -RuntimeVersion '10.0.11' -PackageFolders @($cache) } 'Restored runtime pack is unavailable'
    Write-Output 'Runtime-file verification: 4 cases passed (matching payload, substituted patch, missing binary, missing exact pack).'
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
