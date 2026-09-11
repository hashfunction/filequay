// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Microsoft.Win32.SafeHandles;
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Storage.FileSystem;

namespace Files.App.Helpers;

internal static class ReceiptExportFileIdentity
{
	internal static unsafe string Read(SafeFileHandle handle)
	{
		bool addedReference = false;
		try
		{
			handle.DangerousAddRef(ref addedReference);
			FILE_ID_INFO identity = default;
			if (!PInvoke.GetFileInformationByHandleEx(new HANDLE(handle.DangerousGetHandle()), FILE_INFO_BY_HANDLE_CLASS.FileIdInfo, &identity, (uint)sizeof(FILE_ID_INFO)))
				throw new Win32Exception(Marshal.GetLastWin32Error());
			return Convert.ToHexString(new ReadOnlySpan<byte>(&identity, sizeof(FILE_ID_INFO)));
		}
		finally { if (addedReference) handle.DangerousRelease(); }
	}
}
