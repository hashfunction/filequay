# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.PickerDiagnostic.ps1')
function Require([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Reject([scriptblock]$Action,[string]$Message) {
    $failure='';try {& $Action} catch {$failure=$_.Exception.Message}
    Require ($failure.Contains($Message)) "Expected '$Message'; observed '$failure'."
}
function New-State {
    @{app_live=$true;main_live=$true;main_pid=71;target_process_live=$true;target_live=$true;
        target_pid=72;target_hwnd=202;target_visible=$true;target_enabled=$true;foreground_hwnd=202;owner_chain=@(202,101)}
}
$scope=@{app_pid=71;main_hwnd=101;target_pid=72;target_hwnd=202}
$checks=0
Assert-FileQuayPickerDiagnosticTarget $scope (New-State);$checks++
foreach ($key in @('app_live','main_live','target_process_live','target_live','target_visible')) {
    $state=New-State;$state[$key]=$false
    Reject {Assert-FileQuayPickerDiagnosticTarget $scope $state} 'ownership';$checks++
}
foreach ($key in @('main_pid','target_pid','target_hwnd','foreground_hwnd')) {
    $state=New-State;$state[$key]=999
    Reject {Assert-FileQuayPickerDiagnosticTarget $scope $state} 'ownership';$checks++
}
foreach ($chain in @(@(202,999),@(101,202),@(202,101,202),@(202,1,2,3,4,5,6,7,101))) {
    $state=New-State;$state.owner_chain=$chain
    Reject {Assert-FileQuayPickerDiagnosticTarget $scope $state} 'ownership';$checks++
}
$state=New-State;$state.target_enabled=$false
Assert-FileQuayPickerDiagnosticTarget $scope $state;$checks++

$bounds=[pscustomobject]@{X=20.4;Y=30.2;Width=800.2;Height=600.4}
$desktop=[pscustomobject]@{X=0;Y=0;Width=1024;Height=768}
$pixels=Get-FileQuayPickerCaptureBounds $bounds $desktop
Require ($pixels.x -eq 20 -and $pixels.y -eq 30 -and $pixels.width -eq 801 -and $pixels.height -eq 601) 'Native bounds rounding differs.';$checks++
foreach ($change in @(@{X=-1},@{Width=1100},@{Height=0},@{Width=[double]::NaN},@{X=[double]::PositiveInfinity},@{Width=8193})) {
    $bad=[pscustomobject]@{X=20;Y=30;Width=800;Height=600}
    foreach ($key in $change.Keys) {$bad.$key=$change[$key]}
    Reject {Get-FileQuayPickerCaptureBounds $bad $desktop} 'bounds';$checks++
}

function New-Node([string]$Id,[int]$Owner=72) {
    [pscustomobject]@{Current=[pscustomobject]@{ProcessId=$Owner;NativeWindowHandle=202;AutomationId=$Id;Name=$Id;ClassName='#32770';
        ControlType=[pscustomobject]@{ProgrammaticName='ControlType.Window'};IsOffscreen=$false;IsEnabled=$true;
        HasKeyboardFocus=$false;IsKeyboardFocusable=$true};Children=@();Next=$null}
}
$script:walker=[pscustomobject]@{}
$walker | Add-Member ScriptMethod GetFirstChild {param($Node) if ($Node.Children.Count) {$Node.Children[0]}}
$walker | Add-Member ScriptMethod GetNextSibling {param($Node) $Node.Next}
function Reset-Scenario {
    $script:state=New-State;$script:owner=@{process_id=72;owner_chain=@(202,101)}
    $script:root=New-Node 'save-picker';$script:root.Children=@((New-Node '1001'))
    $script:stateCalls=0;$script:rootReads=0;$script:captures=0;$script:disposed=0;$script:changeAt=0;$script:throwCapture=$false
    $script:process=[pscustomobject]@{Id=72;HasExited=$false;SafeHandle=[pscustomobject]@{IsInvalid=$false;IsClosed=$false}}
    $script:process | Add-Member ScriptMethod Dispose {$script:disposed++}
}
function Get-FileQuayPickerNativeState($Ui,$Process,[long]$Handle) {
    $script:stateCalls++
    $copy=@{}+$script:state
    if ($script:changeAt -and $script:stateCalls -ge $script:changeAt) {$copy.owner_chain=@(202,999)}
    $copy
}
function Get-FileQuayPickerOwner([long]$Handle) {$script:owner}
function Get-FileQuayPickerProcess([int]$Owner) {$script:process}
function Get-FileQuayPickerRoot([long]$Handle) {$script:rootReads++;$script:root}
function Get-FileQuayPickerWalker([string]$View) {$script:walker}
function Get-FileQuayPickerDesktopWindows {
    $foreign=[pscustomobject]@{Current=[pscustomobject]@{NativeWindowHandle=909}}
    $foreign.Current | Add-Member ScriptProperty Name {throw 'Foreign UI text must not be read.'}
    @($foreign,$script:root)
}
function Save-FileQuayPickerDiagnosticScreenshot($Ui,$Scope,[string]$Path) {
    $script:captures++
    if ($script:throwCapture) {throw 'Capture provider failed'}
    @{name='consumer-save-picker-failure.png';fixture_only=$true}
}
$ui=@{application=[pscustomobject]@{Id=71;HasExited=$false};main_hwnd=101;evidence='/owned/evidence';record=@{passed=$false}}
Reset-Scenario
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.owned_foreground -eq $true -and $observed.control_tree.Count -eq 2 -and $observed.raw_tree.Count -eq 2) 'Exact foreground picker tree missing.';$checks++
Require ($observed.control_tree[1].automation_id -ceq '1001' -and $captures -eq 1 -and $disposed -eq 1) 'Owned capture or retained-handle disposal missing.';$checks++
Require ($observed.desktop_scope.windows_observed -eq 2 -and $observed.desktop_scope.matching_roots.Count -eq 1 -and
    $observed.desktop_scope.matching_roots[0].process_id_matches -eq $true -and -not $observed.desktop_scope.matching_roots[0].offscreen) 'Exact owned desktop scope eligibility was not retained.';$checks++
Require (-not $ui.record.passed) 'Diagnostic granted consumer acceptance.';$checks++
Reset-Scenario;$script:owner.owner_chain=@(202,999)
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require (-not $observed.owned_foreground -and $rootReads -eq 0 -and $captures -eq 0 -and -not $observed.Contains('control_tree')) 'Foreign foreground contents were read.';$checks++
Reset-Scenario;$script:process.Id=99
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.observation_error.Contains('process') -and $rootReads -eq 0 -and $disposed -eq 1) 'Changed process reached UI contents or leaked handle.';$checks++
Reset-Scenario;$script:process.SafeHandle.IsInvalid=$true
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.observation_error.Contains('process') -and $rootReads -eq 0 -and $disposed -eq 1) 'Invalid retained process reached UI.';$checks++
Reset-Scenario;$script:changeAt=3
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.observation_error.Contains('ownership') -and -not $observed.owned_foreground -and -not $observed.Contains('control_tree') -and
    $observed.foreground_hwnd -eq 202 -and $captures -eq 0 -and $disposed -eq 1) 'Changed owner leaked contents, lost identity or reached pixels.';$checks++
