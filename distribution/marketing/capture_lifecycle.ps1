# Copyright 2026 Trieflow LLC. MIT. Capture only; the original qualification stays unchanged.
function Assert-FolderSailMarketingComplete($State){
    if($State.outcome.primary_error -or $State.outcome.cleanup_errors.Count -or
       ($State.captures -join '|') -cne '01-folder-workspace|02-operation-receipts|03-export-receipts' -or
       -not $State.displayEvidence.restore_verified -or -not $State.record.csv_committed_verified -or
       -not $State.record.owned_process_cleanup_verified -or -not $State.record.window_disappeared -or
       (-not $State.record.normal_process_exit_verified -and -not $State.record.background_process_observed)){
        throw 'Marketing capture is incomplete; original qualification is unchanged'
    }
    foreach($key in @('normalClose','stopped','uninstalled','removed','inputsUnchanged','trustRemoved','keyRemoved','temporaryRemoved')){
        if($State[$key] -ne $true){throw "Marketing capture incomplete: $key"}
    }
}

function Invoke-FolderSailMarketingLifecycle($State,$Operations){
    $primary=$null;$cleanup=[Collections.Generic.List[string]]::new()
    try{foreach($name in @('Preflight','Prepare','Sign','Install','Activate','Workflow','Close','Uninstall')){& $Operations[$name] $State|Out-Host}}
    catch{$primary=$_.Exception.ToString();try{& $Operations.ObserveFailure $State|Out-Host}catch{$cleanup.Add('ObserveFailure: '+$_.Exception.Message)}}
    finally{foreach($name in @('Stop','RestoreDisplay','RemovePackage','RemoveDemo','RemoveTrust','RemoveKey','RemoveTemporary')){
        try{& $Operations[$name] $State|Out-Host}catch{$cleanup.Add($name+': '+$_.Exception.Message)}
    }}
    return @{primary_error=$primary;cleanup_errors=@($cleanup)}
}

function Assert-FolderSailMarketingProcess($State){
    $process=$State.process;$process.Refresh()
    if($process.HasExited -or $process.SafeHandle.IsClosed -or $process.SafeHandle.IsInvalid -or
       $process.Path -ine (Join-Path $State.installed.InstallLocation 'FolderSail.exe') -or
       [FolderSailMarketing.Native]::PackageName($process.SafeHandle.DangerousGetHandle()) -cne $State.ownership.ownedPackageFullName){throw 'Retained capture process identity changed'}
    $expected=$State.verified.payload['foldersail.exe']
    if((Get-FileHash -LiteralPath $process.Path).Hash.ToLowerInvariant() -cne $expected.sha256){throw 'Installed capture executable bytes changed'}
}

