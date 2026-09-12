# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
function Assert-FileQuayUiaProxyIdentity($Client,$Proxy,[string]$HostRoot) {
    foreach ($entry in @(@{item=$Client;name='UIAutomationClient';token='31bf3856ad364e35'},@{item=$Proxy;name='UIAutomationClientSideProviders';token='b77a5c561934e089'})) {
        $item=$entry.item;$expected=Join-Path $HostRoot ($entry.name+'.dll')
        if ([IO.Path]::GetFullPath($item.path) -ine [IO.Path]::GetFullPath($expected) -or $item.name -ine $entry.name -or
            $item.version -cne $Client.version -or $item.version -notmatch '^10\.0\.0\.0$' -or
            $item.public_key_token -cne $entry.token -or $item.culture -cne '' -or
            $item.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $item.bytes -le 0 -or $item.bytes -gt 8388608 -or
            $item.signature_status -cne 'Valid' -or $item.signer_subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)' -or
            $item.company -cne 'Microsoft Corporation') { throw 'UIA proxy must be the exact signed matching Microsoft assembly in the current PowerShell host.' }
    }
}

function Get-FileQuayUiaAssemblyIdentity([string]$Path) {
    $before=Get-FileQuayWorkflowFile $Path 8388608
    $name=[Reflection.AssemblyName]::GetAssemblyName($Path)
    $signature=Get-AuthenticodeSignature -LiteralPath $Path
    $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    $after=Get-FileQuayWorkflowFile $Path 8388608
    if ($before.bytes -ne $after.bytes -or $before.sha256 -cne $after.sha256) { throw 'UIA host/proxy file changed during identity inspection.' }
    @{path=[IO.Path]::GetFullPath($Path);name=$name.Name;version=$name.Version.ToString();culture=$name.CultureName;
      public_key_token=[Convert]::ToHexString($name.GetPublicKeyToken()).ToLowerInvariant();
      bytes=$before.bytes;sha256=$before.sha256.ToLowerInvariant();signature_status=[string]$signature.Status;
      signer_subject=$(if ($signature.SignerCertificate) {$signature.SignerCertificate.Subject} else {''});company=$version.CompanyName}
}

function Get-FileQuayUiaProxyEvidence($Record) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $client=[System.Windows.Automation.AutomationElement].Assembly
    $Record.host=@{powershell=$PSVersionTable.PSVersion.ToString();framework=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;
        path=(Get-Process -Id $PID).Path;pshome=$PSHOME}
    $Record.client=Get-FileQuayUiaAssemblyIdentity $client.Location
    $path=Join-Path $PSHOME 'UIAutomationClientSideProviders.dll'
    $Record.proxy_file=@{path=$path;exists=(Test-Path -LiteralPath $path -PathType Leaf)}
    if (-not $Record.proxy_file.exists) { throw 'The exact current PSHOME UIAutomationClientSideProviders.dll is absent; no foreign version will be loaded.' }
    $Record.proxy=Get-FileQuayUiaAssemblyIdentity $path
    Assert-FileQuayUiaProxyIdentity $Record.client $Record.proxy $PSHOME
}

function Get-FileQuayUiaBoundedExceptionText([string]$Text,[int]$Limit) {
    if ($null -eq $Text) {$Text=''}
    @{text=$(if ($Text.Length -gt $Limit) {$Text.Substring(0,$Limit)} else {$Text});
      original_chars=$Text.Length;truncated=($Text.Length -gt $Limit)}
}

function Get-FileQuayUiaExceptionEvidence([Management.Automation.ErrorRecord]$Failure) {
    if ($null -eq $Failure -or $null -eq $Failure.Exception) {throw 'Original UIA registration exception required.'}
    $exception=$Failure.Exception;$chain=[Collections.Generic.List[object]]::new()
    for ($index=0;$index -lt 8 -and $null -ne $exception;$index++) {
        $chain.Add(@{type=$exception.GetType().FullName;hresult=$exception.HResult;
            message=(Get-FileQuayUiaBoundedExceptionText $exception.Message 4096);
            stack_trace=(Get-FileQuayUiaBoundedExceptionText $exception.StackTrace 16384)})
        $exception=$exception.InnerException
    }
    @{schema_version=1;exception_text=(Get-FileQuayUiaBoundedExceptionText $Failure.Exception.ToString() 32768);
      script_stack_trace=(Get-FileQuayUiaBoundedExceptionText $Failure.ScriptStackTrace 8192);
      error_id=(Get-FileQuayUiaBoundedExceptionText $Failure.FullyQualifiedErrorId 1024);
      chain=@($chain);chain_truncated=($null -ne $exception);observed_utc=[DateTime]::UtcNow.ToString('o')}
}

