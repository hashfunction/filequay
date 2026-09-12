# Copyright 2026 Trieflow LLC. MIT. Replay OS observations against the actual compiled adapter source.
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
 [FileQuayQualification.ConsumerInput]::FocusedSpace($process,101,$process,202,303)
 Require ([Windows.Win32.PInvoke]::Sends -eq 1 -and ([Windows.Win32.PInvoke]::Calls -join ',') -ceq 'focus,send') 'Focus was not checked at the final native send boundary.';$checks++
 $inputs=[Windows.Win32.PInvoke]::Inputs
 Require ($inputs.Length -eq 2 -and [int]$inputs[0].Anonymous.ki.wVk -eq 32 -and [int]$inputs[1].Anonymous.ki.wVk -eq 32 -and [int]$inputs[1].Anonymous.ki.dwFlags -eq 2) 'Space was not exactly one down/up pair.';$checks++
 foreach($scenario in @('focus-drift','active-drift','query-failure','zero-thread','foreign-foreground','foreign-button','foreign-target','sibling-button','hidden-button','disabled-button','foreign-owner','zero-button')) {
  Reset;$button=303
  switch($scenario){
   'focus-drift'{[Windows.Win32.PInvoke]::Focus=404}
   'active-drift'{[Windows.Win32.PInvoke]::Active=404}
   'query-failure'{[Windows.Win32.PInvoke]::FocusReadable=$false}
   'zero-thread'{[Windows.Win32.PInvoke]::Thread=0}
   'foreign-foreground'{[Windows.Win32.PInvoke]::Foreground=404}
   'foreign-button'{[Windows.Win32.PInvoke]::ButtonPid=999}
   'foreign-target'{[Windows.Win32.PInvoke]::WindowPid=999}
   'sibling-button'{[Windows.Win32.PInvoke]::ButtonRoot=404}
   'hidden-button'{[Windows.Win32.PInvoke]::ButtonVisible=$false}
   'disabled-button'{[Windows.Win32.PInvoke]::ButtonEnabled=$false}
   'foreign-owner'{[Windows.Win32.PInvoke]::Owned=$false}
   'zero-button'{$button=0}
  }
  $failed=$false;$failure='';try{[FileQuayQualification.ConsumerInput]::FocusedSpace($process,101,$process,202,$button)}catch{$failed=$true;$failure=$_.Exception.Message}
  Require ($failed -and [Windows.Win32.PInvoke]::Sends -eq 0) "Native send accepted $scenario";$checks++
  if($scenario -ceq 'focus-drift'){Require ($failure.Contains('expected=303') -and $failure.Contains('focus=404')) 'Actual native focus mismatch evidence was lost.'}
 }
 Reset;[Windows.Win32.PInvoke]::Partial=$true
 $failure='';try{[FileQuayQualification.ConsumerInput]::FocusedSpace($process,101,$process,202,303)}catch{$failure=$_.Exception.Message}
 Require ($failure.Contains('partially') -and [Windows.Win32.PInvoke]::Sends -eq 1) 'Partial input was accepted or replayed.';$checks++
 Reset;[Windows.Win32.PInvoke]::FocusReadable=$false
 [FileQuayQualification.ConsumerInput]::Chord($process,101,$process,202,[int[]]@(17,76))
 Require ([Windows.Win32.PInvoke]::Sends -eq 1 -and ([Windows.Win32.PInvoke]::Calls -join ',') -ceq 'send') 'Generic chord behavior changed.';$checks++
 "PASS native adapter focused Space production boundary: $checks checks. OS calls are replayed; real generated ABI is tested separately."
} finally {$process.Dispose()}
