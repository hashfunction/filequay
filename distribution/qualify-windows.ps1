$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:CI -ne 'true') { throw 'Requires an isolated Windows CI runner.' }
Set-Location (Split-Path $PSScriptRoot -Parent)
./distribution/check-prerequisites.ps1
./distribution/restore-vendor-inputs.ps1
# This identity is for disposable build qualification. It is not a Store reservation.
./.github/scripts/Configure-AppxManifest.ps1 -Identity 'Trieflow.FileQuay.Qualification' -Publisher 'CN=FileQuay-CI-Qualification'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild is missing.' }
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Program failed with $LASTEXITCODE" }
}
Invoke-Checked dotnet @('test','--project','tests/Files.App.UnitTests/Files.App.UnitTests.csproj','-c','Release','--report-trx','--results-directory','artifacts/qualification/unit-tests')
Invoke-Checked $msbuild @('Files.slnx','-t:Restore','-p:Platform=x64','-p:Configuration=Release','-p:PublishReadyToRun=true','-p:RestorePackagesWithLockFile=true','-v:minimal')
Invoke-Checked $msbuild @('src/Files.App/Files.App.csproj','-t:Build','-p:Configuration=Release','-p:Platform=x64','-p:AppxBundlePlatforms=x64','-p:AppxBundle=Never','-p:GenerateAppxPackageOnBuild=true','-p:UapAppxPackageBuildMode=SideloadOnly','-p:AppxPackageDir=artifacts/appx/','-p:AppxPackageSigningEnabled=false','-v:minimal')
Get-ChildItem -Recurse -Filter project.assets.json | ForEach-Object {
  $relative = [IO.Path]::GetRelativePath((Get-Location).Path, $_.FullName)
  $target = Join-Path 'artifacts/qualification/resolved-assets' $relative
  New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
  Copy-Item $_.FullName $target
}
Get-ChildItem -Recurse -File -Include '*.msix','*.appx','*.msixbundle','*.appxbundle' | ForEach-Object {
  @{ path=[IO.Path]::GetRelativePath((Get-Location).Path, $_.FullName); bytes=$_.Length; sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash }
} | ConvertTo-Json -Depth 3 | Set-Content artifacts/qualification/package-inventory.json -Encoding utf8NoBOM
@{ source_commit=$env:GITHUB_SHA; generated_at_utc=[DateTime]::UtcNow.ToString('o'); identity='Trieflow.FileQuay.Qualification'; publisher='CN=FileQuay-CI-Qualification'; native_build=$true; store_identity=$false; installed=$false; native_source_clearance=$false; submitted=$false } | ConvertTo-Json | Set-Content artifacts/qualification/build-result.json -Encoding utf8NoBOM
