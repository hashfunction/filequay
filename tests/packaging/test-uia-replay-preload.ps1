# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
# Execute the real helper's Windows branch in a fresh process on either host.
# Only file loading is doubled. Separate assemblies and PowerShell type lookup
# are real. Isolate replay types because Windows can resolve the Microsoft
# namespace even in a fresh -NoProfile host; retain that actual binding below.
$hostElement=('System.Windows.Automation.AutomationElement') -as [type]
if ($null -eq $hostElement) {
    if ($IsWindows) {
        Microsoft.PowerShell.Utility\Add-Type -Path (Join-Path $PSHOME 'UIAutomationClient.dll')
    } else {
        $hostAssembly=[Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
            [Reflection.AssemblyName]::new('FileQuayObservedHostCollision'),[Reflection.Emit.AssemblyBuilderAccess]::Run)
        $hostModule=$hostAssembly.DefineDynamicModule('Observed')
        $null=$hostModule.DefineType('System.Windows.Automation.AutomationElement',[Reflection.TypeAttributes]::Public).CreateType()
    }
    $hostElement=('System.Windows.Automation.AutomationElement') -as [type]
}
if ($null -eq $hostElement -or ($IsWindows -and $hostElement.Assembly.GetName().Name -cne 'UIAutomationClient')) {
    throw 'The observed preexisting Microsoft type binding is missing or foreign.'
}
$script:replayNamespace='FileQuayCompanionReplay.Automation.'
$script:fixtureHost=Join-Path ([IO.Path]::GetTempPath()) ('foldersail-uia-preload-'+[guid]::NewGuid().ToString('N'))
$script:requested=[Collections.Generic.List[string]]::new()
function Add-Type([string]$Path) {
    if ([IO.Path]::GetDirectoryName($Path) -cne $script:fixtureHost) {throw 'Helper searched outside the exact host directory.'}
    $filename=[IO.Path]::GetFileName($Path)
    if ($filename -cnotin @('UIAutomationClient.dll','UIAutomationTypes.dll')) {throw 'Helper requested an unknown companion.'}
    $script:requested.Add($filename)
    $name=[IO.Path]::GetFileNameWithoutExtension($filename)
    $assembly=[Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly([Reflection.AssemblyName]::new($name),[Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module=$assembly.DefineDynamicModule('Replay')
    $typeNames=if ($filename -ceq 'UIAutomationTypes.dll') {@('AutomationProperty')} else {@('AutomationElement','ValuePattern','InvokePattern')}
    foreach ($typeName in $typeNames) {
        $builder=$module.DefineType(($script:replayNamespace+$typeName),[Reflection.TypeAttributes]::Public)
        $null=$builder.CreateType()
    }
}
$names=@('AutomationElement','AutomationProperty','ValuePattern','InvokePattern')
foreach ($name in $names) {
    if ($null -ne (($script:replayNamespace+$name) -as [type])) {throw "Preload replay requires a fresh process: $name"}
}
$helper=Get-Content (Join-Path $PSScriptRoot 'uia-replay-collision.ps1') -Raw
. ([scriptblock]::Create($helper.Replace('$IsWindows','$true').Replace('$PSHOME','$script:fixtureHost').Replace('System.Windows.Automation.',$script:replayNamespace)))
Initialize-FileQuayUiaReplayCollision $names
if ($script:requested.Count -ne 2 -or @($script:requested | Sort-Object -Unique).Count -ne 2) {throw 'Both exact host companions must load exactly once.'}
foreach ($name in $names) {
    $type=($script:replayNamespace+$name) -as [type]
    $expected=if ($name -eq 'AutomationProperty') {'UIAutomationTypes'} else {'UIAutomationClient'}
    if ($type.Assembly.GetName().Name -cne $expected) {throw "Wrong collision assembly for $name"}
}
if (-not [object]::ReferenceEquals($hostElement,(('System.Windows.Automation.AutomationElement') -as [type]))) {throw 'Replay changed the preexisting Microsoft type binding.'}
'PASS private replay with preexisting Microsoft type preserved: both exact host companions loaded once, real PowerShell discovery from separate assemblies (fixture-only loader).'
