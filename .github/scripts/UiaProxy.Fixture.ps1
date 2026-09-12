# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
function Build-FileQuayUiaFixture([string]$Root,[string]$Work,[string]$DotNet='dotnet') {
    $folder='tests/Files.Qualification.Win32Controls'
    $inputs=@('global.json','Directory.Build.props','Directory.Packages.props','src/Files.App.CsWin32/NativeMethods.json',
        "$folder/FileQuay.Qualification.Win32Controls.csproj","$folder/Win32Controls.cs","$folder/NativeMethods.txt","$folder/packages.lock.json",
        '.github/scripts/Invoke-UiaProxyFixtureChild.ps1','.github/scripts/ConsumerWorkflow.Helpers.ps1','.github/scripts/UiaProxy.Diagnostics.cs')
    $hashes=@(foreach ($relative in $inputs) { @{path=$relative;file=(Get-FileQuayWorkflowFile (Join-Path $Root $relative))} })
    $command=(Get-Command $DotNet -CommandType Application -ErrorAction Stop).Source
    $output=Join-Path $Work 'win32-controls';$null=New-Item -ItemType Directory -Path $output
    $intermediate=Join-Path $output 'obj/';$binary=Join-Path $output 'bin'
    Push-Location $Root
    try {
        $sdk=& $command --version
        if ($LASTEXITCODE -ne 0 -or ($sdk -join '').Trim() -cne (Get-Content global.json -Raw | ConvertFrom-Json).sdk.version) { throw 'Native UIA fixture SDK differs from the source pin.' }
        $log=& $command build "$folder/FileQuay.Qualification.Win32Controls.csproj" -c Release --output $binary "-p:BaseIntermediateOutputPath=$intermediate" '-p:RestoreLockedMode=true' '-v:quiet' '-clp:ErrorsOnly' 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('Native UIA fixture build failed: '+(($log | Select-Object -Last 20) -join "`n")) }
    } finally {Pop-Location}
    foreach ($input in $hashes) {Assert-FileQuayWorkflowFile (Join-Path $Root $input.path) $input.file}
    [xml]$central=Get-Content (Join-Path $Root 'Directory.Packages.props') -Raw
    $pin=@($central.Project.ItemGroup.PackageVersion | Where-Object Include -CEQ 'Microsoft.Windows.CsWin32')
    $assets=Get-Content (Join-Path $intermediate 'project.assets.json') -Raw | ConvertFrom-Json
    $resolved=@($assets.libraries.PSObject.Properties.Name | Where-Object {$_ -clike 'Microsoft.Windows.CsWin32/*'})
    if ($pin.Count -ne 1 -or $resolved.Count -ne 1 -or $resolved[0] -cne "Microsoft.Windows.CsWin32/$($pin[0].Version)") {throw 'Native fixture CsWin32 pin differs.'}
    $path=Join-Path $binary 'FileQuay.Qualification.Win32Controls.dll'
    if (@(Get-ChildItem $binary -Filter '*.dll' -Recurse | Where-Object FullName -CNE $path).Count) {throw 'Unexpected fixture runtime assembly.'}
    @{path=$path;file=(Get-FileQuayWorkflowFile $path);source_inputs=$hashes;sdk_version=($sdk -join '').Trim();cswin32_version=[string]$pin[0].Version}
}

function Assert-FileQuayUiaFixtureReady($Ready,[string]$Nonce,[int]$ProcessId) {
    if ($Ready.schema_version -ne 1 -or $Ready.nonce -cne $Nonce -or $Ready.process_id -ne $ProcessId -or
        $Ready.window -isnot [long] -or $Ready.edit -isnot [long] -or $Ready.button -isnot [long] -or
        $Ready.window -le 0 -or $Ready.edit -le 0 -or $Ready.button -le 0 -or
        @($Ready.window,$Ready.edit,$Ready.button | Sort-Object -Unique).Count -ne 3) {throw 'Native UIA fixture readiness identity differs.'}
}

