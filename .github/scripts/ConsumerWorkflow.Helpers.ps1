# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
function Assert-FileQuayWorkflowAncestors([string]$Path) {
    $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)); $count=0
    while ($parent) {
        if (++$count -gt 64) { throw 'Workflow path exceeds its ancestor budget.' }
        if (Test-Path -LiteralPath $parent) {
            $entry = Get-Item -LiteralPath $parent -Force
            if (-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Workflow path has a substituted ancestor: $parent" }
        }
        $parent = [IO.Path]::GetDirectoryName($parent)
    }
}

function Get-FileQuayWorkflowFile([string]$Path, [long]$MaximumBytes=1048576) {
    Assert-FileQuayWorkflowAncestors $Path
    $file = Get-Item -LiteralPath $Path -Force
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt $MaximumBytes) {
        throw "Workflow file is not a bounded regular file: $Path"
    }
    @{ bytes=$file.Length; sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
}

function Assert-FileQuayWorkflowFile([string]$Path, $Expected) {
    $actual = Get-FileQuayWorkflowFile $Path
    if ($actual.bytes -ne $Expected.bytes -or $actual.sha256 -cne $Expected.sha256) { throw "Workflow file bytes differ: $Path" }
}

function New-FileQuayWorkflowFixture([string]$ParentDirectory) {
    $parent = Get-Item -LiteralPath $ParentDirectory -Force
    if (-not $parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Fixture parent is not a regular directory.' }
    $root = Join-Path $parent.FullName ('consumer-workflow-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $root
    $token = [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText((Join-Path $root '.filequay-workflow-owner'), $token)
    foreach ($name in @('source','copy','move','export')) { $null = New-Item -ItemType Directory -Path (Join-Path $root $name) }
    $fixture = @{
        root=$root;token=$token;directories=@('source','copy','move','export');files=@{}
        source=(Join-Path $root 'source/résumé,原稿.txt');copied=(Join-Path $root 'copy/résumé,原稿.txt')
        moved=(Join-Path $root 'move/résumé,原稿.txt');csv=(Join-Path $root 'export/receipts.csv')
    }
    [IO.File]::WriteAllBytes($fixture.source, [Text.Encoding]::UTF8.GetBytes("FileQuay owned Unicode fixture. Keep the original.`r`nOriginal: 原稿 / résumé.`r`n"))
    foreach ($name in @('source','copy','move')) {
        [IO.File]::WriteAllText((Join-Path $root "$name/protected.txt"), "Protected $name sentinel $token")
    }
    [IO.File]::WriteAllText($fixture.csv, "Previous CSV destination $token")
    foreach ($path in @($fixture.source,$fixture.csv,(Join-Path $root 'source/protected.txt'),(Join-Path $root 'copy/protected.txt'),(Join-Path $root 'move/protected.txt'))) {
        $fixture.files[[IO.Path]::GetRelativePath($root,$path)] = Get-FileQuayWorkflowFile $path
    }
    $fixture.payload = Get-FileQuayWorkflowFile $fixture.source
    $fixture.previous_csv = Get-FileQuayWorkflowFile $fixture.csv
    $fixture.files[[IO.Path]::GetRelativePath($root,$fixture.copied)] = $fixture.payload
    $fixture.files[[IO.Path]::GetRelativePath($root,$fixture.moved)] = $fixture.payload
    $fixture
}

function Get-FileQuayWorkflowTree($Fixture) {
    Assert-FileQuayWorkflowAncestors $Fixture.root
    $root = Get-Item -LiteralPath $Fixture.root -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Fixture ownership root was substituted.' }
    $marker = Join-Path $root.FullName '.filequay-workflow-owner'
    $null = Get-FileQuayWorkflowFile $marker 128
    if ([IO.File]::ReadAllText($marker) -cne $Fixture.token) { throw 'Fixture ownership marker changed.' }
    $pending = [Collections.Generic.Queue[string]]::new(); $pending.Enqueue($root.FullName)
    $files = @{}; $directories = [Collections.Generic.List[string]]::new(); $seen = 0
    while ($pending.Count) {
        foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($pending.Dequeue())) {
            if (++$seen -gt 32) { throw 'Fixture exceeds its bounded entry budget.' }
            $entry = Get-Item -LiteralPath $path -Force
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Fixture contains a link or reparse point: $path" }
            $relative = [IO.Path]::GetRelativePath($root.FullName,$path)
            if ($entry.PSIsContainer) {
                if ($relative -cnotin $Fixture.directories) { throw "Unexpected fixture directory: $relative" }
                $directories.Add($relative); $pending.Enqueue($path)
            } elseif ($relative -cne '.filequay-workflow-owner') {
                if (-not $Fixture.files.ContainsKey($relative)) { throw "Unexpected fixture file: $relative" }
                Assert-FileQuayWorkflowFile $path $Fixture.files[$relative]
                $files[$relative] = $Fixture.files[$relative]
            }
        }
    }
    @{ files=$files;directories=$directories.ToArray() }
}

function Assert-FileQuayWorkflowFiles($Fixture, [ValidateSet('Initial','Copied','Moved')][string]$Phase) {
    $null = Get-FileQuayWorkflowTree $Fixture
    foreach ($path in @($Fixture.source,(Join-Path $Fixture.root 'source/protected.txt'),(Join-Path $Fixture.root 'copy/protected.txt'),(Join-Path $Fixture.root 'move/protected.txt'),$Fixture.csv)) {
        Assert-FileQuayWorkflowFile $path $Fixture.files[[IO.Path]::GetRelativePath($Fixture.root,$path)]
    }
    foreach ($item in @(@($Fixture.copied,($Phase -eq 'Copied')),@($Fixture.moved,($Phase -eq 'Moved')))) {
        if ((Test-Path -LiteralPath $item[0]) -ne $item[1]) { throw "Workflow $Phase presence differs: $($item[0])" }
        if ($item[1]) { Assert-FileQuayWorkflowFile $item[0] $Fixture.payload }
    }
}

function Remove-FileQuayWorkflowFixture($Fixture) {
    $tree = Get-FileQuayWorkflowTree $Fixture
    foreach ($relative in $tree.files.Keys) { [IO.File]::Delete((Join-Path $Fixture.root $relative)) }
    foreach ($relative in ($tree.directories | Sort-Object Length -Descending)) { [IO.Directory]::Delete((Join-Path $Fixture.root $relative)) }
    [IO.File]::Delete((Join-Path $Fixture.root '.filequay-workflow-owner'))
    [IO.Directory]::Delete($Fixture.root)
}

function Complete-FileQuayWorkflowFixtureCleanup($State, [System.Collections.IDictionary]$Record) {
    if ($State.fixture) {
        if (-not $Record.owned_process_cleanup_verified) { throw 'The consumer fixture is preserved because owned process cleanup was not verified.' }
        Remove-FileQuayWorkflowFixture $State.fixture
        $Record.consumer_fixture_cleanup_verified=$true
        $Record.consumer_workflow.cleanup_verified=$true
    }
}

function Read-FileQuayWorkflowReceipts([string]$Path, $Fixture, [int]$ExpectedCount, [DateTimeOffset]$Started, [DateTimeOffset]$Until) {
    if ($ExpectedCount -eq 0 -and -not (Test-Path -LiteralPath $Path)) { return }
    $null = Get-FileQuayWorkflowFile $Path
    $document = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false,$true)) | ConvertFrom-Json -AsHashtable -DateKind String -ErrorAction Stop
    if ($document.schemaVersion -isnot [long] -or $document.schemaVersion -ne 1 -or $document.Keys.Count -ne 2 -or -not $document.Contains('receipts') -or
        $document.receipts -isnot [array] -or $document.receipts.Count -ne $ExpectedCount) { throw 'Receipt history schema/count differs.' }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $operations = [Collections.Generic.HashSet[int]]::new()
    foreach ($r in $document.receipts) {
        $id = [Guid]::Parse($r.id)
        $start = [DateTimeOffset]::Parse($r.startedAtUtc, [Globalization.CultureInfo]::InvariantCulture)
        $end = [DateTimeOffset]::Parse($r.completedAtUtc, [Globalization.CultureInfo]::InvariantCulture)
        if ($r.schemaVersion -isnot [long] -or $r.schemaVersion -ne 1 -or $r.Keys.Count -ne 11 -or $id -eq [Guid]::Empty -or -not $ids.Add($id.ToString()) -or
            $r.fileOperationType -isnot [long] -or $r.returnResult -isnot [long] -or
            $r.fileOperationType -notin @(3,4) -or -not $operations.Add($r.fileOperationType) -or $r.returnResult -ne 1 -or $null -ne $r.failureCode -or
            $r.itemCount -isnot [long] -or $r.totalBytes -isnot [long] -or $r.itemCount -lt 0 -or $r.totalBytes -lt 0 -or
            $start -lt $Started -or $end -gt $Until -or $end -lt $start) { throw 'Receipt identity/result/time/reported-count contract differs.' }
        $expectedSource = if ($r.fileOperationType -eq 3) { $Fixture.source } else { $Fixture.copied }
        $expectedDestination = if ($r.fileOperationType -eq 3) { $Fixture.copied } else { $Fixture.moved }
        if ($r.sourcePaths -isnot [array] -or $r.destinationPaths -isnot [array] -or
            $r.sourcePaths.Count -ne 1 -or $r.destinationPaths.Count -ne 1 -or
            $r.sourcePaths[0] -cne $expectedSource -or $r.destinationPaths[0] -cne $expectedDestination) { throw 'Receipt selected paths differ.' }
    }
    if ($ExpectedCount -gt 0 -and -not $operations.Contains(3)) { throw 'Copy receipt is missing.' }
    if ($ExpectedCount -eq 2 -and -not $operations.Contains(4)) { throw 'Move receipt is missing.' }
    $document.receipts
}

