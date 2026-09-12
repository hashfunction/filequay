# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][string]$AssemblyHash,
    [Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][string]$Nonce)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:CI -ne 'true' -or $PSVersionTable.PSVersion.Major -ne 7 -or
    [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {throw 'Native fixture requires the isolated Windows PowerShell 7 STA host.'}
. (Join-Path $PSScriptRoot 'ConsumerWorkflow.Helpers.ps1')
$inputFile=Get-FileQuayWorkflowFile $AssemblyPath
if ($AssemblyHash -cnotmatch '^[A-F0-9]{64}$' -or $inputFile.sha256 -cne $AssemblyHash) {throw 'Native fixture assembly hash differs.'}
$bytes=[IO.File]::ReadAllBytes($AssemblyPath)
if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $AssemblyHash) {throw 'Native fixture changed during read.'}
$stream=[IO.MemoryStream]::new($bytes,$false);$reader=[Reflection.PortableExecutable.PEReader]::new($stream)
try {
    $metadata=[Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($reader);$cor=$reader.PEHeaders.CorHeader
    if (-not ($cor.Flags -band [Reflection.PortableExecutable.CorFlags]::ILOnly) -or $cor.ManagedNativeHeaderDirectory.Size -ne 0 -or
        $metadata.GetString($metadata.GetAssemblyDefinition().Name) -cne 'FileQuay.Qualification.Win32Controls') {throw 'Expected the exact IL-only Win32 fixture assembly.'}
    foreach ($handle in $metadata.AssemblyReferences) {
        if (-not $metadata.GetString($metadata.GetAssemblyReference($handle).Name).StartsWith('System.',[StringComparison]::Ordinal)) {throw 'Unexpected native fixture non-BCL dependency.'}
    }
} finally {$reader.Dispose();$stream.Dispose()}
$assembly=[Reflection.Assembly]::Load($bytes)
$null=$assembly.GetType('FileQuayQualification.Win32Controls',$true)
exit ([FileQuayQualification.Win32Controls]::Run($Directory,$Nonce))
