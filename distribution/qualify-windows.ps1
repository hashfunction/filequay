$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:CI -ne 'true') { throw 'Requires an isolated Windows CI runner.' }
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Qualification requires PowerShell 7 or later.' }
$qualificationPowerShell = (Get-Process -Id $PID).Path
Set-Location (Split-Path $PSScriptRoot -Parent)
./distribution/check-prerequisites.ps1
foreach ($file in @(Get-ChildItem distribution -Filter '*.ps1') + @(Get-ChildItem .github/scripts -Filter '*.ps1')) {
  $parseTokens = $null; $parseErrors = $null
  $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$parseTokens, [ref]$parseErrors)
  if ($parseErrors.Count) { throw "PowerShell syntax errors in $($file.Name): $parseErrors" }
}
./distribution/test-manifest.ps1
./distribution/restore-vendor-inputs.ps1
# This identity is for disposable build qualification. It is not a Store reservation.
./.github/scripts/Configure-AppxManifest.ps1 -Identity 'Trieflow.FileQuay.Qualification' -Publisher 'CN=FileQuay-CI-Qualification' -Protocol filequay
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild is missing.' }
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Program failed with $LASTEXITCODE" }
}
Invoke-Checked dotnet @('test','--project','tests/Files.App.UnitTests/Files.App.UnitTests.csproj','-c','Release','--report-trx','--results-directory','artifacts/qualification/unit-tests')
Invoke-Checked $msbuild @('Files.slnx','-t:Restore','-p:Platform=x64','-p:Configuration=Release','-p:PublishReadyToRun=true','-p:RestorePackagesWithLockFile=true','-v:minimal')
Invoke-Checked python @('-m','unittest','discover','-s','tests/packaging','-v')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-helpers.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-Scenario','PreinstalledFramework')
Invoke-Checked $msbuild @('src/Files.App/Files.App.csproj','-t:Build','-p:Configuration=Release','-p:Platform=x64','-p:AppxBundlePlatforms=x64','-p:AppxBundle=Never','-p:GenerateAppxPackageOnBuild=true','-p:FileQuayCIQualification=true','-p:UapAppxPackageBuildMode=SideloadOnly','-p:AppxPackageDir=artifacts/appx/','-p:AppxPackageSigningEnabled=false','-v:minimal')
$mainPackages = @(Get-ChildItem -Recurse -File -Include '*.msix','*.appx' | Where-Object { $_.FullName -notmatch '[\\/]Dependencies[\\/]' })
if ($mainPackages.Count -ne 1) { throw "Expected one main package; found $($mainPackages.Count)." }
./distribution/verify-package.ps1 -PackagePath $mainPackages[0].FullName -Identity 'Trieflow.FileQuay.Qualification' -Publisher 'CN=FileQuay-CI-Qualification' -OutputDirectory (Join-Path (Get-Location) 'artifacts/validated-package')
Copy-Item artifacts/validated-package.files.json,artifacts/validated-package.validation.json artifacts/qualification/
Get-ChildItem artifacts/validated-package -Recurse -File | Where-Object { $_.Name -like '*.runtimeconfig.json' -or $_.Name -like '*.deps.json' } | ForEach-Object {
  $relative = [IO.Path]::GetRelativePath((Join-Path (Get-Location) 'artifacts/validated-package'), $_.FullName)
  $target = Join-Path 'artifacts/qualification/package-runtime-metadata' $relative
  New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
  Copy-Item $_.FullName $target
}
Get-ChildItem -Recurse -Filter project.assets.json | ForEach-Object {
  $relative = [IO.Path]::GetRelativePath((Get-Location).Path, $_.FullName)
  $target = Join-Path 'artifacts/qualification/resolved-assets' $relative
  New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
  Copy-Item $_.FullName $target
}
Get-ChildItem -Recurse -File -Include '*.msix','*.appx','*.msixbundle','*.appxbundle' | ForEach-Object {
  @{ path=[IO.Path]::GetRelativePath((Get-Location).Path, $_.FullName); bytes=$_.Length; sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash }
} | ConvertTo-Json -Depth 3 | Set-Content artifacts/qualification/package-inventory.json -Encoding utf8NoBOM
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','.github/scripts/Test-CIInstallation.ps1','-PackagePath',$mainPackages[0].FullName)
@{ source_commit=$env:GITHUB_SHA; generated_at_utc=[DateTime]::UtcNow.ToString('o'); identity='Trieflow.FileQuay.Qualification'; publisher='CN=FileQuay-CI-Qualification'; native_build=$true; store_identity=$false; installation_qualification_passed=$true; instrumented_qualification_build=$true; normal_store_binary_installation_tested=$false; native_source_clearance=$false; submitted=$false } | ConvertTo-Json | Set-Content artifacts/qualification/build-result.json -Encoding utf8NoBOM
