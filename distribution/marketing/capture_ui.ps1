# Copyright 2026 Trieflow LLC. MIT. Existing normal app interactions and unedited pixels.
function Assert-FolderSailMarketingFrame($Value,[int]$ExpectedPid,[long]$Main) {
    if($Value.pid -ne $ExpectedPid -or $Value.hwnd -ne $Main -or $Value.foreground -ne $Main -or
       -not $Value.visible -or -not $Value.enabled -or -not $Value.maximized -or $Value.dpi -ne 96 -or
       -not ([string]$Value.title).EndsWith('FolderSail',[StringComparison]::Ordinal) -or
       [string]::IsNullOrWhiteSpace($Value.class) -or $Value.hit_roots.Count -ne 9 -or
       @($Value.hit_roots|Where-Object {$_ -ne $Main}).Count){throw 'Actual capture window ownership/foreground/occlusion differs'}
    foreach($r in @($Value.bounds,$Value.desktop,$Value.work_area)){
        if($r.Count -ne 4 -or @($r|Where-Object {[double]::IsNaN($_) -or [double]::IsInfinity($_)}).Count -or
           $r[2] -le 0 -or $r[3] -le 0 -or $r[2] -gt 8192 -or $r[3] -gt 8192){throw 'Invalid native capture rectangle'}
    }
    $b=$Value.bounds;$a=$Value.work_area;$d=$Value.desktop
    if($d[2] -lt 1920 -or $d[3] -lt 1080 -or $b[2] -lt 1800 -or $b[3] -lt 1000 -or
       $b[0] -lt $a[0] -or $b[1] -lt $a[1] -or $b[0]+$b[2] -gt $a[0]+$a[2] -or $b[1]+$b[3] -gt $a[1]+$a[3] -or
       $a[0] -lt $d[0] -or $a[1] -lt $d[1] -or $a[0]+$a[2] -gt $d[0]+$d[2] -or $a[1]+$a[3] -gt $d[1]+$d[3]){throw 'Capture does not contain the complete visible native window'}
    if($Value.required.Count -lt 1){throw 'No meaningful visible content was bound to this screenshot'}
    foreach($item in $Value.required){
        $r=$item.bounds;$clip=if($item.ContainsKey('clip')){$item.clip}else{$b}
        if(-not $item.visible -or $item.pid -ne $ExpectedPid -or $r.Count -ne 4 -or $r[2] -le 0 -or $r[3] -le 0 -or
           @(@($r)+@($clip)|Where-Object {[double]::IsNaN($_) -or [double]::IsInfinity($_)}).Count -or
           $clip.Count -ne 4 -or $clip[2] -le 0 -or $clip[3] -le 0 -or
           $clip[0] -lt $b[0] -or $clip[1] -lt $b[1] -or $clip[0]+$clip[2] -gt $b[0]+$b[2] -or $clip[1]+$clip[3] -gt $b[1]+$b[3] -or
           $r[0] -lt $clip[0] -or $r[1] -lt $clip[1] -or $r[0]+$r[2] -gt $clip[0]+$clip[2] -or $r[1]+$r[3] -gt $clip[1]+$clip[3]){throw 'Required screenshot content is clipped, foreign or hidden'}
    }
}

function Get-FolderSailMarketingFrame($State,[object[]]$Required){
    Assert-FolderSailMarketingProcess $State
    $value=[FolderSailMarketing.Native]::Frame($State.ui.main_hwnd)
    $screen=[Windows.Forms.Screen]::FromHandle([IntPtr]$State.ui.main_hwnd);$a=$screen.WorkingArea;$d=$screen.Bounds
    $value['work_area']=@($a.X,$a.Y,$a.Width,$a.Height);$value['desktop']=@($d.X,$d.Y,$d.Width,$d.Height)
    $value['required']=@(foreach($binding in $Required){
        $observed=Get-FileQuayWorkflowTargetState $State.ui $binding
        # A visible WinUI flyout can use an owned non-foreground child window.
        # This is observation only; every input still uses the original stricter
        # input target helper with its own exact foreground requirement.
        if(-not $observed.app_live -or -not $observed.main_live -or $observed.main_pid -ne $State.process.Id -or
           -not $observed.target_process_live -or -not $observed.target_live -or -not $observed.target_visible -or
           $observed.target_pid -ne $State.process.Id -or $observed.target_hwnd -ne $binding.scope.target_hwnd -or
           $State.ui.main_hwnd -notin $observed.owner_chain -or -not $observed.element_within_target -or
           $observed.element_pid -ne $State.process.Id -or -not $observed.element_visible -or -not $observed.element_enabled){throw 'Required visible capture element ownership changed'}
        $current=$binding.element.Current;$r=$current.BoundingRectangle
        $item=@{id=$current.AutomationId;name=$current.Name;pid=$current.ProcessId;visible=(-not $current.IsOffscreen);
          bounds=@($r.X,$r.Y,$r.Width,$r.Height);runtime_id=@($binding.element.GetRuntimeId())}
        if($binding.ContainsKey('clip')){
            $clipState=Get-FileQuayWorkflowTargetState $State.ui $binding.clip
            if(-not $clipState.element_within_target -or $clipState.element_pid -ne $State.process.Id -or
               -not $clipState.app_live -or -not $clipState.target_live -or $clipState.target_pid -ne $State.process.Id -or
               $State.ui.main_hwnd -notin $clipState.owner_chain){throw 'Receipt viewport window ownership changed'}
            $clip=$binding.clip.element.Current;$r=$clip.BoundingRectangle
            if($clip.ProcessId -ne $State.process.Id -or $clip.IsOffscreen){throw 'Receipt viewport ownership/visibility changed'}
            $item.clip=@($r.X,$r.Y,$r.Width,$r.Height)
        }
        $item
    })
    return $value
}

