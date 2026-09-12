# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'uia-replay-collision.ps1')
Initialize-FileQuayUiaReplayCollision @('AutomationElement','ValuePattern')
# Remap only bracketed UIA type references in the in-memory production replay.
. ([scriptblock]::Create((Get-Content (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1') -Raw).Replace('[System.Windows.Automation.','[FileQuayPickerScopeReplay.Automation.')))
# UIA/native providers are replay fixtures. The production scope/selector functions run unchanged.
Add-Type @'
using System;using System.Collections.Generic;
namespace FileQuayPickerScopeReplay.Automation {
 public enum TreeScope { Children }
 public class Condition { public static object TrueCondition=new object(); }
 public class ValuePattern { public static object Pattern=new object(); }
 public class CurrentInfo { public long NativeWindowHandle;public int ProcessId;public bool IsOffscreen; }
 public class AutomationElement {
  public static AutomationElement RootElement=new AutomationElement();
  public static Dictionary<long,AutomationElement> Roots=new Dictionary<long,AutomationElement>();
  public static List<long> Reads=new List<long>();
  public CurrentInfo Current=new CurrentInfo();public object[] Children=new object[0];
  public object[] FindAll(TreeScope scope,object condition) {return Children;}
  public static AutomationElement FromHandle(IntPtr handle) {Reads.Add(handle.ToInt64());return Roots[handle.ToInt64()];}
 }
}
namespace FileQuayQualification {
 public class ConsumerInput {
  public static Dictionary<long,uint> Owners=new Dictionary<long,uint>();
  public static Dictionary<long,long[]> Chains=new Dictionary<long,long[]>();
  public static Dictionary<long,Dictionary<string,object>> States=new Dictionary<long,Dictionary<string,object>>();
  public static uint WindowProcess(long handle) {return Owners[handle];}
  public static long[] OwnerChain(long handle) {return Chains[handle];}
  public static Dictionary<string,object> Observe(object app,long main,object target,long handle) {return States[handle];}
 }
}
'@
function Require([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Reject([scriptblock]$Action,[string]$Label) {
    $failed=$false;try {& $Action | Out-Null} catch {$failed=$true}
    Require $failed "Accepted $Label"
}
function New-Process([int]$Owner) {
    $p=[pscustomobject]@{Id=$Owner;HasExited=$false;SafeHandle=[pscustomobject]@{IsClosed=$false;IsInvalid=$false};disposed=$false}
    $p | Add-Member ScriptMethod Dispose {$this.disposed=$true};$p
}
function Get-Process([int]$Id) {
    $script:retains++
    if ($script:changeOwner) {[FileQuayQualification.ConsumerInput]::Owners[66112]=999}
    $script:broker
}
function Reset-Scenario {
    $script:retains=0;$script:changeOwner=$false;$script:broker=New-Process 7760
    $script:ui=@{application=(New-Process 7272);main_hwnd=262620;brokers=@{}}
    [FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots.Clear();[FileQuayPickerScopeReplay.Automation.AutomationElement]::Reads.Clear()
    [FileQuayQualification.ConsumerInput]::Owners.Clear();[FileQuayQualification.ConsumerInput]::Chains.Clear();[FileQuayQualification.ConsumerInput]::States.Clear()
    foreach ($pair in @(@(262620,7272),@(66112,7760),@(909,999))) {
        $h=[long]$pair[0];$p=[int]$pair[1];$root=[FileQuayPickerScopeReplay.Automation.AutomationElement]::new()
        $root.Current.NativeWindowHandle=$h;$root.Current.ProcessId=$p
        [FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[$h]=$root
        [FileQuayQualification.ConsumerInput]::Owners[$h]=[uint32]$p
        [FileQuayQualification.ConsumerInput]::Chains[$h]=[long[]]$(if ($h -eq 66112) {@(66112,262620)} else {@($h)})
        $state=[Collections.Generic.Dictionary[string,object]]::new()
        foreach ($entry in @{app_live=$true;main_live=$true;main_pid=7272;target_process_live=$true;target_live=$true;target_visible=$true;
            target_enabled=($h -ne 262620);target_pid=$p;target_hwnd=$h;foreground_hwnd=66112;owner_chain=[FileQuayQualification.ConsumerInput]::Chains[$h]}.GetEnumerator()) {$state[$entry.Key]=$entry.Value}
        [FileQuayQualification.ConsumerInput]::States[$h]=$state
    }
    [FileQuayPickerScopeReplay.Automation.AutomationElement]::RootElement.Children=@([FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[262620])
}
$checks=0
Reset-Scenario
$scopes=@(Get-FileQuayWorkflowScopes $ui -AllowBroker)
Require ($scopes.Count -eq 2 -and @($scopes | Where-Object target_hwnd -EQ 66112).Count -eq 1) 'Owned foreground picker absent from desktop enumeration was not discovered.';$checks++
Require ($ui.brokers['7760'] -eq $broker -and $retains -eq 1) 'Picker process handle was not retained exactly once.';$checks++
Reset-Scenario
[FileQuayPickerScopeReplay.Automation.AutomationElement]::RootElement.Children+=@([FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[66112],[FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[66112])
Require (@(Get-FileQuayWorkflowScopes $ui -AllowBroker).Count -eq 2) 'Duplicate native HWND produced duplicate scopes.';$checks++
Reset-Scenario
Require (@(Get-FileQuayWorkflowScopes $ui).Count -eq 1 -and $retains -eq 0 -and 66112 -notin [FileQuayPickerScopeReplay.Automation.AutomationElement]::Reads) 'Broker was read without explicit AllowBroker.';$checks++
Reset-Scenario
[FileQuayQualification.ConsumerInput]::States[262620]['foreground_hwnd']=909
Require (@(Get-FileQuayWorkflowScopes $ui -AllowBroker).Count -eq 1 -and 909 -notin [FileQuayPickerScopeReplay.Automation.AutomationElement]::Reads) 'Unowned foreground UI was read.';$checks++
foreach ($scenario in @('app-exited','app-invalid','changed-foreground','changed-target-pid','changed-chain','main-pid','main-gone','broker-exited','broker-closed','broker-invalid','changed-owner','wrong-uia-pid','wrong-uia-hwnd','offscreen','broker-cache-exited','budget')) {
    Reset-Scenario
    switch ($scenario) {
        'app-exited' {$ui.application.HasExited=$true}
        'app-invalid' {$ui.application.SafeHandle.IsInvalid=$true}
        'changed-foreground' {[FileQuayQualification.ConsumerInput]::States[66112]['foreground_hwnd']=909}
        'changed-target-pid' {[FileQuayQualification.ConsumerInput]::States[66112]['target_pid']=999}
        'changed-chain' {[FileQuayQualification.ConsumerInput]::States[66112]['owner_chain']=@(66112,909)}
        'main-pid' {[FileQuayQualification.ConsumerInput]::States[262620]['main_pid']=999}
        'main-gone' {[FileQuayQualification.ConsumerInput]::States[262620]['main_live']=$false}
        'broker-exited' {$broker.HasExited=$true}
        'broker-closed' {$broker.SafeHandle.IsClosed=$true}
        'broker-invalid' {$broker.SafeHandle.IsInvalid=$true}
        'changed-owner' {$script:changeOwner=$true}
        'wrong-uia-pid' {[FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[66112].Current.ProcessId=999}
        'wrong-uia-hwnd' {[FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[66112].Current.NativeWindowHandle=909}
        'offscreen' {[FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[66112].Current.IsOffscreen=$true}
        'broker-cache-exited' {$ui.brokers['7760']=$broker;$broker.HasExited=$true}
        'budget' {1..8 | ForEach-Object {$ui.brokers[[string]$_]=New-Process $_}}
    }
    $accepted=@();try {$accepted=@(Get-FileQuayWorkflowScopes $ui -AllowBroker)} catch {}
    Require (@($accepted | Where-Object target_hwnd -EQ 66112).Count -eq 0) "Accepted $scenario";$checks++
}
Reset-Scenario
[FileQuayPickerScopeReplay.Automation.AutomationElement]::RootElement.Children=@(1..129 | ForEach-Object {[FileQuayPickerScopeReplay.Automation.AutomationElement]::Roots[262620]})
Reject {Get-FileQuayWorkflowScopes $ui -AllowBroker} 'desktop budget';$checks++
"PASS actual owned-foreground scope discovery and rejection checks: $checks"
function Reset-Filename {
    $scope=@{target_hwnd=66112;target_pid=7760}
    $script:hostControl=@{scope=$scope;element=[pscustomobject]@{Current=[pscustomobject]@{ClassName='AppControlHost'}}}
    $script:filename=@{scope=$scope;element=[pscustomobject]@{Current=[pscustomobject]@{ClassName='Edit'}}}
    $filename.element | Add-Member ScriptMethod TryGetCurrentPattern {
        param($Pattern,$Result)
        if ($script:throwPattern) {throw 'Value provider unavailable'}
        $Result.Value=$(if ($script:nullPattern) {$null} else {[pscustomobject]@{Current=[pscustomobject]@{IsReadOnly=$script:readOnly}}})
        $script:supported
    }
    $script:address=@{scope=$scope;element=[pscustomobject]@{Current=[pscustomobject]@{ClassName='ToolbarWindow32'}}}
    $script:duplicateHost=$false;$script:duplicateFilename=$false;$script:outsideHost=$false
    $script:supported=$true;$script:readOnly=$false;$script:nullPattern=$false;$script:throwPattern=$false;$script:unscoped=0
}
# Keep the actual single-match selector. Only model which observed descendants
# the UI provider returns for the exact host, including the real ID collision.
function Find-FileQuayWorkflowElements($Ui,[string]$Id='',[string]$Name='',$Within=$null,[switch]$AllowBroker,[switch]$IncludeHidden) {
    Require (-not $IncludeHidden) 'Filename selection included hidden controls.'
    if ($Id -ceq 'FileNameControlHost') {
        Require $AllowBroker 'Native host was searched without broker ownership.'
        $script:hostControl;if ($script:duplicateHost) {$script:hostControl}
    } elseif ($Id -ceq '1001') {
        if ($null -eq $Within) {$script:unscoped++;$script:address;$script:filename;return}
        Require ([object]::ReferenceEquals($Within,$script:hostControl)) 'Filename lookup escaped its exact host.'
        if (-not $script:outsideHost) {$script:filename;if ($script:duplicateFilename) {$script:filename}}
    } else {throw "Unexpected filename selector: $Id"}
}
Reset-Scenario;Reset-Filename
$selected=Find-FileQuayWorkflowSaveFilename $ui
Require ([object]::ReferenceEquals($selected,$filename) -and $unscoped -eq 0) 'Same-ID address bar was not excluded by exact host scope.';$checks++
foreach ($scenario in @('duplicate-host','duplicate-filename','outside-host','address-class','wrong-host','main-window','foreign-pid','foreign-hwnd','unsupported','read-only','null-pattern','provider-failure')) {
    Reset-Filename
    switch ($scenario) {
        'duplicate-host' {$script:duplicateHost=$true}
        'duplicate-filename' {$script:duplicateFilename=$true}
        'outside-host' {$script:outsideHost=$true}
        'address-class' {$filename.element.Current.ClassName='ToolbarWindow32'}
        'wrong-host' {$hostControl.element.Current.ClassName='Pane'}
        'main-window' {$hostControl.scope.target_hwnd=$ui.main_hwnd}
        'foreign-pid' {$filename.scope=@{target_hwnd=66112;target_pid=999}}
        'foreign-hwnd' {$filename.scope=@{target_hwnd=909;target_pid=7760}}
        'unsupported' {$script:supported=$false}
        'read-only' {$script:readOnly=$true}
        'null-pattern' {$script:nullPattern=$true}
        'provider-failure' {$script:throwPattern=$true}
    }
    Reject {Find-FileQuayWorkflowSaveFilename $ui} $scenario;$checks++
}
foreach ($scenario in @('unsupported','null pattern','read-only','identity or class')) {
    Reset-Filename
    switch ($scenario) {
        'unsupported' {$script:supported=$false}
        'null pattern' {$script:nullPattern=$true}
        'read-only' {$script:readOnly=$true}
        'identity or class' {$filename.element.Current.ClassName='ToolbarWindow32'}
    }
    $failure='';try {Find-FileQuayWorkflowSaveFilename $ui | Out-Null} catch {$failure=$_.Exception.Message}
    Require ($failure.Contains($scenario)) "Filename rejection did not identify actual gate: $scenario; $failure";$checks++
}
"PASS actual owned scope and native filename selector checks: $checks (provider replay; native Windows remains pending)."
