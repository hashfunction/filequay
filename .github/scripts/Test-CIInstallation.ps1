# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# PowerShell 5.1 is used for Windows AppX and UI Automation framework APIs.
param([Parameter(Mandatory=$true)][string]$PackagePath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT' -or $env:CI -ne 'true') { throw 'Requires a disposable Windows CI runner.' }
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$identity = 'Trieflow.FileQuay.Qualification'
$publisher = 'CN=FileQuay-CI-Qualification'
if (Get-AppxPackage -Name $identity) { throw 'Refusing to replace an existing installation.' }
$beforePackages = @(Get-AppxPackage | Select-Object -ExpandProperty PackageFullName)
$package = Get-Item -LiteralPath $PackagePath
$work = Join-Path $root ('artifacts/install-test/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$signedCopy = Join-Path $work 'FileQuay-test.msix'
$publicCertificate = Join-Path $work 'test.cer'
$signTool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" | Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
if (-not $signTool) { throw 'Windows SDK SignTool is unavailable.' }
$dependencyDirectory = Join-Path $package.Directory.FullName 'Dependencies/x64'
$dependencyPaths = @(Get-ChildItem -LiteralPath $dependencyDirectory -File | Where-Object { $_.Extension -in @('.msix','.appx') } | Select-Object -ExpandProperty FullName)
if ($dependencyPaths.Count -eq 0) { throw 'Declared x64 Windows App Runtime dependency package is missing.' }
$record = [ordered]@{ source_commit=$env:GITHUB_SHA; unsigned_package_sha256=(Get-FileHash $package.FullName -Algorithm SHA256).Hash; installed=$false; main_window_verified=$false; uninstall_verified=$false; trust_removed=$false; submitted=$false }
$certificate = $null
$installed = $null
$application = $null
try {
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
    if (-not $installed -or $installed.Publisher -ne $publisher) { throw 'Installed identity or publisher mismatch.' }
    $record.installed = $true
    $record.installed_package_full_name = $installed.PackageFullName
    $record.signed_test_package_sha256 = (Get-FileHash $signedCopy -Algorithm SHA256).Hash
    $manifest = Get-AppxPackageManifest -Package $installed.PackageFullName
    $appNodes = @($manifest.Package.Applications.Application | Where-Object { $_.Executable -eq 'FileQuay.exe' })
    if ($appNodes.Count -ne 1) { throw 'Expected one owned application entry point.' }
    $executable = Join-Path $installed.InstallLocation 'FileQuay.exe'
    foreach ($relative in @('FileQuay.exe','coreclr.dll','hostfxr.dll','Files.App.Server/Files.App.Server.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installed.InstallLocation $relative))) { throw "Installed runtime file missing: $relative" }
    }
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Start-Process explorer.exe -ArgumentList ('shell:AppsFolder\' + $installed.PackageFamilyName + '!' + $appNodes[0].Id)
    $deadline = (Get-Date).AddSeconds(90)
    $window = $null
    $control = $null
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
    $record.main_window_verified = $true
    $record.window_title = $application.MainWindowTitle
    $record.process_id = $application.Id
    $record.visible_automation_id = $control.Current.AutomationId
    $record.executable_sha256 = (Get-FileHash $executable -Algorithm SHA256).Hash
    $modules | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $root 'artifacts/qualification/installed-modules.json') -Encoding UTF8
    Stop-Process -Id $application.Id -Force
    $application = $null
    Remove-AppxPackage -Package $installed.PackageFullName
    if (Get-AppxPackage -Name $identity) { throw 'Uninstall did not remove the package registration.' }
    $record.uninstall_verified = $true
} catch {
    $record.error = $_.Exception.Message
    throw
} finally {
    if ($application -and -not $application.HasExited) { Stop-Process -Id $application.Id -Force -ErrorAction Continue }
    $remaining = Get-AppxPackage -Name $identity
    if ($remaining) { Remove-AppxPackage -Package $remaining.PackageFullName -ErrorAction Continue }
    if ($certificate) {
        Remove-Item -LiteralPath ('Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint) -ErrorAction Continue
        Remove-Item -LiteralPath ('Cert:\CurrentUser\My\' + $certificate.Thumbprint) -DeleteKey -ErrorAction Continue
        $record.trust_removed = -not (Test-Path ('Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint)) -and -not (Test-Path ('Cert:\CurrentUser\My\' + $certificate.Thumbprint))
    }
    $record.new_framework_packages = @(Get-AppxPackage | Where-Object { $_.PackageFullName -notin $beforePackages -and $_.Name -like 'Microsoft.WindowsAppRuntime*' } | Select-Object -ExpandProperty PackageFullName)
    $record.generated_at_utc = [DateTime]::UtcNow.ToString('o')
    $record | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root 'artifacts/qualification/installation-result.json') -Encoding UTF8
    Remove-Item -LiteralPath $publicCertificate -ErrorAction SilentlyContinue
}
if (-not $record.trust_removed) { throw 'Ephemeral certificate cleanup was incomplete.' }
