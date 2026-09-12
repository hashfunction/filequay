# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
param([string]$EvidenceDirectory='artifacts/qualification/uia-proxy-preflight')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:CI -ne 'true' -or $PSVersionTable.PSVersion.Major -ne 7) {throw 'Requires the isolated Windows PowerShell 7 CI host.'}
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'ConsumerWorkflow.Helpers.ps1')
. (Join-Path $PSScriptRoot 'ConsumerWorkflow.Adapter.ps1')
. (Join-Path $PSScriptRoot 'UiaProxy.Helpers.ps1')
. (Join-Path $PSScriptRoot 'UiaProxy.Fixture.ps1')
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory,$root)
$null=New-Item -ItemType Directory -Path $evidence -ErrorAction Stop
$work=Join-Path $root ('artifacts/uia-proxy-preflight/'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work -Force
$record=@{passed=$false;consumer_acceptance=$false;source_commit=$env:GITHUB_SHA;error=''}
try {
    $adapter=Initialize-FileQuayConsumerAdapter $root $work
    $record.adapter=$adapter
    Invoke-FileQuayUiaProxyPreflight $root $work $adapter $record
} catch {$record.error=$_.Exception.Message;throw}
finally {$record | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $evidence 'uia-proxy-preflight.json') -Encoding utf8NoBOM}
