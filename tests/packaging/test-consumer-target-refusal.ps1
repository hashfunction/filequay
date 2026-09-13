# Copyright 2026 Trieflow LLC. MIT.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
$scope=@{app_pid=41;main_hwnd=101;target_pid=42;target_hwnd=102}
$valid=@{app_live=$true;target_process_live=$true;main_live=$true;main_pid=41;target_live=$true;target_pid=42;target_hwnd=102;target_visible=$true;target_enabled=$true;foreground_hwnd=102;owner_chain=@(102,101);element_pid=42;element_hwnd=102;element_within_target=$true;element_visible=$true;element_enabled=$true}
Assert-FileQuayWorkflowTarget $scope $valid
$checks=1
foreach($mutation in @('foreground_hwnd','element_within_target','target_enabled','owner_chain')) {
    $state=@{}+$valid;$state.unrelated='not retained'
    $state[$mutation]=switch($mutation){'foreground_hwnd'{999};'owner_chain'{@(1..20)};default{$false}}
    $continued=$false;$caught=$null
    try{Assert-FileQuayWorkflowTarget $scope $state;$continued=$true}catch{$caught=$_}
    if($continued -or -not $caught -or $caught.Exception.Message -cne 'Workflow input target ownership, foreground, or UI state changed.' -or
       $caught.Exception.GetType().FullName -cne 'System.Management.Automation.RuntimeException'){throw 'Original immediate refusal changed.'}
    $row=$caught.Exception.Data['FileQuayWorkflowTargetRefusal']
    if(-not $row -or $row.state.ContainsKey('unrelated') -or $row.scope.target_hwnd -ne 102 -or $row.state.foreground_hwnd -ne $state.foreground_hwnd -or
       $row.owner_chain_count -ne $state.owner_chain.Count -or $row.state.owner_chain.Count -gt 8){throw 'Rejected original state was not retained within bounds.'}
    if($mutation -ne 'owner_chain' -and $row.state[$mutation] -ne $state[$mutation]){throw 'Rejected predicate value changed.'}
    $checks++
}
$badScope=@{}+$scope;$badScope.app_pid='invalid';$caught=$null
try{Assert-FileQuayWorkflowTarget $badScope $valid}catch{$caught=$_}
if(-not $caught -or $caught.Exception.Message -cne 'Workflow input target ownership, foreground, or UI state changed.' -or $caught.Exception.GetType().FullName -cne 'System.Management.Automation.RuntimeException'){throw 'Secondary diagnostic failure changed original rejection.'}
$checks++
# The production consumer catch must retain the exception data before any new UI observation.
$path=Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
$catch=$ast.FindAll({param($n)$n -is [Management.Automation.Language.CatchClauseAst] -and $n.Extent.Text.Contains('$workflow.error=')},$true)[0]
$statements=$catch.Body.Statements
$workflow=@{};$continued=$false
try{Assert-FileQuayWorkflowTarget $scope (@{}+$valid+@{extra=$true})}catch{throw 'Valid state changed.'}
$bad=@{}+$valid;$bad.foreground_hwnd=999
try{Assert-FileQuayWorkflowTarget $scope $bad}catch{
    & ([scriptblock]::Create($statements[0].Extent.Text))
    & ([scriptblock]::Create($statements[1].Extent.Text))
}
if(-not $workflow.ContainsKey('target_refusal') -or $workflow.target_refusal.state.foreground_hwnd -ne 999){throw 'Consumer catch lost original rejected state.'}
"PASS target refusal diagnostics: $checks actual guard cases and production catch; unchanged error/type, bounded state, no continued action."
