# Run without AppX APIs; tests the actual qualification cleanup and matching helpers.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/InstallationQualification.Helpers.ps1')
$visited = [System.Collections.Generic.List[string]]::new()
$failures = @(Invoke-FileQuayCleanup ([ordered]@{
    package = { $visited.Add('package'); throw 'registration remains' }
    certificate = { $visited.Add('certificate'); throw 'trust remains' }
    privateKey = { $visited.Add('privateKey') }
}))
if ($visited.Count -ne 3 -or $failures.Count -ne 2) { throw 'A cleanup failure prevented another cleanup action.' }
$message = Get-FileQuayQualificationFailure 'activation failed' $failures
foreach ($expected in @('activation failed','registration remains','trust remains')) {
    if (-not $message.Contains($expected)) { throw "Combined failure lost $expected" }
}
if (Get-FileQuayQualificationFailure '' @()) { throw 'Successful cleanup reported failure.' }
$requirement = [pscustomobject]@{ Name='Microsoft.WindowsAppRuntime.2.4';Publisher='CN=Microsoft';MinVersion='2.4.1.0' }
$package = [pscustomobject]@{ Name=$requirement.Name;Publisher=$requirement.Publisher;Version='2.4.10.0';Architecture='X64' }
if (-not (Test-FileQuayFrameworkRegistration $package $requirement)) { throw 'Compatible pre-existing registration was missed.' }
foreach ($entry in @(@('Name','Other'),@('Publisher','CN=Other'),@('Version','2.4.0.0'),@('Architecture','Arm64'))) {
    $copy = $package.PSObject.Copy(); $copy.($entry[0]) = $entry[1]
    if (Test-FileQuayFrameworkRegistration $copy $requirement) { throw "Incompatible $($entry[0]) was accepted." }
}
'Installation helper checks passed: cleanup continuation, combined errors, and exact compatible registration matching.'
