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
function Set-FileQuayOwnedRegistration(
    [System.Collections.IDictionary]$State,
    [object[]]$Packages,
    [string]$ExpectedName,
    [string]$ExpectedPublisher,
    [string]$ExpectedVersion,
    [string]$ExpectedArchitecture
) {
    if (-not $State.addCompleted) { throw 'Add-AppxPackage did not complete; registration ownership cannot be established.' }
    if ($Packages.Count -ne 1) { throw "Expected exactly one installed qualification package; observed $($Packages.Count)." }
    $candidate = $Packages[0]
    $fullName = [string]$candidate.PackageFullName
    $expectedPrefix = $ExpectedName + '_' + $ExpectedVersion + '_' + $ExpectedArchitecture.ToLowerInvariant() + '_'
    if ([string]$candidate.Name -cne $ExpectedName -or
        [string]$candidate.Publisher -cne $ExpectedPublisher -or
        [string]$candidate.Version -cne $ExpectedVersion -or
        [string]$candidate.Architecture -cne $ExpectedArchitecture -or
        -not $fullName.StartsWith($expectedPrefix, [StringComparison]::Ordinal) -or
        -not [string]$candidate.PackageFamilyName -or
        $State.preflightPackageFullNames -ccontains $fullName) {
        throw 'Installed name/publisher/version/architecture/full-name differs from the qualification identity.'
    }
    $State.ownedPackageFullName = $fullName
    $State.installedByUs = $true
    return $candidate
}
function Remove-FileQuayOwnedRegistration(
    [System.Collections.IDictionary]$State,
    [string]$ExpectedName,
    [scriptblock]$GetPackages,
    [scriptblock]$RemovePackage
) {
    if (-not $State.installAttempted) { return }
    $remaining = @(& $GetPackages)
    $State.residualPackageFullNames = @($remaining | ForEach-Object { [string]$_.PackageFullName })
    if ($State.installedByUs -and $State.ownedPackageFullName) {
        $owned = @($remaining | Where-Object {
            [string]$_.Name -ceq $ExpectedName -and [string]$_.PackageFullName -ceq [string]$State.ownedPackageFullName
        })
        if ($owned.Count -gt 1) { throw 'Ambiguous duplicate registration state; all registrations preserved.' }
        if ($owned.Count -eq 1) { & $RemovePackage ([string]$State.ownedPackageFullName) | Out-Host }
    }
    $remaining = @(& $GetPackages)
    $State.residualPackageFullNames = @($remaining | ForEach-Object { [string]$_.PackageFullName })
    if ($remaining.Count) { throw ('Unowned or unresolved package registrations preserved: ' + ($State.residualPackageFullNames -join ', ')) }
    if ($State.addCompleted -and -not $State.installedByUs) {
        throw 'Add-AppxPackage completed but exact registration ownership was not established; package residue cannot be ruled out.'
    }
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
