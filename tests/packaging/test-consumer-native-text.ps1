# Copyright 2026 Trieflow LLC. MIT. Execute the real adapter with only OS calls replayed.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$source=Get-Content (Join-Path $PSScriptRoot '../../.github/scripts/ConsumerWorkflow.Native.cs') -Raw
$stubs=Get-Content (Join-Path $PSScriptRoot 'fixtures/consumer-input-native-stubs.cs') -Raw
Add-Type -TypeDefinition ($source.Replace('namespace FileQuayQualification;','namespace FileQuayQualification {')+"`n}`n"+$stubs.Replace('using System;','').Replace('using System.Collections.Generic;','').Replace('using System.Diagnostics;','').Replace('using Windows.Win32.Foundation;','').Replace('using Windows.Win32.UI.Input.KeyboardAndMouse;','').Replace('using Windows.Win32.UI.WindowsAndMessaging;','')) -CompilerOptions '/unsafe' -WarningAction SilentlyContinue
function Require($Value,$Message){if(-not $Value){throw $Message}}
function Reset {
 [Windows.Win32.PInvoke]::Foreground=202;[Windows.Win32.PInvoke]::Focus=303;[Windows.Win32.PInvoke]::Active=202;[Windows.Win32.PInvoke]::ButtonRoot=202
 [Windows.Win32.PInvoke]::ButtonPid=[Windows.Win32.PInvoke]::Pid;[Windows.Win32.PInvoke]::WindowPid=[Windows.Win32.PInvoke]::Pid;[Windows.Win32.PInvoke]::Thread=17
 [Windows.Win32.PInvoke]::FocusReadable=$true;[Windows.Win32.PInvoke]::ButtonVisible=$true;[Windows.Win32.PInvoke]::ButtonEnabled=$true
 [Windows.Win32.PInvoke]::Owned=$true;[Windows.Win32.PInvoke]::Partial=$false;[Windows.Win32.PInvoke]::Sends=0;[Windows.Win32.PInvoke]::Calls.Clear()
}
$process=[Diagnostics.Process]::GetCurrentProcess();$checks=0
try {
 Reset
 $text='C:\FolderSail Demo\Receipts\工作 résumé.csv'
 [FileQuayQualification.ConsumerInput]::FocusedText($process,101,$process,202,303,$text)
 Require ([Windows.Win32.PInvoke]::Sends -eq 1 -and ([Windows.Win32.PInvoke]::Calls -join ',') -ceq 'focus,send') 'Exact focus was not checked immediately before one native text delivery.';$checks++
 $inputs=[Windows.Win32.PInvoke]::Inputs
 Require ($inputs.Length -eq (4+2*$text.Length)) 'Native replacement text input count differs.'
 Require ((($inputs[0..3]|ForEach-Object {[int]$_.Anonymous.ki.wVk}) -join ',') -ceq '17,65,65,17') 'Select-all key order differs.'
 Require ((($inputs[0..3]|ForEach-Object {[int]$_.Anonymous.ki.dwFlags}) -join ',') -ceq '0,0,2,2') 'Select-all modifiers were not released before text.';$checks++
 for($i=0;$i -lt $text.Length;$i++){
  $down=$inputs[4+2*$i].Anonymous.ki;$up=$inputs[5+2*$i].Anonymous.ki
  Require ([int]$down.wVk -eq 0 -and [int]$up.wVk -eq 0 -and $down.wScan -eq [int][char]$text[$i] -and $up.wScan -eq $down.wScan -and [int]$down.dwFlags -eq 4 -and [int]$up.dwFlags -eq 6) 'Unicode down/up bytes differ from original filename.'
 };$checks++
 foreach($scenario in @('focus','foreground','owner','pid','hidden','disabled','query','zero','empty','long','newline','surrogate')) {
  Reset;$control=303;$value=$text
  switch($scenario){
   'focus'{[Windows.Win32.PInvoke]::Focus=404}
   'foreground'{[Windows.Win32.PInvoke]::Foreground=404}
   'owner'{[Windows.Win32.PInvoke]::Owned=$false}
   'pid'{[Windows.Win32.PInvoke]::ButtonPid=999}
   'hidden'{[Windows.Win32.PInvoke]::ButtonVisible=$false}
   'disabled'{[Windows.Win32.PInvoke]::ButtonEnabled=$false}
   'query'{[Windows.Win32.PInvoke]::FocusReadable=$false}
   'zero'{$control=0}
   'empty'{$value=''}
   'long'{$value='a'*1025}
   'newline'{$value="a`nb"}
   'surrogate'{$value=[string][char]0xd800}
  }
  $failed=$false;try{[FileQuayQualification.ConsumerInput]::FocusedText($process,101,$process,202,$control,$value)}catch{$failed=$true}
  Require ($failed -and [Windows.Win32.PInvoke]::Sends -eq 0) "Text input accepted $scenario";$checks++
 }
 Reset;[Windows.Win32.PInvoke]::Partial=$true
 $errorText='';try{[FileQuayQualification.ConsumerInput]::FocusedText($process,101,$process,202,303,$text)}catch{$errorText=$_.Exception.Message}
 Require ($errorText.Contains('partially') -and [Windows.Win32.PInvoke]::Sends -eq 1) 'Partial native text was accepted or replayed.';$checks++
 "PASS actual native focused Unicode replacement: $checks checks. OS calls replayed; generated ABI compiled separately."
} finally {$process.Dispose()}
