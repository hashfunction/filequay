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

	public static Dictionary<string, object> ObserveClipboard(Process app, long main)
	{
		RequireTarget(app, main, app, main, true);
		uint before = PInvoke.GetClipboardSequenceNumber();
		long owner = (long)(nint)PInvoke.GetClipboardOwner();
		uint ownerProcess = owner == 0 ? 0 : WindowProcess(owner);
		bool fileDrop = PInvoke.IsClipboardFormatAvailable(15); // CF_HDROP, format availability only.
		uint after = PInvoke.GetClipboardSequenceNumber();
		RequireTarget(app, main, app, main, true);
		return new Dictionary<string, object>
		{
			["owner_hwnd"] = owner,
			["owner_pid"] = ownerProcess,
			["owner_is_consumer"] = ownerProcess == app.Id,
			["sequence_before"] = before,
			["sequence_after"] = after,
			["sequence_stable"] = before == after,
			["file_drop_format_available"] = fileDrop,
		};
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

	private static unsafe void RequireFocusedControl(Process target, long window, long control)
	{
		if (control == 0 || !PInvoke.IsWindow((HWND)(nint)control) || RootWindow(control) != window ||
			WindowProcess(control) != target.Id || !PInvoke.IsWindowVisible((HWND)(nint)control) ||
			!PInvoke.IsWindowEnabled((HWND)(nint)control))
			throw new InvalidOperationException("Native focused button identity or ownership changed.");
		uint thread = PInvoke.GetWindowThreadProcessId((HWND)(nint)window, out uint processId);
		GUITHREADINFO info = new() { cbSize = (uint)sizeof(GUITHREADINFO) };
		bool observed = thread != 0 && processId == target.Id && PInvoke.GetGUIThreadInfo(thread, ref info);
		if (!observed || (long)(nint)info.hwndActive != window || (long)(nint)info.hwndFocus != control)
			throw new InvalidOperationException($"Native workflow button focus changed before input: expected={control}, focus={(long)(nint)info.hwndFocus}, active={(long)(nint)info.hwndActive}, window={window}, observed={observed}.");
	}

	public static void FocusedSpace(Process app, long main, Process target, long window, long control)
	{
		if (control == 0) throw new InvalidOperationException("Native focused button HWND is missing.");
		SendChord(app, main, target, window, new[] { 0x20 }, control);
	}

	public static void Chord(Process app, long main, Process target, long window, int[] keys)
		=> SendChord(app, main, target, window, keys, 0);

	private static unsafe void SendChord(Process app, long main, Process target, long window, int[] keys, long focusedControl)
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
		if (focusedControl != 0) RequireFocusedControl(target, window, focusedControl);
		if (PInvoke.SendInput(inputs, sizeof(INPUT)) != inputs.Length)
			throw new InvalidOperationException("Native workflow key input was only partially delivered.");
	}
}
