# Copyright 2026 Trieflow LLC. MIT. Actual Install operation, original matcher and lifecycle; no Windows acceptance.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')
. (Join-Path $PSScriptRoot 'capture_lifecycle.ps1')
$publisher='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
$expected='Microsoft.WindowsAppRuntime.2_2.4.0.0_x64__8wekyb3d8bbwe'
$requirement=[pscustomobject]@{Name='Microsoft.WindowsAppRuntime.2';Publisher=$publisher;MinVersion='2.4.0.0'}
$good=[pscustomobject]@{Name=$requirement.Name;Publisher=$publisher;Version=[version]'2.4.0.0';Architecture='X64';PackageFullName=$expected}
# Exercise real PowerShell serialization, as used by the compatibility session.
$roundtrip=[Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($good))
if(-not (Test-FileQuayFrameworkRegistration $roundtrip $requirement)){throw 'Serialization alone unexpectedly changes the original predicate'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('foldersail-framework-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $temp 'framework')
[IO.File]::WriteAllText((Join-Path $temp 'framework/Microsoft.WindowsAppRuntime.2.msix'),'framework fixture')
function Add-AppxPackage {param($Path,$DependencyPath,$ErrorAction) $script:addCount++}
function Get-AppxPackage {param($Name,$ErrorAction) if($Name -ceq '1659hashfunction.FileQuay'){return $script:app};return $script:frameworks}
function Get-AppxPackageManifest {param($Package) return $null}
# Other fixed app manifest fields are covered by original qualification; only the actual framework boundary is exercised here.
function Assert-FolderSailPackageIdentity {param($Manifest,$Mode,$Kind)}
try{
    foreach($scenario in @('valid','serialized','absent','full-name','requirement','many','observation-error')){
        $script:frameworks=@($good.PSObject.Copy());$script:addCount=0
        switch($scenario){
            'serialized'{$script:frameworks=@($roundtrip)}
            'absent'{$script:frameworks=@()}
            'full-name'{$script:frameworks[0].PackageFullName='foreign'}
            'requirement'{$script:frameworks[0].Name='foreign'}
            'many'{$script:frameworks=@(1..10|ForEach-Object {$good.PSObject.Copy()})}
            'observation-error'{$script:frameworks[0].PackageFullName='foreign';$script:frameworks[0].Version='invalid-version'}
        }
        $script:app=[pscustomobject]@{Name='1659hashfunction.FileQuay';Publisher='CN=fixture';Version='1.0.1.0';Architecture='X64';PackageFamilyName='family';PackageFullName='1659hashfunction.FileQuay_1.0.1.0_x64__family'}
        $s=@{inputs=$temp;profile=(Join-Path $temp 'absent');signed='owned signed fixture';fullName=$app.PackageFullName;
            identity=@{name=$app.Name;publisher=$app.Publisher;family=$app.PackageFamilyName};record=@{};events=[Collections.Generic.List[string]]::new();
            verified=@{payload=@{};framework=@{artifact_identity=@{Name=$requirement.Name};requirement=$requirement;
                artifact_sha256=(Get-FileHash (Join-Path $temp 'framework/Microsoft.WindowsAppRuntime.2.msix')).Hash}};
            ownership=@{installAttempted=$false;addCompleted=$false;installedByUs=$false;preflightPackageFullNames=@()}}
        $ops=[ordered]@{}
        foreach($name in @('Preflight','Prepare','Sign','Activate','Workflow','Close','Uninstall','ObserveFailure','Stop','RestoreDisplay','RemovePackage','RemoveDemo','RemoveTrust','RemoveKey','RemoveTemporary')){
            $ops[$name]=[scriptblock]::Create('param($s) $s.events.Add("'+$name+'")')
        }
        $ops.Install=(New-FolderSailMarketingOperations).Install
        $outcome=Invoke-FolderSailMarketingLifecycle $s $ops
        $passes=$scenario -in @('valid','serialized')
        if($passes -and $outcome.primary_error){throw $outcome.primary_error}
        if(-not $passes -and $outcome.primary_error -cne 'System.Management.Automation.RuntimeException: Original framework registration differs'){throw "Original failure changed: $($outcome.primary_error)"}
        if(($s.events.Contains('Activate')) -ne $passes -or $s.events[-1] -cne 'RemoveTemporary' -or $addCount -ne 1){throw 'Activation or cleanup boundary changed'}
        if(-not $s.record.ContainsKey('framework_registration_observation')){throw 'Actual Install omitted framework refusal evidence'}
        $o=$s.record.framework_registration_observation
        if($o.expected_full_name -cne $expected -or $o.observed_count -ne $frameworks.Count -or $o.candidates.Count -ne [Math]::Min(8,$frameworks.Count)){throw 'Exact observed identity/count or bound lost'}
        if($o.candidates.Count -and $o.candidates[0].fields.PackageFullName.value -cne $frameworks[0].PackageFullName){throw 'Original full-name observation lost'}
        if($scenario -eq 'observation-error' -and ($o.diagnostic_errors -join '|') -notmatch 'invalid-version'){throw 'Secondary observation failure lost'}
    }
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
Write-Output 'PASS seven actual Install-boundary cases, exact refusal/no activation, bounded observation, serialization and cleanup retention.'
