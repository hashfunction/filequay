# Copyright 2026 Trieflow LLC. MIT. Scene policy and one-move boundary, no generated screenshots.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_ui.ps1')
$ui=@{strings=@{ReceiptOperationCopy='Copy';ReceiptOperationMove='Move';ReceiptResultSuccess='Completed'}}
$receipts=@(@{id='copy';fileOperationType=3;returnResult=1},@{id='move';fileOperationType=4;returnResult=1})
$cards=@(@{element=@{Current=@{Name='Copy · Completed'}}},@{element=@{Current=@{Name='Move · Completed'}}})
function Find-FileQuayWorkflowElements {param($Ui,$Id,$Within) return $script:observed}
$script:observed=$cards
$scene=Read-FolderSailMarketingReceiptHeaders $ui @{} $receipts
if($scene.bindings.Count -ne 2 -or ($scene.rows.id -join '|') -cne 'copy|move'){throw 'Visible headers did not bind exact completed operations'}
foreach($scenario in @('absent','duplicate','wrong-title','wrong-result','wrong-operation','duplicate-id')){
    $script:observed=$cards|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    $r=$receipts|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    switch($scenario){
        'absent'{$script:observed=@($cards[0])}
        'duplicate'{$script:observed=@($cards[0],$cards[0])}
        'wrong-title'{$script:observed[1].element.Current.Name='Move · Failed'}
        'wrong-result'{$r[1].returnResult=0}
        'wrong-operation'{$r[1].fileOperationType=9}
        'duplicate-id'{$r[1].id='copy'}
    }
    $refused=$false;try{$null=Read-FolderSailMarketingReceiptHeaders $ui @{} $r}catch{$refused=$true}
    if(-not $refused){throw "Unproved receipt scene accepted: $scenario"}
}
# Native cursor seam only. Keep actual frame geometry/ownership policy and
# actual capture pointer helper; no pointer/window operation runs on this host.
Add-Type 'namespace System.Windows.Forms { public static class Cursor { static System.Drawing.Point p; public static int Writes; public static bool Ignore; public static System.Drawing.Point Position { get { return p; } set { Writes++; if(!Ignore)p=value; } } } }'
$goodFrame=@{pid=42;hwnd=11;foreground=11;visible=$true;enabled=$true;maximized=$true;dpi=96;
    title='Inbox - FolderSail';class='window';bounds=@(0,0,1920,1040);desktop=@(0,0,1920,1080);
    work_area=@(0,0,1920,1040);hit_roots=@(11,11,11,11,11,11,11,11,11);required=@(@{visible=$true;pid=42;bounds=@(50,80,400,30)})}
function Get-FolderSailMarketingFrame {param($State,$Required) return $script:frame}
function Wait-FileQuayWorkflow {param($Probe,$Description) & $Probe}
foreach($scenario in @('valid','foreign','readback','tooltip')){
    $script:frame=$goodFrame|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    $script:observed=@();[Windows.Forms.Cursor]::Ignore=$false
    [Windows.Forms.Cursor]::Position=[Drawing.Point]::new(1,1);[Windows.Forms.Cursor]::Writes=0
    if($scenario -eq 'foreign'){$script:frame.pid=99}
    if($scenario -eq 'readback'){[Windows.Forms.Cursor]::Ignore=$true}
    if($scenario -eq 'tooltip'){$script:observed=@(@{element=@{Current=@{ControlType=@{ProgrammaticName='ControlType.ToolTip'}}}})}
    $s=@{ui=@{main_hwnd=11};process=@{Id=42};record=@{}}
    $refused=$false;try{Move-FolderSailMarketingPointer $s @(@{})}catch{$refused=$true}
    if($refused -ne ($scenario -ne 'valid') -or [Windows.Forms.Cursor]::Writes -ne $(if($scenario -eq 'foreign'){0}else{1})){throw "Pointer refusal/move count differs: $scenario"}
    if($scenario -eq 'valid' -and (-not $s.record.pointer_observations[0].tooltip_absence_verified -or [Windows.Forms.Cursor]::Position.X -ne 960)){throw 'Pointer/tooltip observation lost'}
}
Write-Output 'PASS exact receipt header joins and six refusals; one owned neutral pointer move, foreign/readback/tooltip refusals.'