function Move-FolderSailMarketingPointer($State,[object[]]$Required){
    $frame=Get-FolderSailMarketingFrame $State $Required
    Assert-FolderSailMarketingFrame $frame $State.process.Id $State.ui.main_hwnd
    # The observed frame center is one of the native ownership/hit-test points.
    # Move once without a click, then allow a short cosmetic settling interval.
    # This does not claim tooltip absence; original pixels need visual review.
    $point=[Drawing.Point]::new($frame.bounds[0]+[int]($frame.bounds[2]/2),$frame.bounds[1]+[int]($frame.bounds[3]/2))
    [Windows.Forms.Cursor]::Position=$point
    $actual=[Windows.Forms.Cursor]::Position
    if($actual.X -ne $point.X -or $actual.Y -ne $point.Y){throw 'Owned neutral pointer readback differs'}
    $settling=[Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 500
    $settling.Stop()
    $actual=[Windows.Forms.Cursor]::Position
    if($actual.X -ne $point.X -or $actual.Y -ne $point.Y){throw 'Owned neutral pointer changed during settling'}
    $current=Get-FolderSailMarketingFrame $State $Required
    Assert-FolderSailMarketingFrame $current $State.process.Id $State.ui.main_hwnd
    if(-not $State.record.Contains('pointer_observations')){$State.record.pointer_observations=@()}
    $State.record.pointer_observations+=@(@{x=$point.X;y=$point.Y;move_count=1;pointer_readback_verified=$true;
        settling_delay_ms=500;settling_elapsed_ms=$settling.ElapsedMilliseconds})
}

function Save-FolderSailMarketingFrame($State,[string]$Stem,[object[]]$Required,[string]$Caption){
    if($Stem -cnotin @('01-folder-workspace','02-operation-receipts','03-export-receipts')){throw 'Unknown marketing screenshot slot'}
    [FileQuayQualification.ConsumerInput]::Foreground($State.process,$State.ui.main_hwnd,$State.process,$State.ui.main_hwnd)
    Move-FolderSailMarketingPointer $State $Required
    $before=Get-FolderSailMarketingFrame $State $Required
    Assert-FolderSailMarketingFrame $before $State.process.Id $State.ui.main_hwnd
    $b=$before.bounds;$bitmap=[Drawing.Bitmap]::new($b[2],$b[3]);$graphics=[Drawing.Graphics]::FromImage($bitmap);$stream=[IO.MemoryStream]::new()
    try{$graphics.CopyFromScreen($b[0],$b[1],0,0,$bitmap.Size);$bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png);$bytes=$stream.ToArray()}
    finally{$graphics.Dispose();$bitmap.Dispose();$stream.Dispose()}
    $after=Get-FolderSailMarketingFrame $State $Required
    Assert-FolderSailMarketingFrame $after $State.process.Id $State.ui.main_hwnd
    if(($before|ConvertTo-Json -Depth 12 -Compress) -cne ($after|ConvertTo-Json -Depth 12 -Compress)){throw 'Observed capture window/content changed during pixel read'}
    $path=Join-Path $State.output ($Stem+'.png');$file=[IO.File]::Open($path,[IO.FileMode]::CreateNew)
    try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
    Write-FileQuayQualificationRecord (Join-Path $State.output ($Stem+'.json')) @{
        schema_version=1;purpose='original Windows marketing capture';consumer_acceptance=$false;pixel_manipulation=$false;
        qualified=$State.bound;capture_source_commit=$env:GITHUB_SHA;capture_run_id=$env:GITHUB_RUN_ID;capture_run_attempt=$env:GITHUB_RUN_ATTEMPT;
        package_full_name=$State.ownership.ownedPackageFullName;process_id=$State.process.Id;before=$before;after=$after;caption=$Caption;
        png=@{bytes=$bytes.Length;sha256=(Get-FileHash $path).Hash.ToLowerInvariant()};captured_at_utc=[DateTimeOffset]::UtcNow.ToString('O')
    } 14
    $State.captures.Add($Stem)
}

