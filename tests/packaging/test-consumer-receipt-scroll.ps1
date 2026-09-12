# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1')
$observed=Get-Content (Join-Path $PSScriptRoot 'fixtures/receipt-scroll-invalid-operation-34693226019.json') -Raw | ConvertFrom-Json
$newObserved=Get-Content (Join-Path $PSScriptRoot 'fixtures/receipt-nonscrollable-34694585269.json') -Raw | ConvertFrom-Json
$newRange=$newObserved.scroll_attempt.details.before
if ($newRange.vertically_scrollable -or $newRange.vertical_scroll_percent -ne -1 -or $newRange.vertical_view_size -ne 100 -or $newObserved.scroll_attempt.details.outcome -cne 'failed') {throw 'Actual non-scrollable pre-call observation differs.'}
$owned=$observed.scroll_action.details.state
$observedList=@($observed.observed_nodes | Where-Object automation_id -CEQ 'ReceiptHistoryList')
if ($observedList.Count -ne 1 -or $observedList[0].process_id -ne $owned.target_pid -or $observedList[0].offscreen -or -not $observedList[0].enabled -or $observedList[0].class_name -cne 'ListView') {throw 'Actual owned list observation differs.'}
# Execute production reader, scroll loop, unique selector and action/ownership
# gates against replaceable UIA providers. This does not claim native UI success.
Add-Type @'
using System;
namespace System.Windows.Automation {
 public class ElementNotAvailableException:Exception {public ElementNotAvailableException():base("Observed unavailable receipt provider") {}}
 public class CurrentInfo {public int ProcessId=Fixture.ProcessId;public string AutomationId,Name;public bool IsOffscreen,IsEnabled=true;public Rectangle BoundingRectangle=new Rectangle();}
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
 public class ScrollInfo {public bool VerticallyScrollable=true,HorizontallyScrollable=false;public double VerticalScrollPercent=0,VerticalViewSize=45,HorizontalScrollPercent=-1,HorizontalViewSize=100;}
 public class ScrollPattern {
  public static object Pattern=new object();public ScrollInfo Current {get {Fixture.RangeReads++;if(Fixture.Mode=="layout-range-error" && Fixture.InvalidOperationCalls>0)throw new Exception("range unavailable after original scroll failure");var v=new ScrollInfo();if(Fixture.InvalidOperationCalls>0){v.VerticallyScrollable=false;v.VerticalScrollPercent=-1;v.VerticalViewSize=100;}if(Fixture.Mode.StartsWith("range-before-") && Fixture.RangeReads>1){v.VerticallyScrollable=false;v.VerticalScrollPercent=Fixture.ObservedScrollPercent;v.VerticalViewSize=Fixture.ObservedViewSize;}return v;}}
  public void Scroll(ScrollAmount x,ScrollAmount y) {Fixture.ScrollCalls++;Fixture.Epoch++;
   if(Fixture.Mode.StartsWith("range-before-") || Fixture.Mode.StartsWith("layout-")){Fixture.InvalidOperationCalls++;throw new InvalidOperationException("Operation is not valid due to the current state of the object.");}
   if(Fixture.Mode=="other-error")throw new InvalidOperationException("ElementNotAvailableException is only text, not its exception type");
   if(Fixture.Mode=="always-stale" || Fixture.ScrollCalls==1)throw new ElementNotAvailableException();Fixture.Visible=true;}
 }
 public class ExpandCollapsePattern {
  public static object Pattern=new object();private Element element;public ExpandCollapsePattern(Element e){element=e;}
  public void Expand(){Fixture.ExpandCalls++;if(Fixture.Mode=="expand-stale")throw new ElementNotAvailableException();}
  public void Collapse(){Fixture.CollapseCalls++;if(Fixture.Mode=="collapse-stale")throw new ElementNotAvailableException();if(element.Info.Name.StartsWith("Move"))Fixture.Collapsed=true;}
 }
 public class Fixture {public static int Epoch,ScrollCalls,ExpandCalls,CollapseCalls,ListQueries,InvalidOperationCalls,ProcessId,RangeReads;public static double ObservedViewSize,ObservedScrollPercent;public static bool Collapsed,Visible;public static string Mode;}
}
namespace FileQuayQualification {public class ConsumerInput {public static void Foreground(object app,long main,object target,long window){}}}
'@
function Require([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function New-Element([string]$Id,[string]$Name,$Parent=$null) {
    $e=[System.Windows.Automation.Element]::new();$e.Info.AutomationId=$Id;$e.Info.Name=$Name
    $e.Epoch=[System.Windows.Automation.Fixture]::Epoch;$e.Parent=$Parent;$e
}
function New-Binding($Element) {
    @{scope=@{app_pid=$owned.main_pid;main_hwnd=$owned.owner_chain[1];target_pid=$owned.target_pid;target_hwnd=$owned.target_hwnd;process=$ui.application};element=$Element}
}
function New-List {
    [System.Windows.Automation.Fixture]::ListQueries++
    New-Binding (New-Element $observedList[0].automation_id $observedList[0].name)
}
function Reset-Scenario([string]$Mode='stale-once') {
    if ($Mode.StartsWith('range-before-')) {$script:owned=$newObserved.scroll_action.details.state}
    else {$script:owned=$observed.scroll_action.details.state}
    [System.Windows.Automation.Fixture]::Epoch=0;[System.Windows.Automation.Fixture]::ScrollCalls=0
    [System.Windows.Automation.Fixture]::ExpandCalls=0;[System.Windows.Automation.Fixture]::CollapseCalls=0
    [System.Windows.Automation.Fixture]::ListQueries=0;[System.Windows.Automation.Fixture]::Collapsed=$false
    [System.Windows.Automation.Fixture]::Visible=$false;[System.Windows.Automation.Fixture]::Mode=$Mode
    [System.Windows.Automation.Fixture]::InvalidOperationCalls=0
    [System.Windows.Automation.Fixture]::RangeReads=0
    [System.Windows.Automation.Fixture]::ObservedViewSize=$newRange.vertical_view_size
    [System.Windows.Automation.Fixture]::ObservedScrollPercent=$newRange.vertical_scroll_percent
    [System.Windows.Automation.Fixture]::ProcessId=$owned.target_pid
    $script:ui=@{application=@{Id=$owned.main_pid};main_hwnd=$owned.owner_chain[1];record=@{trace=[Collections.Generic.List[object]]::new()};
        strings=@{ReceiptOperationCopy='Copy';ReceiptOperationMove='Move';ReceiptResultSuccess='Completed'}}
    $script:receipts=@(@{id='move-id';fileOperationType=4;sourcePaths=@('owned/copy/résumé,原稿.txt');destinationPaths=@('owned/move/résumé,原稿.txt')},
        @{id='copy-id';fileOperationType=3;sourcePaths=@('owned/source/résumé,原稿.txt');destinationPaths=@('owned/copy/résumé,原稿.txt')})
    if ($Mode -ceq 'duplicate-id') {$script:receipts[1].id='move-id'}
    if ($Mode.StartsWith('range-before-')) {$script:receipts=@($newObserved.persisted_receipts)}
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
function Get-FileQuayWorkflowElementWindow($Element) {$null=$Element.Current;$owned.target_hwnd}
function Get-FileQuayWorkflowText($Binding) {$Binding.element.Current.Name}
function Get-FileQuayWorkflowTargetState($Ui,$Binding) {
    $current=$Binding.element.Current
    @{app_live=$true;target_process_live=$true;main_live=$true;main_pid=$owned.main_pid;target_live=$true;
      target_pid=$owned.target_pid;target_hwnd=$owned.target_hwnd;target_visible=$true;target_enabled=$true;
      foreground_hwnd=$(if (([System.Windows.Automation.Fixture]::Mode -in @('foreign-after-stale','layout-foreign') -and [System.Windows.Automation.Fixture]::ScrollCalls) -or ([System.Windows.Automation.Fixture]::Mode -ceq 'range-before-foreign' -and [System.Windows.Automation.Fixture]::RangeReads -ge 2)) {909} else {$owned.foreground_hwnd});
      owner_chain=@($owned.owner_chain);element_pid=$current.ProcessId;element_hwnd=$owned.target_hwnd;
      element_within_target=$true;element_visible=(-not $current.IsOffscreen);element_enabled=$current.IsEnabled}
}
function Start-Sleep([int]$Milliseconds) {
    Require ($Milliseconds -eq 100) 'Scroll cadence changed.';$script:sleeps++
    if ([System.Windows.Automation.Fixture]::Mode -in @('layout-settles','layout-foreign') -and $sleeps -eq 2) {[System.Windows.Automation.Fixture]::Visible=$true}
    if ([System.Windows.Automation.Fixture]::Mode -eq 'range-before-settles') {[System.Windows.Automation.Fixture]::Visible=$true}
    if ([System.Windows.Automation.Fixture]::Mode -eq 'layout-deadline') {[Threading.Thread]::Sleep(25)}
}
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
Reset-Scenario 'layout-settles'
$result=@(Read-FileQuayWorkflowVisibleReceipts $ui $list $receipts)
Require ($result.Count -eq 2 -and ($result.id -join ',') -ceq 'move-id,copy-id') 'Settled layout lost the original two visible receipt proofs.'
Require ([System.Windows.Automation.Fixture]::ScrollCalls -eq 1 -and [System.Windows.Automation.Fixture]::ExpandCalls -eq 2 -and [System.Windows.Automation.Fixture]::CollapseCalls -eq 2) 'Failed Scroll or other actions were replayed.'
$attempts=@($ui.record.trace | Where-Object step -CEQ 'ReceiptScrollAttempt')
Require ($attempts.Count -eq 1 -and $attempts[0].details.outcome -ceq 'failed' -and $attempts[0].details.before.vertically_scrollable -eq $true -and $attempts[0].details.after.vertically_scrollable -eq $false -and $attempts[0].details.after.vertical_view_size -eq 100) 'Actual before/after range and failed outcome were not retained.'
$visible=@($ui.record.trace | Where-Object {$_.step -ceq 'ReceiptScrollVisibilityRequery' -and $_.details.ContainsKey('visible') -and $_.details.visible})
Require ($visible.Count -eq 1 -and -not $visible[0].details.input_sent -and $visible[0].details.state.target_hwnd -eq $owned.target_hwnd -and $visible[0].details.state.element_visible) 'Actual visible owned detail convergence was not retained.'
$checks++
foreach ($mode in @('layout-never-visible','layout-foreign','layout-range-error')) {
    Reset-Scenario $mode;$failure=$null
    try {Read-FileQuayWorkflowVisibleReceipts $ui $list $receipts | Out-Null} catch {$failure=$_}
    Require ($null -ne $failure -and [System.Windows.Automation.Fixture]::ScrollCalls -eq 1) "Accepted/replayed $mode"
    Require ($failure.Exception.ToString().Contains('Operation is not valid due to the current state of the object.')) 'Original provider error was lost.'
    if ($mode -ceq 'layout-never-visible') {Require ($sleeps -eq 16) 'Read-only convergence escaped the existing 16-attempt budget.'}
    if ($mode -ceq 'layout-foreign') {
        $states=@($ui.record.trace | Where-Object step -CEQ 'ReceiptScrollTargetObservation')
        Require ($states.Count -eq 1 -and $states[0].details.expected_hwnd -eq $owned.target_hwnd -and $states[0].details.state.foreground_hwnd -eq 909) 'Failed target observation was discarded before its assertion.'
    }
    $checks++
}
Reset-Scenario 'layout-deadline'
[System.Windows.Automation.Fixture]::Collapsed=$true
$failure=$null
try {Show-FileQuayWorkflowElement $ui 'Copy · Completed' -MaximumSeconds 0.01 | Out-Null} catch {$failure=$_}
Require ($failure -and $sleeps -le 1 -and [System.Windows.Automation.Fixture]::ScrollCalls -le 1) 'Elapsed deadline returned accepted or continued the attempt budget.'
$checks++
# Run 34694585269 actually recorded false/100%/-1 before the rejected call.
# Discovery's earlier scrollable state is a replay transition inferred from the
# production branch; the subsequent unrecorded ownership bit is not fabricated.
Reset-Scenario 'range-before-settles'
$result=@(Read-FileQuayWorkflowVisibleReceipts $ui $list $receipts)
Require ($result.Count -eq 2 -and ($result.id -join ',') -ceq ($newObserved.persisted_receipts.id -join ',')) 'Skipped scroll lost the two actual visible receipt proofs.'
Require ([System.Windows.Automation.Fixture]::ScrollCalls -eq 0 -and [System.Windows.Automation.Fixture]::ExpandCalls -eq 2 -and [System.Windows.Automation.Fixture]::CollapseCalls -eq 2) 'Known non-scrollable provider was called or other actions replayed.'
$attempts=@($ui.record.trace | Where-Object step -CEQ 'ReceiptScrollAttempt')
Require ($attempts.Count -eq 1 -and $attempts[0].details.outcome -ceq 'not-sent-not-scrollable' -and -not $attempts[0].details.before.vertically_scrollable -and $attempts[0].details.after.vertical_view_size -eq 100) 'Known non-scrollable range was counted as successful input.'
$checks++
foreach ($mode in @('range-before-never-visible','range-before-foreign')) {
    Reset-Scenario $mode;$failure=$null
    try {Read-FileQuayWorkflowVisibleReceipts $ui $list $receipts | Out-Null} catch {$failure=$_}
    Require ($failure -and [System.Windows.Automation.Fixture]::ScrollCalls -eq 0 -and $sleeps -le 16) "Skipped range accepted invisible/foreign data or sent input: $mode"
    $checks++
}
"PASS actual receipt scroll requery, wrapped unavailable provider, fresh scoped identity, exact paths/IDs, ownership refusal, action non-replay and 16-attempt budget: $checks scenarios"
