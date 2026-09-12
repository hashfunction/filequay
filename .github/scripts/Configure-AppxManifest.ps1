# Copyright (c) Files Community. SPDX-License-Identifier: MPL-2.0
# FileQuay modifications copyright 2026 Trieflow LLC.
param(
    [string]$Identity = '',
    [string]$Publisher = '',
    [string]$Version = '1.0.1.0',
    [string]$DisplayName = 'FolderSail',
    [string]$PublisherDisplayName = 'Trieflow LLC',
    [string]$ExecutableAlias = '',
    [string]$Protocol = '',
    [string]$AssetDirectory = 'Assets\FileQuay',
    [string]$PackageManifestPath = (Join-Path $PSScriptRoot '..\..\src\Files.App\Package.appxmanifest')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($Identity) -or [string]::IsNullOrWhiteSpace($Publisher)) {
    throw 'FolderSail requires an explicit owned package identity and publisher.'
}
if ($Identity -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$' -or $Identity -match '^(FilesDev$|FilesPreview$|Files$|49306atecsolution\.)' -or $Identity -match 'Required') {
    throw 'Invalid or upstream package identity.'
}
if ($Publisher -notmatch '^CN=.+' -or $Publisher -eq 'CN=Files' -or $Publisher -match 'REQUIRED') { throw 'Invalid or upstream publisher.' }
$parts = $Version.Split('.')
if ($parts.Count -ne 4 -or @($parts | Where-Object { $_ -notmatch '^\d+$' -or [long]$_ -gt 65535 }).Count) { throw 'Version must have four UInt16 components.' }
if ([System.IO.Path]::IsPathRooted($AssetDirectory) -or $AssetDirectory -match '\.\.') { throw 'Assets must be inside the application directory.' }
if ($Protocol -and $Protocol -notmatch '^[a-z][a-z0-9+.-]+$') { throw 'Invalid protocol.' }
if ($ExecutableAlias -and $ExecutableAlias -notmatch '^[A-Za-z0-9.-]+\.exe$') { throw 'Invalid executable alias.' }
[xml]$doc = Get-Content -LiteralPath $PackageManifestPath -Raw
$ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
$ns.AddNamespace('p', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$ns.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')
$ns.AddNamespace('uap5', 'http://schemas.microsoft.com/appx/manifest/uap/windows10/5')
$doc.Package.Identity.SetAttribute('Name', $Identity)
$doc.Package.Identity.SetAttribute('Publisher', $Publisher)
$doc.Package.Identity.SetAttribute('Version', $Version)
$doc.Package.Properties.DisplayName = $DisplayName
$doc.Package.Properties.PublisherDisplayName = $PublisherDisplayName
$doc.Package.Properties.Logo = "$AssetDirectory\StoreLogo.png"
$visual = $doc.SelectSingleNode('//uap:VisualElements', $ns)
$visual.SetAttribute('DisplayName', $DisplayName)
foreach ($attribute in @('Square150x150Logo', 'Square44x44Logo')) { $visual.SetAttribute($attribute, "$AssetDirectory\$attribute.png") }
$tile = $visual.SelectSingleNode('uap:DefaultTile', $ns)
$tile.SetAttribute('ShortName', $DisplayName)
foreach ($name in @('Wide310x150Logo','Square71x71Logo','Square310x310Logo')) { $tile.SetAttribute($name, "$AssetDirectory\$name.png") }
$visual.SelectSingleNode('uap:SplashScreen', $ns).SetAttribute('Image', "$AssetDirectory\SplashScreen.png")
$extensions = $doc.SelectSingleNode('//p:Application/p:Extensions', $ns)
foreach ($old in @($extensions.ChildNodes)) { $null = $extensions.RemoveChild($old) }
if ($Protocol) {
    $extension = $doc.CreateElement('uap', 'Extension', $ns.LookupNamespace('uap'))
    $extension.SetAttribute('Category', 'windows.protocol')
    $entry = $doc.CreateElement('uap', 'Protocol', $ns.LookupNamespace('uap'))
    $entry.SetAttribute('Name', $Protocol)
    $null = $extension.AppendChild($entry); $null = $extensions.AppendChild($extension)
}
if ($ExecutableAlias) {
    $extension = $doc.CreateElement('uap5', 'Extension', $ns.LookupNamespace('uap5'))
    $extension.SetAttribute('Category', 'windows.appExecutionAlias')
    $entry = $doc.CreateElement('uap5', 'AppExecutionAlias', $ns.LookupNamespace('uap5'))
    $alias = $doc.CreateElement('uap5', 'ExecutionAlias', $ns.LookupNamespace('uap5'))
    $alias.SetAttribute('Alias', $ExecutableAlias)
    $null = $entry.AppendChild($alias); $null = $extension.AppendChild($entry); $null = $extensions.AppendChild($extension)
}
$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true; $settings.NewLineChars = "`r`n"; $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
$writer = [System.Xml.XmlWriter]::Create($PackageManifestPath, $settings)
try { $doc.Save($writer) } finally { $writer.Dispose() }
Write-Output "Configured FolderSail manifest; optional protocol/alias are absent unless explicitly supplied."
