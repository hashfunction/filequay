# Copyright 2026 Trieflow LLC. MIT. Scene policy and one-move boundary, no generated screenshots.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_ui.ps1')
$ui=@{strings=@{ReceiptOperationCopy='Copy';ReceiptOperationMove='Move';ReceiptResultSuccess='Completed'}}
$receipts=@(@{id='copy';fileOperationType=3;returnResult=1},@{id='move';fileOperationType=4;returnResult=1})
$cards=@(@{element=@{Current=@{Name='Copy · Completed'}}},@{element=@{Current=@{Name='Move · Completed'}}})
$script:selectorCalls=0
function Find-FileQuayWorkflowElements {param($Ui,$Id,$Within) $script:selectorCalls++;return $script:observed}
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
foreach($scenario in @('valid','foreign','readback','null-roles')){
    $script:frame=$goodFrame|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    $script:observed=@();[Windows.Forms.Cursor]::Ignore=$false
    [Windows.Forms.Cursor]::Position=[Drawing.Point]::new(1,1);[Windows.Forms.Cursor]::Writes=0
    if($scenario -eq 'foreign'){$script:frame.pid=99}
    if($scenario -eq 'readback'){[Windows.Forms.Cursor]::Ignore=$true}
    if($scenario -eq 'null-roles'){
        # Actual run35706490358 retained these unrelated visible controls.
        $script:observed=@('ContextCommandBar','BaseCommandBar','RootGridZoom'|ForEach-Object {
            @{element=@{Current=@{AutomationId=$_;ControlType=$null}}}
        })
    }
    $script:selectorCalls=0
    $s=@{ui=@{main_hwnd=11};process=@{Id=42};record=@{}}
    $refused=$false;try{Move-FolderSailMarketingPointer $s @(@{})}catch{$refused=$true}
    $passes=$scenario -in @('valid','null-roles')
    if($refused -eq $passes -or [Windows.Forms.Cursor]::Writes -ne $(if($scenario -eq 'foreign'){0}else{1})){throw "Pointer refusal/move count differs: $scenario"}
    if($passes){
        $p=$s.record.pointer_observations[0]
        if($p.ContainsKey('tooltip_absence_verified') -or -not $p.pointer_readback_verified -or
           $p.settling_delay_ms -ne 500 -or $p.settling_elapsed_ms -lt 450 -or [Windows.Forms.Cursor]::Position.X -ne 960){throw 'Factual pointer/settling observation differs'}
    }
    if($script:selectorCalls -ne 0){throw 'Cosmetic pointer placement still traverses unrelated UIA controls'}
}
Write-Output 'PASS exact receipt header joins and six refusals; one owned neutral pointer move, real settling delay, null-role independence and foreign/readback refusals.'
