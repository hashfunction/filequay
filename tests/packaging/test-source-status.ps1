# Copyright 2026 Trieflow LLC. MIT.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$path=Join-Path $PSScriptRoot '../../distribution/qualify-windows.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Qualification script does not parse.'}
$function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Write-FolderSailSourceStatus'},$true)
$helperPath=Join-Path ([IO.Path]::GetTempPath()) ('foldersail-status-helper-'+[guid]::NewGuid().ToString('N')+'.ps1')
[IO.File]::WriteAllText($helperPath,$function.Extent.Text)
try{. $helperPath}finally{Remove-Item -LiteralPath $helperPath}
$script:observations=[Collections.Generic.List[string]]::new();$script:diagnosticExit=0
function python {
    if($args.Count -ne 3 -or -not $args[0].EndsWith('observe_source_status.py') -or $args[1] -cne '--phase'){throw 'Unexpected observation command.'}
    $script:observations.Add($args[2]);$global:LASTEXITCODE=$script:diagnosticExit
}
$global:LASTEXITCODE=37
Write-FolderSailSourceStatus 'after-build'
if($global:LASTEXITCODE -ne 37 -or $observations[0] -cne 'after-build'){throw 'Diagnostic altered the native exit code or phase.'}
$script:diagnosticExit=2
Write-FolderSailSourceStatus 'after-installation' -WarningAction SilentlyContinue
if($global:LASTEXITCODE -ne 37){throw 'Secondary diagnostic failure altered native exit code.'}
$sourceManifest=Join-Path ([IO.Path]::GetTempPath()) ('foldersail-status-'+[guid]::NewGuid().ToString('N'))
$originalManifest=[byte[]](1,2,3);$buildFinally=$ast.Find({param($n)$n -is [Management.Automation.Language.TryStatementAst] -and $n.Finally -and $n.Finally.Extent.Text.Contains("Write-FolderSailSourceStatus 'after-build'")},$true).Finally
try {
    $caught=''
    try{try{throw 'original build failure'}finally{& ([scriptblock]::Create(($buildFinally.Statements.Extent.Text -join "`n")))}}catch{$caught=$_.Exception.Message}
    if($caught -cne 'original build failure' -or [Convert]::ToHexString([IO.File]::ReadAllBytes($sourceManifest)) -cne '010203' -or $observations[-1] -cne 'after-build'){throw "Build restoration/status changed original failure: $caught; phases=$($observations -join ',')."}
} finally {if(Test-Path -LiteralPath $sourceManifest){Remove-Item -LiteralPath $sourceManifest}}
$install=$ast.Find({param($n)$n -is [Management.Automation.Language.TryStatementAst] -and $n.Finally -and $n.Finally.Extent.Text.Contains("Write-FolderSailSourceStatus 'after-installation'")},$true)
$qualificationPowerShell='fixture';$mainPackages=@(@{FullName='fixture.msix'});$validatedPackage='fixture';$BuildKind='Consumer';$DependencyMode='RequireClean';$IdentityMode='Store'
$script:installCalls=0
function Invoke-Checked { $script:installCalls++;throw 'original installed workflow failure' }
$caught=''
try{& ([scriptblock]::Create($install.Extent.Text))}catch{$caught=$_.Exception.Message}
if($caught -cne 'original installed workflow failure' -or $installCalls -ne 1 -or $observations[-1] -cne 'after-installation'){throw 'Original failed installation did not retain its final status observation.'}
'PASS production status checkpoints: build restoration, failed installation, bounded observer invocation, secondary failure and native exit code preservation.'