function Get-FolderSailMarketingModules($State){
    Assert-FolderSailMarketingProcess $State
    $prefix=$State.installed.InstallLocation.TrimEnd('\')+'\';$modules=@();$required=@('FolderSail.exe','coreclr.dll')
    foreach($module in @($State.process.Modules)){
        $path=$module.FileName
        if($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
            Assert-FileQuayWorkflowAncestors $path
            $relative=$path.Substring($prefix.Length).Replace('\','/').ToLowerInvariant()
            if(-not $State.verified.payload.ContainsKey($relative)){throw 'Unexpected loaded package module'}
            $expected=$State.verified.payload[$relative];$file=Get-Item -LiteralPath $path
            if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -ne $expected.bytes -or
               (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $expected.sha256){throw 'Loaded package module bytes differ'}
            $modules+=@{name=$module.ModuleName;path=$path;sha256=$expected.sha256}
            $required=@($required|Where-Object {$_ -ine $module.ModuleName})
        }
    }
    if($required.Count){throw 'Captured app did not load its original executable and packaged runtime'}
    return ,$modules
}

function Retain-FolderSailMarketingServers($State){
    if(-not $State.installed){return}
    $expected=Join-Path $State.installed.InstallLocation 'Files.App.Server/Files.App.Server.exe'
    foreach($candidate in @(Get-Process -Name 'Files.App.Server' -ErrorAction SilentlyContinue)){
        try{
            if($candidate.Path -ine $expected){continue}
            if($candidate.SafeHandle.IsInvalid -or $candidate.SafeHandle.IsClosed -or $candidate.HasExited -or
               [FolderSailMarketing.Native]::PackageName($candidate.SafeHandle.DangerousGetHandle()) -cne $State.ownership.ownedPackageFullName){throw 'Capture server ownership unavailable'}
            if((Get-FileHash -LiteralPath $candidate.Path).Hash.ToLowerInvariant() -cne $State.verified.payload['files.app.server/files.app.server.exe'].sha256){throw 'Capture server differs from original package'}
            if(-not $State.servers.ContainsKey([string]$candidate.Id)){$State.servers[[string]$candidate.Id]=$candidate;$candidate=$null}
        }finally{if($candidate){$candidate.Dispose()}}
    }
}

function Write-FolderSailMarketingFrameworkObservation($State,$Packages,[string]$Expected){
    # Read only the already returned candidates. Observation failures remain
    # secondary; the original registration predicate below still decides.
    $observation=[ordered]@{expected_full_name=$Expected;requirement=$State.verified.framework.requirement;
        observed_count=$Packages.Count;candidates=@();truncated=($Packages.Count -gt 8);
        powershell_version=$PSVersionTable.PSVersion.ToString();diagnostic_errors=@()}
    $State.record.framework_registration_observation=$observation
    try{
        foreach($package in @($Packages|Select-Object -First 8)){
            $row=@{fields=@{};requirement_matches=$null;type_names=@($package.PSObject.TypeNames|Select-Object -First 4)}
            $observation.candidates+=@($row)
            foreach($name in @('Name','Publisher','Version','Architecture','PackageFullName','PackageFamilyName','IsFramework','Status')){
                try{
                    $property=$package.PSObject.Properties[$name];$value=if($property){$property.Value}else{$null}
                    $text=if($null -ne $value){[string]$value}else{$null}
                    $row.fields[$name]=@{present=($null -ne $property);value=if($null -ne $text){$text.Substring(0,[Math]::Min(1024,$text.Length))}else{$null};
                        type=if($null -ne $value){$value.GetType().FullName}else{$null};truncated=($null -ne $text -and $text.Length -gt 1024)}
                }catch{if($observation.diagnostic_errors.Count -lt 8){$message=$_.Exception.Message;$observation.diagnostic_errors+=@($name+': '+$message.Substring(0,[Math]::Min(2048,$message.Length)))}}
            }
            try{$row.requirement_matches=Test-FileQuayFrameworkRegistration $package $State.verified.framework.requirement}
            catch{if($observation.diagnostic_errors.Count -lt 8){$message=$_.Exception.Message;$observation.diagnostic_errors+=@('Matcher: '+$message.Substring(0,[Math]::Min(2048,$message.Length)))}}
        }
    }catch{if($observation.diagnostic_errors.Count -lt 8){$message=$_.Exception.Message;$observation.diagnostic_errors+=@('Observation: '+$message.Substring(0,[Math]::Min(2048,$message.Length)))}}
}

function New-FolderSailMarketingOperations {
    # Pass state explicitly. Avoid dynamic-module closures losing the imported
    # original helper functions under Windows PowerShell scope rules.
    [ordered]@{
        Preflight={param($s)
            foreach($path in @($s.demo,$s.profile,$s.output)){
                Assert-FileQuayWorkflowAncestors $path
                if(Test-Path -LiteralPath $path){throw 'Existing marketing content, output or app profile preserved'}
            }
            if(@(Get-AppxPackage -Name $s.identity.name -ErrorAction Stop).Count){throw 'Existing assigned Store registration preserved'}
            $s.frameworkBefore=@(Get-AppxPackage -Name $s.verified.framework.artifact_identity.Name -ErrorAction Stop)
            if($s.frameworkBefore.Count){throw 'Capture requires the same fresh framework installation boundary'}
            New-Item -ItemType Directory -Path $s.output -ErrorAction Stop|Out-Null
            $s.outputOwned=$true
            [IO.File]::Copy((Join-Path $s.inputs 'capture-inputs.json'),(Join-Path $s.output 'capture-inputs.json'),$false)
            [IO.File]::Copy((Join-Path $s.inputs 'verified-inputs.json'),(Join-Path $s.output 'verified-inputs.json'),$false)
        }
        Prepare={param($s)
            $s.temporary=Join-Path $env:RUNNER_TEMP ('.foldersail-marketing-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $s.temporary -ErrorAction Stop|Out-Null
            $s.nativeAdapter=Initialize-FileQuayConsumerAdapter $s.qualified $s.temporary
            Invoke-FileQuayUiaProxyPreflight $s.qualified $s.temporary $s.nativeAdapter $s.uiaProxy
            $raw=Invoke-FolderSailMarketingFiles $s create @('--root',$s.demo)
            $s.fixture=@{root=$s.demo;source=(Join-Path $s.demo 'Inbox/Garden workshop brief.md');copied=(Join-Path $s.demo 'Working drafts/Garden workshop brief.md');
                moved=(Join-Path $s.demo 'Ready to share/Garden workshop brief.md');csv=(Join-Path $s.demo 'Receipts/Workshop receipts.csv')}
            $s.fixture.previous_csv=Get-FileQuayWorkflowFile $s.fixture.csv
            Start-FolderSailMarketingConsumerDisplay $s
        }
        Sign={param($s)
            $s.signed=Join-Path $s.temporary 'FolderSail-marketing.signed.msix';[IO.File]::Copy($s.package,$s.signed,$false)
            $s.certificate=New-SelfSignedCertificate -Type Custom -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -KeySpec Signature -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}') -Subject $s.identity.publisher -FriendlyName 'FolderSail temporary marketing capture' -NotAfter (Get-Date).AddHours(2)
            $public=Join-Path $s.temporary 'capture-public.cer';Export-Certificate -Cert $s.certificate -FilePath $public|Out-Null
            $s.trustAttempted=$true;Import-Certificate -FilePath $public -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'|Out-Null
            $tool=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin/10.0.26100.0/x64/signtool.exe';$hash=(Get-FileHash $tool).Hash
            $s.record.temporary_signing=@{tool=$tool;tool_sha256=$hash.ToLowerInvariant();certificate_thumbprint=$s.certificate.Thumbprint;
                original_unsigned_sha256=$s.bound.package.sha256;signed_copy_sha256=$null;signature_verified=$false}
            foreach($arguments in @(@('sign','/fd','SHA256','/sha1',$s.certificate.Thumbprint,'/s','My',$s.signed),@('verify','/pa','/all','/v',$s.signed))){
                if((Get-FileHash $tool).Hash -cne $hash){throw 'Capture signing tool changed'}
                & $tool @arguments;if($LASTEXITCODE -ne 0){throw 'Temporary capture package signature failed'}
            }
            $signature=Get-AuthenticodeSignature -LiteralPath $s.signed
            if($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $signature.SignerCertificate.Thumbprint -cne $s.certificate.Thumbprint){throw 'Temporary signer identity differs'}
            if((Get-FileHash $s.package).Hash.ToLowerInvariant() -cne $s.bound.package.sha256){throw 'Original unsigned package changed'}
            $s.record.temporary_signing.signed_copy_sha256=(Get-FileHash $s.signed).Hash.ToLowerInvariant();$s.record.temporary_signing.signature_verified=$true
        }
        Install={param($s)
            if(Test-Path -LiteralPath $s.profile){throw 'An existing app profile appeared before installation; preserved'}
            $dependency=Join-Path $s.inputs 'framework/Microsoft.WindowsAppRuntime.2.msix'
            if((Get-FileHash $dependency).Hash.ToLowerInvariant() -cne $s.verified.framework.artifact_sha256.ToLowerInvariant()){throw 'Original framework input changed'}
            $s.ownership.installAttempted=$true;Add-AppxPackage -Path $s.signed -DependencyPath $dependency -ErrorAction Stop;$s.ownership.addCompleted=$true
            $s.installed=Set-FileQuayOwnedRegistration $s.ownership @(Get-AppxPackage -Name $s.identity.name -ErrorAction Stop) $s.identity.name $s.identity.publisher '1.0.1.0' 'X64'
            if($s.installed.PackageFamilyName -cne $s.identity.family -or $s.installed.PackageFullName -cne $s.fullName){throw 'Exact installed marketing package differs'}
            Assert-FolderSailPackageIdentity (Get-AppxPackageManifest -Package $s.fullName) Store Consumer
            foreach($entry in $s.verified.payload.GetEnumerator()){
                if($entry.Key -in @('appxblockmap.xml','appxmetadata/codeintegrity.cat')){continue}
                $path=Join-Path $s.installed.InstallLocation $entry.Key;Assert-FileQuayWorkflowAncestors $path;$file=Get-Item -LiteralPath $path
                if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -ne $entry.Value.bytes -or
                   (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $entry.Value.sha256){throw "Original installed payload changed: $($entry.Key)"}
            }
            $frameworks=@(Get-AppxPackage -Name $s.verified.framework.artifact_identity.Name -ErrorAction Stop)
            $expected='Microsoft.WindowsAppRuntime.2_2.4.0.0_x64__8wekyb3d8bbwe'
            Write-FolderSailMarketingFrameworkObservation $s $frameworks $expected
            if($frameworks.Count -ne 1 -or $frameworks[0].PackageFullName -cne $expected -or
               -not (Test-FileQuayFrameworkRegistration $frameworks[0] $s.verified.framework.requirement)){throw 'Original framework registration differs'}
            $s.record.framework=@{full_name=$expected;installed_from_original_input=$true;cleanup_policy='Retain framework until disposable runner teardown'}
        }
        Activate={param($s)
            Assert-FileQuayWorkflowAncestors (Join-Path $s.profile 'LocalState/OperationReceipts/v1.json')
            if(Test-Path -LiteralPath (Join-Path $s.profile 'LocalState/OperationReceipts/v1.json')){throw 'Existing receipt history preserved'}
            $s.stopped=$false;$s.brokerPid=[FolderSailMarketing.Native]::Activate($s.identity.family+'!App')
            $s.process=[Diagnostics.Process]::GetProcessById($s.brokerPid);$null=$s.process.SafeHandle
            Assert-FolderSailMarketingProcess $s;$s.processOwned=$true
            $window=Wait-FileQuayWorkflow {
                Assert-FolderSailMarketingProcess $s;$s.process.Refresh()
                if($s.process.MainWindowHandle -eq 0){return $null}
                $root=[System.Windows.Automation.AutomationElement]::FromHandle($s.process.MainWindowHandle)
                if($root.Current.ProcessId -ne $s.process.Id -or $root.Current.IsOffscreen){throw 'Original main UIA root differs'}
                $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'ShowStatusCenterButton')
                $button=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
                if($button -and -not $button.Current.IsOffscreen){return $root}
            } 'normal installed FolderSail with visible Status Center'
            $strings=@{};[xml]$resources=Get-Content (Join-Path $s.qualified 'src/Files.App/Strings/en-US/Resources.resw') -Raw
            foreach($entry in $resources.root.data){$strings[[string]$entry.name]=[string]$entry.value}
            $s.ui=@{application=$s.process;main_hwnd=[long]$window.Current.NativeWindowHandle;brokers=@{};record=$s.record;strings=$strings;evidence=$s.output}
            Retain-FolderSailMarketingServers $s
            Write-FileQuayQualificationRecord (Join-Path $s.output 'loaded-package-modules.json') @{modules=(Get-FolderSailMarketingModules $s)}
        }
        Workflow={param($s)
            Assert-FileQuayConsumerAdapter $s.nativeAdapter
            Invoke-FolderSailMarketingUi $s;Retain-FolderSailMarketingServers $s
            Write-FileQuayQualificationRecord (Join-Path $s.output 'loaded-package-modules-after.json') @{modules=(Get-FolderSailMarketingModules $s)}
        }
        Close={param($s)
            Assert-FolderSailMarketingProcess $s;$main=Get-FileQuayWorkflowMain $s.ui
            [FileQuayQualification.ConsumerInput]::Foreground($s.process,$s.ui.main_hwnd,$s.process,$s.ui.main_hwnd)
            Assert-FileQuayWorkflowTarget $main.scope (Get-FileQuayWorkflowTargetState $s.ui $main)
            ([System.Windows.Automation.WindowPattern]$main.element.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)).Close()
            $s.record.normal_window_close_requested=$true
            $null=Wait-FileQuayWorkflow {
                $s.process.Refresh()
                if($s.process.HasExited -or $s.process.MainWindowHandle -eq 0){return $true}
                $observed=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$s.ui.main_hwnd)
                if($observed.Current.IsOffscreen){return $true}
            } 'the normal owned window to disappear' 15
            $s.normalClose=$true;$s.record.window_disappeared=$true
            $s.record.process_exit=Get-FileQuayProcessExitEvidence $s.process 3000
            if($s.record.process_exit.observation_error -or ($s.record.process_exit.wait_completed -and -not $s.record.process_exit.normal_exit)){throw 'Normal close process observation failed'}
            $s.record.normal_process_exit_verified=$s.record.process_exit.normal_exit
            $s.record.background_process_observed=-not $s.record.process_exit.wait_completed
            $s.record.background_policy='Normal Release default LeaveAppRunning=true may hide the final window. Retained owned cleanup is reported separately.'
            Stop-FolderSailMarketingProcesses $s
            $null=Invoke-FolderSailMarketingFiles $s verify @('--phase','Exported')
            $null=Invoke-FolderSailMarketingFiles $s seal @('--stopped');$s.sealed=$true
        }
        Uninstall={param($s)
            if(-not $s.stopped -or -not $s.ownership.installedByUs){throw 'Owned stop/registration required before capture uninstall'}
            Remove-FileQuayOwnedRegistration $s.ownership $s.identity.name {Get-AppxPackage -Name $s.identity.name -ErrorAction Stop} {param($full) Remove-AppxPackage -Package $full -ErrorAction Stop}
            $s.uninstalled=$true
        }
        ObserveFailure={param($s)
            if($s.ui -and $s.processOwned -and -not $s.process.HasExited){$s.record.failure_observation=@(Get-FileQuayWorkflowFailureObservation $s.ui)}
        }
        Stop={param($s) Stop-FolderSailMarketingProcesses $s}
        RestoreDisplay={param($s) Restore-FolderSailMarketingConsumerDisplay $s}
        RemovePackage={param($s)
            if($s.ownership.installAttempted){
                if(-not $s.stopped){throw 'Unstopped capture package preserved'}
                Remove-FileQuayOwnedRegistration $s.ownership $s.identity.name {Get-AppxPackage -Name $s.identity.name -ErrorAction Stop} {param($full) Remove-AppxPackage -Package $full -ErrorAction Stop}
                $s.uninstalled=$true
            }
        }
        RemoveDemo={param($s)
            if($s.fixture){
                if(-not $s.stopped -or ($s.ownership.installAttempted -and -not $s.uninstalled)){throw 'Capture files preserved without stopped/uninstalled ownership'}
                if(Test-Path -LiteralPath $s.profile){throw 'Appx profile remains after uninstall; preserve it for review'}
                if(-not $s.sealed){$null=Invoke-FolderSailMarketingFiles $s seal @('--stopped');$s.sealed=$true}
                $s.removed=(Invoke-FolderSailMarketingFiles $s cleanup @('--stopped')).removed
            }
        }
        RemoveTrust={param($s) if($s.trustAttempted -and $s.certificate){$path='Cert:\LocalMachine\TrustedPeople\'+$s.certificate.Thumbprint;if(Test-Path $path){Remove-Item -LiteralPath $path -Force};if(Test-Path $path){throw 'Owned temporary trust remains'}};$s.trustRemoved=$true}
        RemoveKey={param($s) if($s.certificate){$path='Cert:\CurrentUser\My\'+$s.certificate.Thumbprint;if(Test-Path $path){Remove-Item -LiteralPath $path -DeleteKey -Force};if(Test-Path $path){throw 'Owned temporary certificate/key remains'}};$s.keyRemoved=$true}
        RemoveTemporary={param($s)
            if($s.temporary){
                if(-not $s.stopped){throw 'Unstopped capture temporary files preserved'}
                Assert-FileQuayWorkflowAncestors (Join-Path $s.temporary 'child')
                foreach($path in @(Get-ChildItem -LiteralPath $s.temporary -Recurse -Force)){if($path.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected link in temporary capture tree; preserved'}}
                Remove-Item -LiteralPath $s.temporary -Recurse -Force -ErrorAction Stop
                if(Test-Path -LiteralPath $s.temporary){throw 'Temporary capture tree remains'}
            }
            $s.temporaryRemoved=$true
        }
    }
}

function Stop-FolderSailMarketingProcesses($State){
    if($State.stopped){return}
    if(-not $State.processOwned){throw 'Unproven activated process preserved'}
    Retain-FolderSailMarketingServers $State
    $null=Stop-FileQuayOwnedProcess $State.process 15000
    # Observe again after the app can no longer initiate a new COM server.
    Retain-FolderSailMarketingServers $State
    foreach($server in $State.servers.Values){$null=Stop-FileQuayOwnedProcess $server 15000}
    Retain-FolderSailMarketingServers $State
    foreach($server in $State.servers.Values){$server.Refresh();if(-not $server.HasExited){throw 'An owned capture server remains after cleanup'}}
    $State.stopped=$true;$State.record.owned_process_cleanup_verified=$true
}
