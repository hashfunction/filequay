# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Real processes: attach independently, release the original Process component,
# and distinguish successful exit, nonzero exit and a live timeout.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')
$powerShell = (Get-Process -Id $PID).Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('filequay-process-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$results = [Collections.Generic.List[object]]::new()
try {
    foreach ($case in @(@{ name='zero'; code=0; release=$true }, @{ name='nonzero'; code=7; release=$true }, @{ name='timeout'; code=0; release=$false })) {
        $stem = Join-Path $temporary $case.name
        $quotedStem = $stem.Replace("'", "''")
        $code = "[IO.File]::WriteAllText('$quotedStem.ready','ready'); while (-not [IO.File]::Exists('$quotedStem.release')) { Start-Sleep -Milliseconds 20 }; exit $($case.code)"
        $start = [Diagnostics.ProcessStartInfo]::new($powerShell)
        $start.UseShellExecute = $false
        foreach ($argument in @('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))) { $start.ArgumentList.Add($argument) }
        $launcher = [Diagnostics.Process]::Start($start)
        $observed = $null
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while (-not [IO.File]::Exists($stem + '.ready')) {
                if ($launcher.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Child did not become ready.' }
                Start-Sleep -Milliseconds 20
            }
            $observed = [Diagnostics.Process]::GetProcessById($launcher.Id)
            # Required before release: keep OS exit information after termination.
            $handle = $observed.SafeHandle
            if ($handle.IsInvalid -or $handle.IsClosed) { throw 'No live process observation handle.' }
            $launcher.Dispose()
            if ($case.release) { [IO.File]::WriteAllText($stem + '.release','release') }
            $result = Get-FileQuayProcessExitEvidence $observed $(if ($case.release) { 15000 } else { 50 })
            if ($case.release) {
                if (-not $result.wait_completed -or $result.exit_code -cne $case.code -or $result.observation_error) { throw "Lost actual $($case.name) exit evidence: $($result | ConvertTo-Json -Compress)" }
                if ($result.normal_exit -ne ($case.code -eq 0)) { throw 'Nonzero exit was accepted or zero exit rejected.' }
            } elseif ($result.wait_completed -or $result.normal_exit -or $null -ne $result.exit_code) { throw 'Live timeout was accepted as process exit.' }
            $results.Add([pscustomobject]@{ name=$case.name; evidence=$result })
        } finally {
            if ($observed) {
                if (-not $observed.HasExited) { $observed.Kill(); $null = $observed.WaitForExit(15000) }
                $observed.Dispose()
            }
            $launcher.Dispose()
        }
    }
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
$results | ConvertTo-Json -Depth 5
