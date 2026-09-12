# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# This assembly belongs to qualification. Never load a customer composite/R2R
# component into PowerShell: CoreCLR can FailFast before cleanup is possible.
function Import-FileQuayConsumerAdapter([byte[]]$Bytes) {
    $stream=[IO.MemoryStream]::new($Bytes,$false)
    $reader=$null
    try {
        try {
            $reader=[Reflection.PortableExecutable.PEReader]::new($stream)
            if (-not $reader.HasMetadata) { throw 'Missing metadata.' }
            $metadata=[Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($reader)
        } catch { throw "Qualification adapter is not a managed PE: $($_.Exception.Message)" }
        $cor=$reader.PEHeaders.CorHeader
        if (-not ($cor.Flags -band [Reflection.PortableExecutable.CorFlags]::ILOnly) -or
            $cor.ManagedNativeHeaderDirectory.Size -ne 0 -or $cor.ManagedNativeHeaderDirectory.RelativeVirtualAddress -ne 0) {
            throw 'Qualification adapter must be IL-only, without a managed native/composite header.'
        }
        $name=$metadata.GetString($metadata.GetAssemblyDefinition().Name)
        if ($name -cne 'FileQuay.Qualification.Native') { throw 'Unexpected qualification adapter assembly identity.' }
        $references=@(foreach ($handle in $metadata.AssemblyReferences) {
            $reference=$metadata.GetString($metadata.GetAssemblyReference($handle).Name)
            if (-not $reference.StartsWith('System.',[StringComparison]::Ordinal)) { throw "Qualification adapter has a non-BCL reference: $reference" }
            $reference
        })
        $found=$false
        foreach ($handle in $metadata.TypeDefinitions) {
            $type=$metadata.GetTypeDefinition($handle)
            if ($metadata.GetString($type.Namespace) -ceq 'FileQuayQualification' -and $metadata.GetString($type.Name) -ceq 'ConsumerInput') {$found=$true}
        }
        if (-not $found) { throw 'Missing qualification adapter ConsumerInput type.' }
    } finally {
        if ($reader) {$reader.Dispose()};$stream.Dispose()
    }
    if (@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
        $_.GetName().Name -ceq 'FileQuay.Qualification.Native' -or $_.GetType('FileQuayQualification.ConsumerInput',$false)
    }).Count) { throw 'Qualification adapter identity or type is already loaded; use a fresh qualification process.' }
    # Load precisely the metadata-checked bytes. No customer publish directory is
    # consulted, and a file cannot change between PE validation and CLR loading.
    $assembly=[Reflection.Assembly]::Load($Bytes)
    $null=$assembly.GetType('FileQuayQualification.ConsumerInput',$true)
    $sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
    $script:FileQuayConsumerAdapterIdentity=@{assembly=$assembly;sha256=$sha}
    return @{loaded=$true;il_only=$true;assembly_sha256=$sha;assembly_name=$name;assembly_references=$references}
}

function Assert-FileQuayConsumerAdapter([System.Collections.IDictionary]$Evidence) {
    $identity=Get-Variable -Name FileQuayConsumerAdapterIdentity -Scope Script -ErrorAction SilentlyContinue
    if (-not $identity -or -not $Evidence -or -not $Evidence.loaded -or -not $Evidence.il_only -or
        $identity.Value.sha256 -cne $Evidence.assembly_sha256 -or
        -not [object]::ReferenceEquals([FileQuayQualification.ConsumerInput].Assembly,$identity.Value.assembly)) {
        throw 'Missing or mismatched loaded adapter evidence.'
    }
}

