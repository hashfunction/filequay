# Copyright 2026 Trieflow LLC. MIT. Scalar ownership/geometry tests, no fabricated screenshot.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_ui.ps1')
$good=@{pid=42;hwnd=11;foreground=11;visible=$true;enabled=$true;maximized=$true;dpi=96;
    title='Inbox - FolderSail';class='observed-window-class';bounds=@(0,0,1920,1040);desktop=@(0,0,1920,1080);
    work_area=@(0,0,1920,1040);hit_roots=@(11,11,11,11,11,11,11,11,11);required=@(@{visible=$true;pid=42;bounds=@(50,80,400,30)})}
Assert-FolderSailMarketingFrame $good 42 11
foreach($mutation in @('pid','hwnd','foreground','visible','enabled','maximized','dpi','title','outside','occluded','required','viewport','nan')){
    $bad=$good|ConvertTo-Json -Depth 9|ConvertFrom-Json -AsHashtable
    switch($mutation){
        'pid'{$bad.pid=99};'hwnd'{$bad.hwnd=99};'foreground'{$bad.foreground=99}
        'visible'{$bad.visible=$false};'enabled'{$bad.enabled=$false};'maximized'{$bad.maximized=$false}
        'dpi'{$bad.dpi=144};'title'{$bad.title='Foreign app'};'outside'{$bad.bounds[1]=-10}
        'occluded'{$bad.hit_roots[4]=99};'required'{$bad.required[0].bounds[0]=2000}
        'viewport'{$bad.required[0].clip=@(50,90,400,400)}
        'nan'{$bad.required[0].bounds[0]=[double]::NaN}
    }
    $refused=$false;try{Assert-FolderSailMarketingFrame $bad 42 11}catch{$refused=$true}
    if(-not $refused){throw "Capture accepted changed $mutation"}
}
Write-Output 'PASS native capture scalar ownership, foreground, geometry, visible content and occlusion refusals.'
