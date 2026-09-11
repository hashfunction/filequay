// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using System;
namespace Files.App.Utils.StatusCenter.Receipts;
public sealed class StatusCenterItemCompletedEventArgs(OperationReceipt receipt) : EventArgs
{
	public OperationReceipt Receipt { get; } = receipt;
}
