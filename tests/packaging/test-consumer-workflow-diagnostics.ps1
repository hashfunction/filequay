# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1')

function Require([bool]$Condition,[string]$Message) { if (-not $Condition) {throw $Message} }
function New-Node([string]$Id,[int]$Owner=71) {
    [pscustomobject]@{Current=[pscustomobject]@{ProcessId=$Owner;AutomationId=$Id;Name=$Id;ClassName='Test';
        ControlType=[pscustomobject]@{ProgrammaticName='ControlType.Button'};IsOffscreen=$false;IsEnabled=$true;
        HasKeyboardFocus=$false;IsKeyboardFocusable=$true};Children=@();Next=$null}
}
$walker=[pscustomobject]@{}
$walker | Add-Member ScriptMethod GetFirstChild {param($Node) if ($Node.Children.Count) {$Node.Children[0]}}
$walker | Add-Member ScriptMethod GetNextSibling {param($Node) $Node.Next}
function Observe($Root) { @(Get-FileQuayWorkflowObservedTree @{root=$Root;target_pid=71;target_hwnd=101} $walker) }
$checks=0
Require ((Limit-FileQuayWorkflowDiagnosticText ('x'*2048)).Length -eq 1024) 'Diagnostic text exceeded its field budget.';$checks++
$root=New-Node 'toolbar';$root.Current.ControlType=50021
$paste=New-Node 'InnerNavigationToolbarPasteButton';$paste.Current.IsEnabled=$false
$root.Children=@($paste)
$nodes=@(Observe $root)
Require ($nodes.Count -eq 2) 'An unknown control type discarded the toolbar descendants.';$checks++
Require ($nodes[0].automation_id -ceq 'toolbar' -and $nodes[0].control_type_raw -ceq '50021' -and $nodes[0].property_errors.Contains('control_type')) 'Unknown type lost identity or error evidence.';$checks++
Require ($nodes[1].automation_id -ceq 'InnerNavigationToolbarPasteButton' -and -not $nodes[1].enabled) 'Disabled Paste was not retained.';$checks++
$paste.Current.IsOffscreen=$true
$nodes=@(Observe $root)
Require $nodes[1].offscreen 'Offscreen Paste was not retained.';$checks++
$root.Current.PSObject.Properties.Remove('Name')
$nodes=@(Observe $root)
Require ($nodes.Count -eq 2 -and $nodes[0].property_errors.Contains('name')) 'One failing property discarded descendants.';$checks++
$paste.Current.ProcessId=72
$nodes=@(Observe $root)
Require ($nodes.Count -eq 1) 'A foreign-process descendant entered owned metadata.';$checks++
$paste.Current.ProcessId=71
$root.Current.PSObject.Properties.Remove('ProcessId')
$nodes=@(Observe $root)
Require ($nodes.Count -eq 1 -and $nodes[0].Contains('observation_error')) 'Unreadable process identity did not refuse subtree.';$checks++
$root=New-Node 'root';$last=$root
for ($i=1;$i -lt 12;$i++) {$child=New-Node "depth-$i";$last.Children=@($child);$last=$child}
$nodes=@(Observe $root)
Require ($nodes.Count -eq 9 -and $nodes[-1].depth -eq 8) 'Depth budget was not respected.';$checks++
$root=New-Node 'root';$children=@(1..200 | ForEach-Object {New-Node "child-$_"})
for ($i=0;$i -lt 199;$i++) {$children[$i].Next=$children[$i+1]};$root.Children=$children
$nodes=@(Observe $root)
Require ($nodes.Count -eq 160) 'Node budget was not respected.';$checks++
$nodes=@(Get-FileQuayWorkflowObservedTree @{root=$root;target_pid=71;target_hwnd=101} $walker 2)
Require ($nodes.Count -eq 2) 'Remaining cross-window node budget was not respected.';$checks++
$brokenWalker=[pscustomobject]@{}
$brokenWalker | Add-Member ScriptMethod GetFirstChild {param($Node) throw 'Child provider failed'}
$nodes=@(Get-FileQuayWorkflowObservedTree @{root=$root;target_pid=71;target_hwnd=101} $brokenWalker)
Require ($nodes.Count -eq 1 -and $nodes[0].children_error.Contains('Child provider failed')) 'A child provider error lost its parent identity.';$checks++

