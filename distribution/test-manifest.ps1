# Copyright (c) Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$configurator = Join-Path $root '.github/scripts/Configure-AppxManifest.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('FileQuay-manifest-' + [Guid]::NewGuid().ToString('N') + '.xml')
function Expect-Rejection([hashtable]$Arguments) {
    $before = [IO.File]::ReadAllBytes($fixture)
    $rejected = $false
    try { & $configurator @Arguments -PackageManifestPath $fixture | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid manifest inputs were accepted.' }
    if ([Convert]::ToBase64String($before) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture))) { throw 'Rejected input changed the manifest.' }
}
try {
    Copy-Item (Join-Path $root 'src/Files.App/Package.appxmanifest') $fixture
    Expect-Rejection @{}
    Expect-Rejection @{Identity='FilesDev'; Publisher='CN=FileQuay-CI-Qualification'}
    Expect-Rejection @{Identity='Trieflow.FileQuay.Qualification'; Publisher='CN=FileQuay-CI-Qualification'; Version='1.0.0'}
    Expect-Rejection @{Identity='Trieflow.FileQuay.Qualification'; Publisher='CN=FileQuay-CI-Qualification'; AssetDirectory='..\outside'}
    & $configurator -PackageManifestPath $fixture -Identity 'Trieflow.FileQuay.Qualification' -Publisher 'CN=FileQuay-CI-Qualification' -Protocol filequay | Out-Null
    [xml]$configured = Get-Content $fixture -Raw
    if ($configured.Package.Identity.Name -ne 'Trieflow.FileQuay.Qualification') { throw 'Explicit identity was not retained.' }
    if (@($configured.SelectNodes("//*[local-name()='Protocol' and @Name='filequay']")).Count -ne 1) { throw 'Owned activation protocol missing.' }
    if ($configured.OuterXml -match 'windows.startupTask|windows.appExecutionAlias|windows.fileTypeAssociation|packageManagement|49306atecsolution') { throw 'Undeclared upstream registration remains.' }
    & $configurator -PackageManifestPath $fixture -Identity 'Trieflow.FileQuay.Qualification' -Publisher 'CN=FileQuay-CI-Qualification' | Out-Null
    [xml]$withoutOptional = Get-Content $fixture -Raw
    if (@($withoutOptional.SelectNodes("//*[local-name()='Protocol']")).Count -ne 0) { throw 'Protocol was not explicit opt-in.' }
    Write-Output 'Manifest tests passed: required owned inputs, rejection without mutation, owned protocol opt-in and no default-handler/startup/update declarations.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture }
}
