# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
function Invoke-FileQuayCleanup([System.Collections.IDictionary]$Steps) {
    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Steps.Keys) {
        try { $null = & $Steps[$name] } catch { $failures.Add("${name}: $($_.Exception.Message)") }
    }
    return $failures.ToArray()
}
function Get-FileQuayQualificationFailure([string]$PrimaryError, [string[]]$CleanupErrors) {
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($PrimaryError) { $parts.Add('Qualification failed: ' + $PrimaryError) }
    if ($CleanupErrors.Count) { $parts.Add('Cleanup failed: ' + ($CleanupErrors -join '; ')) }
    return $parts -join "`n"
}
function Test-FileQuayFrameworkRegistration($Package, $Requirement) {
    return $Package.Name -ceq $Requirement.Name -and
        (-not $Requirement.PSObject.Properties['Publisher'] -or $Package.Publisher -ceq $Requirement.Publisher) -and
        [version]$Package.Version -ge [version]$Requirement.MinVersion -and
        $Package.Architecture.ToString().ToLowerInvariant() -in @('x64', 'neutral')
}
function Get-FileQuayProcessExitEvidence([Diagnostics.Process]$Process, [int]$TimeoutMilliseconds) {
    $evidence = [ordered]@{ process_id=$Process.Id; wait_completed=$false; exit_code=$null; normal_exit=$false; observation_error=$null }
    try {
        $evidence.wait_completed = $Process.WaitForExit($TimeoutMilliseconds)
        if ($evidence.wait_completed) {
            # Invoke the getter explicitly: PowerShell can turn a failed property
            # getter into null, concealing the difference from a nonzero exit.
            $evidence.exit_code = $Process.get_ExitCode()
            $evidence.normal_exit = $evidence.exit_code -eq 0
        }
    } catch { $evidence.observation_error = $_.Exception.ToString() }
    return [pscustomobject]$evidence
}