function Find-FolderSailMarketingSelectedFile($Ui,[string]$Path){
    $matches=@();$seen=[Collections.Generic.HashSet[string]]::new()
    foreach($name in @([IO.Path]::GetFileName($Path),[IO.Path]::GetFileNameWithoutExtension($Path))){
        foreach($candidate in @(Find-FileQuayWorkflowElements $Ui -Name $name)){
            $element=$candidate.element
            for($depth=0;$element -and $depth -lt 8;$depth++){
                $pattern=$null
                if($element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern,[ref]$pattern)){
                    if($pattern.Current.IsSelected -and $seen.Add([string]::Join(',',[int[]]$element.GetRuntimeId()))){$matches+=@{scope=$candidate.scope;element=$element}}
                    break
                }
                $element=[System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($element)
            }
        }
    }
    if($matches.Count -ne 1){throw 'Exactly one visible selected demo item is required'}
    return $matches[0]
}

function Invoke-FolderSailMarketingFiles($State,[string]$Mode,[string[]]$Extra=@()){
    $raw=& python (Join-Path $PSScriptRoot 'capture_files.py') $Mode --state $State.fixtureState @Extra
    if($LASTEXITCODE -ne 0){throw "Owned marketing files failed: $Mode"}
    return ($raw -join "`n")|ConvertFrom-Json -AsHashtable
}

function Read-FolderSailMarketingReceiptHeaders($Ui,$List,[object[]]$Receipts){
    $cards=@(Find-FileQuayWorkflowElements $Ui 'ReceiptDetailsExpander' -Within $List)
    if($cards.Count -ne 2 -or $Receipts.Count -ne 2){throw 'Exactly two visible completed operation headers are required'}
    $ids=[Collections.Generic.HashSet[string]]::new();$operations=[Collections.Generic.HashSet[int]]::new()
    $bindings=@();$rows=@()
    foreach($receipt in $Receipts){
        if($receipt.fileOperationType -notin @(3,4) -or $receipt.returnResult -ne 1 -or
           [string]::IsNullOrWhiteSpace($receipt.id) -or -not $ids.Add($receipt.id) -or -not $operations.Add($receipt.fileOperationType)){
            throw 'Receipt headers require distinct successful persisted Copy and Move operations'
        }
        $operation=if($receipt.fileOperationType -eq 3){'Copy'}else{'Move'}
        $title=$Ui.strings["ReceiptOperation$operation"]+' · '+$Ui.strings.ReceiptResultSuccess
        $match=@($cards|Where-Object {$_.element.Current.Name -ceq $title})
        if($match.Count -ne 1){throw 'Visible receipt header differs from the completed persisted operation'}
        $bindings+=@($match[0]);$rows+=@(@{id=$receipt.id;title=$title})
    }
    @{bindings=$bindings;rows=$rows}
}

