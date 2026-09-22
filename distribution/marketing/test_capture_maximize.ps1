# Copyright 2026 Trieflow LLC. MIT. Exact observed caption route; no Windows acceptance.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_ui.ps1')
Add-Type @'
namespace FolderSailMarketing { public static class Native {
 public static bool Maximized; public static System.Collections.Generic.Dictionary<string,object> Frame(long handle) {
  return new System.Collections.Generic.Dictionary<string,object>{{"hwnd",handle},{"pid",42},{"maximized",Maximized}};
 }
} }
namespace System.Windows.Automation { public static class ControlType { public static readonly object Button=new object(); } }
'@
function Assert-FolderSailMarketingProcess {param($State)}
function Get-FileQuayWorkflowMain {param($Ui) return $script:main}
function Find-FileQuayWorkflowElement {param($Ui,$Id,$Name,$Within)
    if($Id -cne 'Maximize' -or $Name -cne 'Maximize' -or $Within -ne $script:main){throw 'Caption selector or owned main scope changed'}
    return $script:button
}
function Invoke-FileQuayWorkflowAction {param($Ui,$Binding,$Action)
    if($Binding -ne $script:button -or $Action -cne 'Invoke'){throw 'Unexpected maximize input'}
    $script:actions++
    if($script:scenario -eq 'action-failed'){throw 'original caption action failed'}
    if($script:scenario -ne 'no-state-change'){[FolderSailMarketing.Native]::Maximized=$true}
}
function Wait-FileQuayWorkflow {param($Probe,$Description)
    for($i=0;$i -lt 3;$i++){if(& $Probe){return}}
    throw 'native maximized state not reached'
}
foreach($script:scenario in @('normal','already-maximized','foreign-window','foreign-pid','wrong-role','action-failed','no-state-change')){
    $s=@{ui=@{main_hwnd=11};process=@{Id=42};record=@{}}
    $script:main=@{scope=@{target_hwnd=11}}
    $script:button=@{scope=@{target_hwnd=11};element=@{Current=@{ProcessId=42;ControlType=[System.Windows.Automation.ControlType]::Button}}}
    $script:actions=0;[FolderSailMarketing.Native]::Maximized=$scenario -eq 'already-maximized'
    if($scenario -eq 'foreign-window'){$script:button.scope.target_hwnd=99}
    if($scenario -eq 'foreign-pid'){$script:button.element.Current.ProcessId=99}
    if($scenario -eq 'wrong-role'){$script:button.element.Current.ControlType=$null}
    $failure=$null;try{Set-FolderSailMarketingMaximized $s}catch{$failure=$_.Exception.Message}
    if(($null -eq $failure) -ne ($scenario -in @('normal','already-maximized'))){throw "Maximize result differs: $scenario / $failure"}
    $expectedMoves=if($scenario -in @('normal','action-failed','no-state-change')){1}else{0}
    if($actions -ne $expectedMoves){throw "Caption action repeated or sent to a foreign target: $scenario"}
    if($scenario -eq 'action-failed' -and $failure -cne 'original caption action failed'){throw 'Original action error changed'}
    if($scenario -eq 'no-state-change' -and ($failure -cne 'native maximized state not reached' -or $s.record.window_placement.after.maximized)){throw 'Incomplete native placement accepted'}
}
Write-Output 'PASS seven exact caption-route cases, one action/no replay, native-state requirement and original failure preservation.'
