// Copyright 2026 Trieflow LLC. MIT. Test-only OS observation replay; never packaged.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using Windows.Win32.Foundation;
using Windows.Win32.UI.Input.KeyboardAndMouse;
using Windows.Win32.UI.WindowsAndMessaging;
namespace Windows.Win32.Foundation {
 public struct HWND {public nint Value;public static explicit operator HWND(nint v)=>new HWND{Value=v}; public static explicit operator nint(HWND h)=>h.Value;}
}
namespace Windows.Win32.UI.WindowsAndMessaging {
 public enum GET_ANCESTOR_FLAGS {GA_ROOT} public enum GET_WINDOW_CMD {GW_OWNER}
 public struct GUITHREADINFO {public uint cbSize;public uint flags;public HWND hwndActive,hwndFocus,hwndCapture,hwndMenuOwner,hwndMoveSize,hwndCaret;}
}
namespace Windows.Win32.UI.Input.KeyboardAndMouse {
 public enum INPUT_TYPE {INPUT_KEYBOARD} public enum VIRTUAL_KEY {} public enum KEYBD_EVENT_FLAGS {KEYEVENTF_KEYUP=2,KEYEVENTF_UNICODE=4}
 public struct KEYBDINPUT {public VIRTUAL_KEY wVk;public ushort wScan;public KEYBD_EVENT_FLAGS dwFlags;}
 public struct InputUnion {public KEYBDINPUT ki;}
 public struct INPUT {public INPUT_TYPE type;public InputUnion Anonymous;}
}
namespace Windows.Win32 {
 public static class PInvoke {
  public static long Foreground=202,Focus=303,Active=202,ButtonRoot=202,Button=303;
  public static uint Pid=(uint)Process.GetCurrentProcess().Id,ButtonPid=Pid,WindowPid=Pid,Thread=17;
  public static bool FocusReadable=true,ButtonVisible=true,ButtonEnabled=true,Owned=true,Partial=false;
  public static int Sends;public static List<string> Calls=new();public static INPUT[] Inputs;
  public static HWND GetAncestor(HWND h,GET_ANCESTOR_FLAGS f)=>(HWND)(h.Value==303?(nint)ButtonRoot:h.Value);
  public static uint GetWindowThreadProcessId(HWND h,out uint pid){pid=h.Value==303?ButtonPid:h.Value==202?WindowPid:Pid;return Thread;}
  public static HWND GetWindow(HWND h,GET_WINDOW_CMD c)=>(HWND)(nint)(h.Value==202&&Owned?101:0);
  public static bool IsWindow(HWND h)=>h.Value==101||h.Value==202||h.Value==303;
  public static bool IsWindowVisible(HWND h)=>h.Value!=303||ButtonVisible;
  public static bool IsWindowEnabled(HWND h)=>h.Value!=303||ButtonEnabled;
  public static HWND GetForegroundWindow()=>(HWND)(nint)Foreground;
  public static bool SetForegroundWindow(HWND h){Foreground=(long)h.Value;return true;}
  public static uint GetClipboardSequenceNumber()=>0;public static HWND GetClipboardOwner()=>default;
  public static bool IsClipboardFormatAvailable(uint f)=>false;
  public static bool GetGUIThreadInfo(uint thread,ref GUITHREADINFO info){Calls.Add("focus");info.hwndActive=(HWND)(nint)Active;info.hwndFocus=(HWND)(nint)Focus;return FocusReadable;}
  public static uint SendInput(ReadOnlySpan<INPUT> input,int size){Calls.Add("send");Sends++;Inputs=input.ToArray();return (uint)(input.Length-(Partial?1:0));}
 }
}
