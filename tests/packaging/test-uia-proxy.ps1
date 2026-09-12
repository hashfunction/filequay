# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot '../../.github/scripts/UiaProxy.Helpers.ps1')
function Require([bool]$Condition,[string]$Message) {if (-not $Condition) {throw $Message}}
function Reject([scriptblock]$Action,[string]$Label) {$failed=$false;try {& $Action} catch {$failed=$true};Require $failed "Accepted $Label"}
$hostRoot=Join-Path ([IO.Path]::GetTempPath()) 'fixture-powershell-host'
function Identity([string]$Name) {
    @{path=(Join-Path $hostRoot ($Name+'.dll'));name=$Name;version='10.0.0.0';public_key_token=$(if ($Name -ceq 'UIAutomationClient') {'31bf3856ad364e35'} else {'b77a5c561934e089'});
        culture='';sha256=('a'*64);bytes=400000;signature_status='Valid';signer_subject='CN=Microsoft Corporation, O=Microsoft Corporation, C=US';company='Microsoft Corporation'}
}
$client=Identity 'UIAutomationClient';$proxy=Identity 'UIAutomationClientSideProviders'
Assert-FileQuayUiaProxyIdentity $client $proxy $hostRoot
$checks=1
foreach ($mode in @('foreign-path','wrong-name','wrong-version','wrong-token','client-token-on-proxy','proxy-token-on-client','wrong-culture','unsigned','foreign-signer','wrong-company','missing-hash','empty-file','foreign-client')) {
    $c=@{}+$client;$p=@{}+$proxy
    switch ($mode) {
        'foreign-path' {$p.path=Join-Path ([IO.Path]::GetTempPath()) 'other/UIAutomationClientSideProviders.dll'}
        'wrong-name' {$p.name='Other'}
        'wrong-version' {$p.version='9.0.0.0'}
        'wrong-token' {$p.public_key_token='0'*16}
        'client-token-on-proxy' {$p.public_key_token=$client.public_key_token}
        'proxy-token-on-client' {$c.public_key_token=$proxy.public_key_token}
        'wrong-culture' {$p.culture='fr'}
        'unsigned' {$p.signature_status='NotSigned'}
        'foreign-signer' {$p.signer_subject='CN=Other, O=Other'}
        'wrong-company' {$p.company='Other'}
        'missing-hash' {$p.sha256=''}
        'empty-file' {$p.bytes=0}
        'foreign-client' {$c.path=Join-Path ([IO.Path]::GetTempPath()) 'other/UIAutomationClient.dll'}
    }
    Reject {Assert-FileQuayUiaProxyIdentity $c $p $hostRoot} $mode;$checks++
}
$nonce='b'*32;$expected='owned-'+$nonce
$record=@{schema_version=1;nonce=$nonce;value=$expected;invoke_count=1;window_destroyed=$true;timed_out=$false;error=''}
Assert-FileQuayUiaFixtureResult $record $nonce 0
$checks++
foreach ($mode in @('wrong-nonce','wrong-value','no-invoke','duplicate-invoke','window-residual','timeout','provider-error','bad-exit','string-count')) {
    $r=@{}+$record;$exit=0
    switch ($mode) {
        'wrong-nonce' {$r.nonce='c'*32}
        'wrong-value' {$r.value='initial'}
        'no-invoke' {$r.invoke_count=0}
        'duplicate-invoke' {$r.invoke_count=2}
        'window-residual' {$r.window_destroyed=$false}
        'timeout' {$r.timed_out=$true}
        'provider-error' {$r.error='failed'}
        'bad-exit' {$exit=1}
        'string-count' {$r.invoke_count='1'}
    }
    Reject {Assert-FileQuayUiaFixtureResult $r $nonce $exit} $mode;$checks++
}
"PASS exact provider provenance and independent native control result: $checks cases"

