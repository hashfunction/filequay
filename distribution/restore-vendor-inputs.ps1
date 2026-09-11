$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
$root = (Get-Location).Path + [IO.Path]::DirectorySeparatorChar
$manifest = Get-Content (Join-Path $PSScriptRoot 'vendor-inputs.json') -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw 'Unsupported vendor input manifest.' }
foreach ($item in $manifest.inputs) {
  $target = [IO.Path]::GetFullPath((Join-Path $root $item.path))
  if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Vendor path leaves the source directory.' }
  if (Test-Path $target) {
    if ((Get-FileHash $target -Algorithm SHA256).Hash -ine $item.sha256) { throw "Existing vendor input differs: $($item.path)" }
    continue
  }
  New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
  $stage = $target + '.' + [Guid]::NewGuid().ToString('N') + '.download'
  try {
    Invoke-WebRequest -Uri $item.url -OutFile $stage
    if ((Get-Item $stage).Length -ne $item.bytes -or (Get-FileHash $stage -Algorithm SHA256).Hash -ine $item.sha256) {
      throw "Vendor input hash/size mismatch: $($item.path)"
    }
    [IO.File]::Move($stage, $target, $false)
  } finally {
    if (Test-Path $stage) { Remove-Item $stage }
  }
}
Write-Output 'Exact upstream vendor inputs verified. This does not clear binary redistribution.'
