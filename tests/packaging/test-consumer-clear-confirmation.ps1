# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
$path=Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1'
$text=[IO.File]::ReadAllText($path)
# Only native UIA/Win32 leaves are replaced. Execute the production selector,
# exact caller, unique-element reader, input action and ownership predicate.
. ([scriptblock]::Create($text.Replace('[System.Windows.Automation.','[FileQuayClearReplay.')))
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$match=[regex]::Match($text,"(?m)^[ \t]+Invoke-FileQuayWorkflowAction[^\r\n]*'ReceiptClearButton'[^\r\n]*\r?\n[\s\S]*?(?=^[ \t]+\`$null=Wait-FileQuayWorkflow[^\r\n]*Read-FileQuayWorkflowReceipts)")
Require $match.Success 'Actual clear confirmation caller was not found.'
$sequence=[scriptblock]::Create($match.Value.Replace('[System.Windows.Automation.','[FileQuayClearReplay.'))
$fixturePath=Join-Path $PSScriptRoot 'fixtures/clear-confirmation-34710948563.json'
Require ((Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq '24e2b6903f1ca7dc243022c0bc0672f2ad38a8ef0036e1e9c2610e665d2e823e') 'Original observation extract bytes changed.'
$original=Get-Content $fixturePath -Raw | ConvertFrom-Json -AsHashtable
Require ($original.originalReceiptBytes -eq 185240 -and $original.originalReceiptSha256 -ceq '62a780fdc75d7ddf0ee3798a2c15528e93e666ae951b0755e2318e037447a013') 'Original receipt binding differs.'
Require ($original.failureObservation.Count -eq 160) 'Original failure observation is incomplete.'
Add-Type @'
using System;
namespace FileQuayClearReplay {
 public class ControlType { public static readonly string Window="ControlType.Window"; }
 public class InvokePattern {
  public static object Pattern=new object();public string Id;
  public void Invoke(){if(Id=="PrimaryButton")Fixture.Confirmations++;else if(Id=="ReceiptClearButton")Fixture.Openings++;else throw new Exception("Unexpected input");}
 }
 public static class Fixture {public static int Confirmations,Openings;}
}
namespace FileQuayQualification {public class ConsumerInput {public static void Foreground(object app,long main,object target,long window){}}}
'@
$strings=@{};[xml]$resources=Get-Content (Join-Path $PSScriptRoot '../../src/Files.App/Strings/en-US/Resources.resw') -Raw
foreach($entry in $resources.root.data){$strings[[string]$entry.name]=[string]$entry.value}
$owned=$original.clearAction.details.state
function Binding($Row) {
 $element=[pscustomobject]@{Current=[pscustomobject]@{ClassName=$Row.class_name;ControlType=$Row.control_type;Name=$Row.name;AutomationId=$Row.automation_id;ProcessId=$Row.process_id;IsOffscreen=$Row.offscreen;IsEnabled=$Row.enabled}}
 $element|Add-Member ScriptMethod GetCurrentPattern {param($id);$p=[FileQuayClearReplay.InvokePattern]::new();$p.Id=$this.Current.AutomationId;return $p}
 @{element=$element;scope=@{app_pid=$owned.main_pid;main_hwnd=$owned.owner_chain[-1];target_pid=$owned.target_pid;target_hwnd=$owned.owner_chain[-1];process=@{Id=$owned.target_pid}}}
}
function Find-FileQuayWorkflowElements($Ui,[string]$Id='',[string]$Name='',$Within=$null,[switch]$AllowBroker,[switch]$IncludeHidden) {
 Require (-not $AllowBroker) 'Clear confirmation allowed unrelated broker discovery.'
 if($Within){Require ([object]::ReferenceEquals($Within,$script:dialog)) 'Confirmation child lookup escaped its exact selected popup.'}
 $rows=if($Id -ceq 'ReceiptClearButton'){@($script:openButton)}elseif($Id -ceq 'PrimaryButton'){@($script:primary)}elseif($Within){@($script:message)}else{@($script:dialog)}
 foreach($r in $rows) {
  $c=$r.element.Current
  if($Name -and $c.Name -cne $Name){continue}
  if(-not $IncludeHidden -and ($c.IsOffscreen -or -not $c.IsEnabled)){continue}
  if($c.ProcessId -ne $owned.target_pid){continue}
  $r
  if($script:mode -ceq 'duplicate-popup' -and -not $Within -and -not $Id){$r}
  if($script:mode -ceq 'duplicate-primary' -and $Id -ceq 'PrimaryButton'){$r}
 }
}
function Get-FileQuayWorkflowTargetState($Ui,$Binding) {
 $state=@{}+$owned;$state.target_hwnd=$owned.owner_chain[-1];$state.foreground_hwnd=$state.target_hwnd
 $state.element_hwnd=$state.target_hwnd;$state.owner_chain=@($state.target_hwnd)
 $state.element_pid=$Binding.element.Current.ProcessId;$state.element_visible=-not $Binding.element.Current.IsOffscreen;$state.element_enabled=$Binding.element.Current.IsEnabled
 if($Binding.element.Current.AutomationId -ceq 'PrimaryButton') {
  if($script:mode -ceq 'foreign-foreground'){$state.foreground_hwnd=909}
  if($script:mode -ceq 'changed-owner'){$state.owner_chain=@(909)}
 }
 $state
}
function Wait-FileQuayWorkflow([scriptblock]$Observe,[string]$Label){& $Observe}
$checks=0
foreach($case in @('actual','wrong-class','wrong-role','wrong-title','duplicate-popup','hidden-popup','disabled-popup','foreign-popup','wrong-content','missing-primary','duplicate-primary','foreign-foreground','changed-owner')) {
 $script:mode=$case
 $script:dialog=Binding (@($original.failureObservation|Where-Object {$_.name -ceq $strings.ReceiptClear -and $_.class_name -ceq 'Popup'})[0])
 $script:primary=Binding (@($original.failureObservation|Where-Object automation_id -CEQ 'PrimaryButton')[0])
 $script:openButton=Binding (@($original.failureObservation|Where-Object automation_id -CEQ 'ReceiptClearButton')[0])
 $script:message=Binding (@($original.failureObservation|Where-Object name -CEQ $strings.ReceiptClearConfirm)[0])
 switch($case) {
  'wrong-class'{$dialog.element.Current.ClassName='ContentDialog'}
  'wrong-role'{$dialog.element.Current.ControlType='ControlType.Button'}
  'wrong-title'{$dialog.element.Current.Name='Delete files'}
  'hidden-popup'{$dialog.element.Current.IsOffscreen=$true}
  'disabled-popup'{$dialog.element.Current.IsEnabled=$false}
  'foreign-popup'{$dialog.element.Current.ProcessId=909}
  'wrong-content'{$message.element.Current.Name='Delete files permanently'}
  'missing-primary'{$primary.element.Current.IsOffscreen=$true}
 }
 $ui=@{application=@{Id=$owned.main_pid};main_hwnd=$owned.owner_chain[-1];strings=$strings;record=@{trace=[Collections.Generic.List[object]]::new()}}
 [FileQuayClearReplay.Fixture]::Confirmations=0;[FileQuayClearReplay.Fixture]::Openings=0
 $failure='';try{& $sequence}catch{$failure=$_.Exception.Message}
 Require ([FileQuayClearReplay.Fixture]::Openings -eq 1) 'Opening input was replayed or skipped.'
 if($case -ceq 'actual') {Require (-not $failure -and [FileQuayClearReplay.Fixture]::Confirmations -eq 1) "Original exact owned clear confirmation was refused: $failure"}
 else {Require ($failure -and [FileQuayClearReplay.Fixture]::Confirmations -eq 0) "Unproved clear confirmation accepted: $case"}
 $checks++
}
"PASS: $checks actual clear-caller/selector/action scenarios, exact original Popup/Window, metadata text, uniqueness, visibility, PID, final foreground/owner refusals and zero input replay."
