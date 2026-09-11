# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# PowerShell 7 supplies Windows AppX and UI Automation APIs.
param([Parameter(Mandatory=$true)][string]$PackagePath,
      [ValidateSet('RequireClean','AllowPreinstalled')][string]$DependencyMode='RequireClean')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT' -or $env:CI -ne 'true') { throw 'Requires a disposable Windows CI runner.' }
. (Join-Path $PSScriptRoot 'InstallationQualification.Helpers.ps1')
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$identity = 'Trieflow.FileQuay.Qualification'
$publisher = 'CN=FileQuay-CI-Qualification'
if (Get-AppxPackage -Name $identity) { throw 'Refusing to replace an existing installation.' }
$beforePackages = @(Get-AppxPackage)
$beforeFullNames = @($beforePackages | Select-Object -ExpandProperty PackageFullName)
$package = Get-Item -LiteralPath $PackagePath
$work = Join-Path $root ('artifacts/install-test/' + [Guid]::NewGuid().ToString('N'))
$evidence = Join-Path $root 'artifacts/qualification'
New-Item -ItemType Directory -Path $work -Force | Out-Null
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$signedCopy = Join-Path $work 'FileQuay-test.msix'
$publicCertificate = Join-Path $work 'test.cer'
$record = [ordered]@{ source_commit=$env:GITHUB_SHA; unsigned_package_sha256=(Get-FileHash $package.FullName -Algorithm SHA256).Hash;
    instrumented_qualification_build=$true; normal_store_binary_installation_tested=$false;
    dependency_mode=$DependencyMode; dependency_artifacts_verified=$false; framework_registration_verified=$false;
    installed=$false; main_window_verified=$false; com_activation_verified=$false; server_natural_exit_verified=$false;
    uninstall_verified=$false; trust_removed=$false; installation_qualification_passed=$false; submitted=$false }
