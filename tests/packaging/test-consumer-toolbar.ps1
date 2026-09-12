# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Ui.ps1')

function Require([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function New-Binding([string]$Id,[string]$Name,[string]$Class) {
    @{scope=@{app_pid=71;main_hwnd=101;target_pid=71;target_hwnd=101};
      element=[pscustomobject]@{Current=[pscustomobject]@{AutomationId=$Id;Name=$Name;ClassName=$Class;
        ProcessId=71;IsEnabled=$true;IsOffscreen=$false}}}
}
function Reset-Scenario([bool]$Direct=$false) {
    $script:ui=@{application=@{Id=71};main_hwnd=101;record=@{trace=[Collections.Generic.List[object]]::new()}}
    $script:main=New-Binding '' 'main' 'Window'
    $script:bar=New-Binding 'ContextCommandBar' '' 'ApplicationBar'
    $script:more=New-Binding 'MoreButton' 'More options' 'Button'
    $script:paste=New-Binding 'InnerNavigationToolbarPasteButton' 'Paste' 'AppBarButton'
    $script:actions=[Collections.Generic.List[string]]::new()
    $script:opened=$false;$script:direct=$Direct;$script:withhold=$false;$script:duplicate=$false
    $script:foreignForeground=$false;$script:postForeign=$false;$script:failMore=$false
    $script:duplicateMore=$false;$script:missingMore=$false;$script:waits=0
}
# Execute the actual production sequencing with observed UI providers. Input stays
# behind the production ownership predicate; this fixture is not Windows UI proof.
function Wait-FileQuayWorkflow([scriptblock]$Observe,[string]$Description,[int]$Seconds=30) {
    Require ($Seconds -eq 30) 'The native wait bound changed.'
    $script:waits++;$last='absent'
    for ($attempt=0;$attempt -lt 3;$attempt++) {
        try {$value=& $Observe;if ($null -ne $value -and $value -ne $false) {return $value}}
        catch {$last=$_.Exception.Message}
    }
    throw "Bounded fixture timeout for ${Description}: $last"
}
function Get-FileQuayWorkflowMain($Ui) {$script:main}
function Find-FileQuayWorkflowElements($Ui,[string]$Id,[string]$Name='',$Within=$null,[switch]$IncludeHidden) {
    Require (-not $IncludeHidden) 'Hidden/disabled command lookup bypassed the normal filter.'
    if ($Id -ceq 'InnerNavigationToolbarPasteButton') {
        if (($script:direct -or $script:opened) -and -not $script:withhold -and
            $script:paste.element.Current.IsEnabled -and -not $script:paste.element.Current.IsOffscreen) {
            $script:paste
            if ($script:duplicate) {$script:paste}
        }
    } elseif ($Id -ceq 'ContextCommandBar') {
        Require ([object]::ReferenceEquals($Within,$script:main)) 'Toolbar lookup escaped the retained main window.'
        $script:bar
    } elseif ($Id -ceq 'MoreButton') {
        Require ([object]::ReferenceEquals($Within,$script:bar)) 'More lookup escaped ContextCommandBar.'
        Require ($Name -ceq 'More options') 'More lookup lost its exact observed name.'
        if (-not $script:missingMore) {$script:more;if ($script:duplicateMore) {$script:more}}
    } else {throw "Unexpected selector $Id"}
}
function Invoke-FileQuayWorkflowAction($Ui,$Binding,[string]$Action) {
    Require ($Action -ceq 'Invoke') 'Toolbar used synthetic keyboard input.'
    $state=@{app_live=$true;target_process_live=$true;main_live=$true;main_pid=71;target_live=$true;
        target_pid=$Binding.scope.target_pid;target_hwnd=$Binding.scope.target_hwnd;target_visible=$true;target_enabled=$true;
        foreground_hwnd=$(if ($script:foreignForeground) {303} else {101});owner_chain=@(101);
        element_pid=$Binding.element.Current.ProcessId;element_hwnd=$Binding.scope.target_hwnd;
        element_within_target=$true;element_visible=(-not $Binding.element.Current.IsOffscreen);element_enabled=$Binding.element.Current.IsEnabled}
    Assert-FileQuayWorkflowTarget $Binding.scope $state
    $id=$Binding.element.Current.AutomationId
    if ($id -ceq 'MoreButton') {
        $script:actions.Add($id)
        if ($script:failMore) {throw 'Provider Invoke failed'}
        $script:opened=$true
        if ($script:postForeign) {$script:foreignForeground=$true}
    } elseif ($id -ceq 'InnerNavigationToolbarPasteButton') {
        Require ($script:direct -or $script:opened) 'Paste was invoked before it became observable.'
        $script:actions.Add($id)
    } else {throw "Unexpected action $id"}
}
function Add-FileQuayWorkflowClipboardObservation($Ui,[string]$Stage) {
    Require $script:opened 'Overflow diagnostics ran before the menu opened.'
    Require ($Stage -ceq 'paste-overflow-opened') 'Overflow stage evidence changed.'
}
function Reject([scriptblock]$Action,[string]$Label,[int]$ExpectedInputs=0) {
    $failure='';try {& $Action} catch {$failure=$_.Exception.Message}
    Require (-not [string]::IsNullOrEmpty($failure)) "Accepted $Label"
    Require ($script:actions.Count -eq $ExpectedInputs) "Unexpected input on $Label"
}
$checks=0
Reset-Scenario $true
Invoke-FileQuayWorkflowPaste $ui 'copy Paste'
Require (($actions -join ',') -ceq 'InnerNavigationToolbarPasteButton' -and $waits -eq 1) 'Visible Paste opened unrelated overflow.';$checks++
Reset-Scenario
Invoke-FileQuayWorkflowPaste $ui 'copy Paste'
Require (($actions -join ',') -ceq 'MoreButton,InnerNavigationToolbarPasteButton' -and $waits -eq 2) 'Overflow Paste did not reacquire the exact command.';$checks++
foreach ($scenario in @('missing','disabled','hidden','duplicate-command','duplicate-more','missing-more','wrong-name','wrong-class','wrong-bar-class','disabled-more','hidden-more','foreign-bar','foreign-pid','foreign-window','foreign-foreground','foreground-after-more','invoke-failure')) {
    Reset-Scenario
    $expected=0
    switch ($scenario) {
        'missing' {$script:withhold=$true;$expected=1}
        'disabled' {$paste.element.Current.IsEnabled=$false;$expected=1}
        'hidden' {$paste.element.Current.IsOffscreen=$true;$expected=1}
        'duplicate-command' {$script:direct=$true;$script:duplicate=$true}
        'duplicate-more' {$script:duplicateMore=$true}
        'missing-more' {$script:missingMore=$true}
        'wrong-name' {$more.element.Current.Name='Other'}
        'wrong-class' {$more.element.Current.ClassName='TextBox'}
        'wrong-bar-class' {$bar.element.Current.ClassName='Other'}
        'disabled-more' {$more.element.Current.IsEnabled=$false}
        'hidden-more' {$more.element.Current.IsOffscreen=$true}
        'foreign-bar' {$bar.scope.target_pid=72;$bar.element.Current.ProcessId=72}
        'foreign-pid' {$more.scope.target_pid=72;$more.element.Current.ProcessId=72}
        'foreign-window' {$more.scope.target_hwnd=202}
        'foreign-foreground' {$script:foreignForeground=$true}
        'foreground-after-more' {$script:postForeign=$true;$expected=1}
        'invoke-failure' {$script:failMore=$true;$expected=1}
    }
    Reject {Invoke-FileQuayWorkflowPaste $ui 'move Paste'} $scenario $expected
    Require ($actions.Where({$_ -ceq 'MoreButton'}).Count -le 1) 'Overflow toggled more than once.'
    $checks++
}
"Consumer toolbar checks passed: $checks (actual orchestration, exact overflow scope, enabled command reacquisition, bounded refusal and ownership gates)."
