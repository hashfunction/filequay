# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')

$errorOnly = @([pscustomobject]@{ depth=0; observation_error='UIA provider failed' })
if (Test-FileQuayAutomationTreeCapture $errorOnly 'ShowStatusCenterButton') {
    throw 'An observation-error placeholder was accepted as a captured UI tree.'
}

$missingRoot = @(
    [pscustomobject]@{ depth=1; name='Status Center'; automation_id='ShowStatusCenterButton'; control_type='ControlType.Button'; is_offscreen=$false }
)
if (Test-FileQuayAutomationTreeCapture $missingRoot 'ShowStatusCenterButton') {
    throw 'A descendant-only observation was accepted without a successful root.'
}

$meaningful = @(
    [pscustomobject]@{ depth=0; name='Home - FileQuay'; automation_id='Root'; control_type='ControlType.Window'; is_offscreen=$false },
    [pscustomobject]@{ depth=1; name='Status Center'; automation_id='ShowStatusCenterButton'; control_type='ControlType.Button'; is_offscreen=$false },
    [pscustomobject]@{ depth=1; observation_error='One unrelated provider failed' }
)
if (-not (Test-FileQuayAutomationTreeCapture $meaningful 'ShowStatusCenterButton')) {
    throw 'A successful root and source-backed Status Center node were rejected.'
}

if (Test-FileQuayWindowDisappearance $false ([IntPtr]42) $false $false) {
    throw 'An unobserved UIA state was treated as disappearance while the process and HWND remained.'
}
if (Test-FileQuayWindowDisappearance $false ([IntPtr]42) $true $false) {
    throw 'A successfully observed visible window was treated as disappeared.'
}
if (-not (Test-FileQuayWindowDisappearance $false ([IntPtr]42) $true $true)) {
    throw 'A successfully observed offscreen window was not accepted as disappeared.'
}
if (-not (Test-FileQuayWindowDisappearance $false ([IntPtr]::Zero) $false $false)) {
    throw 'A zero HWND was not accepted as disappearance.'
}
if (-not (Test-FileQuayWindowDisappearance $true ([IntPtr]42) $false $false)) {
    throw 'An exited process was not accepted as disappearance.'
}

'Consumer observation checks passed: error-only trees fail closed and disappearance requires actual state.'
