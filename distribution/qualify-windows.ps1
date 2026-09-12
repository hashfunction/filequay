[CmdletBinding()]
param([ValidateSet('RequireClean','AllowPreinstalled')][string]$DependencyMode='RequireClean',
      [Parameter(Mandatory=$true)][ValidateSet('Instrumented','Consumer')][string]$BuildKind,
      [ValidateSet('Qualification','Store')][string]$IdentityMode='Qualification')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:CI -ne 'true') { throw 'Requires an isolated Windows CI runner.' }
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Qualification requires PowerShell 7 or later.' }
$qualificationPowerShell = (Get-Process -Id $PID).Path
Set-Location (Split-Path $PSScriptRoot -Parent)
. ./.github/scripts/InstallationQualification.Helpers.ps1
. ./.github/scripts/PackageIdentity.Helpers.ps1
$packageIdentity=Get-FolderSailPackageIdentity $IdentityMode $BuildKind
if ($IdentityMode -eq 'Store' -and $DependencyMode -ne 'RequireClean') {throw 'Store qualification requires clean framework installation.'}
$buildConfiguration = Get-FileQuayBuildKindConfiguration (Get-Location).Path $BuildKind $IdentityMode
$qualificationEvidence = $buildConfiguration.evidence_output
New-Item -ItemType Directory -Path $qualificationEvidence -Force | Out-Null
./distribution/check-prerequisites.ps1
foreach ($file in @(Get-ChildItem distribution -Filter '*.ps1') + @(Get-ChildItem .github/scripts -Filter '*.ps1')) {
  $parseTokens = $null; $parseErrors = $null
  $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$parseTokens, [ref]$parseErrors)
  if ($parseErrors.Count) { throw "PowerShell syntax errors in $($file.Name): $parseErrors" }
}
./distribution/test-manifest.ps1
if ($BuildKind -eq 'Consumer') {
  & $qualificationPowerShell -NoProfile -File .github/scripts/Test-UiaProxyPreflight.ps1 -EvidenceDirectory (Join-Path $qualificationEvidence 'uia-proxy-preflight')
  if ($LASTEXITCODE -ne 0) { throw 'Native UIA proxy preflight failed before application build.' }
}
./distribution/restore-vendor-inputs.ps1
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
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-build-kind-acceptance.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-store-identity.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-store-orchestration.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-observation.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-workflow.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-receipt-scroll.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-uia-replay-preload.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-uia-proxy.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-uia-proxy-fixture.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-workflow-diagnostics.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-picker-diagnostics.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-picker-scope.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-toolbar.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-adapter.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-native-space.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-consumer-picker-input.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-qualification-record-publication.ps1')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-managed-build-kind.ps1')
& $qualificationPowerShell -NoProfile -File tests/packaging/test-process-observation.ps1 | Set-Content artifacts/qualification/process-observation-tests.json -Encoding utf8NoBOM
if ($LASTEXITCODE -ne 0) { throw "Actual process exit observation tests failed with $LASTEXITCODE" }
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-IdentityMode',$IdentityMode)
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-IdentityMode',$IdentityMode,'-Scenario','PreinstalledFramework')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-IdentityMode',$IdentityMode,'-Scenario','FailedAddRace')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-IdentityMode',$IdentityMode,'-Scenario','PackageChanged')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-IdentityMode',$IdentityMode,'-Scenario','ReportingFailure')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-IdentityMode',$IdentityMode,'-Scenario','AdapterFailure')
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','tests/packaging/test-installation-failures.ps1','-IdentityMode',$IdentityMode,'-Scenario','ProxyFailure')
Invoke-Checked dotnet @('publish','tests/Files.SQLiteQualification/Files.SQLiteQualification.csproj','--framework','net10.0-windows10.0.26100.0','--configuration','Release','--runtime','win-x64','--self-contained','false','--output','artifacts/sqlite-qualification','-p:RestoreLockedMode=true')
& ./artifacts/sqlite-qualification/Files.SQLiteQualification.exe --native-evidence-self-test | Set-Content artifacts/qualification/sqlite-native-evidence-tests.json -Encoding utf8NoBOM
if ($LASTEXITCODE -ne 0) { throw "SQLite module evidence regression checks failed with $LASTEXITCODE" }
& ./artifacts/sqlite-qualification/Files.SQLiteQualification.exe | Set-Content artifacts/qualification/sqlite-execution.json -Encoding utf8NoBOM
if ($LASTEXITCODE -ne 0) { throw "Actual Windows SQLite qualification failed with $LASTEXITCODE" }
$buildOutput = $buildConfiguration.appx_output
if (Test-Path -LiteralPath $buildOutput) { throw "Refusing a non-fresh build output: $buildOutput" }
$qualificationProperty = $buildConfiguration.qualification_property
$sourceManifest=[IO.Path]::GetFullPath('src/Files.App/Package.appxmanifest')
$originalManifest=[IO.File]::ReadAllBytes($sourceManifest)
try {
  ./.github/scripts/Configure-AppxManifest.ps1 -Identity $packageIdentity.name -Publisher $packageIdentity.publisher -PublisherDisplayName $packageIdentity.publisher_display_name -Protocol filequay
  Invoke-Checked $msbuild @('src/Files.App/Files.App.csproj','-t:Build','-p:Configuration=Release','-p:Platform=x64','-p:AppxBundlePlatforms=x64','-p:AppxBundle=Never','-p:GenerateAppxPackageOnBuild=true',("-p:FileQuayCIQualification=$qualificationProperty"),'-p:UapAppxPackageBuildMode=SideloadOnly',("-p:AppxPackageDir=$buildOutput\"),'-p:AppxPackageSigningEnabled=false','-v:minimal')
} finally { [IO.File]::WriteAllBytes($sourceManifest,$originalManifest) }
$mainPackages = @(Get-ChildItem -LiteralPath $buildOutput -Recurse -File | Where-Object { $_.Extension -in @('.msix','.appx') -and $_.FullName -notmatch '[\\/]Dependencies[\\/]' })
if ($mainPackages.Count -ne 1) { throw "Expected one main package; found $($mainPackages.Count)." }
$validatedPackage = $buildConfiguration.validation_output
./distribution/verify-package.ps1 -PackagePath $mainPackages[0].FullName -Identity $packageIdentity.name -Publisher $packageIdentity.publisher -OutputDirectory $validatedPackage -IdentityMode $IdentityMode -BuildKind $BuildKind
$managedBuild = Get-FileQuayManagedBuildKindEvidence (Join-Path $validatedPackage 'FolderSail.dll') $BuildKind
$managedBuild | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $qualificationEvidence 'managed-build-kind.json') -Encoding utf8NoBOM
$sqliteAssets = Get-Content src/Files.App/obj/project.assets.json -Raw | ConvertFrom-Json
Invoke-Checked python @('distribution/windows_sdk_policy.py','--props','Directory.Build.props','--deps',(Join-Path $validatedPackage 'FolderSail.deps.json'),'--package-cache',$sqliteAssets.project.restore.packagesPath,'--output',(Join-Path $qualificationEvidence 'windows-sdk-package.json'))
Invoke-Checked python @('distribution/verify-sqlite-assets.py','--assets','src/Files.App/obj/project.assets.json','--package-cache',$sqliteAssets.project.restore.packagesPath,'--package-root',$validatedPackage,'--output',(Join-Path $qualificationEvidence 'sqlite-package-assets.json'))
Invoke-Checked python @('distribution/source_notices.py','--source',(Get-Location).Path,'--package-root',$validatedPackage,'--output',(Join-Path $qualificationEvidence 'source-notices.json'))
Copy-Item ($validatedPackage + '.files.json'),($validatedPackage + '.validation.json') $qualificationEvidence
Get-ChildItem $validatedPackage -Recurse -File | Where-Object { $_.Name -like '*.runtimeconfig.json' -or $_.Name -like '*.deps.json' } | ForEach-Object {
  $relative = [IO.Path]::GetRelativePath($validatedPackage, $_.FullName)
  $target = Join-Path $qualificationEvidence 'package-runtime-metadata' $relative
  New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
  Copy-Item $_.FullName $target
}
Get-ChildItem -Recurse -Filter project.assets.json | ForEach-Object {
  $relative = [IO.Path]::GetRelativePath((Get-Location).Path, $_.FullName)
  $target = Join-Path $qualificationEvidence 'resolved-assets' $relative
  New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
  Copy-Item $_.FullName $target
}
Get-ChildItem -LiteralPath $buildOutput -Recurse -File | Where-Object { $_.Extension -in @('.msix','.appx','.msixbundle','.appxbundle') } | ForEach-Object {
  @{ path=[IO.Path]::GetRelativePath((Get-Location).Path, $_.FullName); bytes=$_.Length; sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash }
} | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $qualificationEvidence 'package-inventory.json') -Encoding utf8NoBOM
Invoke-Checked $qualificationPowerShell @('-NoProfile','-File','.github/scripts/Test-CIInstallation.ps1','-PackagePath',$mainPackages[0].FullName,'-ValidatedPackageDirectory',$validatedPackage,'-BuildKind',$BuildKind,'-DependencyMode',$DependencyMode,'-IdentityMode',$IdentityMode)
@{ source_commit=$env:GITHUB_SHA; workflow_run_id=$env:GITHUB_RUN_ID; workflow_run_attempt=$env:GITHUB_RUN_ATTEMPT; generated_at_utc=[DateTime]::UtcNow.ToString('o'); identity=$packageIdentity.name; publisher=$packageIdentity.publisher; identity_mode=$IdentityMode; package_path=[IO.Path]::GetRelativePath((Get-Location).Path,$mainPackages[0].FullName); package_sha256=(Get-FileHash $mainPackages[0].FullName -Algorithm SHA256).Hash; native_build=$true; store_identity=($IdentityMode -eq 'Store'); installation_qualification_passed=$true; requested_build_kind=$BuildKind; actual_build_kind=$managedBuild.actual_build_kind; managed_build_kind_verified=$true; instrumented_qualification_build=($BuildKind -eq 'Instrumented'); normal_store_binary_installation_tested=($BuildKind -eq 'Consumer'); dependency_mode=$DependencyMode; dependency_installation_from_artifacts_verified=($DependencyMode -eq 'RequireClean'); dependency_resolution_only=($DependencyMode -eq 'AllowPreinstalled'); clean_framework_installation_gate_passed=($DependencyMode -eq 'RequireClean'); store_clean_environment_gate_pending=($DependencyMode -eq 'AllowPreinstalled'); native_source_clearance=$false; submitted=$false } | ConvertTo-Json | Set-Content (Join-Path $qualificationEvidence 'build-result.json') -Encoding utf8NoBOM