function Get-FileQuayUiaFixtureControl($Process,$Ready,[ValidateSet('Edit','Button')][string]$Kind,[switch]$RequireForeground) {
    $window=[long]$Ready.window;$handle=if ($Kind -ceq 'Edit') {[long]$Ready.edit} else {[long]$Ready.button}
    $native=[FileQuayQualification.ConsumerInput]::Observe($Process,$window,$Process,$window)
    if (-not $native.app_live -or -not $native.main_live -or -not $native.target_live -or
        $native.main_pid -ne $Process.Id -or $native.target_pid -ne $Process.Id -or
        -not $native.target_visible -or -not $native.target_enabled -or ($RequireForeground -and $native.foreground_hwnd -ne $window) -or
        [FileQuayQualification.ConsumerInput]::WindowProcess($handle) -ne $Process.Id -or
        [FileQuayQualification.ConsumerInput]::RootWindow($handle) -ne $window) {throw 'Owned native UIA fixture target changed.'}
    $element=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$handle)
    $current=$element.Current
    if ($current.ProcessId -ne $Process.Id -or $current.NativeWindowHandle -ne $handle -or
        $current.ClassName -cne $Kind -or $current.IsOffscreen -or -not $current.IsEnabled) {throw 'UIA fixture control ownership or visibility differs.'}
    $value=$null;$invoke=$null
    $hasValue=$element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$value)
    $hasInvoke=$element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern,[ref]$invoke)
    @{element=$element;value=$value;invoke=$invoke;observation=@{pid=$current.ProcessId;hwnd=$handle;class=$current.ClassName;
        automation_id=$current.AutomationId;name=$current.Name;role=$(if ($current.ControlType) {$current.ControlType.ProgrammaticName} else {'Unavailable'});
        visible=(-not $current.IsOffscreen);enabled=$current.IsEnabled;value_supported=$hasValue;invoke_supported=$hasInvoke;
        value_pattern_type=$(if ($value) {$value.GetType().FullName} else {''});invoke_pattern_type=$(if ($invoke) {$invoke.GetType().FullName} else {''})}}
}

function Assert-FileQuayUiaFixtureControl($Control,[ValidateSet('Edit','Button')][string]$Kind) {
    $o=$Control.observation
    $role=if ($Kind -ceq 'Edit') {'ControlType.Edit'} else {'ControlType.Button'}
    $id=if ($Kind -ceq 'Edit') {'1001'} else {'1'}
    if ($o.role -cne $role -or $o.automation_id -cne $id -or $o.class -cne $Kind -or -not $o.visible -or -not $o.enabled) {throw 'Native fixture lacks the required exact standard control semantics.'}
    if ($Kind -ceq 'Edit') {
        if (-not $o.value_supported -or $Control.value -isnot [System.Windows.Automation.ValuePattern] -or $Control.value.Current.IsReadOnly) {throw 'Native Edit proxy has no editable ValuePattern.'}
    } elseif (-not $o.invoke_supported -or $Control.invoke -isnot [System.Windows.Automation.InvokePattern]) {throw 'Native Button proxy has no InvokePattern.'}
}

function Get-FileQuayUiaProcessRefusal($Process,[string]$HostPath) {
    $observation=@{at_utc=[DateTime]::UtcNow.ToString('o');expected_path=$HostPath;
        framework=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;observation_errors=@()}
    $reads=[ordered]@{
        pid={$Process.Id};has_exited={$Process.HasExited};path={$Process.Path};
        handle_is_invalid={$Process.SafeHandle.IsInvalid};handle_is_closed={$Process.SafeHandle.IsClosed};
        handle_value={$Process.SafeHandle.DangerousGetHandle().ToInt64()};
        exit_code={if($Process.HasExited){$Process.ExitCode}else{$null}};
        stdout_stream_type={$Process.StandardOutput.BaseStream.GetType().FullName};
        stderr_stream_type={$Process.StandardError.BaseStream.GetType().FullName}
    }
    foreach($key in $reads.Keys){
        $observation[$key]=$null
        try {
            $value=& $reads[$key]
            if($value -is [string] -and $value.Length -gt 4096){$value=$value.Substring(0,4096);$observation[$key+'_truncated']=$true}
            $observation[$key]=$value
        } catch {
            $message=$_.Exception.Message
            $observation.observation_errors+=@(@{field=$key;error=$message.Substring(0,[Math]::Min(512,$message.Length))})
        }
    }
    $observation
}

