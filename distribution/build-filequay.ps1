# Copyright (c) Trieflow LLC. Licensed under the MIT License.
param([string]$Identity = '', [string]$Publisher = '', [string]$Version = '1.0.1.0')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'FolderSail packaging requires Windows; portable test results are not package qualification.' }
if (-not $Identity -or -not $Publisher) { throw 'Explicit owned Identity and Publisher are required. No Store identity is inferred.' }
Set-Location (Split-Path $PSScriptRoot -Parent)
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
$sourceCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'A committed source checkout is required.' }
$dirty = & git status --porcelain --untracked-files=all
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Build from a clean committed checkout so the source archive matches implementation inputs.' }
./distribution/check-prerequisites.ps1
./distribution/test-manifest.ps1
Invoke-Checked python @('-m','unittest','discover','-s','tests/packaging')
./tests/packaging/test-runtime-files.ps1
./distribution/restore-vendor-inputs.ps1
./.github/scripts/Configure-AppxManifest.ps1 -Identity $Identity -Publisher $Publisher -Version $Version -Protocol filequay
$runDirectory = Join-Path (Get-Location).Path ('artifacts/release/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild is missing.' }
$packageDirectory = Join-Path $runDirectory 'packages'
Invoke-Checked dotnet @('test','--project','tests/Files.App.UnitTests/Files.App.UnitTests.csproj','-c','Release','--report-trx','--results-directory',(Join-Path $runDirectory 'unit-tests'))
Invoke-Checked $msbuild @('Files.slnx','-t:Restore','-p:Platform=x64','-p:Configuration=Release','-p:PublishReadyToRun=true','-v:quiet','-clp:ErrorsOnly')
Invoke-Checked $msbuild @('src/Files.App/Files.App.csproj','-t:Build','-p:Configuration=Release','-p:Platform=x64','-p:AppxBundlePlatforms=x64','-p:AppxBundle=Never','-p:GenerateAppxPackageOnBuild=true','-p:UapAppxPackageBuildMode=SideloadOnly',('-p:AppxPackageDir=' + $packageDirectory + '\'),'-p:AppxPackageSigningEnabled=false','-v:quiet','-clp:ErrorsOnly')
$packages = @(Get-ChildItem -LiteralPath $packageDirectory -Recurse -File | Where-Object { $_.Extension -in @('.msix','.appx') -and $_.FullName -notmatch '[\\/]Dependencies[\\/]' })
if ($packages.Count -ne 1) { throw "Expected exactly one main unsigned package, found $($packages.Count). Review package output before staging." }
$unpacked = Join-Path $runDirectory 'validated-package'
./distribution/verify-package.ps1 -PackagePath $packages[0].FullName -Identity $Identity -Publisher $Publisher -OutputDirectory $unpacked
Invoke-Checked python @('distribution/inventory.py','--package-root',$unpacked)
$sourceArchive = Join-Path $runDirectory ('FolderSail-source-' + $sourceCommit + '.zip')
Invoke-Checked git @('archive','--format=zip',('--output=' + $sourceArchive),$sourceCommit)
Copy-Item distribution/dependencies.spdx.json,distribution/resources.csv -Destination $runDirectory
$hashes = @($packages[0].FullName, $sourceArchive, (Join-Path $runDirectory 'dependencies.spdx.json'), (Join-Path $runDirectory 'resources.csv')) | ForEach-Object { [ordered]@{ name=[IO.Path]::GetFileName($_); sha256=(Get-FileHash $_ -Algorithm SHA256).Hash } }
[ordered]@{ source_commit=$sourceCommit; generated_at_utc=[DateTime]::UtcNow.ToString('o'); identity=$Identity; publisher=$Publisher; version=$Version; sdk=(& dotnet --version); unsigned_package_built=$true; unit_tests_passed=$true; makeappx_semantic_validation_passed=$true; package_payload_inspection_passed=$true; runtime_startup_verified=$false; hashes=$hashes; installed=$false; interaction_tests_passed=$false; wack_passed=$false; license_audit_complete=$false; store_identity_verified=$false; submitted=$false } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $runDirectory 'build-record.json') -Encoding utf8NoBOM
Write-Output "Unsigned build evidence: $runDirectory. Installation, interaction tests, WACK and license clearance remain separate gates."
