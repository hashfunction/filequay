# Copyright 2026 Trieflow LLC. MIT. Real script parsing/loading and existing-output preservation.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
foreach($path in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')){
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors|Out-String)}
}
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($name in @('InstallationQualification.Helpers.ps1','PackageIdentity.Helpers.ps1','ConsumerWorkflow.Helpers.ps1',
    'ConsumerWorkflow.Ui.ps1','ConsumerWorkflow.PickerDiagnostic.ps1','ConsumerWorkflow.Adapter.ps1','UiaProxy.Helpers.ps1','UiaProxy.Fixture.ps1')){
    . (Join-Path $root ('.github/scripts/'+$name))
}
foreach($name in @('capture_ui.ps1','capture_display.ps1','capture_lifecycle.ps1')){. (Join-Path $PSScriptRoot $name)}
$defined=@(Get-Command -CommandType Function|ForEach-Object Name)
foreach($name in @('capture_ui.ps1','capture_lifecycle.ps1','capture_display.ps1','capture.ps1')){
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
    foreach($command in $ast.FindAll({param($item) $item -is [Management.Automation.Language.CommandAst]},$true)){
        $called=$command.GetCommandName()
        if($called -match '^[A-Za-z]+-(FileQuay|FolderSail)' -and $called -notin $defined){throw "Capture references unavailable original/own helper: $called"}
    }
}
# The real Preflight operation must stop before any mutation when an output or
# demo belongs to someone else. It must not acquire ownership of those paths.
$tempRoot=(& python -c 'from pathlib import Path; import tempfile; print(Path(tempfile.gettempdir()).resolve())').Trim()
if($LASTEXITCODE -ne 0){throw 'Fixture temporary root lookup failed'}
$temporary=Join-Path $tempRoot ('foldersail-marketing-preflight-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temporary
try{
    $existing=Join-Path $temporary 'existing';$null=New-Item -ItemType Directory -Path $existing
    $original=Join-Path $existing 'original.txt';[IO.File]::WriteAllText($original,'original user bytes')
    $s=@{demo=(Join-Path $temporary 'demo');profile=(Join-Path $temporary 'profile');output=$existing;outputOwned=$false}
    $refused=$false;try{& (New-FolderSailMarketingOperations).Preflight $s}catch{
        if(-not $_.Exception.Message.Contains('Existing marketing content')){throw};$refused=$true
    }
    if(-not $refused -or $s.outputOwned -or [IO.File]::ReadAllText($original) -cne 'original user bytes' -or
       @(Get-ChildItem -LiteralPath $existing -Force).Count -ne 1){throw 'Existing output was modified or adopted'}
}finally{Remove-Item -LiteralPath $temporary -Recurse -Force}
Write-Output 'PASS script parsing, exact helper availability and real preflight existing-output preservation.'