$certificate = $null; $installed = $null; $application = $null; $probe = $null; $server = $null
$probeStem = $null; $primaryError = ''; $cleanupErrors = @()
try {
    $signTool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" | Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
    if (-not $signTool) { throw 'Windows SDK SignTool is unavailable.' }
    $dependencyDirectory = Join-Path $package.Directory.FullName 'Dependencies/x64'
    $dependencyJson = & python (Join-Path $root 'distribution/verify-package-payload.py') --main-package $package.FullName --dependency-directory $dependencyDirectory
    if ($LASTEXITCODE -ne 0) { throw "Manifest-to-framework matching failed: $dependencyJson" }
    $dependencies = ($dependencyJson -join "`n") | ConvertFrom-Json
    $dependencyJson | Set-Content (Join-Path $evidence 'framework-artifacts.json') -Encoding UTF8
    $record.dependency_artifacts_verified = $dependencies.manifest_to_artifact_matching_passed
    $record.frameworks = @($dependencies.frameworks | ForEach-Object {
        $required = $_.requirement
        $preexisting = @($beforePackages | Where-Object { Test-FileQuayFrameworkRegistration $_ $required } | Select-Object -ExpandProperty PackageFullName)
        [pscustomobject]@{ requirement=$required; artifact_identity=$_.identity; artifact_path=$_.path; artifact_sha256=$_.sha256;
            compatible_preexisting_full_names=$preexisting; resolved_full_names=@(); artifact_registered=$false; newly_registered_full_names=@() }
    })
    if ($DependencyMode -eq 'RequireClean' -and @($record.frameworks | Where-Object { $_.compatible_preexisting_full_names.Count -gt 0 }).Count -gt 0) {
        throw 'A required compatible framework was already registered. RequireClean cannot prove installation from supplied artifacts; use a clean disposable image.'
    }
    $dependencyPaths = @($record.frameworks | ForEach-Object {
        if ((Get-FileHash $_.artifact_path -Algorithm SHA256).Hash -ine $_.artifact_sha256) { throw 'Framework archive changed after manifest validation.' }
        $_.artifact_path
    })
    Copy-Item -LiteralPath $package.FullName -Destination $signedCopy
    $certificate = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}') -NotAfter (Get-Date).AddDays(1)
    Export-Certificate -Cert $certificate -FilePath $publicCertificate | Out-Null
    Import-Certificate -FilePath $publicCertificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    & $signTool.FullName sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $signedCopy
    if ($LASTEXITCODE -ne 0) { throw "Test signing failed: $LASTEXITCODE" }
    & $signTool.FullName verify /pa $signedCopy
    if ($LASTEXITCODE -ne 0) { throw "Test signature verification failed: $LASTEXITCODE" }
    Add-AppxPackage -Path $signedCopy -DependencyPath $dependencyPaths
    $installed = Get-AppxPackage -Name $identity
    if (-not $installed -or $installed.Publisher -cne $publisher) { throw 'Installed identity or publisher mismatch.' }
    $record.installed = $true
    $record.installed_package_full_name = $installed.PackageFullName
    $record.signed_test_package_sha256 = (Get-FileHash $signedCopy -Algorithm SHA256).Hash
    foreach ($framework in $record.frameworks) {
        $required = $framework.requirement
        $resolved = @(Get-AppxPackage -Name $required.Name | Where-Object { Test-FileQuayFrameworkRegistration $_ $required })
        if ($resolved.Count -eq 0) { throw "Required framework did not resolve after installation: $($required.Name)" }
        $framework.resolved_full_names = @($resolved | Select-Object -ExpandProperty PackageFullName)
        $framework.newly_registered_full_names = @($framework.resolved_full_names | Where-Object { $_ -notin $beforeFullNames })
        $artifact = $framework.artifact_identity
        $framework.artifact_registered = @($resolved | Where-Object { $_.Name -ceq $artifact.Name -and $_.Publisher -ceq $artifact.Publisher -and
            [version]$_.Version -eq [version]$artifact.Version -and $_.Architecture.ToString() -ieq $artifact.ProcessorArchitecture }).Count -eq 1
        if ($DependencyMode -eq 'RequireClean' -and (-not $framework.artifact_registered -or $framework.newly_registered_full_names.Count -ne 1)) {
            throw "The supplied framework artifact was not newly registered: $($required.Name)"
        }
    }
    $record.framework_registration_verified = $true
    $record.dependency_installation_from_artifacts_verified = $DependencyMode -eq 'RequireClean'
    $record.dependency_resolution_only = $DependencyMode -eq 'AllowPreinstalled'
    $manifest = Get-AppxPackageManifest -Package $installed.PackageFullName
    $appNodes = @($manifest.Package.Applications.Application | Where-Object { $_.Executable -eq 'FileQuay.exe' })
    if ($appNodes.Count -ne 1) { throw 'Expected one owned application entry point.' }
    $executable = Join-Path $installed.InstallLocation 'FileQuay.exe'
    $serverExecutable = Join-Path $installed.InstallLocation 'Files.App.Server\Files.App.Server.exe'
    foreach ($relative in @('FileQuay.exe','coreclr.dll','hostfxr.dll','Files.App.Server\Files.App.Server.exe','Files.App.Server.winmd')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installed.InstallLocation $relative))) { throw "Installed runtime file missing: $relative" }
    }
    $aumid = $installed.PackageFamilyName + '!' + $appNodes[0].Id
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Start-Process explorer.exe -ArgumentList ('shell:AppsFolder\' + $aumid)
    $deadline = (Get-Date).AddSeconds(90); $window = $null; $control = $null
    while ((Get-Date) -lt $deadline) {
        $application = Get-Process -Name FileQuay -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $executable } | Select-Object -First 1
        if ($application) {
            $application.Refresh()
            if ($application.MainWindowHandle -ne [IntPtr]::Zero) {
                $window = [System.Windows.Automation.AutomationElement]::FromHandle($application.MainWindowHandle)
                $condition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ShowStatusCenterButton')
                $control = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
                if ($control -and -not $control.Current.IsOffscreen) { break }
            }
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $application -or -not $window -or -not $control -or $control.Current.IsOffscreen) { throw 'No installed FileQuay main window with its visible Status Center control.' }
    Start-Sleep -Seconds 3
    $application.Refresh()
    if ($application.HasExited -or $application.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Installed application exited after appearing.' }
    $modules = @($application.Modules | ForEach-Object { @{ name=$_.ModuleName; path=$_.FileName } })
    $coreclr = @($modules | Where-Object { $_.name -ieq 'coreclr.dll' })
    if ($coreclr.Count -ne 1 -or $coreclr[0].path -ine (Join-Path $installed.InstallLocation 'coreclr.dll')) { throw 'Application did not load its packaged .NET runtime.' }
    $record.main_window_verified = $true; $record.window_title = $application.MainWindowTitle; $record.process_id = $application.Id
    $record.visible_automation_id = $control.Current.AutomationId
    $record.executable_sha256 = (Get-FileHash $executable -Algorithm SHA256).Hash
    $modules | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $evidence 'installed-modules.json') -Encoding UTF8
    Stop-Process -Id $application.Id -Force
    if (-not $application.WaitForExit(15000)) { throw 'The main application did not exit before the independent COM probe.' }
    $application = $null
    if (@(Get-Process -Name Files.App.Server -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $serverExecutable }).Count) { throw 'An owned server was already running before explicit activation.' }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace FileQuayQualification {
 [ComImport, Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IApplicationActivationManager {
  [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string id, [MarshalAs(UnmanagedType.LPWStr)] string arguments, uint options, out uint processId);
  [PreserveSig] int ActivateForFile(string id, IntPtr items, string verb, out uint processId);
  [PreserveSig] int ActivateForProtocol(string id, IntPtr items, out uint processId);
 }
 [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")] class ApplicationActivationManager { }
 public static class Activation {
  public static int Run(string id, string arguments, out uint processId) {
   var manager = (IApplicationActivationManager)new ApplicationActivationManager();
   try { return manager.ActivateApplication(id, arguments, 2, out processId); }
   finally { Marshal.ReleaseComObject(manager); }
  }
 }
}
'@
    $nonce = [Guid]::NewGuid().ToString('N')
    $probeStem = Join-Path $env:LOCALAPPDATA ('Packages/' + $installed.PackageFamilyName + '/LocalState/com-probe-' + $nonce)
    [uint32]$probeId = 0
    $record.client_activation_hresult = [FileQuayQualification.Activation]::Run($aumid, ('--filequay-ci-com-probe=' + $nonce), [ref]$probeId)
    if ($record.client_activation_hresult -lt 0) { throw ('Packaged probe activation failed: 0x{0:X8}' -f $record.client_activation_hresult) }
    $probe = Get-Process -Id $probeId
    if ($probe.Path -ine $executable) { throw 'Activation returned a process outside the installed FileQuay package.' }
    # This Process was attached by PID, not started by this component. Retain its
    # OS handle while alive so exit status remains queryable after it terminates.
    $probeHandle = $probe.SafeHandle
    if ($probeHandle.IsInvalid -or $probeHandle.IsClosed) { throw 'Cannot retain the live installed client handle.' }
    $record.probe_process_id = $probeId
    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Test-Path -LiteralPath ($probeStem + '.json')) -and (Get-Date) -lt $deadline) {
        $probe.Refresh()
        if ($probe.HasExited) { throw 'The packaged probe exited before recording its COM activation result.' }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath ($probeStem + '.json'))) {
        $probe.Refresh()
        $record.probe_timeout_window_title = $probe.MainWindowTitle
        $record.probe_timeout_process_alive = -not $probe.HasExited
        throw 'The installed client did not record its CI COM probe result within 45 seconds; inspect activation arguments and probe logs.'
    }
    $activation = Get-Content -LiteralPath ($probeStem + '.json') -Raw | ConvertFrom-Json
    $record.com_activation = $activation
    if (-not $activation.activation_succeeded -or $activation.activation_hresult -ne 0 -or $activation.client_process_id -ne $probeId -or
        $activation.package_full_name -cne $installed.PackageFullName) { throw 'The actual generated StartMonitor call did not succeed in the installed client.' }
    $servers = @(Get-Process -Name Files.App.Server -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $serverExecutable })
    if ($servers.Count -ne 1) { throw "Expected exactly one activated packaged server; found $($servers.Count)." }
    $server = $servers[0]
    $serverHandle = $server.SafeHandle
    if ($serverHandle.IsInvalid -or $serverHandle.IsClosed) { throw 'Cannot retain the live installed server handle.' }
    $serverModules = @($server.Modules | ForEach-Object { @{ name=$_.ModuleName; path=$_.FileName } })
    $serverClr = @($serverModules | Where-Object { $_.name -ieq 'coreclr.dll' })
    if ($serverClr.Count -ne 1 -or $serverClr[0].path -ine (Join-Path $installed.InstallLocation 'Files.App.Server\coreclr.dll')) { throw 'COM server did not load its own packaged CoreCLR.' }
    $record.server_process_id = $server.Id; $record.server_executable_path = $server.Path
    $record.server_winmd_sha256 = (Get-FileHash (Join-Path $installed.InstallLocation 'Files.App.Server.winmd') -Algorithm SHA256).Hash
    $record.server_executable_sha256 = (Get-FileHash $serverExecutable -Algorithm SHA256).Hash
    $record.server_coreclr_path = $serverClr[0].path
    $record.com_activation_verified = $true
    $serverModules | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $evidence 'installed-server-modules.json') -Encoding UTF8
    Set-Content -LiteralPath ($probeStem + '.release') -Value 'Exit the monitored client normally.' -Encoding UTF8
    $record.client_exit = Get-FileQuayProcessExitEvidence $probe 15000
    if (-not $record.client_exit.normal_exit) { throw ('The monitored client did not exit normally after release: ' + ($record.client_exit | ConvertTo-Json -Compress)) }
    $record.server_exit = Get-FileQuayProcessExitEvidence $server 15000
    if (-not $record.server_exit.normal_exit) { throw ('The COM server did not exit naturally after its monitored client exited: ' + ($record.server_exit | ConvertTo-Json -Compress)) }
    if (@(Get-Process -Name Files.App.Server -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $serverExecutable }).Count) { throw 'A packaged server remained after client exit.' }
    $record.server_natural_exit_verified = $true
} catch {
    $primaryError = $_.Exception.ToString()
    $record.error = $primaryError
} finally {
    $cleanupErrors = @(Invoke-FileQuayCleanup ([ordered]@{
        probeEvidence = {
            if ($probeStem) {
                $serverLog = Join-Path (Split-Path $probeStem -Parent) 'debug_server.log'
                if (Test-Path -LiteralPath $serverLog) { Copy-Item -LiteralPath $serverLog -Destination (Join-Path $evidence 'server-debug-log.txt') -Force }
                foreach ($extension in @('.json','.stdout.txt','.stderr.txt')) {
                    if (Test-Path -LiteralPath ($probeStem + $extension)) { Copy-Item -LiteralPath ($probeStem + $extension) -Destination (Join-Path $evidence ('com-probe' + $extension)) -Force }
                }
            }
        }
        ownedProcesses = {
            if ($installed) {
                $paths = @((Join-Path $installed.InstallLocation 'FileQuay.exe'), (Join-Path $installed.InstallLocation 'Files.App.Server\Files.App.Server.exe'))
                $processErrors = [System.Collections.Generic.List[string]]::new()
                foreach ($process in @(Get-Process -Name FileQuay,Files.App.Server -ErrorAction SilentlyContinue | Where-Object { $_.Path -in $paths })) {
                    try {
                        Stop-Process -Id $process.Id -Force
                        if (-not $process.WaitForExit(15000)) { throw "Owned process $($process.Id) remained after cleanup." }
                    } catch { $processErrors.Add($_.Exception.Message) }
                }
                if ($processErrors.Count) { throw ($processErrors -join '; ') }
            }
        }
        observationHandles = {
            foreach ($observed in @($probe, $server)) { if ($observed) { $observed.Dispose() } }
        }
        package = {
            $remaining = Get-AppxPackage -Name $identity
            if ($remaining) { Remove-AppxPackage -Package $remaining.PackageFullName }
            $record.uninstall_verified = -not [bool](Get-AppxPackage -Name $identity)
            if (-not $record.uninstall_verified) { throw 'Owned package registration remains.' }
        }
        trust = { if ($certificate -and (Test-Path ('Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint))) { Remove-Item -LiteralPath ('Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint) } }
        privateCertificate = { if ($certificate -and (Test-Path ('Cert:\CurrentUser\My\' + $certificate.Thumbprint))) { Remove-Item -LiteralPath ('Cert:\CurrentUser\My\' + $certificate.Thumbprint) -DeleteKey } }
        verifyTrust = {
            $record.trust_removed = -not $certificate -or (-not (Test-Path ('Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint)) -and -not (Test-Path ('Cert:\CurrentUser\My\' + $certificate.Thumbprint)))
            if (-not $record.trust_removed) { throw 'Ephemeral certificate or trust remains.' }
        }
        publicCertificate = { if (Test-Path -LiteralPath $publicCertificate) { Remove-Item -LiteralPath $publicCertificate } }
        frameworkInventory = {
            $record.new_framework_packages = @(Get-AppxPackage | Where-Object { $_.PackageFullName -notin $beforeFullNames -and $_.IsFramework } | Select-Object -ExpandProperty PackageFullName)
            $record.framework_cleanup_policy = 'Retain newly installed frameworks until disposable runner teardown.'
            $record.full_environment_cleanup_verified = $record.new_framework_packages.Count -eq 0 -and $record.uninstall_verified -and $record.trust_removed
        }
    }))
    $record.cleanup_errors = $cleanupErrors
    if ($cleanupErrors.Count) { $record.full_environment_cleanup_verified = $false }
    $record.generated_at_utc = [DateTime]::UtcNow.ToString('o')
    $record.installation_qualification_passed = -not $primaryError -and $cleanupErrors.Count -eq 0 -and $record.main_window_verified -and
        $record.com_activation_verified -and $record.server_natural_exit_verified -and $record.dependency_artifacts_verified -and $record.framework_registration_verified
    $record | ConvertTo-Json -Depth 9 | Set-Content (Join-Path $evidence 'installation-result.json') -Encoding UTF8
}
$failure = Get-FileQuayQualificationFailure $primaryError $cleanupErrors
if ($failure) { throw $failure }
if (-not $record.installation_qualification_passed) { throw 'Installation qualification did not pass every required gate.' }
