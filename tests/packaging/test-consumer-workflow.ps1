# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Helpers.ps1')

function Require-Failure([scriptblock]$Action, [string]$Label) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    if (-not $failed) { throw "Accepted invalid workflow evidence: $Label" }
}
function New-Receipt($Fixture, [int]$Operation, [string]$Id) {
    $from = if ($Operation -eq 3) { $Fixture.source } else { $Fixture.copied }
    $to = if ($Operation -eq 3) { $Fixture.copied } else { $Fixture.moved }
    [ordered]@{
        schemaVersion=1; id=$Id; startedAtUtc='2026-09-12T05:00:01.0000000+00:00'
        completedAtUtc='2026-09-12T05:00:02.0000000+00:00'; fileOperationType=$Operation
        returnResult=1; sourcePaths=@($from); destinationPaths=@($to)
        itemCount=1; totalBytes=73; failureCode=$null
    }
}
function Write-History([string]$Path, $Receipts) {
    [IO.File]::WriteAllText($Path, (@{schemaVersion=1;receipts=@($Receipts)} | ConvertTo-Json -Depth 5))
}
function Write-Csv([string]$Path, $Receipts) {
    $rows = foreach ($r in $Receipts) {
        [pscustomobject][ordered]@{
            Id=$r.id; StartedAtUtc=$r.startedAtUtc; CompletedAtUtc=$r.completedAtUtc
            Operation=$(if ($r.fileOperationType -eq 3) {'Copy'} else {'Move'}); Result='Success'
            ItemCount=[string]$r.itemCount; TotalBytes=[string]$r.totalBytes
            SourcePaths=$r.sourcePaths[0]; DestinationPaths=$r.destinationPaths[0]; FailureCode=''
        }
    }
    [IO.File]::WriteAllText($Path, (($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n") + "`r`n")
}

$temporaryBase = if ($IsMacOS) { '/private/tmp' } else { [IO.Path]::GetTempPath() }
$parent = Join-Path $temporaryBase ('filequay-workflow-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $parent
$checks = 0
try {
    $fixture = New-FileQuayWorkflowFixture $parent
    $original = [IO.File]::ReadAllBytes($fixture.source)
    Assert-FileQuayWorkflowFiles $fixture 'Initial'; $checks++
    [IO.File]::Copy($fixture.source, $fixture.copied)
    Assert-FileQuayWorkflowFiles $fixture 'Copied'; $checks++
    [IO.File]::WriteAllText($fixture.copied, 'wrong bytes')
    Require-Failure { Assert-FileQuayWorkflowFiles $fixture 'Copied' } 'changed copied bytes'; $checks++
    [IO.File]::WriteAllBytes($fixture.copied, $original)
    [IO.File]::Move($fixture.copied, $fixture.moved)
    Assert-FileQuayWorkflowFiles $fixture 'Moved'; $checks++
    [IO.File]::Copy($fixture.source, $fixture.copied)
    Require-Failure { Assert-FileQuayWorkflowFiles $fixture 'Moved' } 'copy remained after move'; $checks++
    [IO.File]::Delete($fixture.copied)
    [IO.File]::WriteAllText($fixture.source, 'changed original')
    Require-Failure { Assert-FileQuayWorkflowFiles $fixture 'Moved' } 'original changed'; $checks++
    [IO.File]::WriteAllBytes($fixture.source, $original)

    $history = Join-Path $parent 'history.json'
    $first = New-Receipt $fixture 3 '11111111-1111-4111-8111-111111111111'
    $second = New-Receipt $fixture 4 '22222222-2222-4222-8222-222222222222'
    $start = [DateTimeOffset]'2026-09-12T05:00:00Z'; $end = [DateTimeOffset]'2026-09-12T05:00:03Z'
    Write-History $history @($second,$first)
    $receipts = @(Read-FileQuayWorkflowReceipts $history $fixture 2 $start $end); $checks++
    if ($receipts.Count -ne 2) { throw 'Did not return both independent receipts.' }
    foreach ($mutation in @('duplicate-id','duplicate-operation','missing','wrong-source','wrong-destination','failed','negative-count','string-result','wrong-schema','outside-time','inverted-time')) {
        $a = [ordered]@{} + $first; $b = [ordered]@{} + $second; $rows=@($a,$b)
        switch ($mutation) {
            'duplicate-id' { $b.id=$a.id }
            'duplicate-operation' { $b.fileOperationType=3 }
            'missing' { $rows=@($a) }
            'wrong-source' { $b.sourcePaths=@($fixture.source) }
            'wrong-destination' { $a.destinationPaths=@($fixture.moved) }
            'failed' { $a.returnResult=4 }
            'negative-count' { $a.itemCount=-1 }
            'string-result' { $a.returnResult='1' }
            'wrong-schema' { $a.schemaVersion=2 }
            'outside-time' { $a.startedAtUtc='2026-09-12T04:00:00Z' }
            'inverted-time' { $a.completedAtUtc='2026-09-12T05:00:00Z' }
        }
        Write-History $history $rows
        Require-Failure { Read-FileQuayWorkflowReceipts $history $fixture 2 $start $end } $mutation; $checks++
    }
    Write-History $history @($first,$second)
    $csv = Join-Path $parent 'independent.csv'
    Write-Csv $csv @($first,$second)
    Assert-FileQuayWorkflowCsv $csv $receipts; $checks++
    foreach ($mutation in @('wrong-content','missing-row','duplicate-row','wrong-columns','extra-column','malformed-quote')) {
        Write-Csv $csv @($first,$second)
        switch ($mutation) {
            'wrong-content' { [IO.File]::WriteAllText($csv, [IO.File]::ReadAllText($csv).Replace('Success','Cancelled')) }
            'missing-row' { Write-Csv $csv @($first) }
            'duplicate-row' { Write-Csv $csv @($first,$first) }
            'wrong-columns' { [IO.File]::WriteAllText($csv, [IO.File]::ReadAllText($csv).Replace('DestinationPaths','OtherPaths')) }
            'extra-column' { [IO.File]::WriteAllText($csv, [IO.File]::ReadAllText($csv).Replace('"Success"','"Success","extra"')) }
            'malformed-quote' { [IO.File]::AppendAllText($csv, '"unterminated') }
        }
        Require-Failure { Assert-FileQuayWorkflowCsv $csv $receipts } "CSV $mutation"; $checks++
    }

    $scope = @{app_pid=71;main_hwnd=101;target_pid=72;target_hwnd=202}
    $state = @{
        app_live=$true;target_process_live=$true;main_live=$true;main_pid=71
        target_live=$true;target_pid=72;target_visible=$true;target_enabled=$true
        target_hwnd=202;foreground_hwnd=202;owner_chain=@(202,101)
        element_pid=72;element_hwnd=202;element_within_target=$true;element_visible=$true;element_enabled=$true
    }
    Assert-FileQuayWorkflowTarget $scope $state; $checks++
    foreach ($mutation in @('app-exited','main-reused','target-reused','wrong-hwnd','foreign-owner','foreign-foreground','foreign-element','sibling-window','outside-root','hidden','disabled','target-exited')) {
        $bad = @{} + $state
        switch ($mutation) {
            'app-exited' { $bad.app_live=$false }
            'main-reused' { $bad.main_pid=73 }
            'target-reused' { $bad.target_pid=73 }
            'wrong-hwnd' { $bad.target_hwnd=203 }
            'foreign-owner' { $bad.owner_chain=@(202,303) }
            'foreign-foreground' { $bad.foreground_hwnd=303 }
            'foreign-element' { $bad.element_pid=73 }
            'sibling-window' { $bad.element_hwnd=203 }
            'outside-root' { $bad.element_within_target=$false }
            'hidden' { $bad.element_visible=$false }
            'disabled' { $bad.target_enabled=$false }
            'target-exited' { $bad.target_process_live=$false }
        }
        Require-Failure { Assert-FileQuayWorkflowTarget $scope $bad } "UI $mutation"; $checks++
    }
    $marker = Join-Path $fixture.root '.filequay-workflow-owner'
    [IO.File]::WriteAllText($marker, 'foreign owner')
    Require-Failure { Remove-FileQuayWorkflowFixture $fixture } 'changed ownership marker'; $checks++
    if (-not (Test-Path -LiteralPath $fixture.source)) { throw 'Failed ownership check removed original.' }
    [IO.File]::WriteAllText($marker, $fixture.token)
    $extra = Join-Path $fixture.root 'unowned.txt'; [IO.File]::WriteAllText($extra, 'preserve')
    Require-Failure { Remove-FileQuayWorkflowFixture $fixture } 'unexpected file'; $checks++
    if ([IO.File]::ReadAllText($extra) -cne 'preserve') { throw 'Unexpected file was removed.' }
    [IO.File]::Delete($extra)
    $outside = Join-Path $parent 'outside'; $null=New-Item -ItemType Directory $outside
    [IO.File]::WriteAllText((Join-Path $outside 'preserve.txt'), 'outside target')
    $link = Join-Path $fixture.root 'linked'
    if ($IsWindows) { $null=New-Item -ItemType Junction -Path $link -Target $outside }
    else { $null=New-Item -ItemType SymbolicLink -Path $link -Target $outside }
    Require-Failure { Remove-FileQuayWorkflowFixture $fixture } 'actual linked directory'; $checks++
    if ([IO.File]::ReadAllText((Join-Path $outside 'preserve.txt')) -cne 'outside target') { throw 'Cleanup touched a link target.' }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $link -Force
    $recovery = $fixture.csv + '.' + [Guid]::NewGuid().ToString('N') + '.filequay-original'
    [IO.File]::Move($fixture.csv, $recovery)
    Write-Csv $fixture.csv $receipts
    Register-FileQuayWorkflowExport $fixture $receipts $recovery; $checks++
    $state=@{fixture=$fixture}; $record=@{owned_process_cleanup_verified=$false;consumer_fixture_cleanup_verified=$false;consumer_workflow=@{cleanup_verified=$false}}
    Require-Failure { Complete-FileQuayWorkflowFixtureCleanup $state $record } 'cleanup before retained process stops'; $checks++
    if (-not (Test-Path -LiteralPath $fixture.source)) { throw 'Live-process refusal removed fixture data.' }
    $record.owned_process_cleanup_verified=$true
    Complete-FileQuayWorkflowFixtureCleanup $state $record; $checks++
    if (-not $record.consumer_fixture_cleanup_verified -or -not $record.consumer_workflow.cleanup_verified) { throw 'Actual cleanup did not record both success facts.' }
    if (Test-Path -LiteralPath $fixture.root) { throw 'Owned fixture remains.' }
    "Consumer workflow independent boundary checks passed: $checks. No native UI invoked."
} finally {
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $parent -Recurse -Force
}
