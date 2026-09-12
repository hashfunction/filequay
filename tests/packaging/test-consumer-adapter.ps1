# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
param([string]$DotNet='dotnet')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Adapter.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$work=Join-Path ([IO.Path]::GetTempPath()) ('filequay-adapter-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
$checks=0
function Reject([scriptblock]$Action,[string]$Message) {
    $failure=''
    try { & $Action } catch { $failure=$_.Exception.Message }
    if (-not $failure.Contains($Message)) { throw "Expected '$Message'; got '$failure'." }
}
try {
    $evidence=Initialize-FileQuayConsumerAdapter $root $work $DotNet
    if (-not $evidence.loaded -or -not $evidence.il_only -or $evidence.source_inputs.Count -lt 6) { throw 'Missing source/IL/load evidence.' };$checks++
    if ($evidence.cswin32_version -cne '0.3.298') { throw 'Wrong source generator.' };$checks++
    $adapter=[FileQuayQualification.ConsumerInput].Assembly
    if ($adapter.GetName().Name -cne 'FileQuay.Qualification.Native') { throw 'Loaded a customer assembly.' };$checks++
    if (@($adapter.GetReferencedAssemblies() | Where-Object Name -Like 'Files.*').Count) { throw 'Customer runtime reference.' };$checks++
    foreach ($name in @('Observe','RootWindow','WindowProcess','OwnerChain','Foreground','Chord','ObserveClipboard')) {
        if (-not [FileQuayQualification.ConsumerInput].GetMethod($name)) { throw "Missing adapter $name." };$checks++
    }
    foreach ($name in @('GetAncestor','GetWindowThreadProcessId','GetWindow','IsWindow','IsWindowVisible','IsWindowEnabled','GetForegroundWindow','SetForegroundWindow','SendInput','GetClipboardOwner','GetClipboardSequenceNumber','IsClipboardFormatAvailable')) {
        if (-not @($adapter.GetType('Windows.Win32.PInvoke').GetMethods() | Where-Object Name -CEQ $name).Count) { throw "Missing generated native API $name." };$checks++
    }
    foreach ($name in @('GetClipboardData','OpenClipboard','EmptyClipboard','SetClipboardData','OleGetClipboard')) {
        if (@($adapter.GetType('Windows.Win32.PInvoke').GetMethods() | Where-Object Name -CEQ $name).Count) { throw "Payload/mutation API entered the diagnostic adapter: $name." };$checks++
    }
    # Observe Windows ABI from the actual generated INPUT, without sending input.
    $inputType=$adapter.GetType('Windows.Win32.UI.Input.KeyboardAndMouse.INPUT')
    $expectedSize=if ([IntPtr]::Size -eq 8) {40} else {28}
    if ([Runtime.InteropServices.Marshal].GetMethod('SizeOf',[type[]]@([Type])).Invoke($null,@($inputType)) -ne $expectedSize) { throw 'Generated INPUT ABI mismatch.' };$checks++
    $bytes=[IO.File]::ReadAllBytes($evidence.assembly_path)
    $stream=[IO.MemoryStream]::new($bytes,$false)
    $reader=[Reflection.PortableExecutable.PEReader]::new($stream)
    try {$nativeOffset=$reader.PEHeaders.CorHeaderStartOffset+64;$flagsOffset=$reader.PEHeaders.CorHeaderStartOffset+16} finally {$reader.Dispose();$stream.Dispose()}
    $mutant=[byte[]]$bytes.Clone()
    [BitConverter]::GetBytes([int]1).CopyTo($mutant,$nativeOffset)
    [BitConverter]::GetBytes([int]1).CopyTo($mutant,$nativeOffset+4)
    Reject {Import-FileQuayConsumerAdapter $mutant} 'IL-only';$checks++
    $mutant=[byte[]]$bytes.Clone();[BitConverter]::GetBytes([int]0).CopyTo($mutant,$flagsOffset)
    Reject {Import-FileQuayConsumerAdapter $mutant} 'IL-only';$checks++
    # Alter a real AssemblyRef string without invoking the loader on it.
    $mutant=[byte[]]$bytes.Clone()
    $needle=[Text.Encoding]::UTF8.GetBytes('System.Collections')
    $replacement=[Text.Encoding]::UTF8.GetBytes('Foreign.Assemblies')
    $replaced=$false
    for ($i=0;$i -le $mutant.Length-$needle.Length;$i++) {
        $same=$true
        for ($j=0;$j -lt $needle.Length;$j++) {if ($mutant[$i+$j] -ne $needle[$j]) {$same=$false;break}}
        if ($same) {$replacement.CopyTo($mutant,$i);$replaced=$true}
    }
    if (-not $replaced) {throw 'Assembly-reference mutation fixture did not match the actual generated assembly.'}
    Reject {Import-FileQuayConsumerAdapter $mutant} 'non-BCL reference';$checks++
    Reject {Import-FileQuayConsumerAdapter ([byte[]]@(1,2,3,4))} 'managed PE';$checks++
    $foreign=Join-Path $work 'foreign.dll'
    Add-Type 'public class ForeignAdapterFixture {}' -OutputAssembly $foreign
    Reject {Import-FileQuayConsumerAdapter ([IO.File]::ReadAllBytes($foreign))} 'assembly identity';$checks++
    Reject {Import-FileQuayConsumerAdapter $bytes} 'already loaded';$checks++
    Assert-FileQuayConsumerAdapter $evidence;$checks++
    $wrong=@{}+$evidence;$wrong.assembly_sha256='0'*64
    Reject {Assert-FileQuayConsumerAdapter $wrong} 'loaded adapter evidence';$checks++
    "Consumer native adapter checks passed: $checks (actual source generation, IL load, native ABI, PE rejection, identity and retained assembly)."
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
