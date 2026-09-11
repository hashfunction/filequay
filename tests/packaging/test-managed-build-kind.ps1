# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Builds real managed PE fixtures and inspects their metadata without loading them.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')

$dotnet = if ($env:FILEQUAY_DOTNET) { $env:FILEQUAY_DOTNET } else { 'dotnet' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('filequay-managed-kind-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    foreach ($kind in @('Consumer','Instrumented')) {
        $project = Join-Path $temporary $kind
        New-Item -ItemType Directory -Path $project | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'Fixture.csproj') -Encoding UTF8 -Value @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup>
</Project>
'@
        $source = if ($kind -eq 'Instrumented') {
            'namespace Files.App.Utils.Qualification { public sealed class CiComActivationProbe {} }'
        } else {
            'namespace Files.App { public sealed class ConsumerMarker {} }'
        }
        Set-Content -LiteralPath (Join-Path $project 'Fixture.cs') -Encoding UTF8 -Value $source
        & $dotnet build (Join-Path $project 'Fixture.csproj') --configuration Release --nologo --verbosity quiet
        if ($LASTEXITCODE -ne 0) { throw "Fixture compilation failed for $kind." }
    }

    $consumer = Join-Path $temporary 'Consumer/bin/Release/net10.0/Fixture.dll'
    $instrumented = Join-Path $temporary 'Instrumented/bin/Release/net10.0/Fixture.dll'
    $consumerEvidence = Get-FileQuayManagedBuildKindEvidence $consumer 'Consumer'
    if ($consumerEvidence.actual_build_kind -cne 'Consumer' -or $consumerEvidence.ci_probe_type_present -or
        $consumerEvidence.assembly_sha256 -cne (Get-FileHash $consumer -Algorithm SHA256).Hash) {
        throw 'A real consumer assembly was not classified and bound to its exact bytes.'
    }
    $instrumentedEvidence = Get-FileQuayManagedBuildKindEvidence $instrumented 'Instrumented'
    if ($instrumentedEvidence.actual_build_kind -cne 'Instrumented' -or -not $instrumentedEvidence.ci_probe_type_present) {
        throw 'A real instrumented assembly was not classified from its managed metadata.'
    }

    foreach ($mislabeled in @(@($consumer,'Instrumented'), @($instrumented,'Consumer'))) {
        $failure = $null
        try { $null = Get-FileQuayManagedBuildKindEvidence $mislabeled[0] $mislabeled[1] }
        catch { $failure = $_.Exception.Message }
        if (-not $failure -or -not $failure.Contains('Managed build kind mismatch')) {
            throw "A coherently mislabeled $($mislabeled[1]) binary was accepted."
        }
    }

    $invalid = Join-Path $temporary 'not-managed.dll'
    Set-Content -LiteralPath $invalid -Value 'not a PE assembly' -NoNewline
    try { $null = Get-FileQuayManagedBuildKindEvidence $invalid 'Consumer'; throw 'Malformed assembly was accepted.' }
    catch { if ($_.Exception.Message -eq 'Malformed assembly was accepted.') { throw } }
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

'Managed build-kind checks passed: real consumer/instrumented PE metadata, byte binding, mislabeled and malformed rejection.'
