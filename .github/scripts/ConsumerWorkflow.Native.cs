// Copyright 2026 Trieflow LLC. Licensed under the MIT License.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.Input.KeyboardAndMouse;
using Windows.Win32.UI.WindowsAndMessaging;

namespace FileQuayQualification;

public static class ConsumerInput
{
	public static long RootWindow(long handle)
		=> (long)(nint)PInvoke.GetAncestor((HWND)(nint)handle, GET_ANCESTOR_FLAGS.GA_ROOT);

	public static uint WindowProcess(long handle)
	{
		PInvoke.GetWindowThreadProcessId((HWND)(nint)handle, out uint processId);
		return processId;
	}

	public static long[] OwnerChain(long handle)
	{
		var result = new List<long>();
		for (int i = 0; handle != 0 && i < 8; i++)
		{
			if (!PInvoke.IsWindow((HWND)(nint)handle) || result.Contains(handle)) break;
			result.Add(handle);
			handle = (long)(nint)PInvoke.GetWindow((HWND)(nint)handle, GET_WINDOW_CMD.GW_OWNER);
		}
		return result.ToArray();
	}

	public static Dictionary<string, object> Observe(Process app, long main, Process target, long window)
	{
		return new Dictionary<string, object>
		{
			["app_live"] = !app.HasExited && !app.SafeHandle.IsClosed,
			["target_process_live"] = !target.HasExited && !target.SafeHandle.IsClosed,
			["main_live"] = (bool)PInvoke.IsWindow((HWND)(nint)main),
			["main_pid"] = WindowProcess(main),
			["target_live"] = (bool)PInvoke.IsWindow((HWND)(nint)window),
			["target_pid"] = WindowProcess(window),
			["target_hwnd"] = window,
			["target_visible"] = (bool)PInvoke.IsWindowVisible((HWND)(nint)window),
			["target_enabled"] = (bool)PInvoke.IsWindowEnabled((HWND)(nint)window),
			["foreground_hwnd"] = (long)(nint)PInvoke.GetForegroundWindow(),
			["owner_chain"] = OwnerChain(window),
		};
	}

	private static void RequireTarget(Process app, long main, Process target, long window, bool foreground)
	{
		if (app.HasExited || target.HasExited || app.SafeHandle.IsClosed || target.SafeHandle.IsClosed ||
			!PInvoke.IsWindow((HWND)(nint)main) || WindowProcess(main) != app.Id ||
			!PInvoke.IsWindow((HWND)(nint)window) || WindowProcess(window) != target.Id ||
			!PInvoke.IsWindowVisible((HWND)(nint)window) || !PInvoke.IsWindowEnabled((HWND)(nint)window) ||
			Array.IndexOf(OwnerChain(window), main) < 0 ||
			(foreground && (long)(nint)PInvoke.GetForegroundWindow() != window))
			throw new InvalidOperationException("Native workflow target ownership or foreground changed.");
	}

	public static void Foreground(Process app, long main, Process target, long window)
	{
		RequireTarget(app, main, target, window, false);
		for (int i = 0; i < 20; i++)
		{
			PInvoke.SetForegroundWindow((HWND)(nint)window);
			if ((long)(nint)PInvoke.GetForegroundWindow() == window)
			{
				RequireTarget(app, main, target, window, true);
				return;
			}
			Thread.Sleep(50);
		}
		throw new InvalidOperationException("The owned workflow window did not become foreground.");
	}

	public static unsafe void Chord(Process app, long main, Process target, long window, int[] keys)
	{
		if (keys.Length < 1 || keys.Length > 3) throw new ArgumentException("Unbounded native key chord.");
		var inputs = new INPUT[keys.Length * 2];
		for (int i = 0; i < keys.Length; i++)
		{
			if (keys[i] < 1 || keys[i] > 255) throw new ArgumentException("Invalid virtual key.");
			inputs[i].type = INPUT_TYPE.INPUT_KEYBOARD;
			inputs[i].Anonymous.ki.wVk = (VIRTUAL_KEY)keys[i];
			int release = inputs.Length - 1 - i;
			inputs[release].type = INPUT_TYPE.INPUT_KEYBOARD;
			inputs[release].Anonymous.ki.wVk = (VIRTUAL_KEY)keys[i];
			inputs[release].Anonymous.ki.dwFlags = KEYBD_EVENT_FLAGS.KEYEVENTF_KEYUP;
		}
		RequireTarget(app, main, target, window, true);
		if (PInvoke.SendInput(inputs, sizeof(INPUT)) != inputs.Length)
			throw new InvalidOperationException("Native workflow key input was only partially delivered.");
	}
}