function Initialize-FileQuayConsumerAdapter([string]$Root,[string]$Work,[string]$DotNet='dotnet') {
    $sourceDirectory='tests/Files.Qualification.Native'
    $relativeProject="$sourceDirectory/FileQuay.Qualification.Native.csproj"
    $inputs=@('global.json','Directory.Build.props','Directory.Packages.props',
        '.github/scripts/ConsumerWorkflow.Native.cs','src/Files.App.CsWin32/NativeMethods.json',
        'src/Files.App.CsWin32/NativeMethods.txt',"$sourceDirectory/NativeMethods.txt",
        "$sourceDirectory/packages.lock.json",$relativeProject)
    $hashes=@(foreach ($relative in $inputs) {
        @{path=$relative;sha256=(Get-FileHash -LiteralPath (Join-Path $Root $relative) -Algorithm SHA256).Hash}
    })
    $subset=@(Get-Content (Join-Path $Root "$sourceDirectory/NativeMethods.txt") | Where-Object {$_ -match '\S'})
    $production=@(Get-Content (Join-Path $Root 'src/Files.App.CsWin32/NativeMethods.txt'))
    $adapterSource=Get-Content (Join-Path $Root '.github/scripts/ConsumerWorkflow.Native.cs') -Raw
    $calls=@([regex]::Matches($adapterSource,'\bPInvoke\.(\w+)\(') | ForEach-Object {$_.Groups[1].Value} | Sort-Object -Unique)
    # Exact qualification-only focus observation; customer interop inputs stay unchanged.
    $allowed=@($production)+@('GetGUIThreadInfo')
    if (@(Compare-Object $subset $calls -CaseSensitive).Count -or @($subset | Where-Object {$_ -cnotin $allowed}).Count) {
        throw 'Qualification API subset differs from the adapter calls or allowed source-owned CsWin32 inputs.'
    }
    [xml]$central=Get-Content (Join-Path $Root 'Directory.Packages.props') -Raw
    $pin=@($central.Project.ItemGroup.PackageVersion | Where-Object Include -CEQ 'Microsoft.Windows.CsWin32')
    if ($pin.Count -ne 1) { throw 'Missing unique central CsWin32 pin.' }
    $dotnetCommand=(Get-Command $DotNet -CommandType Application -ErrorAction Stop).Source
    $output=Join-Path $Work 'consumer-native-adapter'
    $null=New-Item -ItemType Directory -Path $output -ErrorAction Stop
    $intermediate=Join-Path $output 'obj/'
    $binaryDirectory=Join-Path $output 'bin'
    Push-Location $Root
    try {
        $sdkOutput=& $dotnetCommand --version
        if ($LASTEXITCODE -ne 0 -or ($sdkOutput -join '').Trim() -cne (Get-Content global.json -Raw | ConvertFrom-Json).sdk.version) { throw 'Qualification adapter SDK differs from global.json.' }
        $buildOutput=& $dotnetCommand build $relativeProject -c Release --output $binaryDirectory "-p:BaseIntermediateOutputPath=$intermediate" '-p:RestoreLockedMode=true' '-v:quiet' '-clp:ErrorsOnly' 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('Qualification adapter build failed: '+(($buildOutput | Select-Object -Last 20) -join "`n")) }
    } finally {Pop-Location}
    foreach ($input in $hashes) {
        if ((Get-FileHash -LiteralPath (Join-Path $Root $input.path) -Algorithm SHA256).Hash -cne $input.sha256) { throw 'Qualification adapter source changed during build.' }
    }
    $assets=Get-Content (Join-Path $intermediate 'project.assets.json') -Raw | ConvertFrom-Json
    $resolved=@($assets.libraries.PSObject.Properties.Name | Where-Object {$_ -clike 'Microsoft.Windows.CsWin32/*'})
    if ($resolved.Count -ne 1 -or $resolved[0] -cne "Microsoft.Windows.CsWin32/$($pin[0].Version)") { throw 'Qualification adapter source generator differs from central pin.' }
    $assemblyPath=Join-Path $binaryDirectory 'FileQuay.Qualification.Native.dll'
    if (@(Get-ChildItem -LiteralPath $binaryDirectory -Filter '*.dll' -Recurse | Where-Object {$_.FullName -cne $assemblyPath}).Count) { throw 'Unexpected runtime assembly in isolated qualification adapter output.' }
    $result=Import-FileQuayConsumerAdapter ([IO.File]::ReadAllBytes($assemblyPath))
    $result.assembly_path=$assemblyPath
    $result.source_inputs=$hashes
    $result.cswin32_version=[string]$pin[0].Version
    $result.sdk_version=($sdkOutput -join '').Trim()
    Assert-FileQuayConsumerAdapter $result
    return $result
}
