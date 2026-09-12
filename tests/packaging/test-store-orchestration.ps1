# Copyright 2026 Trieflow LLC. MIT.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../distribution/qualify-store.ps1') -LibraryOnly
$script:calls=[Collections.Generic.List[object]]::new();$script:failure=0
function Invoke-FolderSailStoreCommand([string]$Program,[string[]]$Arguments) {
    $script:calls.Add(@{program=$Program;arguments=@($Arguments)})
    if ($script:failure -eq $script:calls.Count) {throw ('fixture step failure '+$script:failure)}
}
$context=@{source_commit='a'*40;workflow_run_id='123';workflow_run_attempt='1'}
$root=Join-Path ([IO.Path]::GetTempPath()) 'foldersail-store-sequence'
Invoke-FolderSailStoreRelease $root $context
if ($calls.Count -ne 2 -or $calls[0].arguments[-1] -cne 'Store' -or $calls[0].arguments[-3] -cne 'RequireClean' -or
    $calls[0].arguments[-5] -cne 'Consumer' -or $calls[1].program -cne 'python' -or
    -not $calls[1].arguments[0].EndsWith('export_store.py') -or $calls[1].arguments[-1] -cne '1') {throw 'Store build/identity/export sequence differs.'}
foreach ($step in @(1,2)) {
    $script:calls.Clear();$script:failure=$step;$errorText=''
    try {Invoke-FolderSailStoreRelease $root $context} catch {$errorText=$_.Exception.Message}
    if ($errorText -cne "fixture step failure $step" -or $calls.Count -ne $step) {throw 'A failed Store step was swallowed or followed by export.'}
}
'PASS actual Store orchestration: normal Consumer/RequireClean/Store, exact current context, qualification-before-export, and both failure short circuits.'
