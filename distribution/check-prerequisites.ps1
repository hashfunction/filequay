param()
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Native FolderSail qualification requires Windows.' }
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force artifacts/qualification | Out-Null
dotnet --info | Out-File artifacts/qualification/dotnet-info.txt
if ($LASTEXITCODE -ne 0) { throw 'dotnet --info failed.' }
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'Visual Studio Installer/vswhere is missing.' }
& $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -format json | Out-File artifacts/qualification/visual-studio.json
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild is missing.' }
& $msbuild -version -nologo | Out-File artifacts/qualification/msbuild-version.txt
if ($LASTEXITCODE -ne 0) { throw 'MSBuild version failed.' }
Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory | Select-Object Name | ConvertTo-Json | Out-File artifacts/qualification/windows-sdks.json
Write-Output "MSBuild=$msbuild"
