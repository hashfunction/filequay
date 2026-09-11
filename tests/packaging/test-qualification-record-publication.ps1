# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('filequay-record-publication-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    $collision = Join-Path $temporary 'foreign-stage.tmp'
    [IO.File]::WriteAllText($collision, 'foreign stage bytes')
    function New-FileQuayQualificationStagePath { param([string]$Path) return $collision }
    $collisionFailure = ''
    try { Write-FileQuayQualificationRecord (Join-Path $temporary 'collision.json') ([ordered]@{ result='new' }) }
    catch { $collisionFailure = $_.Exception.ToString() }
    if (-not $collisionFailure -or $collisionFailure.Contains('parameter') -or
        [IO.File]::ReadAllText($collision) -cne 'foreign stage bytes' -or
        [IO.File]::Exists((Join-Path $temporary 'collision.json'))) {
        throw "A stage collision was accepted, deleted, or rejected by the wrong boundary: $collisionFailure"
    }

    $destination = Join-Path $temporary 'existing.json'
    [IO.File]::WriteAllText($destination, 'existing result bytes')
    $ownedStage = Join-Path $temporary 'owned-stage.tmp'
    function New-FileQuayQualificationStagePath { param([string]$Path) return $ownedStage }
    function Remove-FileQuayQualificationStage { param([string]$Path) throw 'fixture owned-stage cleanup failure' }
    $combinedFailure = ''
    try { Write-FileQuayQualificationRecord $destination ([ordered]@{ result='new' }) }
    catch { $combinedFailure = $_.Exception.ToString() }
    if (-not $combinedFailure.Contains('existing.json') -or -not $combinedFailure.Contains('fixture owned-stage cleanup failure') -or
        [IO.File]::ReadAllText($destination) -cne 'existing result bytes' -or -not [IO.File]::Exists($ownedStage)) {
        throw "Publication/cleanup failure aggregation lost an error or existing bytes: $combinedFailure"
    }
} finally {
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $temporary -Recurse -Force
}

'Qualification record publication checks passed: foreign stages survive and publication plus owned-stage cleanup failures are retained.'
