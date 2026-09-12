# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Pure boundary tests; real UIA support is proved only by the separate Windows fixture.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/UiaProxy.Helpers.ps1')
. (Join-Path $PSScriptRoot 'uia-replay-collision.ps1')
Initialize-FileQuayUiaReplayCollision @('ValuePattern','InvokePattern','AutomationElement')
# Remap only bracketed UIA type references in the in-memory production replay.
. ([scriptblock]::Create((Get-Content (Join-Path $PSScriptRoot '../../.github/scripts/UiaProxy.Fixture.ps1') -Raw).Replace('[System.Windows.Automation.','[FileQuayProxyFixtureReplay.Automation.')))
function Require([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Reject([scriptblock]$Action,[string]$Label) {$failed=$false;try {& $Action} catch {$failed=$true};Require $failed "Accepted $Label"}
Add-Type -TypeDefinition @'
namespace FileQuayProxyFixtureReplay.Automation {
 public sealed class ValuePattern {
  public sealed class State { public bool IsReadOnly {get;set;} }
  public State Current {get;} = new State();
 }
 public sealed class InvokePattern {}
 public sealed class AutomationElement {}
}
'@
$nonce='c'*32
$ready=@{schema_version=1;nonce=$nonce;process_id=9001;window=[long]1;edit=[long]2;button=[long]3}
Assert-FileQuayUiaFixtureReady $ready $nonce 9001
$checks=1
foreach ($mode in @('foreign-pid','wrong-nonce','alias-control','missing-window','string-handle')) {
    $r=@{}+$ready
    switch ($mode) {
        'foreign-pid' {$r.process_id=9002}
        'wrong-nonce' {$r.nonce='d'*32}
        'alias-control' {$r.button=$r.edit}
        'missing-window' {$r.window=[long]0}
        'string-handle' {$r.edit='2'}
    }
    Reject {Assert-FileQuayUiaFixtureReady $r $nonce 9001} $mode;$checks++
}
foreach ($kind in @('Edit','Button')) {
    $control=@{observation=@{role=('ControlType.'+$kind);automation_id=$(if ($kind -ceq 'Edit') {'1001'} else {'1'});
        class=$kind;visible=$true;enabled=$true;value_supported=$true;invoke_supported=$true};
        value=[FileQuayProxyFixtureReplay.Automation.ValuePattern]::new();invoke=[FileQuayProxyFixtureReplay.Automation.InvokePattern]::new()}
    Assert-FileQuayUiaFixtureControl $control $kind;$checks++
    foreach ($mode in @('basic-pane','foreign-id','foreign-class','invisible','disabled','unsupported','wrong-pattern','read-only')) {
        if ($mode -ceq 'read-only' -and $kind -ceq 'Button') {continue}
        $c=@{}+$control;$c.observation=@{}+$control.observation
        switch ($mode) {
            'basic-pane' {$c.observation.role='ControlType.Pane'}
            'foreign-id' {$c.observation.automation_id='999'}
            'foreign-class' {$c.observation.class='Other'}
            'invisible' {$c.observation.visible=$false}
            'disabled' {$c.observation.enabled=$false}
            'unsupported' {$c.observation.value_supported=$false;$c.observation.invoke_supported=$false}
            'wrong-pattern' {$c.value=[object]::new();$c.invoke=[object]::new()}
            'read-only' {$c.value=[FileQuayProxyFixtureReplay.Automation.ValuePattern]::new();$c.value.Current.IsReadOnly=$true}
        }
        Reject {Assert-FileQuayUiaFixtureControl $c $kind} "$kind $mode";$checks++
    }
}
"PASS native fixture readiness and real-pattern policy boundary: $checks cases"
# Actual loader boundary: an absent exact PSHOME provider must be recorded before
# any proxy assembly load/registration can occur. Only OS identity I/O is doubled.
function Add-Type {param($AssemblyName)}
$script:identities=0
function Get-FileQuayUiaAssemblyIdentity([string]$Path) {$script:identities++;@{path=$Path}}
function Test-Path {param($LiteralPath,$PathType) $false}
$missing=@{}
Reject {Get-FileQuayUiaProxyEvidence $missing} 'absent current-host provider'
Require ($missing.proxy_file.exists -eq $false -and $missing.proxy_file.path -ceq (Join-Path $PSHOME 'UIAutomationClientSideProviders.dll') -and $script:identities -eq 1) 'Missing provider was not recorded before registration.'
Remove-Item Function:Add-Type,Function:Get-FileQuayUiaAssemblyIdentity,Function:Test-Path
'PASS production missing-host-provider boundary (no foreign search/load)'
# Exercise the production isolated build, including exact SDK/lock/source binding.
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dotnet=if ($env:FILEQUAY_DOTNET) {$env:FILEQUAY_DOTNET} else {'dotnet'}
$work=Join-Path $root ('artifacts/foldersail-uia-fixture-build-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
try {
    $build=Build-FileQuayUiaFixture $root $work $dotnet
    Require ($build.file.bytes -gt 0 -and $build.source_inputs.Count -eq 10) 'Fixture build lacks source/file evidence.'
    Assert-FileQuayWorkflowFile $build.path $build.file
    [IO.File]::AppendAllText($build.path,'changed')
    Reject {Assert-FileQuayWorkflowFile $build.path $build.file} 'changed fixture assembly'
    'PASS production fixture locked build and post-build mutation rejection (no Windows UI claim)'
} finally {Remove-Item -LiteralPath $work -Recurse -Force}
