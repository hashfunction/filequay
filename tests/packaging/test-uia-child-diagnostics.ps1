# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Actual parent function + real subprocess/pipes; native UI readiness is not
# simulated as success. Only fixture build/proxy setup and non-Windows STA flag
# are substituted. Every child deliberately fails before publishing readiness.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$source=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $source '.github/scripts/ConsumerWorkflow.Helpers.ps1')
$production=Get-Content (Join-Path $source '.github/scripts/UiaProxy.Fixture.ps1') -Raw
. ([scriptblock]::Create($production.Replace('[Diagnostics.Process]::Start($start)','(Start-FixtureTestProcess $start)')))
function Require([bool]$ok,[string]$message){if(-not $ok){throw $message}}
function Assert-FileQuayConsumerAdapter($Adapter){}
function Get-FileQuayUiaProxyEvidence($Record){}
function Register-FileQuayUiaProxy($Record){$Record.registered=$true}
function Start-FixtureTestProcess($Start){
    Require ($Start.RedirectStandardOutput -and $Start.RedirectStandardError) 'Actual producer does not retain child pipes'
    Require (-not $Start.UseShellExecute) 'Unexpected shell launch'
    if(-not $IsWindows){$null=$Start.ArgumentList.Remove('-STA')}
    [Diagnostics.Process]::Start($Start)
}
function Build-FileQuayUiaFixture($Root,$Work,$DotNet){
    $path=Join-Path $Root 'placeholder.dll'
    @{path=$path;file=(Get-FileQuayWorkflowFile $path);source_inputs=@(foreach($n in @('.github/scripts/Invoke-UiaProxyFixtureChild.ps1','.github/scripts/ConsumerWorkflow.Helpers.ps1','.github/scripts/UiaProxy.Diagnostics.cs')){@{path=$n;file=(Get-FileQuayWorkflowFile (Join-Path $Root $n))}})}
}
$temp=Join-Path (Join-Path $source 'artifacts') ('foldersail-child-evidence-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $temp '.github/scripts') -Force
try {
    Copy-Item (Join-Path $source '.github/scripts/UiaProxy.Diagnostics.cs') (Join-Path $temp '.github/scripts/UiaProxy.Diagnostics.cs')
    Set-Content (Join-Path $temp '.github/scripts/ConsumerWorkflow.Helpers.ps1') '# fixture source only'
    Set-Content (Join-Path $temp 'placeholder.dll') 'fixture bytes only'
    foreach($mode in @('bounded-error','foreign-record','oversized-record')){
        $child=@'
param($AssemblyPath,$AssemblyHash,$Directory,$Nonce)
Start-Sleep -Milliseconds 400
[Console]::Out.Write(('O'*20000))
[Console]::Error.Write(('E'*24000))
$r=@{schema_version=1;nonce=$Nonce;error='original-child-failure'}
MODE
[IO.File]::WriteAllText((Join-Path $Directory 'result.json'),($r|ConvertTo-Json -Compress))
exit 7
'@
        $mutation=switch($mode){'bounded-error' {''};'foreign-record' {"`$r.nonce='foreign'"};'oversized-record' {"`$r.error='X'*5000"}}
        [IO.File]::WriteAllText((Join-Path $temp '.github/scripts/Invoke-UiaProxyFixtureChild.ps1'),$child.Replace('MODE',$mutation))
        $record=@{};$failure=''
        try{Invoke-FileQuayUiaProxyPreflight $temp $temp @{} $record}catch{$failure=$_.Exception.Message}
        Require ($failure -ceq 'Native UIA fixture did not expose its owned window before the deadline.') "Original readiness failure changed: $failure"
        Require (-not $record.passed -and -not $record.consumer_acceptance) 'Diagnostic accepted a failed child'
        Require ($record.fixture.ready_refusal.has_exited -and $record.fixture.ready_refusal.exit_code -eq 7 -and -not $record.fixture.ready_refusal.ready_exists) 'Pre-cleanup exit cause missing'
        Require ($record.fixture.process_cleanup_verified -and -not $record.fixture.forced_cleanup -and $record.fixture.cleanup_exit_code -eq 7) 'Owned child cleanup differs'
        Require ($record.fixture.output_completed) 'Child output did not finish'
        foreach($channel in @('stdout','stderr')){
            $o=$record.fixture[$channel];$c=if($channel -ceq 'stdout'){'O'}else{'E'};$count=if($channel -ceq 'stdout'){20000}else{24000}
            Require ($o.completed -and $o.truncated -and $null -eq $o.read_error -and $o.observed_bytes -eq $count -and $o.retained_bytes -eq 8192 -and $o.text -ceq ($c*8192)) 'Output not bounded/drained exactly'
            $sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($c*8192)))
            Require ($o.sha256 -ceq $sha -and [Convert]::FromBase64String($o.raw_base64).Length -eq 8192) 'Retained original output bytes/hash differ'
        }
        if($mode -ceq 'bounded-error'){
            Require ($record.fixture.diagnostic_errors.Count -eq 0 -and $record.fixture.retained_records['result.json'].record.error -ceq 'original-child-failure') 'Original result not retained'
            Assert-FileQuayWorkflowFile (Join-Path $record.fixture.directory 'result.json') $record.fixture.retained_records['result.json'].file
        }else{Require ($record.fixture.diagnostic_errors.Count -eq 1 -and $record.fixture.retained_records.Count -eq 0) 'Invalid diagnostic file was accepted or original failure masked'}
    }
    'PASS actual failed-child parent: bounded concurrent streams, original file hashes, nonce/size refusals, pre-cleanup exit and unchanged rejection/cleanup.'
} finally {Remove-Item -LiteralPath $temp -Recurse -Force}
