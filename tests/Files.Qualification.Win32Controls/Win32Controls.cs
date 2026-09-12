// Copyright 2026 Trieflow LLC. Licensed under the MIT License.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace FileQuayQualification;

// Separate test process: real standard Win32 controls, no application/proxy provider.
[SupportedOSPlatform("windows5.0")]
public sealed unsafe class Win32Controls
{
	private HWND window, edit, button;
	private readonly object windowLifetime = new();
	private bool destroyed;
	private volatile bool timedOut;
	private int invokes;
	private string value = "", error = "";
	[UnmanagedFunctionPointer(CallingConvention.StdCall)]
	private delegate LRESULT WindowProcedure(HWND handle, uint message, WPARAM wParam, LPARAM lParam);
	private readonly WindowProcedure procedure;
	private Win32Controls() { procedure = WindowProc; }

	public static int Run(string directory, string nonce)
	{
		if (!Regex.IsMatch(nonce, "^[a-f0-9]{32}$") || !Directory.Exists(directory))
			throw new ArgumentException("Expected a fresh owned fixture directory and nonce.");
		var fixture = new Win32Controls();
		return fixture.RunCore(directory, nonce);
	}

	private int RunCore(string directory, string nonce)
	{
		string className = "FolderSailUiaFixture" + nonce;
		var module = PInvoke.GetModuleHandle(default(PCWSTR));
		try
		{
			fixed (char* name = className)
			{
				var callback = (delegate* unmanaged[Stdcall]<HWND, uint, WPARAM, LPARAM, LRESULT>)Marshal.GetFunctionPointerForDelegate(procedure);
				WNDCLASSEXW wc = new() { cbSize = (uint)sizeof(WNDCLASSEXW), lpfnWndProc = callback,
					hInstance = module, lpszClassName = name };
				if (PInvoke.RegisterClassEx(in wc) == 0) throw new InvalidOperationException("Native class registration failed.");
			}
			window = Create(className, "FolderSail UIA fixture " + nonce,
				WINDOW_STYLE.WS_OVERLAPPEDWINDOW | WINDOW_STYLE.WS_VISIBLE, 80, 80, 540, 220,
				default, 0);
			if (window == default) throw new InvalidOperationException("Native fixture window missing.");
			edit = Create("Edit", "initial",
				WINDOW_STYLE.WS_CHILD | WINDOW_STYLE.WS_VISIBLE | WINDOW_STYLE.WS_BORDER | WINDOW_STYLE.WS_TABSTOP,
				20, 25, 480, 30, window, 1001);
			button = Create("Button", "Verify native value",
				WINDOW_STYLE.WS_CHILD | WINDOW_STYLE.WS_VISIBLE | WINDOW_STYLE.WS_TABSTOP,
				20, 80, 210, 35, window, 1);
			if (edit == default || button == default) throw new InvalidOperationException("Native Edit/Button creation failed.");
			WriteNew(directory, "ready.json", new {schema_version=1, nonce, process_id=Environment.ProcessId,
				window=(long)(nint)window, edit=(long)(nint)edit, button=(long)(nint)button});
			using var timeout = new Timer(_ =>
			{
				lock (windowLifetime)
					if (!destroyed) { timedOut=true; PInvoke.PostMessage(window, 0x0010, default, default); }
			}, null, 30000, Timeout.Infinite);
			while (true)
			{
				int status = PInvoke.GetMessage(out MSG message, default, 0, 0);
				if (status == -1) throw new InvalidOperationException("Native message loop failed.");
				if (status == 0) break;
				PInvoke.TranslateMessage(in message);
				PInvoke.DispatchMessage(in message);
			}
		}
		catch (Exception ex) { error=ex.GetType().Name+": "+ex.Message; }
		finally
		{
			if (!destroyed && window != default) PInvoke.DestroyWindow(window);
			fixed (char* name = className) PInvoke.UnregisterClass(name, module);
			GC.KeepAlive(procedure);
		}
		WriteNew(directory, "result.json", new {schema_version=1, nonce, value, invoke_count=invokes,
			window_destroyed=destroyed, timed_out=timedOut, error});
		return error.Length==0 && !timedOut && destroyed && invokes==1 && value=="owned-"+nonce ? 0 : 1;
	}

	private static HWND Create(string className, string title, WINDOW_STYLE style,
		int x, int y, int width, int height, HWND parent, int id)
	{
		fixed (char* name = className)
		fixed (char* text = title)
			return PInvoke.CreateWindowEx(0, name, text, style, x, y, width, height,
				parent, (HMENU)(nint)id, PInvoke.GetModuleHandle(default(PCWSTR)), null);
	}

	private LRESULT WindowProc(HWND handle, uint message, WPARAM wParam, LPARAM lParam)
	{
		try
		{
			if (message==0x0111 && button != default && lParam.Value==(nint)button && (wParam.Value >> 16)==0 && (wParam.Value & 0xffff)==1)
			{
				invokes++;
				Span<char> text = stackalloc char[128];
				int count = PInvoke.GetWindowText(edit, text);
				if (count < 0 || count >= 127) throw new InvalidOperationException("Unbounded native edit text.");
				value = new string(text[..count]);
				PInvoke.PostMessage(handle, 0x0010, default, default);
				return default;
			}
			if (message==0x0002) { lock (windowLifetime) destroyed=true; PInvoke.PostQuitMessage(0);return default; }
			return PInvoke.DefWindowProc(handle, message, wParam, lParam);
		}
		catch (Exception ex) { error=ex.GetType().Name+": "+ex.Message;PInvoke.PostMessage(handle, 0x0010, default, default);return default; }
	}

	private static void WriteNew(string directory, string file, object result)
	{
		string temporary = Path.Combine(directory,file+".pending");
		using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
			JsonSerializer.Serialize(stream,result);
		File.Move(temporary,Path.Combine(directory,file));
	}
}
