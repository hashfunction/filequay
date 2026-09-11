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

if (-not (Get-Command Set-FileQuayOwnedRegistration -ErrorAction SilentlyContinue) -or
    -not (Get-Command Remove-FileQuayOwnedRegistration -ErrorAction SilentlyContinue)) {
    throw 'Package registration ownership helpers are missing.'
}

$owned = [pscustomobject]@{
    Name='Trieflow.FileQuay.Qualification'; Publisher='CN=FileQuay-CI-Qualification'; Version='1.0.0.0'; Architecture='X64'
    PackageFullName='Trieflow.FileQuay.Qualification_1.0.0.0_x64__fixture'; PackageFamilyName='Trieflow.FileQuay.Qualification_fixture'
}
$foreign = [pscustomobject]@{
    Name=$owned.Name; Publisher=$owned.Publisher; Version=$owned.Version; Architecture='Arm64'
    PackageFullName='Trieflow.FileQuay.Qualification_1.0.0.0_arm64__fixture'; PackageFamilyName=$owned.PackageFamilyName
}

foreach ($scenario in @('failed-add-race','missing-capture','ambiguous-capture','wrong-architecture','owned','owned-with-foreign','remove-failed')) {
    $fixture = [ordered]@{ registrations=@(); removed=[Collections.Generic.List[string]]::new(); removeFailure=$false }
    $ownership = [ordered]@{
        installAttempted=$true; addCompleted=$false; installedByUs=$false; ownedPackageFullName=$null
        preflightPackageFullNames=@(); residualPackageFullNames=@()
    }
    switch ($scenario) {
        'failed-add-race' { $fixture.registrations=@($owned) }
        'missing-capture' { $ownership.addCompleted=$true }
        'ambiguous-capture' {
            $ownership.addCompleted=$true; $fixture.registrations=@($owned,$foreign)
            try { Set-FileQuayOwnedRegistration $ownership @($fixture.registrations) $owned.Name $owned.Publisher $owned.Version 'X64'; throw 'expected ambiguous capture rejection' }
            catch { if ($_.Exception.Message -match 'expected ambiguous') { throw } }
        }
        'wrong-architecture' {
            $ownership.addCompleted=$true; $fixture.registrations=@($foreign)
            try { Set-FileQuayOwnedRegistration $ownership @($fixture.registrations) $owned.Name $owned.Publisher $owned.Version 'X64'; throw 'expected architecture rejection' }
            catch { if ($_.Exception.Message -match 'expected architecture') { throw } }
        }
        default {
            $ownership.addCompleted=$true; $fixture.registrations=@($owned)
            $captured = Set-FileQuayOwnedRegistration $ownership @($fixture.registrations) $owned.Name $owned.Publisher $owned.Version 'X64'
            if ($captured.PackageFullName -cne $owned.PackageFullName) { throw "${scenario}: exact registration was not returned" }
            if ($scenario -eq 'owned-with-foreign') { $fixture.registrations += $foreign }
            if ($scenario -eq 'remove-failed') { $fixture.removeFailure=$true }
        }
    }
    $getPackages = { @($fixture.registrations) }.GetNewClosure()
    $removePackage = {
        param([string]$PackageFullName)
        $fixture.removed.Add($PackageFullName)
        if ($fixture.removeFailure) { throw 'fixture owned removal failed' }
        $fixture.registrations=@($fixture.registrations | Where-Object PackageFullName -CNE $PackageFullName)
    }.GetNewClosure()
    $cleanupFailure = $null
    try { Remove-FileQuayOwnedRegistration $ownership $owned.Name $getPackages $removePackage }
    catch { $cleanupFailure=$_.Exception.Message }
    if ($scenario -eq 'owned') {
        if ($cleanupFailure -or $fixture.removed.Count -ne 1 -or $fixture.removed[0] -cne $owned.PackageFullName -or $fixture.registrations.Count) {
            throw 'owned: exact captured package was not removed once'
        }
    } elseif ($scenario -in @('owned-with-foreign','remove-failed')) {
        if (-not $cleanupFailure -or $fixture.removed.Count -ne 1 -or $fixture.removed[0] -cne $owned.PackageFullName -or -not $fixture.registrations.Count) {
            throw "${scenario}: exact owned removal/residue evidence is incorrect"
        }
    } else {
        if (-not $cleanupFailure -or $fixture.removed.Count -or ($scenario -ne 'missing-capture' -and -not $fixture.registrations.Count)) {
            throw "${scenario}: unresolved registration was removed or not reported"
        }
    }
}

'Installation helper checks passed: cleanup/error aggregation, framework matching, and seven exact registration ownership scenarios.'
