# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
function Invoke-FileQuayCleanup([System.Collections.IDictionary]$Steps) {
    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Steps.Keys) {
        try { $null = & $Steps[$name] } catch { $failures.Add("${name}: $($_.Exception.Message)") }
    }
    return $failures.ToArray()
}
function Get-FileQuayQualificationFailure {
    param(
        [string]$PrimaryError,
        [string[]]$CleanupErrors = @(),
        [string[]]$EvidenceErrors = @(),
        [string[]]$ReportingErrors = @()
    )
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($PrimaryError) { $parts.Add('Qualification failed: ' + $PrimaryError) }
    if (@($CleanupErrors).Count) { $parts.Add('Cleanup failed: ' + ($CleanupErrors -join '; ')) }
    if (@($EvidenceErrors).Count) { $parts.Add('Evidence failed: ' + ($EvidenceErrors -join '; ')) }
    if (@($ReportingErrors).Count) { $parts.Add('Reporting failed: ' + ($ReportingErrors -join '; ')) }
    return $parts -join "`n"
}
function Test-FileQuayAutomationTreeCapture([object[]]$Nodes, [string]$ExpectedAutomationId) {
    $successful = @($Nodes | Where-Object {
        -not $_.PSObject.Properties['observation_error'] -and
        $_.PSObject.Properties['depth'] -and $_.PSObject.Properties['control_type']
    })
    $roots = @($successful | Where-Object { [int]$_.depth -eq 0 -and [string]$_.control_type })
    $expected = @($successful | Where-Object {
        $_.PSObject.Properties['automation_id'] -and [string]$_.automation_id -ceq $ExpectedAutomationId -and
        [string]$_.control_type
    })
    return $roots.Count -eq 1 -and $expected.Count -ge 1
}
function Test-FileQuayWindowDisappearance(
    [bool]$ProcessHasExited,
    [IntPtr]$MainWindowHandle,
    [bool]$OffscreenObserved,
    [bool]$IsOffscreen
) {
    return $ProcessHasExited -or $MainWindowHandle -eq [IntPtr]::Zero -or ($OffscreenObserved -and $IsOffscreen)
}
function New-FileQuayQualificationStagePath([string]$Path) {
    return $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
}
function Remove-FileQuayQualificationStage([string]$Path) {
    [IO.File]::Delete($Path)
}
function Write-FileQuayQualificationRecord(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Record,
    [int]$Depth = 9
) {
    $stage = New-FileQuayQualificationStagePath $Path
    $stream = $null
    $ownsStage = $false
    $publicationException = $null
    $cleanupFailures = [System.Collections.Generic.List[string]]::new()
    try {
        $payload = ($Record | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($payload)
        $stream = [IO.File]::Open($stage, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $ownsStage = $true
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose(); $stream = $null
        [IO.File]::Move($stage, $Path, $false)
        $ownsStage = $false
    } catch {
        $publicationException = $_.Exception
    } finally {
        if ($stream) {
            try { $stream.Dispose() } catch { $cleanupFailures.Add('stage stream: ' + $_.Exception.ToString()) }
        }
        if ($ownsStage -and [IO.File]::Exists($stage)) {
            try { Remove-FileQuayQualificationStage $stage }
            catch { $cleanupFailures.Add('owned stage: ' + $_.Exception.ToString()) }
        }
    }
    if ($publicationException -and $cleanupFailures.Count) {
        throw [InvalidOperationException]::new(
            "Qualification record publication failed for ${Path}: $($publicationException.ToString())`nOwned stage cleanup failed: $($cleanupFailures -join '; ')",
            $publicationException
        )
    }
    if ($publicationException) { throw $publicationException }
    if ($cleanupFailures.Count) {
        throw [InvalidOperationException]::new("Qualification record owned-stage cleanup failed for ${Path}: $($cleanupFailures -join '; ')")
    }
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
function Stop-FileQuayOwnedProcess([Diagnostics.Process]$Process, [int]$TimeoutMilliseconds) {
    $Process.Refresh()
    if (-not $Process.HasExited) {
        $handle = $Process.SafeHandle
        if ($handle.IsInvalid -or $handle.IsClosed) { throw 'Cannot terminate a process without its retained live handle.' }
        $Process.Kill()
        if (-not $Process.WaitForExit($TimeoutMilliseconds)) { throw "Owned process $($Process.Id) remained after cleanup." }
    }
    return $Process.HasExited
}
function Get-FileQuayManagedBuildKindEvidence(
    [Parameter(Mandatory=$true)][string]$AssemblyPath,
    [Parameter(Mandatory=$true)][ValidateSet('Instrumented','Consumer')][string]$ExpectedBuildKind
) {
    $assembly = Get-Item -LiteralPath $AssemblyPath
    $stream = [IO.File]::Open($assembly.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $peReader = $null
    try {
        $peReader = [Reflection.PortableExecutable.PEReader]::new($stream)
        if (-not $peReader.HasMetadata) { throw 'The supplied assembly does not contain managed metadata.' }
        $metadata = [Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
        $probePresent = $false
        foreach ($handle in $metadata.TypeDefinitions) {
            $definition = $metadata.GetTypeDefinition($handle)
            if ($metadata.GetString($definition.Namespace) -ceq 'Files.App.Utils.Qualification' -and
                $metadata.GetString($definition.Name) -ceq 'CiComActivationProbe') {
                $probePresent = $true
                break
            }
        }
        $actualBuildKind = if ($probePresent) { 'Instrumented' } else { 'Consumer' }
        if ($actualBuildKind -cne $ExpectedBuildKind) {
            throw "Managed build kind mismatch: expected $ExpectedBuildKind but metadata proves $actualBuildKind."
        }
        return [pscustomobject][ordered]@{
            expected_build_kind = $ExpectedBuildKind
            actual_build_kind = $actualBuildKind
            ci_probe_type = 'Files.App.Utils.Qualification.CiComActivationProbe'
            ci_probe_type_present = $probePresent
            assembly_path = $assembly.FullName
            assembly_bytes = $assembly.Length
            assembly_sha256 = (Get-FileHash -LiteralPath $assembly.FullName -Algorithm SHA256).Hash
        }
    } finally {
        if ($peReader) { $peReader.Dispose() }
        $stream.Dispose()
    }
}
function Get-FileQuayBuildKindConfiguration(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][ValidateSet('Instrumented','Consumer')][string]$BuildKind
) {
    return [pscustomobject][ordered]@{
        build_kind = $BuildKind
        qualification_property = $(if ($BuildKind -eq 'Instrumented') { 'true' } else { 'false' })
        appx_output = Join-Path $Root 'artifacts/appx' $BuildKind
        validation_output = Join-Path $Root 'artifacts/validated-package' $BuildKind
        evidence_output = Join-Path $Root 'artifacts/qualification' $BuildKind
    }
}
function Test-FileQuayInstallationAcceptance(
    [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Record,
    [Parameter(Mandatory=$true)][ValidateSet('Instrumented','Consumer')][string]$BuildKind
) {
    $common = $Record.installed -and $Record.managed_build_kind_verified -and
        $Record.actual_build_kind -ceq $BuildKind -and $Record.dependency_artifacts_verified -and
        $Record.framework_registration_verified -and $Record.main_window_verified -and
        $Record.registration_ownership_established -and $Record.uninstall_verified -and
        $Record.trust_removed -and @($Record.cleanup_errors).Count -eq 0
    if (-not $common) { return $false }
    if ($BuildKind -eq 'Instrumented') {
        return $Record.ci_probe_type_present -and $Record.com_activation_verified -and
            $Record.server_natural_exit_verified
    }
    return -not $Record.ci_probe_type_present -and -not $Record.consumer_com_probe_invoked -and
        $Record.broker_process_identity_verified -and $Record.ui_tree_captured -and
        $Record.screenshot_captured -and $Record.window_close_requested -and
        $Record.window_disappeared -and $Record.consumer_process_outcome_accepted -and
        $Record.owned_process_cleanup_verified -and $Record.consumer_workflow_verified -and
        $Record.consumer_fixture_cleanup_verified
}
