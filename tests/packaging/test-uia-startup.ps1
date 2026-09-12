# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Real process/clock/file boundary only; readiness alone never qualifies native UIA.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/UiaProxy.Fixture.ps1')
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('foldersail-startup-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$childSource=Join-Path $PSScriptRoot '../../.github/scripts/Invoke-UiaProxyFixtureChild.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($childSource,[ref]$null,[ref]$null)
$writer=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Write-FileQuayFixtureStartup'},$false)
Require ($writer.Count -eq 1) 'Exact production startup writer missing'
. ([scriptblock]::Create($writer[0].Extent.Text))
$child=Join-Path $root 'child.ps1'
[IO.File]::WriteAllText($child,@'
param($Ready,$Delay)
Start-Sleep -Milliseconds $Delay
[IO.File]::WriteAllText($Ready,'{}')
Start-Sleep -Seconds 60
'@)
try {
    $Directory=$root;$Nonce=[Guid]::NewGuid().ToString('N')
    foreach($phase in @('child-entered','assembly-verified','assembly-loaded','native-entry')){
        Write-FileQuayFixtureStartup $phase
        $path=Join-Path $root ('startup-'+$phase+'.json');$raw=[IO.File]::ReadAllBytes($path)
        $row=Get-Content $path -Raw|ConvertFrom-Json -DateKind String
        Require ($raw.Length -lt 4096 -and $row.schema_version -eq 1 -and $row.nonce -ceq $Nonce -and
            $row.process_id -eq $PID -and $row.phase -ceq $phase -and [DateTime]::Parse($row.at_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).Kind -eq 'Utc') 'Actual startup phase identity/bounds differ'
    }
    $before=[IO.File]::ReadAllText($path);$originalError=[Console]::Error;$observedError=[IO.StringWriter]::new()
    try {[Console]::SetError($observedError);Write-FileQuayFixtureStartup native-entry} finally {[Console]::SetError($originalError)}
    Require ([IO.File]::ReadAllText($path) -ceq $before -and $observedError.ToString().StartsWith('Startup observation native-entry: ') -and
        $observedError.ToString().Length -lt 256) 'Diagnostic failure overwrote a phase or escaped its secondary bound'
    foreach($case in @('delayed','expired')){
        $ready=Join-Path $root ($case+'.json');$record=@{diagnostic_errors=@()};$process=$null
        try {
            $start=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$start.UseShellExecute=$false
            foreach($arg in @('-NoProfile','-NonInteractive','-File',$child,'-Ready',$ready,'-Delay',$(if($case -ceq 'delayed'){'11000'}else{'60000'}))){$start.ArgumentList.Add($arg)}
            $process=[Diagnostics.Process]::Start($start);$null=$process.SafeHandle
            $failure='';try {Wait-FileQuayUiaFixtureReady $process $ready $record}catch{$failure=$_.Exception.Message}
            Require ($record.startup_allowance_seconds -eq 30) 'Production startup allowance differs'
            if($case -ceq 'delayed'){
                Require (-not $failure -and $record.ready_elapsed_ms -ge 11000 -and $record.ready_elapsed_ms -lt 30000) 'Owned delayed readiness was rejected or exceeded its single budget'
            }else{
                Require ($failure -ceq 'Native UIA fixture did not expose its owned window before the deadline.' -and
                    $record.ready_refusal.elapsed_ms -ge 30000 -and $record.ready_refusal.elapsed_ms -lt 35000 -and
                    -not $record.ready_refusal.has_exited -and -not $record.ready_refusal.ready_exists) 'Live startup expiry was accepted/reset or lost original refusal'
            }
            Require ($record.diagnostic_errors.Count -eq 0) 'Unexpected startup diagnostic failure'
        } finally {
            if($process){if(-not $process.HasExited){$process.Kill();Require ($process.WaitForExit(5000)) 'Owned startup fixture survived cleanup'};$process.Dispose()}
        }
    }
    'PASS actual startup boundary: readiness after eleven seconds, single thirty-second expiry, original failure and retained-process cleanup; no UI acceptance.'
} finally {Remove-Item -LiteralPath $root -Recurse -Force}
