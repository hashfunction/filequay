# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) 'filequay-build-kind-fixture'
$consumerBuild = Get-FileQuayBuildKindConfiguration $fixtureRoot 'Consumer'
$instrumentedBuild = Get-FileQuayBuildKindConfiguration $fixtureRoot 'Instrumented'
if ($consumerBuild.qualification_property -cne 'false' -or $instrumentedBuild.qualification_property -cne 'true') {
    throw 'Build-kind dispatch did not compile consumer without the probe and instrumented with the probe.'
}
if ($consumerBuild.appx_output -ceq $instrumentedBuild.appx_output -or $consumerBuild.validation_output -ceq $instrumentedBuild.validation_output) {
    throw 'Build-kind dispatch can reuse another kind output.'
}
if (-not $consumerBuild.appx_output.EndsWith((Join-Path 'artifacts/appx' 'Consumer')) -or
    -not $instrumentedBuild.validation_output.EndsWith((Join-Path 'artifacts/validated-package' 'Instrumented'))) {
    throw 'Build-kind output paths are not confined to their explicit kind.'
}

$common = [ordered]@{
    managed_build_kind_verified=$true; dependency_artifacts_verified=$true; framework_registration_verified=$true
    installed=$true; main_window_verified=$true; broker_process_identity_verified=$true; uninstall_verified=$true; trust_removed=$true
    registration_ownership_established=$true; cleanup_errors=@()
}
$consumer = [ordered]@{} + $common
$consumer.actual_build_kind='Consumer'; $consumer.ci_probe_type_present=$false
$consumer.ui_tree_captured=$true; $consumer.screenshot_captured=$true; $consumer.window_close_requested=$true
$consumer.window_disappeared=$true; $consumer.consumer_process_outcome_accepted=$true; $consumer.owned_process_cleanup_verified=$true
$consumer.consumer_com_probe_invoked=$false
$consumer.consumer_workflow_verified=$true; $consumer.consumer_fixture_cleanup_verified=$true
if (-not (Test-FileQuayInstallationAcceptance $consumer 'Consumer')) { throw 'A complete consumer qualification was rejected.' }
$consumer.com_activation_verified=$false
if (-not (Test-FileQuayInstallationAcceptance $consumer 'Consumer')) { throw 'Consumer acceptance incorrectly requires the CI COM probe.' }

$instrumented = [ordered]@{} + $common
$instrumented.actual_build_kind='Instrumented'; $instrumented.ci_probe_type_present=$true
$instrumented.com_activation_verified=$true; $instrumented.server_natural_exit_verified=$true
if (-not (Test-FileQuayInstallationAcceptance $instrumented 'Instrumented')) { throw 'A complete instrumented qualification was rejected.' }

foreach ($mutation in @('wrong-kind','probe-present','probe-invoked','window-visible','cleanup-missing','workflow-missing','fixture-cleanup-missing')) {
    $candidate = [ordered]@{} + $consumer
    switch ($mutation) {
        'wrong-kind' { $candidate.actual_build_kind='Instrumented' }
        'probe-present' { $candidate.ci_probe_type_present=$true }
        'probe-invoked' { $candidate.consumer_com_probe_invoked=$true }
        'window-visible' { $candidate.window_disappeared=$false }
        'cleanup-missing' { $candidate.owned_process_cleanup_verified=$false }
        'workflow-missing' { $candidate.consumer_workflow_verified=$false }
        'fixture-cleanup-missing' { $candidate.consumer_fixture_cleanup_verified=$false }
    }
    if (Test-FileQuayInstallationAcceptance $candidate 'Consumer') { throw "Consumer acceptance ignored $mutation." }
}
$instrumented.com_activation_verified=$false
if (Test-FileQuayInstallationAcceptance $instrumented 'Instrumented') { throw 'Instrumented qualification passed without actual COM activation.' }

'Build-kind acceptance checks passed: consumer and instrumented gates remain distinct and fail closed.'
