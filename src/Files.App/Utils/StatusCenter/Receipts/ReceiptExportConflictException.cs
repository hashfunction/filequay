// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using System;
using System.IO;

namespace Files.App.Utils.StatusCenter.Receipts;

public sealed class ReceiptExportConflictException(string recoveryPath, Exception innerException)
	: IOException("CSV was not published. The displaced file is preserved at the recovery path.", innerException)
{
	public string RecoveryPath { get; } = recoveryPath;
}
