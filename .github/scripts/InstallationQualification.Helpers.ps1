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
