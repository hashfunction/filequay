# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Executes the real installer in an isolated fixture with failing AppX/certificate
# APIs. No package, certificate store, activation API or user environment is touched.
param([ValidateSet('InstallationAndCleanup','PreinstalledFramework')][string]$Scenario='InstallationAndCleanup')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('filequay-install-failure-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path (Join-Path $temporary '.github/scripts'), (Join-Path $temporary 'distribution'), (Join-Path $temporary 'package/Dependencies/x64'), (Join-Path $temporary 'artifacts/qualification') -Force
$installerSource = Join-Path $source '.github/scripts/Test-CIInstallation.ps1'
if ($env:FILEQUAY_INSTALLER_SOURCE) { $installerSource = $env:FILEQUAY_INSTALLER_SOURCE }
Copy-Item $installerSource (Join-Path $temporary '.github/scripts/Test-CIInstallation.ps1')
Copy-Item (Join-Path $source '.github/scripts/InstallationQualification.Helpers.ps1') (Join-Path $temporary '.github/scripts/')
Copy-Item (Join-Path $source 'distribution/verify-package-payload.py') (Join-Path $temporary 'distribution/')
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Write-TestArchive([string]$Path, [string]$Manifest) {
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try { $writer = [IO.StreamWriter]::new($archive.CreateEntry('AppxManifest.xml').Open()); try { $writer.Write($Manifest) } finally { $writer.Dispose() } }
    finally { $archive.Dispose() }
}
$namespace = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
Write-TestArchive (Join-Path $temporary 'package/main.msix') "<Package xmlns='$namespace'><Identity Name='Trieflow.FileQuay.Qualification' ProcessorArchitecture='x64' /><Dependencies><PackageDependency Name='Microsoft.WindowsAppRuntime.2.4' Publisher='CN=Microsoft' MinVersion='2.4.0.0' /></Dependencies></Package>"
Write-TestArchive (Join-Path $temporary 'package/Dependencies/x64/runtime.msix') "<Package xmlns='$namespace'><Identity Name='Microsoft.WindowsAppRuntime.2.4' Publisher='CN=Microsoft' Version='2.4.0.0' ProcessorArchitecture='x64' /><Properties><Framework>true</Framework></Properties></Package>"
$fakeSignTool = Join-Path $temporary 'sign.ps1'
Set-Content $fakeSignTool '$global:LASTEXITCODE = 0'
$certificateAttempts = [System.Collections.Generic.List[string]]::new()
function Get-AppxPackage {
    param($Name)
    if ($Scenario -eq 'PreinstalledFramework' -and (-not $Name -or $Name -eq 'Microsoft.WindowsAppRuntime.2.4')) {
        [pscustomobject]@{ Name='Microsoft.WindowsAppRuntime.2.4';Publisher='CN=Microsoft';Version='2.4.0.0';Architecture='X64';IsFramework=$true;PackageFullName='Microsoft.WindowsAppRuntime.2.4_2.4.0.0_x64__fixture' }
    }
}
function New-SelfSignedCertificate { param($Type,$Subject,$KeyUsage,$KeyExportPolicy,$CertStoreLocation,$TextExtension,$NotAfter) [pscustomobject]@{Thumbprint='FIXTURE'} }
function Export-Certificate { param($Cert,$FilePath) }
function Import-Certificate { param($FilePath,$CertStoreLocation) }
function Add-AppxPackage { param($Path,$DependencyPath) throw 'primary fixture installation error' }
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
    $failure = ''
    try { & (Join-Path $temporary '.github/scripts/Test-CIInstallation.ps1') -PackagePath (Join-Path $temporary 'package/main.msix') }
    catch { $failure = $_.Exception.Message }
    $record = Get-Content (Join-Path $temporary 'artifacts/qualification/installation-result.json') -Raw | ConvertFrom-Json
    if ($Scenario -eq 'PreinstalledFramework') {
        if (-not $failure.Contains('already registered') -or $certificateAttempts.Count -ne 0 -or $record.installed -or
            $record.installation_qualification_passed -or $record.frameworks[0].compatible_preexisting_full_names.Count -ne 1) {
            throw "RequireClean failed to reject and record the pre-existing framework: $failure"
        }
        'Actual installer preinstalled-framework test passed: dependency artifact matched, prior registration recorded, installation refused.'
    } else {
        if (-not $failure.Contains('primary fixture installation error') -or -not $failure.Contains('Cleanup failed:') -or $certificateAttempts.Count -ne 2) {
            throw "Installer did not preserve the original failure and enforce both certificate cleanup failures. Actual: $failure"
        }
        if ($record.trust_removed -or $record.cleanup_errors.Count -lt 2 -or $record.installation_qualification_passed) { throw 'Failure evidence claimed successful cleanup or qualification.' }
        'Actual installer failure-path test passed: primary error retained, both certificate removals attempted, cleanup failures enforced.'
    }
} finally {
    $env:OS = $priorOS; $env:CI = $priorCI
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $priorProgramFiles)
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $temporary -Recurse -Force
}