function Assert-FileQuayWorkflowCsv([string]$Path, [object[]]$Receipts) {
    $null = Get-FileQuayWorkflowFile $Path
    $columns = @('Id','StartedAtUtc','CompletedAtUtc','Operation','Result','ItemCount','TotalBytes','SourcePaths','DestinationPaths','FailureCode')
    $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($Path, [Text.UTF8Encoding]::new($false,$true), $true)
    try {
        $parser.SetDelimiters(','); $parser.HasFieldsEnclosedInQuotes=$true; $parser.TrimWhiteSpace=$false
        $header = $parser.ReadFields()
        if ($header.Count -ne $columns.Count -or [string]::Join('|',$header) -cne [string]::Join('|',$columns)) { throw 'CSV columns differ.' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        while (-not $parser.EndOfData) {
            $fields = $parser.ReadFields()
            if ($fields.Count -ne 10 -or -not $seen.Add($fields[0])) { throw 'CSV row width/identity differs.' }
            $matches = @($Receipts | Where-Object { $_.id -ceq $fields[0] })
            if ($matches.Count -ne 1) { throw 'CSV does not match a persisted receipt.' }
            $r = $matches[0]
            $expected = @($r.id,$r.startedAtUtc,$r.completedAtUtc,$(if ($r.fileOperationType -eq 3) {'Copy'} else {'Move'}),'Success',
                [string]$r.itemCount,[string]$r.totalBytes,([string]::Join("`n",[string[]]$r.sourcePaths)),([string]::Join("`n",[string[]]$r.destinationPaths)),'')
            for ($i=0; $i -lt 10; $i++) {
                if ($i -in @(1,2)) {
                    if ([DateTimeOffset]::Parse($fields[$i]) -ne [DateTimeOffset]::Parse($expected[$i])) { throw 'CSV timestamp differs.' }
                } elseif ($fields[$i] -cne $expected[$i]) { throw "CSV $($columns[$i]) differs." }
            }
        }
        if ($seen.Count -ne $Receipts.Count -or $seen.Count -ne 2) { throw 'CSV receipt count differs.' }
    } finally { $parser.Dispose() }
}

function Register-FileQuayWorkflowExport($Fixture, [object[]]$Receipts, [string]$Recovery) {
    Assert-FileQuayWorkflowCsv $Fixture.csv $Receipts
    $expectedPattern = '^' + [regex]::Escape($Fixture.csv) + '\.[0-9a-f]{32}\.filequay-original$'
    if ($Recovery -cnotmatch $expectedPattern) { throw 'CSV recovery is not the expected owned sibling.' }
    Assert-FileQuayWorkflowFile $Recovery $Fixture.previous_csv
    $Fixture.files[[IO.Path]::GetRelativePath($Fixture.root,$Fixture.csv)] = Get-FileQuayWorkflowFile $Fixture.csv
    $Fixture.files[[IO.Path]::GetRelativePath($Fixture.root,$Recovery)] = Get-FileQuayWorkflowFile $Recovery
}

function Assert-FileQuayWorkflowTarget($Scope, $State) {
    if (-not $State.app_live -or -not $State.target_process_live -or -not $State.main_live -or $State.main_pid -ne $Scope.app_pid -or
        -not $State.target_live -or $State.target_pid -ne $Scope.target_pid -or $State.target_hwnd -ne $Scope.target_hwnd -or
        -not $State.target_visible -or -not $State.target_enabled -or $State.foreground_hwnd -ne $Scope.target_hwnd -or
        $State.owner_chain.Count -lt 1 -or $State.owner_chain.Count -gt 8 -or $State.owner_chain[0] -ne $Scope.target_hwnd -or
        $Scope.main_hwnd -notin $State.owner_chain -or $State.element_pid -ne $Scope.target_pid -or $State.element_hwnd -ne $Scope.target_hwnd -or -not $State.element_within_target -or
        -not $State.element_visible -or -not $State.element_enabled) { throw 'Workflow input target ownership, foreground, or UI state changed.' }
}
