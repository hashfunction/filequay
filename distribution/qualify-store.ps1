# Copyright 2026 Trieflow LLC. MIT.
param([switch]$LibraryOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Invoke-FolderSailStoreCommand([string]$Program,[string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {throw "$Program failed with $LASTEXITCODE"}
}
function Invoke-FolderSailStoreRelease([string]$Root,$Context) {
    $hostPowerShell=(Get-Process -Id $PID).Path
    Invoke-FolderSailStoreCommand $hostPowerShell @('-NoProfile','-File',(Join-Path $Root 'distribution/qualify-windows.ps1'),
        '-BuildKind','Consumer','-DependencyMode','RequireClean','-IdentityMode','Store')
    Invoke-FolderSailStoreCommand python @((Join-Path $Root 'distribution/export_store.py'),
        '--source',$Root,'--prior',(Join-Path $Root 'artifacts/prior-qualification'),
        '--store',(Join-Path $Root 'artifacts/qualification/Store-Consumer'),
        '--output',(Join-Path $Root 'artifacts/store-upload'),
        '--source-commit',$Context.source_commit,'--workflow-run-id',$Context.workflow_run_id,'--workflow-run-attempt',$Context.workflow_run_attempt)
}
if ($LibraryOnly) {return}
if (-not $IsWindows -or $env:CI -ne 'true') {throw 'Store qualification requires an isolated Windows CI runner.'}
$root=Split-Path $PSScriptRoot -Parent
Set-Location $root
Invoke-FolderSailStoreRelease $root @{source_commit=$env:GITHUB_SHA;workflow_run_id=$env:GITHUB_RUN_ID;workflow_run_attempt=$env:GITHUB_RUN_ATTEMPT}