function Invoke-FolderSailMarketingUi($State){
    $ui=$State.ui;$fixture=$State.fixture;$started=[DateTimeOffset]::UtcNow
    $history=Join-Path $State.profile 'LocalState/OperationReceipts/v1.json'
    $null=Read-FileQuayWorkflowReceipts $history $fixture 0 $started ([DateTimeOffset]::UtcNow)
    $null=Invoke-FolderSailMarketingFiles $State verify @('--phase','Initial')
    Set-FileQuayWorkflowFolder $ui ([IO.Path]::GetDirectoryName($fixture.source))
    Select-FileQuayWorkflowFile $ui $fixture.source
    $main=Get-FileQuayWorkflowMain $ui
    [FileQuayQualification.ConsumerInput]::Foreground($ui.application,$ui.main_hwnd,$ui.application,$ui.main_hwnd)
    Assert-FileQuayWorkflowTarget $main.scope (Get-FileQuayWorkflowTargetState $ui $main)
    ([System.Windows.Automation.WindowPattern]$main.element.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)).SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized)
    $null=Wait-FileQuayWorkflow {if(([FolderSailMarketing.Native]::Frame($ui.main_hwnd)).maximized){$true}} 'actual maximized FolderSail window'
    $item=Find-FolderSailMarketingSelectedFile $ui $fixture.source
    Save-FolderSailMarketingFrame $State '01-folder-workspace' @($item) 'Keep project files together in a clear folder workspace.'
    Invoke-FileQuayWorkflowAction $ui (Wait-FileQuayWorkflow {Find-FileQuayWorkflowElement $ui 'InnerNavigationToolbarCopyButton'} 'enabled Copy action') Invoke
    Set-FileQuayWorkflowFolder $ui ([IO.Path]::GetDirectoryName($fixture.copied));Invoke-FileQuayWorkflowPaste $ui 'copy the workshop brief'
    $null=Wait-FileQuayWorkflow {Invoke-FolderSailMarketingFiles $State verify @('--phase','Copied')} 'independent copied bytes'
    $null=Wait-FileQuayWorkflow {Read-FileQuayWorkflowReceipts $history $fixture 1 $started ([DateTimeOffset]::UtcNow)} 'one actual Copy receipt'
    Select-FileQuayWorkflowFile $ui $fixture.copied
    Invoke-FileQuayWorkflowAction $ui (Wait-FileQuayWorkflow {Find-FileQuayWorkflowElement $ui 'InnerNavigationToolbarCutButton'} 'enabled Cut action') Invoke
    Set-FileQuayWorkflowFolder $ui ([IO.Path]::GetDirectoryName($fixture.moved));Invoke-FileQuayWorkflowPaste $ui 'move the finished workshop brief'
    $null=Wait-FileQuayWorkflow {Invoke-FolderSailMarketingFiles $State verify @('--phase','Moved')} 'independent moved bytes and unchanged originals'
    $receipts=@(Wait-FileQuayWorkflow {Read-FileQuayWorkflowReceipts $history $fixture 2 $started ([DateTimeOffset]::UtcNow)} 'two actual Copy and Move receipts')
    $list=Open-FileQuayWorkflowHistory $ui
    $scene=Wait-FileQuayWorkflow {Read-FolderSailMarketingReceiptHeaders $ui $list $receipts} 'two visible completed operation headers'
    $State.record.visible_receipts=@($scene.rows)
    $State.record.receipts=$receipts
    $visible=@($scene.bindings)
    foreach($binding in $visible){$binding.clip=$list}
    Save-FolderSailMarketingFrame $State '02-operation-receipts' $visible 'Review completed Copy and Move operations in local receipt history.'
    # The qualified helper owns all native filename delivery and picker input.
    $dialog=Open-FileQuayWorkflowExportConfirmation $ui $fixture
    Save-FolderSailMarketingFrame $State '03-export-receipts' @($dialog,(Find-FileQuayWorkflowElement $ui 'PrimaryButton' -Within $dialog)) 'Confirm where to save receipt history as a CSV file.'
    Invoke-FileQuayWorkflowAction $ui (Find-FileQuayWorkflowElement $ui 'PrimaryButton' -Within $dialog) Invoke
    $null=Wait-FileQuayWorkflow { if (@(Find-FileQuayWorkflowElements $ui 'ReceiptExportConfirmationDialog').Count -eq 0) { $true } } 'confirmed export dialog to close'
    $null=Open-FileQuayWorkflowHistory $ui
    $recovery=Wait-FileQuayWorkflow {
        Assert-FileQuayWorkflowCsv $fixture.csv $receipts
        $bar=Find-FileQuayWorkflowElement $ui 'ReceiptStorageErrorBar'
        $text=@(Find-FileQuayWorkflowElements $ui -Within $bar -IncludeHidden|ForEach-Object {$_.element.Current.Name}) -join "`n"
        if(-not $text.Contains($ui.strings.ReceiptExportOriginalPreserved)){throw 'Actual CSV preservation result is absent'}
        $paths=@([regex]::Matches($text,[regex]::Escape($fixture.csv)+'\.[0-9a-f]{32}\.filequay-original')|ForEach-Object Value|Select-Object -Unique)
        if($paths.Count -ne 1){throw 'Actual CSV recovery path is absent or ambiguous'}
        Assert-FileQuayWorkflowFile $paths[0] $fixture.previous_csv
        $paths[0]
    } 'committed CSV and actual preserved original'
    $receiptFile=Join-Path $State.output 'actual-operation-receipts.json'
    Write-FileQuayQualificationRecord $receiptFile @{receipts=$receipts} 12
    # Separate raw list for the independent CSV parser; both originate from the
    # read-only app history, not generated operation history or a private app API.
    $listFile=Join-Path $State.temporary 'actual-receipts.json'
    [IO.File]::WriteAllText($listFile,($receipts|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $State.record.csv=Invoke-FolderSailMarketingFiles $State register-export @('--receipts',$listFile,'--recovery',$recovery)
    $State.record.csv_committed_verified=$true
}