function Initialize-FileQuayUiaRegistration($Record) {
    $path=Join-Path $PSScriptRoot 'UiaProxy.Register.cs'
    $source=Get-FileQuayWorkflowFile $path 16384
    $clientName=[Reflection.AssemblyName]::GetAssemblyName($Record.client.path)
    $type='FileQuayQualification.UiaProxyRegistration' -as [type]
    if ($type) {
        $owned=Get-Variable FileQuayUiaRegistrationIdentity -Scope Script -ErrorAction SilentlyContinue
        if (-not $owned -or -not [object]::ReferenceEquals($owned.Value.type,$type) -or
            $owned.Value.source.sha256 -cne $source.sha256 -or $owned.Value.source.bytes -ne $source.bytes -or
            $owned.Value.client_reference -cne $clientName.FullName) {throw 'Typed UIA caller is not bound to this exact source and verified client.'}
    } else {
        # Compile only this source against the already identity-checked host client.
        # No customer/R2R assembly or alternate framework/provider is referenced.
        $code=[IO.File]::ReadAllText($path)
        Assert-FileQuayWorkflowFile $path $source
        $types=@(Add-Type -TypeDefinition $code -ReferencedAssemblies $Record.client.path -PassThru)
        Assert-FileQuayWorkflowFile $path $source
        if ($types.Count -ne 1 -or $types[0].FullName -cne 'FileQuayQualification.UiaProxyRegistration') {throw 'Unexpected compiled UIA caller type.'}
        $type=$types[0]
        $script:FileQuayUiaRegistrationIdentity=@{type=$type;source=$source;client_reference=$clientName.FullName}
    }
    $method=$type.GetMethod('Register')
    $references=@($type.Assembly.GetReferencedAssemblies())
    if ($null -eq $method -or -not $method.IsStatic -or $method.ReturnType -ne [void] -or
        $method.GetParameters().Count -ne 1 -or $method.GetParameters()[0].ParameterType -ne [Reflection.AssemblyName] -or
        ($method.GetMethodImplementationFlags() -band [Reflection.MethodImplAttributes]::NoInlining) -eq 0 -or
        @($references | Where-Object FullName -CEQ $clientName.FullName).Count -ne 1) {throw 'Typed UIA caller lost its non-inlined direct client boundary.'}
    $Record.registration_shim=@{source_path='.github/scripts/UiaProxy.Register.cs';source_file=$source;
        assembly_identity=$type.Assembly.FullName;mvid=$type.Assembly.ManifestModule.ModuleVersionId.ToString();
        client_reference=$clientName.FullName;no_inlining=$true;assembly_references=@($references.FullName)}
}

function Register-FileQuayUiaProxy($Record) {
    Get-FileQuayUiaProxyEvidence $Record
    $path=$Record.proxy.path
    $assembly=[Reflection.Assembly]::LoadFrom($path)
    if ($assembly.Location -ine $path) { throw 'UIA proxy resolved outside its verified host file.' }
    # Use the spelling in the framework's own default proxy loader; it also
    # determines the public provider table namespace (lower-case "side").
    $name=[Reflection.AssemblyName]::new($assembly.FullName)
    $name.Name='UIAutomationClientsideProviders'
    $Record.registration_call=@{api='System.Windows.Automation.ClientSettings.RegisterClientSideProviderAssembly';
        route='source-owned typed public API (NoInlining)';assembly_name=$name.FullName;entered=$false}
    try {
        Initialize-FileQuayUiaRegistration $Record
        $Record.registration_call.entered=$true
        [FileQuayQualification.UiaProxyRegistration]::Register($name)
    } catch {
        $primary=$_
        # Capture here, before outer cleanup replaces the ErrorRecord with its
        # short message. Diagnostics must never replace the original refusal.
        try {$Record.registration_exception=Get-FileQuayUiaExceptionEvidence $primary}
        catch {$Record.registration_exception_error=(Get-FileQuayUiaBoundedExceptionText $_.Exception.Message 4096).text}
        throw $primary
    }
    foreach ($row in @($Record.client,$Record.proxy)) {
        $after=Get-FileQuayUiaAssemblyIdentity $row.path
        foreach ($key in $row.Keys) {
            if ($after[$key] -cne $row[$key]) { throw 'UIA host/proxy file changed during registration.' }
        }
    }
    $Record.registered=$true
    $Record.loaded_proxy=@{identity=$assembly.FullName;path=$assembly.Location;mvid=$assembly.ManifestModule.ModuleVersionId.ToString()}
}

function Assert-FileQuayUiaFixtureResult($Record,[string]$Nonce,[int]$ExitCode) {
    if ($Nonce -cnotmatch '^[a-f0-9]{32}$' -or $ExitCode -ne 0 -or $Record.schema_version -ne 1 -or
        $Record.nonce -cne $Nonce -or $Record.value -cne ('owned-'+$Nonce) -or
        -not ($Record.invoke_count -is [int] -or $Record.invoke_count -is [long]) -or $Record.invoke_count -ne 1 -or
        $Record.window_destroyed -isnot [bool] -or -not $Record.window_destroyed -or
        $Record.timed_out -isnot [bool] -or $Record.timed_out -or $Record.error -cne '') {
        throw 'Native UIA fixture did not independently verify one Value/Invoke action and normal owned window/process cleanup.'
    }
}
