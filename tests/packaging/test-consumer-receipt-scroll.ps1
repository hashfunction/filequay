# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1')
# Execute production reader, scroll loop, unique selector and action/ownership
# gates against replaceable UIA providers. This does not claim native UI success.
Add-Type @'
using System;
namespace System.Windows.Automation {
 public class ElementNotAvailableException:Exception {public ElementNotAvailableException():base("Observed unavailable receipt provider") {}}
 public class CurrentInfo {public int ProcessId=1896;public string AutomationId,Name;public bool IsOffscreen,IsEnabled=true;public Rectangle BoundingRectangle=new Rectangle();}
 public class Rectangle {public double Top=100;}
 public class Element {
  public CurrentInfo Info=new CurrentInfo();public Element Parent;public int Epoch;
  public CurrentInfo Current {get {if(Epoch!=Fixture.Epoch) throw new ElementNotAvailableException();
   Info.IsOffscreen=Info.AutomationId=="ReceiptDetailsExpander" && Info.Name.StartsWith("Copy") && Fixture.Collapsed && !Fixture.Visible;return Info;}}
  public bool TryGetCurrentPattern(object id,out object pattern) {pattern=new ScrollPattern();return Info.AutomationId=="ReceiptHistoryList";}
  public object GetCurrentPattern(object id) {if(id==ScrollPattern.Pattern)return new ScrollPattern();return new ExpandCollapsePattern(this);}
 }
 public class TreeWalker {public static TreeWalker RawViewWalker=new TreeWalker();public Element GetParent(Element e){return e.Parent;}}
 public enum ScrollAmount {NoAmount,SmallIncrement,SmallDecrement}
 public class ScrollInfo {public bool VerticallyScrollable=true;}
 public class ScrollPattern {
  public static object Pattern=new object();public ScrollInfo Current=new ScrollInfo();
  public void Scroll(ScrollAmount x,ScrollAmount y) {Fixture.ScrollCalls++;Fixture.Epoch++;
   if(Fixture.Mode=="other-error")throw new InvalidOperationException("ElementNotAvailableException is only text, not its exception type");
   if(Fixture.Mode=="always-stale" || Fixture.ScrollCalls==1)throw new ElementNotAvailableException();Fixture.Visible=true;}
 }
 public class ExpandCollapsePattern {
  public static object Pattern=new object();private Element element;public ExpandCollapsePattern(Element e){element=e;}
  public void Expand(){Fixture.ExpandCalls++;if(Fixture.Mode=="expand-stale")throw new ElementNotAvailableException();}
  public void Collapse(){Fixture.CollapseCalls++;if(Fixture.Mode=="collapse-stale")throw new ElementNotAvailableException();if(element.Info.Name.StartsWith("Move"))Fixture.Collapsed=true;}
 }
 public class Fixture {public static int Epoch,ScrollCalls,ExpandCalls,CollapseCalls,ListQueries;public static bool Collapsed,Visible;public static string Mode;}
}
namespace FileQuayQualification {public class ConsumerInput {public static void Foreground(object app,long main,object target,long window){}}}
'@
function Require([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function New-Element([string]$Id,[string]$Name,$Parent=$null) {
    $e=[System.Windows.Automation.Element]::new();$e.Info.AutomationId=$Id;$e.Info.Name=$Name
    $e.Epoch=[System.Windows.Automation.Fixture]::Epoch;$e.Parent=$Parent;$e
}
function New-Binding($Element) {
    @{scope=@{app_pid=1896;main_hwnd=459052;target_pid=1896;target_hwnd=262700;process=$ui.application};element=$Element}
}
function New-List {
    [System.Windows.Automation.Fixture]::ListQueries++
    New-Binding (New-Element 'ReceiptHistoryList' '')
}
function Reset-Scenario([string]$Mode='stale-once') {
    [System.Windows.Automation.Fixture]::Epoch=0;[System.Windows.Automation.Fixture]::ScrollCalls=0
    [System.Windows.Automation.Fixture]::ExpandCalls=0;[System.Windows.Automation.Fixture]::CollapseCalls=0
    [System.Windows.Automation.Fixture]::ListQueries=0;[System.Windows.Automation.Fixture]::Collapsed=$false
    [System.Windows.Automation.Fixture]::Visible=$false;[System.Windows.Automation.Fixture]::Mode=$Mode
    $script:ui=@{application=@{Id=1896};main_hwnd=459052;record=@{trace=[Collections.Generic.List[object]]::new()};
        strings=@{ReceiptOperationCopy='Copy';ReceiptOperationMove='Move';ReceiptResultSuccess='Completed'}}
    $script:receipts=@(@{id='move-id';fileOperationType=4;sourcePaths=@('owned/copy/résumé,原稿.txt');destinationPaths=@('owned/move/résumé,原稿.txt')},
        @{id='copy-id';fileOperationType=3;sourcePaths=@('owned/source/résumé,原稿.txt');destinationPaths=@('owned/copy/résumé,原稿.txt')})
    if ($Mode -ceq 'duplicate-id') {$script:receipts[1].id='move-id'}
    $script:list=New-List;$script:sleeps=0
}
function Find-FileQuayWorkflowElements($Ui,[string]$Id='',[string]$Name='',$Within=$null,[switch]$AllowBroker,[switch]$IncludeHidden) {
    Require (-not $AllowBroker) 'Receipt lookup enabled broker discovery.'
    if ($Id -ceq 'ReceiptHistoryList') {Require ($null -eq $Within) 'List discovery reused a retained ancestor.';New-List;return}
    $null=$Within.element.Current
    if ($Id -ceq 'ReceiptDetailsExpander') {
        Require ($Within.element.Info.AutomationId -ceq 'ReceiptHistoryList') 'Receipt card escaped its exact current list.'
        foreach ($title in @('Move · Completed','Copy · Completed')) {
            if ($Name -and $Name -cne $title) {continue}
            $b=New-Binding (New-Element $Id $title $Within.element)
            if ($IncludeHidden -or -not $b.element.Current.IsOffscreen) {$b}
            if ([System.Windows.Automation.Fixture]::Mode -ceq 'duplicate-card' -and $Name -and $title.StartsWith('Copy')) {$b}
        }
    } elseif ($Id -in @('ReceiptSourcePaths','ReceiptDestinationPaths')) {
        Require ($Within.element.Info.AutomationId -ceq 'ReceiptDetailsExpander') 'Receipt detail escaped its current exact card.'
        $r=$receipts[$(if ($Within.element.Info.Name.StartsWith('Move')) {0} else {1})]
        $text=if ($Id -ceq 'ReceiptSourcePaths') {$r.sourcePaths[0]} else {$r.destinationPaths[0]}
        if ([System.Windows.Automation.Fixture]::Mode -ceq 'wrong-path' -and $Id -ceq 'ReceiptDestinationPaths') {$text='unowned/wrong'}
        New-Binding (New-Element $Id $text $Within.element)
    } else {throw "Unexpected receipt selector $Id"}
}
function Get-FileQuayWorkflowElementWindow($Element) {$null=$Element.Current;262700}
function Get-FileQuayWorkflowText($Binding) {$Binding.element.Current.Name}
function Get-FileQuayWorkflowTargetState($Ui,$Binding) {
    $current=$Binding.element.Current
    @{app_live=$true;target_process_live=$true;main_live=$true;main_pid=1896;target_live=$true;
      target_pid=1896;target_hwnd=262700;target_visible=$true;target_enabled=$true;
      foreground_hwnd=$(if ([System.Windows.Automation.Fixture]::Mode -eq 'foreign-after-stale' -and [System.Windows.Automation.Fixture]::ScrollCalls) {909} else {262700});
      owner_chain=@(262700,459052);element_pid=$current.ProcessId;element_hwnd=262700;
      element_within_target=$true;element_visible=(-not $current.IsOffscreen);element_enabled=$current.IsEnabled}
}
function Start-Sleep([int]$Milliseconds) {Require ($Milliseconds -eq 100) 'Scroll cadence changed.';$script:sleeps++}
function Wait-FileQuayWorkflow([scriptblock]$Observe,[string]$Description,[int]$Seconds=30) {& $Observe}
$checks=0
Reset-Scenario
$result=@(Read-FileQuayWorkflowVisibleReceipts $ui $list $receipts)
Require ($result.Count -eq 2 -and ($result.id -join ',') -ceq 'move-id,copy-id') 'Distinct persisted receipt identity or paths were lost.'
Require ([System.Windows.Automation.Fixture]::ScrollCalls -eq 2 -and [System.Windows.Automation.Fixture]::ExpandCalls -eq 2 -and [System.Windows.Automation.Fixture]::CollapseCalls -eq 2) 'Scroll did not requery or other actions were replayed.'
Require (@($ui.record.trace | Where-Object step -CEQ 'ReceiptScrollRequery').Count -eq 1) 'Stale scroll observation was not retained.';$checks++
foreach ($mode in @('always-stale','other-error','foreign-after-stale','duplicate-card','wrong-path','duplicate-id','expand-stale','collapse-stale')) {
    Reset-Scenario $mode;$failure=$null
    try {Read-FileQuayWorkflowVisibleReceipts $ui $list $receipts | Out-Null} catch {$failure=$_}
    Require ($null -ne $failure) "Accepted $mode"
    if ($mode -eq 'always-stale') {
        Require ([System.Windows.Automation.Fixture]::ScrollCalls -eq 16 -and $sleeps -eq 16) 'Stale observations bypassed the 16-attempt total scroll budget.'
        Require ($failure.Exception.Message -match 'scroll budget' -and $failure.Exception.InnerException -is [System.Windows.Automation.ElementNotAvailableException]) 'Budget failure or original unavailable exception was obscured.'
    } elseif ($mode -eq 'other-error') {Require ([System.Windows.Automation.Fixture]::ScrollCalls -eq 1) 'An unrelated provider failure was retried.'}
    elseif ($mode -eq 'foreign-after-stale') {Require ([System.Windows.Automation.Fixture]::ScrollCalls -eq 1) 'Requery scrolled a foreign foreground window.'}
    elseif ($mode -eq 'expand-stale') {Require ([System.Windows.Automation.Fixture]::ExpandCalls -eq 1 -and [System.Windows.Automation.Fixture]::ScrollCalls -eq 0) 'Non-scroll action was replayed.'}
    elseif ($mode -eq 'collapse-stale') {Require ([System.Windows.Automation.Fixture]::CollapseCalls -eq 1 -and [System.Windows.Automation.Fixture]::ExpandCalls -eq 1) 'Collapse was replayed.'}
    $checks++
}
"PASS actual receipt scroll requery, wrapped unavailable provider, fresh scoped identity, exact paths/IDs, ownership refusal, action non-replay and 16-attempt budget: $checks scenarios"