function Invoke-FileQuayUiaProxyPreflight([string]$Root,[string]$Work,$Adapter,$Record,[string]$DotNet='dotnet') {
    Assert-FileQuayConsumerAdapter $Adapter
    $Record.schema_version=1;$Record.source_commit=$env:GITHUB_SHA;$Record.consumer_acceptance=$false
    $Record.passed=$false;$Record.cleanup_errors=@();$Record.proxy=@{registered=$false}
    $Record.fixture=@{normal_exit=$false;forced_cleanup=$false};$process=$null;$ready=$null;$primary='';$output=$null
    $Record.fixture.diagnostic_errors=@()
    try {
        Get-FileQuayUiaProxyEvidence $Record.proxy
        $Record.loaded_providers_before_registration=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -ieq 'UIAutomationClientSideProviders' } | ForEach-Object { @{identity=$_.FullName;path=$_.Location} })
        # Register before fresh HWNDs/queries; cached HWND-only fallback objects
        # from an earlier query are not the fixture's support evidence.
        Register-FileQuayUiaProxy $Record.proxy
        $build=Build-FileQuayUiaFixture $Root $Work $DotNet;$Record.build=$build
        $directory=Join-Path $Work ('uia-controls-'+[Guid]::NewGuid().ToString('N'))
        $null=New-Item -ItemType Directory -Path $directory
        $nonce=[Guid]::NewGuid().ToString('N');$hostPath=(Get-Process -Id $PID).Path
        $Record.fixture.directory=$directory;$Record.fixture.nonce=$nonce;$Record.fixture.host_path=$hostPath
        $start=[Diagnostics.ProcessStartInfo]::new($hostPath);$start.UseShellExecute=$false
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $diagnostics=Join-Path $Root '.github/scripts/UiaProxy.Diagnostics.cs'
        Assert-FileQuayWorkflowFile $diagnostics @($build.source_inputs | Where-Object path -CEQ '.github/scripts/UiaProxy.Diagnostics.cs')[0].file
        Add-Type -Path $diagnostics
        $child=Join-Path $Root '.github/scripts/Invoke-UiaProxyFixtureChild.ps1'
        Assert-FileQuayWorkflowFile $build.path $build.file
        foreach ($relative in @('.github/scripts/Invoke-UiaProxyFixtureChild.ps1','.github/scripts/ConsumerWorkflow.Helpers.ps1')) {
            Assert-FileQuayWorkflowFile (Join-Path $Root $relative) @($build.source_inputs | Where-Object path -CEQ $relative)[0].file
        }
        foreach ($arg in @('-NoProfile','-NonInteractive','-STA','-File',$child,'-AssemblyPath',$build.path,'-AssemblyHash',$build.file.sha256,'-Directory',$directory,'-Nonce',$nonce)) {$start.ArgumentList.Add($arg)}
        $process=[Diagnostics.Process]::Start($start);$null=$process.SafeHandle
        $outputClock=[Diagnostics.Stopwatch]::StartNew()
        $output=[FileQuayQualification.FixtureChildOutput]::new($process.StandardOutput.BaseStream,$process.StandardError.BaseStream)
        $Record.fixture.output_constructor_ms=$outputClock.ElapsedMilliseconds
        try {
            if ($process.HasExited -or $process.SafeHandle.IsInvalid -or $process.SafeHandle.IsClosed -or $process.Path -ine $hostPath) {throw 'Native UIA fixture process could not be retained.'}
        } catch {
            $refusal=$_
            try {$Record.fixture.retention_refusal=Get-FileQuayUiaProcessRefusal $process $hostPath}
            catch {$Record.fixture.diagnostic_errors+=@('Retention observation: '+$_.Exception.GetType().Name)}
            throw $refusal
        }
        $Record.fixture.pid=$process.Id;$Record.fixture.start_time_utc=$process.StartTime.ToUniversalTime().ToString('o')
        $readyPath=Join-Path $directory 'ready.json';$deadline=[DateTime]::UtcNow.AddSeconds(10);$readyClock=[Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $readyPath)) {
            if ($process.HasExited -or [DateTime]::UtcNow -ge $deadline) {
                try {$Record.fixture.ready_refusal=@{at_utc=[DateTime]::UtcNow.ToString('o');elapsed_ms=$readyClock.ElapsedMilliseconds;
                    has_exited=$process.HasExited;exit_code=$(if($process.HasExited){$process.ExitCode}else{$null});ready_exists=(Test-Path -LiteralPath $readyPath)}}
                catch {$Record.fixture.diagnostic_errors+=@($_.Exception.Message)}
                throw 'Native UIA fixture did not expose its owned window before the deadline.'
            }
            Start-Sleep -Milliseconds 100
        }
        $null=Get-FileQuayWorkflowFile $readyPath 4096
        $ready=Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-FileQuayUiaFixtureReady $ready $nonce $process.Id;$Record.fixture.ready=$ready
        $edit=Get-FileQuayUiaFixtureControl $process $ready Edit;$button=Get-FileQuayUiaFixtureControl $process $ready Button
        $Record.after=@{edit=$edit.observation;button=$button.observation}
        Assert-FileQuayUiaFixtureControl $edit Edit;Assert-FileQuayUiaFixtureControl $button Button
        [FileQuayQualification.ConsumerInput]::Foreground($process,$ready.window,$process,$ready.window)
        $edit=Get-FileQuayUiaFixtureControl $process $ready Edit -RequireForeground;Assert-FileQuayUiaFixtureControl $edit Edit
        $edit.value.SetValue('owned-'+$nonce)
        if ($edit.value.Current.Value -cne ('owned-'+$nonce)) {throw 'Native fixture ValuePattern readback differs.'}
        $Record.fixture.value_readback=$edit.value.Current.Value
        $button=Get-FileQuayUiaFixtureControl $process $ready Button -RequireForeground;Assert-FileQuayUiaFixtureControl $button Button
        $button.invoke.Invoke()
        if (-not $process.WaitForExit(5000)) {throw 'Native fixture did not close normally after its one Invoke action.'}
        $Record.fixture.exit_code=$process.ExitCode
        $resultPath=Join-Path $directory 'result.json';$null=Get-FileQuayWorkflowFile $resultPath 4096
        $Record.fixture.result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-FileQuayUiaFixtureResult $Record.fixture.result $nonce $process.ExitCode
        if ([FileQuayQualification.ConsumerInput]::WindowProcess($ready.window) -ne 0) {throw 'Native fixture HWND remains live after normal exit.'}
        $Record.fixture.normal_exit=$true;$Record.passed=$true
    } catch {$primary=$_.Exception.Message;$Record.error=$primary}
    finally {
        if ($process) {
            try {
                if (-not $process.HasExited) {
                    if ($process.SafeHandle.IsClosed -or $process.SafeHandle.IsInvalid -or $process.Path -ine $Record.fixture.host_path) {throw 'Fixture cleanup retained process identity changed.'}
                    $Record.fixture.close_requested=$process.CloseMainWindow()
                    if (-not $process.WaitForExit(3000)) {$process.Kill();$Record.fixture.forced_cleanup=$true;if (-not $process.WaitForExit(3000)) {throw 'Owned native fixture survived forced cleanup.'}}
                }
                $Record.fixture.cleanup_exit_code=$process.ExitCode;$Record.fixture.process_cleanup_verified=$true
            } catch {$Record.cleanup_errors+=@($_.Exception.Message);$Record.passed=$false}
            finally {
                try {
                    if ($output) {$Record.fixture.output_completed=$output.Finish(1000);$Record.fixture.stdout=$output.Stdout();$Record.fixture.stderr=$output.Stderr()}
                    if ($Record.fixture.process_cleanup_verified) {
                        $Record.fixture.retained_records=@{}
                        foreach ($name in @('ready.json','result.json')) {
                            $path=Join-Path $directory $name
                            if (Test-Path -LiteralPath $path) {
                                $file=Get-FileQuayWorkflowFile $path 4096
                                $value=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
                                if($value.nonce -cne $nonce){throw 'Child diagnostic nonce differs.'}
                                Assert-FileQuayWorkflowFile $path $file
                                $Record.fixture.retained_records[$name]=@{file=$file;record=$value}
                            }
                        }
                    }
                } catch {$Record.fixture.diagnostic_errors+=@($_.Exception.Message)}
                finally {$process.Dispose()}
            }
        }
    }
    if ($primary -or $Record.cleanup_errors.Count) {
        $failures=@($primary)+@($Record.cleanup_errors)
        throw (($failures | Where-Object {$_}) -join '; ')
    }
    if (-not $Record.passed) {throw 'Native UIA proxy preflight did not pass.'}
}
