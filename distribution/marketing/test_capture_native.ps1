# Copyright 2026 Trieflow LLC. MIT. Compile native observer without invoking Windows off-platform.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Add-Type -Path (Join-Path $PSScriptRoot 'CaptureNative.cs')
$type=[FolderSailMarketing.Native]
foreach($name in @('Activate','PackageName','Frame')){if(-not $type.GetMethod($name)){throw "Missing native capture boundary: $name"}}
$imports=@($type.GetMethods([Reflection.BindingFlags]'Static,NonPublic')|Where-Object {$_.IsDefined([Runtime.InteropServices.DllImportAttribute],$false)}|ForEach-Object Name|Sort-Object)
$expected=@('DwmGetWindowAttribute','GetAncestor','GetClassName','GetDpiForWindow','GetForegroundWindow','GetPackageFullName',
    'GetWindowText','GetWindowThreadProcessId','IsWindowEnabled','IsWindowVisible','IsZoomed','WindowFromPoint')|Sort-Object
if(Compare-Object $imports $expected -CaseSensitive){throw 'Unexpected native observer imports'}
Write-Output 'PASS actual C# compiler and read-only Win32 frame import boundary; no Windows calls simulated.'
