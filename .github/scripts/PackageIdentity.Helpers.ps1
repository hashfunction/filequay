# Copyright 2026 Trieflow LLC. MIT.
function Get-FolderSailPackageIdentity(
    [ValidateSet('Qualification','Store')][string]$IdentityMode='Qualification',
    [ValidateSet('Consumer','Instrumented')][string]$BuildKind='Consumer'
) {
    if ($IdentityMode -eq 'Store' -and $BuildKind -ne 'Consumer') {throw 'Only the normal Consumer binary may use the assigned Store identity.'}
    $store=$IdentityMode -eq 'Store'
    [pscustomobject][ordered]@{
        mode=$IdentityMode
        name=$(if($store){'1659hashfunction.FileQuay'}else{'Trieflow.FileQuay.Qualification'})
        publisher=$(if($store){'CN=B6A2631A-FD32-45CC-AE12-82466975F528'}else{'CN=FileQuay-CI-Qualification'})
        publisher_display_name=$(if($store){'hashfunction'}else{'Trieflow LLC'})
        family=$(if($store){'1659hashfunction.FileQuay_r3hxytd7jt6c4'}else{'Trieflow.FileQuay.Qualification_2b9rgm65gdcnr'})
        version='1.0.1.0'; architecture='x64'; application_id='App'; executable='FolderSail.exe'; display_name='FolderSail'
    }
}

function Assert-FolderSailPackageIdentity([xml]$Manifest,
    [ValidateSet('Qualification','Store')][string]$IdentityMode='Qualification',
    [ValidateSet('Consumer','Instrumented')][string]$BuildKind='Consumer'
) {
    $expected=Get-FolderSailPackageIdentity $IdentityMode $BuildKind
    $identity=$Manifest.Package.Identity
    $applications=@($Manifest.Package.Applications.Application)
    if ($identity.Name -cne $expected.name -or $identity.Publisher -cne $expected.publisher -or
        $identity.Version -cne $expected.version -or $identity.ProcessorArchitecture -cne $expected.architecture -or
        $applications.Count -ne 1 -or $applications[0].Id -cne $expected.application_id -or
        $applications[0].Executable -cne $expected.executable -or
        $Manifest.Package.Properties.DisplayName -cne $expected.display_name -or
        $Manifest.Package.Properties.PublisherDisplayName -cne $expected.publisher_display_name) {
        throw 'Package differs from the exact FolderSail identity, version, application or branding mode.'
    }
}