# Exercise the actual observation entry point with a read-only scoped provider.
$script:observedPaste=New-Node 'InnerNavigationToolbarPasteButton';$script:observedPaste.Current.IsEnabled=$false
function Find-FileQuayWorkflowElements($Ui,$Id,[switch]$IncludeHidden) {
    if (-not $IncludeHidden) {throw 'Diagnostic lookup filtered disabled/offscreen controls.'}
    if ($Id -ceq 'InnerNavigationToolbarPasteButton') {@{element=$script:observedPaste;scope=@{target_pid=71;target_hwnd=101}}}
}
function Invoke-FileQuayWorkflowAction {throw 'A diagnostic attempted input.'}
$ui=@{application=$null;main_hwnd=101;record=@{trace=[Collections.Generic.List[object]]::new()}}
Add-FileQuayWorkflowClipboardObservation $ui 'test-stage'
Require ($ui.record.trace.Count -eq 1 -and $ui.record.trace[0].details.stage -ceq 'test-stage') 'Stage evidence was not retained.';$checks++
$observation=$ui.record.trace[0].details
Require ($observation.commands.InnerNavigationToolbarPasteButton.Count -eq 1 -and -not $observation.commands.InnerNavigationToolbarPasteButton[0].enabled) 'Stage metadata lost disabled Paste.';$checks++
Require ($observation.Contains('clipboard_error') -and -not $observation.Contains('clipboard')) 'Unavailable native observation was reported as clipboard proof.';$checks++
$script:observedPaste.Current.ProcessId=72
Add-FileQuayWorkflowClipboardObservation $ui 'foreign-stage'
Require ($ui.record.trace[1].details.commands.InnerNavigationToolbarPasteButton.Count -eq 0) 'Stage metadata included a foreign PID.';$checks++
$published=@{consumer_workflow=$ui.record} | ConvertTo-Json -Depth 9 -WarningAction Stop | ConvertFrom-Json -AsHashtable
Require ($published.consumer_workflow.trace[0].details.commands.InnerNavigationToolbarPasteButton[0].enabled -eq $false) 'Existing receipt JSON depth truncated stage metadata.';$checks++

$work=Join-Path $(if ($IsMacOS) {'/private/tmp'} else {[IO.Path]::GetTempPath()}) ('filequay-diagnostic-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
try {
    $path=Join-Path $work 'debug.log'
    [IO.File]::WriteAllText($path,('old line'+"`n")*8000+"last diagnostic line`n")
    $tail=Read-FileQuayWorkflowLogTail $path
    Require ($tail.bytes_read -eq 32768 -and $tail.truncated -and $tail.text.EndsWith("last diagnostic line`n")) 'Log tail was not byte-bounded and end-relative.';$checks++
    Require ($tail.file_bytes -eq (Get-Item $path).Length) 'Log length provenance missing.';$checks++
    [IO.File]::WriteAllText($path,'small')
    $tail=Read-FileQuayWorkflowLogTail $path
    Require ($tail.text -ceq 'small' -and -not $tail.truncated) 'Small log tail changed.';$checks++
    $link=Join-Path $work 'link.log';$null=New-Item -ItemType SymbolicLink -Path $link -Target $path
    $failure='';try {Read-FileQuayWorkflowLogTail $link} catch {$failure=$_.Exception.Message}
    Require ($failure.Contains('regular file')) 'Reparse/link log was read.';$checks++
} finally {Remove-Item -LiteralPath $work -Recurse -Force}
"Consumer diagnostic checks passed: $checks (actual traversal, provider errors, foreign PID, budgets, and log reads)."
