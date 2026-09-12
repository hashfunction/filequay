# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Actual parent function + real subprocess/pipes; native UI readiness is not
# simulated as success. Fixture build/proxy setup, plus non-Windows STA and
# image-query I/O, are substituted. Every child deliberately fails before publishing readiness.
param([switch]$OriginalModulePath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$source=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
& (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'test-uia-output-collector.ps1')
if($LASTEXITCODE -ne 0){throw 'Actual collector blocking-prefix regression failed.'}
$script:childMode=''
$script:latePathReads=0
$script:imageQueries=0
. (Join-Path $source '.github/scripts/ConsumerWorkflow.Helpers.ps1')
$production=Get-Content (Join-Path $source '.github/scripts/UiaProxy.Fixture.ps1') -Raw
if($OriginalModulePath){$production=$production.Replace('Get-FileQuayUiaFixtureImagePath $process','$process.Path')}
. ([scriptblock]::Create($production.Replace('[Diagnostics.Process]::Start($start)','(Start-FixtureTestProcess $start)')))
# Windows executes the real retained-handle Win32 query. This local substitute
# is only for the non-Windows pipe/process tests; it cannot qualify native UIA.
if(-not $IsWindows){
    function Get-FileQuayUiaFixtureImagePath([Diagnostics.Process]$Process){
        if($Process.HasExited -or $Process.SafeHandle.IsInvalid -or $Process.SafeHandle.IsClosed){throw 'Native UIA fixture process could not be retained.'}
        $Process.MainModule.FileName
    }
}
$script:readFixtureImage=${function:Get-FileQuayUiaFixtureImagePath}
function Get-FileQuayUiaFixtureImagePath([Diagnostics.Process]$Process){
    $script:imageQueries++
    $image=& $script:readFixtureImage $Process
    # One wrong observation tests the existing immediate comparison; the same
    # real retained child still has its correct identity during owned cleanup.
    if($script:childMode -ceq 'foreign-image' -and $script:imageQueries -eq 1){$image+'.foreign'}else{$image}
}
function Require([bool]$ok,[string]$message){if(-not $ok){throw $message}}
function Assert-FileQuayConsumerAdapter($Adapter){}
function Get-FileQuayUiaProxyEvidence($Record){}
function Register-FileQuayUiaProxy($Record){$Record.registered=$true}
function Start-FixtureTestProcess($Start){
    Require ($Start.RedirectStandardOutput -and $Start.RedirectStandardError) 'Actual producer does not retain child pipes'
    Require (-not $Start.UseShellExecute) 'Unexpected shell launch'
    if(-not $IsWindows){$null=$Start.ArgumentList.Remove('-STA')}
    $process=[Diagnostics.Process]::Start($Start)
    if($script:childMode -ceq 'retained-exit'){
        $null=$process.SafeHandle
        Require ($process.WaitForExit(5000)) 'Early-exit fixture did not finish'
    }
    if($script:childMode -ceq 'late-path'){
        $script:latePathReads=0
        Update-TypeData -Force -TypeName 'LateFixtureProcess' -MemberType ScriptProperty -MemberName Path -Value {
            $script:latePathReads++
            if($script:latePathReads -gt 1){$this.MainModule.FileName}
        }
        $process.PSTypeNames.Insert(0,'LateFixtureProcess')
    }
    $process
}
function Build-FileQuayUiaFixture($Root,$Work,$DotNet){
    $path=Join-Path $Root 'placeholder.dll'
    @{path=$path;file=(Get-FileQuayWorkflowFile $path);source_inputs=@(foreach($n in @('.github/scripts/Invoke-UiaProxyFixtureChild.ps1','.github/scripts/ConsumerWorkflow.Helpers.ps1','.github/scripts/UiaProxy.Diagnostics.cs')){@{path=$n;file=(Get-FileQuayWorkflowFile (Join-Path $Root $n))}})}
}
$self=Get-Process -Id $PID
$observed=Get-FileQuayUiaProcessRefusal $self $self.Path
Require ($observed.pid -eq $PID -and -not $observed.has_exited -and $observed.path -ceq $self.Path -and
    -not $observed.handle_is_invalid -and -not $observed.handle_is_closed -and
    $observed.handle_value -eq $self.SafeHandle.DangerousGetHandle().ToInt64()) 'Live process refusal observation fields differ'
$unavailableHandle=[pscustomobject]@{IsInvalid=$false;IsClosed=$false}
$unavailableHandle|Add-Member ScriptMethod DangerousGetHandle {throw ('unavailable-handle-'*100)}
$unavailable=[pscustomobject]@{Id=123;HasExited=$true;ExitCode=7;Path=$null;SafeHandle=$unavailableHandle;
    StandardOutput=@{BaseStream=[IO.MemoryStream]::new()};StandardError=@{BaseStream=[IO.MemoryStream]::new()}}
$observed=Get-FileQuayUiaProcessRefusal $unavailable $self.Path
Require ($null -eq $observed.path -and $null -eq $observed.handle_value -and $observed.pid -eq 123 -and
    $observed.has_exited -and $observed.exit_code -eq 7 -and $observed.stderr_stream_type -ceq 'System.IO.MemoryStream' -and
    $observed.observation_errors.Count -eq 1 -and $observed.observation_errors[0].field -ceq 'handle_value' -and
    $observed.observation_errors[0].error.Length -eq 512) 'Failed handle observation hid other fields or exceeded bounds'
$unavailable.Path='P'*5000
$observed=Get-FileQuayUiaProcessRefusal $unavailable $self.Path
Require ($observed.path -ceq ('P'*4096) -and $observed.path_truncated) 'Observed text exceeded its bound'
$temp=Join-Path (Join-Path $source 'artifacts') ('foldersail-child-evidence-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $temp '.github/scripts') -Force
try {
    Copy-Item (Join-Path $source '.github/scripts/UiaProxy.Diagnostics.cs') (Join-Path $temp '.github/scripts/UiaProxy.Diagnostics.cs')
    Set-Content (Join-Path $temp '.github/scripts/ConsumerWorkflow.Helpers.ps1') '# fixture source only'
    Set-Content (Join-Path $temp 'placeholder.dll') 'fixture bytes only'
    foreach($mode in @('bounded-error','foreign-record','oversized-record','retained-exit','late-path','foreign-image')){
        $script:childMode=$mode;$script:imageQueries=0
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
        $mutation=switch($mode){'bounded-error' {''};'foreign-record' {"`$r.nonce='foreign'"};'oversized-record' {"`$r.error='X'*5000"};'retained-exit' {''};'late-path' {''};'foreign-image' {''}}
        if($mode -ceq 'retained-exit'){$child=$child.Replace('Start-Sleep -Milliseconds 400','').Replace('20000','64').Replace('24000','64')}
        [IO.File]::WriteAllText((Join-Path $temp '.github/scripts/Invoke-UiaProxyFixtureChild.ps1'),$child.Replace('MODE',$mutation))
        $record=@{};$failure=''
        try{Invoke-FileQuayUiaProxyPreflight $temp $temp @{} $record}catch{$failure=$_.Exception.Message}
        $facts=@{mode=$mode;failure=$failure;retention_refusal=$record.fixture['retention_refusal'];ready_refusal=$record.fixture['ready_refusal'];
            output_constructor_ms=$record.fixture['output_constructor_ms'];retained_image_path=$record.fixture['retained_image_path'];cleanup_errors=$record.cleanup_errors}|ConvertTo-Json -Depth 6 -Compress
        Require (-not $record.passed -and -not $record.consumer_acceptance) 'Diagnostic accepted a failed child'
        if($mode -ceq 'retained-exit'){
            Require ($failure -ceq 'Native UIA fixture process could not be retained.') "Original early refusal changed: $facts"
            $refused=$record.fixture.retention_refusal
            Require ($refused.has_exited -and $refused.exit_code -eq 7 -and $refused.pid -gt 0 -and
                -not $refused.handle_is_invalid -and -not $refused.handle_is_closed -and $refused.handle_value -ne 0 -and
                $refused.expected_path -ceq (Get-Process -Id $PID).Path -and $refused.ContainsKey('path') -and
                $refused.stdout_stream_type -and $refused.stderr_stream_type) "Early refusal fields missing: $facts"
        }elseif($mode -ceq 'foreign-image'){
            Require ($failure -ceq 'Native UIA fixture process could not be retained.' -and
                $record.fixture.retained_image_path -ceq ($self.Path+'.foreign') -and
                $null -eq $record.fixture['ready_refusal'] -and $script:imageQueries -eq 2) "Foreign image was accepted/retried before cleanup: $facts"
        }else{
            Require ($failure -ceq 'Native UIA fixture did not expose its owned window before the deadline.') "Original readiness failure changed: $facts"
            Require ($record.fixture.ready_refusal.has_exited -and $record.fixture.ready_refusal.exit_code -eq 7 -and -not $record.fixture.ready_refusal.ready_exists) "Pre-cleanup exit cause missing: $facts"
        }
        if($mode -ceq 'late-path'){Require ($script:latePathReads -eq 0 -and $record.fixture.retained_image_path -ceq $self.Path) 'Ownership gate queried the late module-based Path property'}
        Require ($record.fixture.process_cleanup_verified -and -not $record.fixture.forced_cleanup -and $record.fixture.cleanup_exit_code -eq 7) 'Owned child cleanup differs'
        Require ($record.fixture.output_completed) 'Child output did not finish'
        foreach($channel in @('stdout','stderr')){
            $o=$record.fixture[$channel];$c=if($channel -ceq 'stdout'){'O'}else{'E'};$count=if($mode -ceq 'retained-exit'){64}elseif($channel -ceq 'stdout'){20000}else{24000};$kept=[Math]::Min(8192,$count)
            Require ($o.completed -and ($o.truncated -eq ($count -gt 8192)) -and $null -eq $o.read_error -and $o.observed_bytes -eq $count -and $o.retained_bytes -eq $kept -and $o.text -ceq ($c*$kept)) 'Output not bounded/drained exactly'
            $sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($c*$kept)))
            Require ($o.sha256 -ceq $sha -and [Convert]::FromBase64String($o.raw_base64).Length -eq $kept) 'Retained original output bytes/hash differ'
        }
        if($mode -cin @('bounded-error','retained-exit','late-path','foreign-image')){
            Require ($record.fixture.diagnostic_errors.Count -eq 0 -and $record.fixture.retained_records['result.json'].record.error -ceq 'original-child-failure') 'Original result not retained'
            Assert-FileQuayWorkflowFile (Join-Path $record.fixture.directory 'result.json') $record.fixture.retained_records['result.json'].file
        }else{Require ($record.fixture.diagnostic_errors.Count -eq 1 -and $record.fixture.retained_records.Count -eq 0) 'Invalid diagnostic file was accepted or original failure masked'}
    }
    'PASS actual failed-child parent: bounded concurrent streams, original file hashes, nonce/size refusals, pre-cleanup exit and unchanged rejection/cleanup.'
} finally {Remove-Item -LiteralPath $temp -Recurse -Force}