Reset-Scenario;$script:root.Current.ProcessId=99
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.observation_error.Contains('UIA') -and $captures -eq 0 -and $disposed -eq 1) 'Foreign UIA root reached pixels.';$checks++
Reset-Scenario;$script:root.Current.PSObject.Properties.Remove('Name')
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.control_tree.Count -eq 2 -and $observed.control_tree[0].property_errors.Contains('name')) 'Property failure discarded picker descendants.';$checks++
Reset-Scenario;$script:root.Current.IsOffscreen=$true
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.desktop_scope.matching_roots[0].offscreen -and $observed.raw_tree.Count -eq 2) 'Offscreen UIA scope exclusion concealed the owned native foreground.';$checks++
Reset-Scenario;$script:root.Current.NativeWindowHandle=0
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.desktop_scope.matching_roots.Count -eq 0 -and $observed.desktop_scope.zero_handle_roots -eq 1 -and $observed.raw_tree.Count -eq 2) 'Missing UIA native handle concealed native-owned foreground evidence.';$checks++
function Get-FileQuayPickerDesktopWindows {1..129 | ForEach-Object {$script:root}}
Reset-Scenario
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.desktop_scope_error.Contains('window budget') -and $observed.raw_tree.Count -eq 2) 'Desktop enumeration budget failure discarded bounded direct-owned evidence.';$checks++
function Get-FileQuayPickerDesktopWindows {@($script:root)}
Reset-Scenario
$children=@(1..200 | ForEach-Object {New-Node "item-$_"})
for ($i=0;$i -lt 199;$i++) {$children[$i].Next=$children[$i+1]};$script:root.Children=$children
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.control_tree.Count -eq 80 -and $observed.raw_tree.Count -eq 80) 'Combined tree node budget exceeded.';$checks++
Reset-Scenario;$script:throwCapture=$true
$observed=Get-FileQuayPickerFailureDiagnostic $ui
Require ($observed.control_tree.Count -eq 2 -and $observed.screenshot_error.Contains('Capture provider failed')) 'Secondary screenshot failure discarded picker tree.';$checks++

# Execute the real export boundary, with only platform observation/action adapters scoped.
function Find-FileQuayWorkflowElement {param($Ui,$Id,[switch]$AllowBroker) if ($Id -ceq 'ReceiptExportButton') {return 'export'};throw "Expected one owned workflow element '1001'/''; observed 0."}
function Invoke-FileQuayWorkflowAction {param($Ui,$Binding,$Action) Require ($Binding -ceq 'export' -and $Action -ceq 'Invoke') 'Unexpected diagnostic input.'}
function Wait-FileQuayWorkflow {param([scriptblock]$Observe,[string]$Description) & $Observe}
Reset-Scenario
Reject {Open-FileQuayWorkflowExportConfirmation $ui @{csv='/owned/receipts.csv'}} "observed 0"
Require ($ui.record.save_picker_failure.control_tree.Count -eq 2 -and -not $ui.record.passed) 'Actual export timeout did not retain diagnostic failure.';$checks++
Reset-Scenario;$script:changeAt=2
Reject {Open-FileQuayWorkflowExportConfirmation $ui @{csv='/owned/receipts.csv'}} 'observed 0'
Require ($ui.record.save_picker_failure.observation_error.Contains('ownership')) 'Partial diagnostic identity was lost on ownership failure.';$checks++
Reset-Scenario;$script:state.app_live=$false
Reject {Open-FileQuayWorkflowExportConfirmation $ui @{csv='/owned/receipts.csv'}} 'observed 0'
Require ($ui.record.save_picker_diagnostic_error.Contains('ownership')) 'Diagnostic failure replaced original missing-element failure.';$checks++
"Consumer picker diagnostic checks passed: $checks (production boundaries; no native UI or pixels claimed)."
