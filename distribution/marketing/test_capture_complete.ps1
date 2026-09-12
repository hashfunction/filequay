# Copyright 2026 Trieflow LLC. MIT. Completion policy fixtures, never Windows acceptance.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_lifecycle.ps1')
$good=@{captures=@('01-folder-workspace','02-operation-receipts','03-export-receipts');normalClose=$true;
    stopped=$true;uninstalled=$true;removed=$true;inputsUnchanged=$true;trustRemoved=$true;keyRemoved=$true;temporaryRemoved=$true;
    displayEvidence=@{restore_verified=$true};record=@{csv_committed_verified=$true;owned_process_cleanup_verified=$true;
        normal_process_exit_verified=$false;background_process_observed=$true;window_disappeared=$true};
    outcome=@{primary_error=$null;cleanup_errors=@()}}
Assert-FolderSailMarketingComplete $good
foreach($mutation in @('captures','normalClose','stopped','uninstalled','removed','inputsUnchanged','trustRemoved','keyRemoved','temporaryRemoved','display','csv','cleanup','primary','exit')){
    $bad=$good|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    switch($mutation){
        'captures'{$bad.captures[2]='02-operation-receipts'}
        'display'{$bad.displayEvidence.restore_verified=$false}
        'csv'{$bad.record.csv_committed_verified=$false}
        'cleanup'{$bad.outcome.cleanup_errors=@('original cleanup failure')}
        'primary'{$bad.outcome.primary_error='original failure'}
        'exit'{$bad.record.background_process_observed=$false}
        default{$bad[$mutation]=$false}
    }
    $refused=$false;try{Assert-FolderSailMarketingComplete $bad}catch{$refused=$true}
    if(-not $refused){throw "Incomplete capture accepted: $mutation"}
}
$good.record.background_process_observed=$false;$good.record.normal_process_exit_verified=$true
Assert-FolderSailMarketingComplete $good
Write-Output 'PASS exact three scenes, CSV result, close/cleanup outcomes and source preservation refusals.'
