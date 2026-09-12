# Copyright 2026 Trieflow LLC. MIT.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root '.github/scripts/PackageIdentity.Helpers.ps1')
. (Join-Path $root '.github/scripts/InstallationQualification.Helpers.ps1')
$work=Join-Path ([IO.Path]::GetTempPath()) ('foldersail-identity-' + [Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work
$checks=0
try {
    foreach ($mode in @('Qualification','Store')) {
        $identity=Get-FolderSailPackageIdentity $mode 'Consumer'
        $path=Join-Path $work "$mode.xml"
        Copy-Item (Join-Path $root 'src/Files.App/Package.appxmanifest') $path
        & (Join-Path $root '.github/scripts/Configure-AppxManifest.ps1') -Identity $identity.name -Publisher $identity.publisher -PublisherDisplayName $identity.publisher_display_name -Protocol filequay -PackageManifestPath $path
        [xml]$manifest=Get-Content $path -Raw
        $manifest.Package.Identity.SetAttribute('ProcessorArchitecture','x64')
        $manifest.Package.Applications.Application.SetAttribute('Executable','FolderSail.exe')
        Assert-FolderSailPackageIdentity $manifest $mode 'Consumer'
        $checks++
        foreach ($field in @('Name','Publisher','Version','ProcessorArchitecture','application','executable','display','publisher-display')) {
            [xml]$bad=$manifest.OuterXml
            switch ($field) {
                'application' {$bad.Package.Applications.Application.SetAttribute('Id','FileQuay')}
                'executable' {$bad.Package.Applications.Application.SetAttribute('Executable','Files.exe')}
                'display' {$bad.Package.Properties.DisplayName='FileQuay'}
                'publisher-display' {$bad.Package.Properties.PublisherDisplayName='foreign'}
                default {$bad.Package.Identity.SetAttribute($field,'foreign')}
            }
            $failed=$false
            try {Assert-FolderSailPackageIdentity $bad $mode 'Consumer'} catch {$failed=$true}
            if (-not $failed) {throw "Accepted $mode $field drift"}; $checks++
        }
        $other=if($mode -eq 'Store'){'Qualification'}else{'Store'}
        $failed=$false
        try {Assert-FolderSailPackageIdentity $manifest $other 'Consumer'} catch {$failed=$true}
        if (-not $failed) {throw 'Accepted cross-mode package'}; $checks++
    }
    $failed=$false
    try {Get-FolderSailPackageIdentity 'Store' 'Instrumented'} catch {$failed=$true}
    if (-not $failed) {throw 'Store instrumentation was accepted'}; $checks++
    $normal=Get-FileQuayBuildKindConfiguration $work Consumer
    $store=Get-FileQuayBuildKindConfiguration $work Consumer Store
    if($normal.evidence_output -eq $store.evidence_output -or $store.qualification_property -ne 'false' -or -not $store.evidence_output.EndsWith('Store-Consumer')) {throw 'Store output reuse/probe mismatch'}
    $checks++
    "PASS: $checks exact identity, compatibility, drift and output isolation checks."
} finally {Remove-Item $work -Recurse -Force}
