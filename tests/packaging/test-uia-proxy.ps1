# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
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
