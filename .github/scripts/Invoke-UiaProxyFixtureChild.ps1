# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][string]$AssemblyHash,
    [Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][string]$Nonce)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Write-FileQuayFixtureStartup([ValidateSet('child-entered','assembly-verified','assembly-loaded','native-entry')][string]$Phase) {
    try {
        $value=@{schema_version=1;nonce=$Nonce;process_id=$PID;phase=$Phase;at_utc=[DateTime]::UtcNow.ToString('o')}
        $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $value -Compress))
        $path=Join-Path $Directory ('startup-'+$Phase+'.json')
        $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$stream.Write($bytes,0,$bytes.Length)} finally {$stream.Dispose()}
    } catch {[Console]::Error.WriteLine('Startup observation '+$Phase+': '+$_.Exception.GetType().Name)}
}
if (-not $IsWindows -or $env:CI -ne 'true' -or $PSVersionTable.PSVersion.Major -ne 7 -or
    [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {throw 'Native fixture requires the isolated Windows PowerShell 7 STA host.'}
Write-FileQuayFixtureStartup child-entered
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
Write-FileQuayFixtureStartup assembly-verified
$assembly=[Reflection.Assembly]::Load($bytes)
Write-FileQuayFixtureStartup assembly-loaded
$null=$assembly.GetType('FileQuayQualification.Win32Controls',$true)
Write-FileQuayFixtureStartup native-entry
exit ([FileQuayQualification.Win32Controls]::Run($Directory,$Nonce))
