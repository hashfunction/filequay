# Copyright 2026 Trieflow LLC. MIT. Capture the exact previously qualified Store payload.
param([Parameter(Mandatory)][string]$Inputs,[Parameter(Mandatory)][string]$QualifiedSource,
      [string]$Output=(Join-Path $PSScriptRoot '../../artifacts/marketing'))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($env:OS -cne 'Windows_NT' -or $env:CI -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'hashfunction/filequay' -or
   $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $PSVersionTable.PSVersion -lt [version]'7.6'){
    throw 'Marketing capture requires the isolated manual Windows CI job and current PowerShell.'
}
$Inputs=[IO.Path]::GetFullPath($Inputs);$QualifiedSource=[IO.Path]::GetFullPath($QualifiedSource);$Output=[IO.Path]::GetFullPath($Output)
# Independently replay the original Store exporter checks before loading its
# exact source helpers, and again after both UI work and cleanup.
& python (Join-Path $PSScriptRoot 'capture_checks.py') --inputs $Inputs --qualified-source $QualifiedSource
if($LASTEXITCODE -ne 0){throw 'Original qualified input verification failed before any capture mutation'}
$verified=Get-Content (Join-Path $Inputs 'verified-inputs.json') -Raw|ConvertFrom-Json -AsHashtable
$bound=(Get-Content (Join-Path $PSScriptRoot 'binding.json') -Raw|ConvertFrom-Json -AsHashtable).qualified
foreach($relative in @('InstallationQualification.Helpers.ps1','PackageIdentity.Helpers.ps1','ConsumerWorkflow.Helpers.ps1',
                      'ConsumerWorkflow.Ui.ps1','ConsumerWorkflow.PickerDiagnostic.ps1','ConsumerWorkflow.Adapter.ps1',
                      'UiaProxy.Helpers.ps1','UiaProxy.Fixture.ps1')){
    . (Join-Path $QualifiedSource ('.github/scripts/'+$relative))
}
Import-Module Appx -UseWindowsPowerShell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'CaptureNative.cs')
foreach($name in @('capture_ui.ps1','capture_display.ps1','capture_lifecycle.ps1')){. (Join-Path $PSScriptRoot $name)}
$identity=Get-FolderSailPackageIdentity Store Consumer
$record=[ordered]@{schema_version=1;purpose='original Windows marketing capture';consumer_acceptance=$false;
    marketing_capture_complete=$false;pixel_manipulation=$false;source_commit=$env:GITHUB_SHA;workflow_run_id=$env:GITHUB_RUN_ID;
    workflow_run_attempt=$env:GITHUB_RUN_ATTEMPT;qualified=$bound;started_at_utc=[DateTimeOffset]::UtcNow.ToString('O');
    trace=[Collections.Generic.List[object]]::new();normal_window_close_requested=$false;window_disappeared=$false;
    normal_process_exit_verified=$false;background_process_observed=$false;owned_process_cleanup_verified=$false;csv_committed_verified=$false}
$state=@{inputs=$Inputs;qualified=$QualifiedSource;output=$Output;outputOwned=$false;bound=$bound;verified=$verified;identity=$identity;record=$record;
    package=(Join-Path $Inputs 'store/FolderSail_1.0.1.0_x64.msix');demo='C:\FolderSail Demo';
    profile=(Join-Path $env:LOCALAPPDATA ('Packages/'+$identity.family));fullName=($identity.name+'_1.0.1.0_x64__r3hxytd7jt6c4');
    fixtureState=(Join-Path $Output 'demo-file-ownership.json');fixture=$null;temporary=$null;nativeAdapter=$null;uiaProxy=@{};
    process=$null;processOwned=$false;installed=$null;ui=$null;servers=@{};certificate=$null;trustAttempted=$false;
    stopped=$true;normalClose=$false;uninstalled=$false;sealed=$false;removed=$false;inputsUnchanged=$false;
    trustRemoved=$false;keyRemoved=$false;temporaryRemoved=$false;captures=[Collections.Generic.List[string]]::new();
    displayOriginalMode=$null;displayDevice=$null;displayRestoreRequired=$false;displayEvidence=@{restore_verified=$false};
    ownership=[ordered]@{installAttempted=$false;addCompleted=$false;installedByUs=$false;ownedPackageFullName=$null;
        preflightPackageFullNames=@();residualPackageFullNames=@()}}
$state.outcome=Invoke-FolderSailMarketingLifecycle $state (New-FolderSailMarketingOperations)
try{
    & python (Join-Path $PSScriptRoot 'capture_checks.py') --inputs $Inputs --qualified-source $QualifiedSource
    if($LASTEXITCODE -ne 0){throw 'Original source, helpers or qualified package changed during capture'}
    $state.inputsUnchanged=$true
    Assert-FolderSailMarketingComplete $state
    $record.marketing_capture_complete=$true
}catch{$state.outcome.cleanup_errors+=@('Final capture verification: '+$_.Exception.Message)}
finally{
    # Shared system picker brokers are only observed; never terminate them.
    if($state.ui){foreach($broker in $state.ui.brokers.Values){$broker.Dispose()}}
    foreach($server in $state.servers.Values){$server.Dispose()}
    if($state.process){$state.process.Dispose()}
    $record.finished_at_utc=[DateTimeOffset]::UtcNow.ToString('O');$record.captures=@($state.captures)
    $record.original_inputs_unchanged=$state.inputsUnchanged;$record.native_adapter=$state.nativeAdapter;$record.uia_proxy=$state.uiaProxy
    $record.display=$state.displayEvidence;$record.registration=$state.ownership;$record.outcome=$state.outcome
    $record.cleanup=@{normal_window_close=$state.normalClose;owned_processes_stopped=$state.stopped;uninstalled=$state.uninstalled;
        demo_removed=$state.removed;profile_absent=(-not (Test-Path -LiteralPath $state.profile));trust_removed=$state.trustRemoved;
        private_key_removed=$state.keyRemoved;temporary_files_removed=$state.temporaryRemoved}
    if($state.outputOwned){Write-FileQuayQualificationRecord (Join-Path $Output 'marketing-capture.json') $record 20}
}
if(-not $record.marketing_capture_complete){throw 'Marketing capture failed. Original errors and cleanup outcomes are retained separately.'}
Write-Output 'Three raw screenshots and actual CSV result verified; original consumer qualification remains separate.'