# Preserve the real C# exception/inner stack at the actual registration boundary.
# This deliberately failing public API is a test double, not a Windows provider.
# Reuse an already loaded read-only host assembly solely for the load boundary;
# the identity-policy test above remains responsible for rejecting foreign DLLs.
$assemblyPath=[System.Management.Automation.PSObject].Assembly.Location
$work=Join-Path ([IO.Path]::GetTempPath()) ('foldersail-typed-uia-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory $work -ErrorAction Stop
$clientPath=Join-Path $work 'ClientApiDouble.dll'
try {
Add-Type -OutputAssembly $clientPath -TypeDefinition @'
using System;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Diagnostics;
namespace System.Windows.Automation {
 public sealed class FixtureDiagnosticException : Exception {
  public FixtureDiagnosticException() : base("original-registration-failure") {}
  public override string ToString() { throw new InvalidOperationException("diagnostic-format-failure"); }
 }
 public static class ClientSettings {
  public static int Calls; public static bool BreakDiagnostic,WalkStack; public static string CallingType; public static bool MissingReflectedType;
  [MethodImpl(MethodImplOptions.NoInlining)]
  public static void RegisterClientSideProviderAssembly(AssemblyName name) {
   Calls++;
   if(name.Name!="UIAutomationClientsideProviders")throw new ArgumentException("Unexpected provider name");
   if(WalkStack){CheckOriginalCallerWalk();return;}
   if(BreakDiagnostic)throw new FixtureDiagnosticException();
   FailInTypedFrame();
  }
  [MethodImpl(MethodImplOptions.NoInlining)]
  static void FailInTypedFrame() { throw new NullReferenceException("fixture-null-reference"); }
  // Exact relevant WPF v10.0.11 algorithm, including its unguarded dereference.
  // This is a public-API test double; no private framework state is touched.
  [MethodImpl(MethodImplOptions.NoInlining)]
  static void CheckOriginalCallerWalk() {
   Assembly current=Assembly.GetExecutingAssembly();StackTrace stack=new StackTrace();
   for(int i=0;i<stack.FrameCount;i++) {
    MethodBase method=stack.GetFrame(i).GetMethod();Type type=method.ReflectedType;
    MissingReflectedType=type==null;Assembly assembly=type.Assembly;
    if(assembly.GetName().Name!=current.GetName().Name){CallingType=type.FullName;return;}
   }
   throw new InvalidOperationException("No external caller");
  }
 }
}
'@
 $stream=[IO.MemoryStream]::new([IO.File]::ReadAllBytes($clientPath),$false)
 try{$null=[Runtime.Loader.AssemblyLoadContext]::Default.LoadFromStream($stream)}finally{$stream.Dispose()}
 function Get-FileQuayUiaProxyEvidence($Record) {
  $Record.client=@{path=$clientPath};$Record.proxy=@{path=$assemblyPath};$Record.registered=$false
 }
 $r=@{registered=$false}
 $caught=$null;try{Register-FileQuayUiaProxy $r}catch{$caught=$_}
 Require ($null -ne $caught -and [System.Windows.Automation.ClientSettings]::Calls -eq 1 -and -not $r.registered) 'Registration failure was swallowed, retried or marked registered.'
 $saved=$r|ConvertTo-Json -Depth 15|ConvertFrom-Json -AsHashtable
 $trace=$saved.registration_exception
 Require ($trace.exception_text.text -like '*fixture-null-reference*' -and $trace.exception_text.text -like '*FailInTypedFrame*' -and
  $trace.script_stack_trace.text -like '*Register-FileQuayUiaProxy*') 'Real exception ToString/inner/script stack did not survive JSON.'
 Require (@($trace.chain|Where-Object {$_.type -ceq 'System.NullReferenceException' -and $_.stack_trace.text -like '*FailInTypedFrame*'}).Count -eq 1 -and
  $saved.registration_call.api -ceq 'System.Windows.Automation.ClientSettings.RegisterClientSideProviderAssembly' -and
  $saved.registration_call.route -ceq 'source-owned typed public API (NoInlining)') 'Exact native exception chain/unchanged call route missing.'
 # Bounded metadata retains explicit truncation, including an over-depth chain.
 $deep=[Exception]::new(('x'*70000))
 foreach($i in 1..10){$deep=[Exception]::new("wrapper-$i",$deep)}
 $failure=[Management.Automation.ErrorRecord]::new($deep,'long-exception',[Management.Automation.ErrorCategory]::NotSpecified,$null)
 $bounded=Get-FileQuayUiaExceptionEvidence $failure
 Require ($bounded.exception_text.text.Length -eq 32768 -and $bounded.exception_text.truncated -and
  $bounded.chain.Count -eq 8 -and $bounded.chain_truncated) 'Exception metadata exceeded text/chain bounds or hid truncation.'
 [System.Windows.Automation.ClientSettings]::BreakDiagnostic=$true
 $r=@{registered=$false};$caught=$null;try{Register-FileQuayUiaProxy $r}catch{$caught=$_}
 Require ($caught.Exception.Message -like '*original-registration-failure*' -and -not $r.registered -and
  $r.registration_exception_error -like '*diagnostic-format-failure*' -and [System.Windows.Automation.ClientSettings]::Calls -eq 2) 'Diagnostic formatting failure masked primary registration refusal or caused replay.'
 'PASS actual registration-boundary C# exception/JSON retention, bounded chain/text and original-error preservation (no native UI claim).'

 [System.Windows.Automation.ClientSettings]::BreakDiagnostic=$false
 [System.Windows.Automation.ClientSettings]::WalkStack=$true
 $directFailure=$null
 try{[System.Windows.Automation.ClientSettings]::RegisterClientSideProviderAssembly([Reflection.AssemblyName]::new('UIAutomationClientsideProviders'))}catch{$directFailure=$_}
 Require ($null -ne $directFailure -and [System.Windows.Automation.ClientSettings]::MissingReflectedType) 'Direct PowerShell call did not reproduce the actual WPF caller-frame defect.'
 $r=@{client=@{path=$clientPath}}
 Initialize-FileQuayUiaRegistration $r
 [FileQuayQualification.UiaProxyRegistration]::Register([Reflection.AssemblyName]::new('UIAutomationClientsideProviders'))
 Require (-not [System.Windows.Automation.ClientSettings]::MissingReflectedType -and
  [System.Windows.Automation.ClientSettings]::CallingType -ceq 'FileQuayQualification.UiaProxyRegistration' -and
  $r.registration_shim.no_inlining -and $r.registration_shim.source_file.bytes -gt 0) 'Compiled production shim did not stop the exact stack walk before the dynamic frame.'
 $method=[FileQuayQualification.UiaProxyRegistration].GetMethod('Register')
 Require (($method.GetMethodImplementationFlags() -band [Reflection.MethodImplAttributes]::NoInlining) -ne 0) 'Production typed caller can be inlined away.'
 $firstHash=$r.registration_shim.source_file.sha256
 Initialize-FileQuayUiaRegistration $r
 Require ($r.registration_shim.source_file.sha256 -ceq $firstHash) 'Owned compiled caller lost its exact source binding.'
 $originalBinding=$script:FileQuayUiaRegistrationIdentity
 foreach($drift in @('source','type','client')) {
  $script:FileQuayUiaRegistrationIdentity=@{}+$originalBinding
  switch($drift) {
   'source'{$script:FileQuayUiaRegistrationIdentity.source=@{}+$originalBinding.source;$script:FileQuayUiaRegistrationIdentity.source.sha256='0'*64}
   'type'{$script:FileQuayUiaRegistrationIdentity.type=[object]}
   'client'{$script:FileQuayUiaRegistrationIdentity.client_reference='Foreign, Version=1.0.0.0'}
  }
  $callsBefore=[System.Windows.Automation.ClientSettings]::Calls;$r=@{registered=$false}
  Reject {Register-FileQuayUiaProxy $r} "typed caller $drift binding drift"
  Require (-not $r.registered -and -not $r.registration_call.entered -and [System.Windows.Automation.ClientSettings]::Calls -eq $callsBefore) 'Unbound typed caller reached the public API or changed registration acceptance.'
 }
 $script:FileQuayUiaRegistrationIdentity=$originalBinding
 'PASS real PowerShell dynamic-frame failure and compiled production non-inlined typed-caller recovery through the public-API double; three caller-binding refusals before registration.'
} finally {Remove-Item -LiteralPath $work -Recurse -Force}
