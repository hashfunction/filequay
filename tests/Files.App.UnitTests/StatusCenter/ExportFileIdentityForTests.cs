// Copyright (c) Trieflow LLC. Licensed under the MIT License.
// Test host identity readers; production Windows uses the existing CsWin32 declarations.
using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;

namespace Files.App.UnitTests.StatusCenter;

internal static class ExportFileIdentityForTests
{
	[DllImport("libc", EntryPoint = "fstat", SetLastError = true)] private static extern int FStat(int fd, IntPtr data);
	[DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
	private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int infoClass, IntPtr data, uint size);
	internal static string Read(SafeFileHandle handle)
	{
		IntPtr memory = Marshal.AllocHGlobal(512);
		try
		{
			if (OperatingSystem.IsWindows())
			{
				if (!GetFileInformationByHandleEx(handle, 18, memory, 24)) throw new IOException("Windows test identity read failed.");
				byte[] identity = new byte[24]; Marshal.Copy(memory, identity, 0, identity.Length);
				return Convert.ToHexString(identity);
			}
			if (!OperatingSystem.IsMacOS() && !OperatingSystem.IsLinux()) throw new PlatformNotSupportedException();
			if (FStat(handle.DangerousGetHandle().ToInt32(), memory) != 0) throw new IOException("Unix test identity read failed.");
			long device = OperatingSystem.IsMacOS() ? Marshal.ReadInt32(memory) : Marshal.ReadInt64(memory);
			return device + ":" + Marshal.ReadInt64(memory, 8);
		}
		finally { Marshal.FreeHGlobal(memory); }
	}
}
