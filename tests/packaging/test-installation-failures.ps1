# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Executes the real installer in an isolated fixture with failing AppX/certificate
# APIs. No package, certificate store, activation API or user environment is touched.
param([ValidateSet('InstallationAndCleanup','PreinstalledFramework','FailedAddRace','PackageChanged','ReportingFailure','AdapterFailure','ProxyFailure')][string]$Scenario='InstallationAndCleanup',
      [ValidateSet('Qualification','Store')][string]$IdentityMode='Qualification')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $source '.github/scripts/PackageIdentity.Helpers.ps1')
$fixtureIdentity=Get-FolderSailPackageIdentity $IdentityMode Consumer
$fixtureOutputKind=if ($IdentityMode -eq 'Store') {'Store-Consumer'} else {'Consumer'}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('filequay-install-failure-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path (Join-Path $temporary '.github/scripts'), (Join-Path $temporary 'distribution'), (Join-Path $temporary 'package/Dependencies/x64'), (Join-Path $temporary 'validated'), (Join-Path $temporary 'artifacts/qualification') -Force
$installerSource = Join-Path $source '.github/scripts/Test-CIInstallation.ps1'
if ($env:FILEQUAY_INSTALLER_SOURCE) { $installerSource = $env:FILEQUAY_INSTALLER_SOURCE }
Copy-Item $installerSource (Join-Path $temporary '.github/scripts/Test-CIInstallation.ps1')
Copy-Item (Join-Path $source '.github/scripts/InstallationQualification.Helpers.ps1') (Join-Path $temporary '.github/scripts/')
Copy-Item (Join-Path $source '.github/scripts/PackageIdentity.Helpers.ps1') (Join-Path $temporary '.github/scripts/')
Copy-Item (Join-Path $source '.github/scripts/ConsumerWorkflow.Helpers.ps1'),(Join-Path $source '.github/scripts/ConsumerWorkflow.Ui.ps1'),(Join-Path $source '.github/scripts/ConsumerWorkflow.PickerDiagnostic.ps1') (Join-Path $temporary '.github/scripts/')
# Only the external SDK/build/CLR-loading boundary is doubled. The actual
# installer must call it before any trust/package mutation, even on failure.
@'
function Initialize-FileQuayConsumerAdapter($Root,$Work) {
    $global:FileQuayAdapterAttempts++
    if ($Scenario -eq 'AdapterFailure') {throw 'fixture adapter load rejected'}
    return @{loaded=$true;il_only=$true}
}
'@ | Set-Content (Join-Path $temporary '.github/scripts/ConsumerWorkflow.Adapter.ps1')
# The separate native process/provider boundary is doubled here; its actual
# implementation is exercised by the Windows preflight and focused fixture tests.
'' | Set-Content (Join-Path $temporary '.github/scripts/UiaProxy.Helpers.ps1')
@'
function Invoke-FileQuayUiaProxyPreflight($Root,$Work,$Adapter,$Record) {
    $global:FileQuayProxyAttempts++
    if ($Scenario -eq 'ProxyFailure') {throw 'fixture proxy support rejected'}
    $Record.passed=$true
}
'@ | Set-Content (Join-Path $temporary '.github/scripts/UiaProxy.Fixture.ps1')
Copy-Item (Join-Path $source 'distribution/verify-package-payload.py') (Join-Path $temporary 'distribution/')
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Write-TestArchive([string]$Path, [string]$Manifest) {
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try { $writer = [IO.StreamWriter]::new($archive.CreateEntry('AppxManifest.xml').Open()); try { $writer.Write($Manifest) } finally { $writer.Dispose() } }
    finally { $archive.Dispose() }
}
$namespace = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
Write-TestArchive (Join-Path $temporary 'package/main.msix') "<Package xmlns='$namespace'><Identity Name='$($fixtureIdentity.name)' ProcessorArchitecture='x64' /><Dependencies><PackageDependency Name='Microsoft.WindowsAppRuntime.2.4' Publisher='CN=Microsoft' MinVersion='2.4.0.0' /></Dependencies></Package>"
Write-TestArchive (Join-Path $temporary 'package/Dependencies/x64/runtime.msix') "<Package xmlns='$namespace'><Identity Name='Microsoft.WindowsAppRuntime.2.4' Publisher='CN=Microsoft' Version='2.4.0.0' ProcessorArchitecture='x64' /><Properties><Framework>true</Framework></Properties></Package>"
Add-Type -TypeDefinition 'namespace Files.App { public sealed class ConsumerFixture {} }' -OutputAssembly (Join-Path $temporary 'validated/FolderSail.dll')
$fakeSignTool = Join-Path $temporary 'sign.ps1'
Set-Content $fakeSignTool '$global:LASTEXITCODE = 0'
$certificateAttempts = [System.Collections.Generic.List[string]]::new()
$packageRemovalAttempts = [System.Collections.Generic.List[string]]::new()
$global:FileQuayAdapterAttempts=0; $global:FileQuayProxyAttempts=0; $global:FileQuayMutationAttempts=0
$global:FileQuayRaceRegistration = $null
function Get-AppxPackage {
    param($Name)
    if ($Scenario -eq 'FailedAddRace' -and $Name -eq $fixtureIdentity.name -and $global:FileQuayRaceRegistration) {
        return $global:FileQuayRaceRegistration
    }
    if ($Scenario -eq 'PreinstalledFramework' -and (-not $Name -or $Name -eq 'Microsoft.WindowsAppRuntime.2.4')) {
        [pscustomobject]@{ Name='Microsoft.WindowsAppRuntime.2.4';Publisher='CN=Microsoft';Version='2.4.0.0';Architecture='X64';IsFramework=$true;PackageFullName='Microsoft.WindowsAppRuntime.2.4_2.4.0.0_x64__fixture' }
    }
}
function New-SelfSignedCertificate { param($Type,$Subject,$KeyUsage,$KeyExportPolicy,$CertStoreLocation,$TextExtension,$NotAfter) $global:FileQuayMutationAttempts++; [pscustomobject]@{Thumbprint='FIXTURE'} }
function Export-Certificate { param($Cert,$FilePath) $global:FileQuayMutationAttempts++ }
function Import-Certificate { param($FilePath,$CertStoreLocation) $global:FileQuayMutationAttempts++ }
function Add-AppxPackage {
    param($Path,$DependencyPath)
    $global:FileQuayMutationAttempts++
    if ($Scenario -eq 'FailedAddRace') {
        $global:FileQuayRaceRegistration = [pscustomobject]@{
            Name=$fixtureIdentity.name;Publisher=$fixtureIdentity.publisher;Version='1.0.1.0';Architecture='X64';IsFramework=$false
            PackageFullName=($fixtureIdentity.name+'_1.0.1.0_x64__raced');PackageFamilyName=($fixtureIdentity.name+'_raced')
        }
    }
    if ($Scenario -eq 'PackageChanged') {
        [IO.File]::AppendAllText((Join-Path $temporary 'package/main.msix'), 'changed after preflight')
    }
    if ($Scenario -eq 'ReportingFailure') {
        $resultPath = Join-Path $temporary ('artifacts/qualification/'+$fixtureOutputKind+'/installation-result.json')
        [IO.File]::WriteAllBytes($resultPath, [Text.Encoding]::UTF8.GetBytes('previous qualification evidence'))
    }
    throw 'primary fixture installation error'
}
function Remove-AppxPackage { param($Package) $packageRemovalAttempts.Add($Package) }
function Get-ChildItem {
    param($Path,$LiteralPath,[switch]$File)
    if ($Path -like '*Windows Kits*') { return [pscustomobject]@{FullName=$fakeSignTool;Directory=[pscustomobject]@{Parent=[pscustomobject]@{Name='10.0.26100.0'}}} }
    if ($LiteralPath) { Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $LiteralPath -File:$File }
    else { Microsoft.PowerShell.Management\Get-ChildItem -Path $Path -File:$File }
}
function Test-Path {
    param($Path,$LiteralPath)
    $value = if ($LiteralPath) {$LiteralPath} else {$Path}
    if ($value -like 'Cert:*') { return $true }
    Microsoft.PowerShell.Management\Test-Path -LiteralPath $value
}
function Remove-Item {
    [CmdletBinding()]param($LiteralPath,[switch]$DeleteKey)
    if ($LiteralPath -like 'Cert:*') { $certificateAttempts.Add($LiteralPath); Write-Error ('fixture cleanup denied ' + $LiteralPath); return }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath
}
$priorOS = $env:OS; $priorCI = $env:CI
$priorProgramFiles = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
try {
    # Process-local mock preconditions; native APIs above remain test doubles.
    $env:OS = 'Windows_NT'; $env:CI = 'true'
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $temporary)
    $resultPath = Join-Path $temporary ('artifacts/qualification/'+$fixtureOutputKind+'/installation-result.json')
    $failure = ''
    try { & (Join-Path $temporary '.github/scripts/Test-CIInstallation.ps1') -PackagePath (Join-Path $temporary 'package/main.msix') -ValidatedPackageDirectory (Join-Path $temporary 'validated') -BuildKind Consumer -IdentityMode $IdentityMode }
    catch { $failure = $_.Exception.Message }
    if ($Scenario -ne 'ReportingFailure' -and -not (Test-Path $resultPath)) { throw "Installer fixture produced no receipt; original failure: $failure" }
    $record = if ($Scenario -ne 'ReportingFailure') { Get-Content $resultPath -Raw | ConvertFrom-Json } else { $null }
    if ($record -and ($record.identity_mode -cne $IdentityMode -or $record.identity -cne $fixtureIdentity.name -or $record.publisher -cne $fixtureIdentity.publisher)) {throw 'Installer failure receipt used the wrong identity mode.'}
    if ($global:FileQuayAdapterAttempts -ne 1) {throw 'Installer did not initialize the adapter exactly once.'}
    if ($global:FileQuayProxyAttempts -ne $(if ($Scenario -eq 'AdapterFailure') {0} else {1})) {throw 'Installer proxy preflight invocation count differs.'}
    if ($Scenario -eq 'ProxyFailure') {
        if (-not $failure.Contains('fixture proxy support rejected') -or $global:FileQuayMutationAttempts -ne 0 -or
            $certificateAttempts.Count -ne 0 -or $packageRemovalAttempts.Count -ne 0 -or $record.installed -or
            $record.consumer_uia_proxy_verified -or $record.installation_qualification_passed -or -not $record.unsigned_package_unchanged) {throw 'Proxy preflight did not fail before trust/install mutation.'}
        'Actual installer proxy-failure test passed: no trust/install mutations, original failure retained.'
    } elseif ($Scenario -eq 'AdapterFailure') {
        if (-not $failure.Contains('fixture adapter load rejected') -or $global:FileQuayMutationAttempts -ne 0 -or
            $certificateAttempts.Count -ne 0 -or $packageRemovalAttempts.Count -ne 0 -or $record.installed -or
            $record.consumer_native_adapter_verified -or $record.installation_qualification_passed -or -not $record.unsigned_package_unchanged) {
            throw "Adapter preflight did not fail before trust/install mutation: $failure"
        }
        'Actual installer adapter-failure test passed: load rejected, zero trust/install mutations, failure and unchanged package recorded.'
    } elseif ($Scenario -eq 'PreinstalledFramework') {
        if (-not $failure.Contains('already registered') -or $certificateAttempts.Count -ne 0 -or $record.installed -or
            $record.installation_qualification_passed -or $record.frameworks[0].compatible_preexisting_full_names.Count -ne 1) {
            throw "RequireClean failed to reject and record the pre-existing framework: $failure"
        }
        'Actual installer preinstalled-framework test passed: dependency artifact matched, prior registration recorded, installation refused.'
    } elseif ($Scenario -eq 'FailedAddRace') {
        if (-not $failure.Contains('primary fixture installation error') -or -not $failure.Contains('registrations preserved') -or
            $packageRemovalAttempts.Count -ne 0 -or $record.registration_ownership_established -or $record.owned_package_full_name -or
            $record.residual_package_full_names.Count -ne 1 -or $record.installation_qualification_passed) {
            throw "Failed-Add race did not preserve the foreign registration and both error classes: $failure"
        }
        'Actual installer failed-Add race test passed: exact matching foreign registration preserved and reported.'
    } elseif ($Scenario -eq 'PackageChanged') {
        if (-not $failure.Contains('primary fixture installation error') -or -not $failure.Contains('Cleanup failed:') -or
            -not $failure.Contains('unsigned package changed') -or $record.unsigned_package_unchanged -or
            -not $record.unsigned_package_final_sha256 -or $record.unsigned_package_final_sha256 -ceq $record.unsigned_package_sha256 -or
            $record.installation_qualification_passed) {
            throw "Final input hash failure did not preserve the primary and cleanup failures: $failure"
        }
        'Actual installer input-mutation test passed: final hash differs and all failure classes were preserved.'
    } elseif ($Scenario -eq 'ReportingFailure') {
        $oldBytes = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($resultPath))
        if ($oldBytes -cne 'previous qualification evidence' -or -not $failure.Contains('primary fixture installation error') -or
            -not $failure.Contains('Cleanup failed:') -or -not $failure.Contains('Reporting failed:') -or
            -not $failure.Contains('Cert:\LocalMachine\TrustedPeople\FIXTURE') -or
            -not $failure.Contains('Cert:\CurrentUser\My\FIXTURE') -or
            -not $failure.Contains('installation-result.json')) {
            throw "Exclusive result publication did not preserve old bytes and all failure classes: $failure"
        }
        'Actual installer reporting-failure test passed: existing evidence survived and primary, cleanup and reporting failures were preserved.'
    } else {
        if (-not $failure.Contains('primary fixture installation error') -or -not $failure.Contains('Cleanup failed:') -or $certificateAttempts.Count -ne 2) {
            throw "Installer did not preserve the original failure and enforce both certificate cleanup failures. Actual: $failure"
        }
        if ($record.trust_removed -or $record.cleanup_errors.Count -lt 2 -or $record.installation_qualification_passed) { throw 'Failure evidence claimed successful cleanup or qualification.' }
        if (-not $record.unsigned_package_unchanged -or $record.unsigned_package_final_sha256 -cne $record.unsigned_package_sha256) {
            throw 'Failure evidence did not reverify the unchanged unsigned package.'
        }
        'Actual installer failure-path test passed: primary error retained, both certificate removals attempted, cleanup failures enforced.'
    }
} finally {
    $env:OS = $priorOS; $env:CI = $priorCI
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $priorProgramFiles)
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $temporary -Recurse -Force
    Remove-Variable FileQuayAdapterAttempts,FileQuayMutationAttempts -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable FileQuayRaceRegistration -Scope Global -ErrorAction SilentlyContinue
}
