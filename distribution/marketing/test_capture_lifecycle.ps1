# Copyright 2026 Trieflow LLC. MIT. Sequence tests inject operations, never app acceptance.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_lifecycle.ps1')
$phases=@('Preflight','Prepare','Sign','Install','Activate','Workflow','Close','Uninstall')
$cleanup=@('ObserveFailure','Stop','RestoreDisplay','RemovePackage','RemoveDemo','RemoveTrust','RemoveKey','RemoveTemporary')
foreach($failure in @('')+$phases){
    $state=@{events=[Collections.Generic.List[string]]::new();failure=$failure}
    $operations=[ordered]@{}
    foreach($name in $phases+$cleanup){
        $operations[$name]=[scriptblock]::Create('param($s) $s.events.Add("'+$name+'"); if($s.failure -ceq "'+$name+'"){throw "original '+$name+' failure"}')
    }
    $result=Invoke-FolderSailMarketingLifecycle $state $operations
    if($failure){
        if(-not $result.primary_error.Contains('original '+$failure+' failure')){throw 'Original failure lost'}
        $index=[array]::IndexOf($phases,$failure);$expected=@($phases[0..$index])+$cleanup
    }else{$expected=$phases+$cleanup[1..7];if($result.primary_error){throw 'Unexpected primary failure'}}
    if(($state.events -join '|') -cne ($expected -join '|') -or $result.cleanup_errors.Count){throw 'Capture or cleanup sequence differs'}
}
$state=@{events=[Collections.Generic.List[string]]::new();failure='RemoveTrust'}
$result=Invoke-FolderSailMarketingLifecycle $state $operations
if($result.cleanup_errors.Count -ne 1 -or -not $result.cleanup_errors[0].Contains('RemoveTrust') -or $state.events[-1] -cne 'RemoveTemporary'){throw 'Cleanup failure hid later cleanup'}
Write-Output 'PASS original error retention and complete cleanup sequencing at every capture boundary.'

# Exercise the real owned-process stop helper on processes started solely by
# this fixture. Only packaged-server discovery is replaced by an explicit seam.
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')
function New-CaptureFixtureProcess {
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})))
    $start.UseShellExecute=$false
    foreach($arg in @('-NoProfile','-Command','Start-Sleep -Seconds 30')){$start.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($start);$null=$process.SafeHandle;return $process
}
function Retain-FolderSailMarketingServers($State){
    $State.observations++
    if($State.observations -eq $State.spawnOn){$child=New-CaptureFixtureProcess;$State.servers[[string]$child.Id]=$child}
}
foreach($spawnOn in @(2,3)){
    $s=@{process=(New-CaptureFixtureProcess);processOwned=$true;servers=@{};stopped=$false;record=@{};observations=0;spawnOn=$spawnOn}
    try{
        $refused=$false;try{Stop-FolderSailMarketingProcesses $s}catch{
            if(-not $_.Exception.Message.Contains('remains after cleanup')){throw};$refused=$true
        }
        if(-not $s.process.HasExited -or $s.observations -ne 3 -or $refused -ne ($spawnOn -eq 3) -or $s.stopped -ne ($spawnOn -eq 2)){
            throw 'Post-app-stop server observation or late-server refusal differs'
        }
        if($spawnOn -eq 2 -and @($s.servers.Values|Where-Object {-not $_.HasExited}).Count){throw 'Fixture server remained'}
    }finally{
        foreach($process in @($s.process)+@($s.servers.Values)){
            if(-not $process.HasExited){$process.Kill();$null=$process.WaitForExit(5000)};$process.Dispose()
        }
    }
}
Write-Output 'PASS real retained child-process stop, second server inventory and refusal of a late live server.'
