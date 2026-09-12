// Copyright 2026 Trieflow LLC. MIT. Marketing activation and read-only native frame observations.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace FolderSailMarketing {
 [ComImport, Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IApplicationActivationManager {
  [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string id, [MarshalAs(UnmanagedType.LPWStr)] string arguments, uint options, out uint processId);
  [PreserveSig] int ActivateForFile(string id, IntPtr items, string verb, out uint processId);
  [PreserveSig] int ActivateForProtocol(string id, IntPtr items, out uint processId);
 }
 [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")] class ApplicationActivationManager { }
 public static class Native {
  [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
  [StructLayout(LayoutKind.Sequential)] struct Point { public int X,Y; public Point(int x,int y){X=x;Y=y;} }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern int GetPackageFullName(IntPtr process,ref uint length,StringBuilder name);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint processId);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr window);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr window);
  [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window,uint flags);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window,StringBuilder text,int count);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder text,int count);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window,int attribute,out Rect bounds,int size);
  public static uint Activate(string aumid) {
   var manager=(IApplicationActivationManager)new ApplicationActivationManager(); uint pid;
   try { int result=manager.ActivateApplication(aumid,"",2,out pid); if(result<0)Marshal.ThrowExceptionForHR(result); if(pid==0)throw new InvalidOperationException("Empty activation PID"); return pid; }
   finally {Marshal.ReleaseComObject(manager);}
  }
  public static string PackageName(IntPtr process) {
   uint length=0; int result=GetPackageFullName(process,ref length,null);
   if(result!=122 || length==0 || length>1024)throw new InvalidOperationException("Packaged process sizing failed: "+result);
   var text=new StringBuilder((int)length); result=GetPackageFullName(process,ref length,text);
   if(result!=0)throw new InvalidOperationException("Packaged process identity failed: "+result); return text.ToString();
  }
  public static Dictionary<string,object> Frame(long handle) {
   var window=(IntPtr)handle;uint pid;Rect bounds;
   if(handle==0 || GetWindowThreadProcessId(window,out pid)==0 || DwmGetWindowAttribute(window,9,out bounds,Marshal.SizeOf(typeof(Rect)))!=0)
    throw new InvalidOperationException("Original visible DWM frame is unavailable");
   var title=new StringBuilder(1024);var cls=new StringBuilder(256);GetWindowText(window,title,title.Capacity);GetClassName(window,cls,cls.Capacity);
   var hits=new List<long>();
   foreach(int x in new[]{bounds.Left+8,(bounds.Left+bounds.Right)/2,bounds.Right-9})
    foreach(int y in new[]{bounds.Top+8,(bounds.Top+bounds.Bottom)/2,bounds.Bottom-9})
     // Owned WinUI flyouts belong to the same root owner as the main window.
     hits.Add(GetAncestor(WindowFromPoint(new Point(x,y)),3).ToInt64());
   return new Dictionary<string,object>{{"hwnd",handle},{"pid",pid},{"foreground",GetForegroundWindow().ToInt64()},
    {"title",title.ToString()},{"class",cls.ToString()},{"visible",IsWindowVisible(window)},{"enabled",IsWindowEnabled(window)},
    {"maximized",IsZoomed(window)},{"dpi",GetDpiForWindow(window)},
    {"bounds",new[]{bounds.Left,bounds.Top,bounds.Right-bounds.Left,bounds.Bottom-bounds.Top}},{"hit_roots",hits.ToArray()}};
  }
 }
}
