# Copyright 2026 Trieflow LLC. MIT. Real picker helper/confirmation sequencing with provider observations replayed.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1')
Add-Type @'
using System;using System.Collections.Generic;
namespace System.Windows.Automation {
 public class ControlType {public static string Button="Button";}
 public class ValuePattern {public static object Pattern=new();public ValueInfo Current=new();}
 public class ValueInfo {public bool IsReadOnly;public string Value="";}
}
namespace FileQuayQualification {
 public class ConsumerInput {
  public static int Spaces;public static bool FailSend;public static List<long> Buttons=new();
  public static void Foreground(object app,long main,object target,long window){}
  public static long[] OwnerChain(long window)=>new long[]{window,3473742};
  public static void FocusedSpace(object app,long main,object target,long window,long button){Spaces++;Buttons.Add(button);if(FailSend)throw new InvalidOperationException("native focus changed");}
 }
}
'@
function Require($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,$Text){$failure='';try{& $Action|Out-Null}catch{$failure=$_.Exception.Message};Require ($failure.Contains($Text)) "Expected $Text; got $failure"}
function New-Element($Id,$Name,$Class,$Type,$Handle,$Owner) {
 $e=[pscustomobject]@{Current=[pscustomobject]@{AutomationId=$Id;Name=$Name;ClassName=$Class;ControlType=$Type;NativeWindowHandle=$Handle;ProcessId=$Owner;IsOffscreen=$false;IsEnabled=$true;IsKeyboardFocusable=$true;HasKeyboardFocus=$false}}
 $e|Add-Member ScriptMethod SetFocus {
  $this.Current.HasKeyboardFocus=$true;$script:events.Add('focus-'+$this.Current.AutomationId)
  if($script:drift){$this.Current.($script:drift.key)=$script:drift.value}
 }
 $e
}
function Reset {
 $script:nativeError=$false;$script:events=[Collections.Generic.List[string]]::new();$script:drift=$null;$script:badState=$false;$script:wrongValue=$false;$script:needsOverwrite=$false;$script:reads=0
 [FileQuayQualification.ConsumerInput]::Spaces=0;[FileQuayQualification.ConsumerInput]::FailSend=$false;[FileQuayQualification.ConsumerInput]::Buttons.Clear()
 $process=[pscustomobject]@{Id=1752;Path='C:\Windows\System32\PickerHost.exe'}
 $scope=@{app_pid=9136;main_hwnd=3473742;target_pid=1752;target_hwnd=131642;process=$process;root=$null}
 $script:filename=@{scope=$scope;element=(New-Element '1001' 'File name:' 'Edit' 'Edit' 303 1752)}
 $script:pattern=[System.Windows.Automation.ValuePattern]::new()
 $filename.element|Add-Member ScriptMethod GetCurrentPattern {param($Id)$script:reads++;$script:events.Add('filename-read');$script:pattern}
 $script:save=@{scope=$scope;element=(New-Element '1' 'Save' 'Button' 'Button' 404 1752)}
 $script:yes=@{scope=(@{}+$scope);element=(New-Element '6' 'Yes' 'Button' 'Button' 505 1752)};$yes.scope.target_hwnd=606
 $script:custom=@{scope=@{target_hwnd=3473742;target_pid=9136};element=(New-Element 'ReceiptExportConfirmationDialog' 'Export receipts' '' 'Window' 3473742 9136)}
 $script:ui=@{application=[pscustomobject]@{Id=9136};main_hwnd=3473742;record=@{trace=[Collections.Generic.List[object]]::new()}}
 $script:fixture=@{csv='C:\owned\export\receipts.csv';previous_csv=@{sha256='exact-original'}}
}
function Wait-FileQuayWorkflow([scriptblock]$Observe,[string]$Description,[int]$Seconds=30){$v=& $Observe;if($null -eq $v){throw "No observation: $Description"};$v}
function Find-FileQuayWorkflowSaveFilename($Ui){$script:filename}
function Find-FileQuayWorkflowElement($Ui,[string]$Id='',[string]$Name='',$Within=$null,[switch]$AllowBroker,[switch]$IncludeHidden){
 switch($Id){'ReceiptExportButton'{@{element=(New-Element $Id 'Export receipts…' '' 'Button' 3473742 9136)}} '1'{$script:save} 'ReceiptExportConfirmationDialog'{$script:custom} 'PrimaryButton'{@{element=(New-Element $Id 'Export' '' 'Button' 3473742 9136)}} default{throw "Unexpected selector $Id"}}
}
function Find-FileQuayWorkflowElements($Ui,[string]$Id='',[string]$Name='',$Within=$null,[switch]$AllowBroker,[switch]$IncludeHidden){
 if($nativeError -and $Id -in @('ReceiptExportConfirmationDialog','6')){
  foreach($node in $errorFixture.native_error_nodes | Where-Object automation_id -CEQ $Id){throw 'Unexpected accepted selector on retained actual error dialog.'};return
 }
 if($Id -ceq 'ReceiptExportConfirmationDialog'){if(-not $needsOverwrite){$custom};return}
 if($Id -ceq '6'){$yes;return}
 if($Within){@{element=[pscustomobject]@{Current=[pscustomobject]@{Name=$fixture.csv}}};return}
 throw "Unexpected plural selector $Id"
}
function Get-FileQuayWorkflowTargetState($Ui,$Binding){
 @{app_live=$true;main_live=$true;main_pid=9136;target_process_live=$true;target_live=$true;target_pid=$Binding.scope.target_pid;target_hwnd=$Binding.scope.target_hwnd;
  target_visible=$true;target_enabled=(-not $badState);foreground_hwnd=$Binding.scope.target_hwnd;owner_chain=@($Binding.scope.target_hwnd,3473742);
  element_pid=$Binding.element.Current.ProcessId;element_hwnd=$Binding.scope.target_hwnd;element_within_target=$true;element_visible=(-not $Binding.element.Current.IsOffscreen);element_enabled=$Binding.element.Current.IsEnabled}
}
function Invoke-FileQuayWorkflowAction($Ui,$Binding,$Action,$Value=$null){
 if($Binding.element.Current.AutomationId -ceq 'ReceiptExportButton' -and $Action -ceq 'Invoke'){$events.Add('export-invoke');return}
 if($Binding.element.Current.AutomationId -ceq '1001' -and $Action -ceq 'Value'){$events.Add('filename-value');$pattern.Current.Value=$(if($wrongValue){'FolderSail-receipts.csv'}else{$Value});return}
 throw 'Synchronous native button Invoke must not be used.'
}
function Assert-FileQuayWorkflowFile($Path,$Previous){Require ($Path -ceq $fixture.csv -and $Previous.sha256 -ceq 'exact-original') 'Original destination proof changed.';$events.Add('original-file-proof')}
$errorFixture=Get-Content (Join-Path $PSScriptRoot 'fixtures/picker-sync-call-34691657713.json') -Raw|ConvertFrom-Json
Require (($errorFixture.native_error_nodes | Where-Object automation_id -CEQ 'ContentText').name.Contains('input-synchronous call')) 'Retained actual native failure fixture changed.'
$checks=0
Reset
$result=Open-FileQuayWorkflowExportConfirmation $ui $fixture
Require ([object]::ReferenceEquals($result,$custom) -and [FileQuayQualification.ConsumerInput]::Spaces -eq 1 -and $reads -eq 1) 'Native Save did not reach exact app confirmation after readback.';$checks++
Require (($events -join ',') -ceq 'export-invoke,filename-value,filename-read,focus-1,original-file-proof') 'Save sequence changed.';$checks++
Require ($ui.record.picker_filename.value -ceq $fixture.csv -and $ui.record.picker_filename.verified) 'Exact filename observation not retained.';$checks++
Reset;$needsOverwrite=$true
# The original replacement dialog content/path check executes, then its focused Space permits app confirmation.
$result=Open-FileQuayWorkflowExportConfirmation $ui $fixture
Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 2 -and ([FileQuayQualification.ConsumerInput]::Buttons -join ',') -ceq '404,505') 'Save and native Yes were not one-shot native actions.';$checks++
Reset;$wrongValue=$true
Reject {Open-FileQuayWorkflowExportConfirmation $ui $fixture} 'filename'
Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 0 -and $ui.record.picker_filename.value -ceq 'FolderSail-receipts.csv' -and -not $ui.record.picker_filename.verified) 'Mismatched filename was saved or diagnostic lost.';$checks++
Reset;$nativeError=$true
Reject {Open-FileQuayWorkflowExportConfirmation $ui $fixture} 'No observation'
Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 1) 'Actual input-synchronous error was accepted, dismissed or Save replayed.';$checks++
Reset;$pattern.Current.IsReadOnly=$true
Reject {Open-FileQuayWorkflowExportConfirmation $ui $fixture} 'filename'
Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 0) 'Read-only filename was saved.';$checks++
foreach($change in @(@('AutomationId','2'),@('Name','Cancel'),@('ClassName','foreign'),@('ControlType','Pane'),@('NativeWindowHandle',0),@('ProcessId',999),@('IsKeyboardFocusable',$false),@('IsEnabled',$false),@('IsOffscreen',$true))){
 Reset;$save.element.Current.($change[0])=$change[1]
 Reject {Invoke-FileQuayWorkflowPickerButton $ui $save '1' 'Save'} 'button'
 Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 0) "Changed $($change[0]) accepted";$checks++
}
foreach($change in @(@('AutomationId','2'),@('Name','Cancel'),@('ClassName','foreign'),@('ControlType','Pane'),@('NativeWindowHandle',405),@('ProcessId',999),@('HasKeyboardFocus',$false))){
 Reset;$drift=@{key=$change[0];value=$change[1]}
 Reject {Invoke-FileQuayWorkflowPickerButton $ui $save '1' 'Save'} 'button'
 Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 0) "Live $($change[0]) drift accepted";$checks++
}
Reset;$badState=$true
Reject {Invoke-FileQuayWorkflowPickerButton $ui $save '1' 'Save'} 'target'
Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 0) 'Disabled native target received input.';$checks++
Reset;[FileQuayQualification.ConsumerInput]::FailSend=$true
Reject {Open-FileQuayWorkflowExportConfirmation $ui $fixture} 'native focus changed'
Require ([FileQuayQualification.ConsumerInput]::Spaces -eq 1) 'Native failure was retried or replaced.';$checks++
"PASS production picker filename/Space/confirmation sequence and refusal: $checks checks."
