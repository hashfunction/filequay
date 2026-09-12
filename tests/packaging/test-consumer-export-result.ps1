# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$sourcePath=Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1'
. $sourcePath
function Require([bool]$Condition,[string]$Message) {if(-not $Condition){throw $Message}}
$fixturePath=Join-Path $PSScriptRoot 'fixtures/export-flyout-34707732569.json'
Require ((Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq 'f0ba82f2a4c408e39ccafebd4f648ecaa562e85e55faff6f69a9b5763993fe09') 'Original observation fixture bytes changed.'
$original=Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json -AsHashtable
Require ($original.originalReceiptSha256 -ceq '549309e0401785c7e38bb42a0de35faf85401037b81349d9e39829cd2095f688') 'Original receipt identity changed.'
Require ($original.failureObservation.Count -eq 145) 'Original failure tree is incomplete.'
foreach($id in @('ReceiptHistoryTab','ReceiptHistoryList','ReceiptStorageErrorBar')) {
    Require (@($original.failureObservation | Where-Object automation_id -CEQ $id).Count -eq 0) "Original closed flyout unexpectedly contains $id."
}
$button=@($original.failureObservation | Where-Object automation_id -CEQ 'ShowStatusCenterButton')
Require ($button.Count -eq 1 -and $button[0].enabled -and -not $button[0].offscreen -and $button[0].process_id -eq 2476) 'Original owned button differs.'
# Execute the actual caller's post-confirmation statements, not a rewritten
# workflow. Windows UIA leaves are represented by the original closed-flyout
# observation; the production history-opening function above remains intact.
$sequences=@(foreach($caller in @($sourcePath,(Join-Path $PSScriptRoot '../../distribution/marketing/capture_ui.ps1'))) {
    $text=[IO.File]::ReadAllText($caller)
    $match=[regex]::Match($text,"(?m)^[ \t]+Invoke-FileQuayWorkflowAction[^\r\n]*'PrimaryButton'[^\r\n]*\r?\n(?<after>[\s\S]*?)^[ \t]+\`$recovery=Wait-FileQuayWorkflow")
    Require $match.Success "Actual confirmed-export caller boundary is absent: $caller"
    $last=[regex]::Match($match.Value,'(?m)^[ \t]+\$recovery=Wait-FileQuayWorkflow')
    @{caller=$caller;sequence=[scriptblock]::Create($match.Value.Substring(0,$last.Index))}
})
$script:events=[Collections.Generic.List[string]]::new()
function Wait-FileQuayWorkflow([scriptblock]$Check,[string]$Label) {
    for($i=0;$i -lt 3;$i++) { $value=& $Check; if($value){return $value} }
    throw "Fixture observation deadline: $Label"
}
function Find-FileQuayWorkflowElements($Ui,[string]$Id) {
    $script:events.Add("read:$Id")
    if($Id -ceq 'ReceiptExportConfirmationDialog') {
        $script:reads++
        if($script:neverCloses -or $script:reads -lt 2){return @{id=$Id}}
        return
    }
    if($Id -ceq 'ReceiptHistoryTab' -and $script:open){return @{id=$Id}}
}
function Find-FileQuayWorkflowElement($Ui,[string]$Id,$Within=$null) {
    if($Id -ceq 'PrimaryButton'){return @{id=$Id}}
    if($Id -ceq 'ShowStatusCenterButton') {
        if($script:unowned){throw 'Exact owned button unavailable.'}
        return @{id=$Id;original=$button[0]}
    }
    if($Id -in @('ReceiptHistoryTab','ReceiptHistoryList') -and $script:open){return @{id=$Id}}
    throw "Visible owned result element absent: $Id"
}
function Invoke-FileQuayWorkflowAction($Ui,$Binding,[string]$Action) {
    $script:events.Add("input:$($Binding.id):$Action")
    if($Binding.id -ceq 'PrimaryButton'){return}
    if($script:reads -lt 2 -or $script:neverCloses){throw 'Input before the original confirmation closed.'}
    if($Binding.id -ceq 'ShowStatusCenterButton' -and $Action -ceq 'Invoke'){$script:open=$true;return}
    if($Binding.id -ceq 'ReceiptHistoryTab' -and $Action -ceq 'Select') {
        if($script:selectionFails){throw 'Original selection failure.'};return
    }
    throw 'Unexpected or replayed input.'
}
$ui=@{};$dialog=@{}
foreach($entry in $sequences) {
$sequence=$entry.sequence
foreach($case in @('closed','already-open','confirmation-stays','unowned-button','selection-fails')) {
    $script:events.Clear();$script:reads=0;$script:open=$case -ceq 'already-open'
    $script:neverCloses=$case -ceq 'confirmation-stays';$script:unowned=$case -ceq 'unowned-button';$script:selectionFails=$case -ceq 'selection-fails'
    $failure='';try{& $sequence}catch{$failure=$_.Exception.Message}
    $inputs=@($script:events | Where-Object { $_.StartsWith('input:') })
    Require (@($inputs | Where-Object {$_ -ceq 'input:PrimaryButton:Invoke'}).Count -eq 1) 'Confirmation input was replayed.'
    if($case -in @('closed','already-open')) {
        Require (-not $failure -and $script:open) "Status history remained closed after successful export: $failure"
        Require ($script:reads -eq 2) 'Result input did not wait for confirmation disappearance.'
        Require (@($inputs | Where-Object {$_ -ceq 'input:ShowStatusCenterButton:Invoke'}).Count -eq $(if($case -ceq 'closed'){1}else{0})) 'History toggle was repeated or unnecessary.'
        Require ($inputs[-1] -ceq 'input:ReceiptHistoryTab:Select') 'Receipt history was not selected.'
    } else {
        Require (-not [string]::IsNullOrEmpty($failure)) "Unproved result was accepted: $case"
        Require (@($inputs | Where-Object {$_ -ceq 'input:ShowStatusCenterButton:Invoke'}).Count -le 1) 'Failed observation replayed input.'
        if($case -ne 'selection-fails'){Require ($inputs.Count -eq 1) 'Refused state still issued result input.'}
    }
}
}
'PASS: actual consumer and marketing confirmed-export callers and history opener; closed/visible flyout, pending confirmation, ownership refusal, selection failure, and no input replay.'
