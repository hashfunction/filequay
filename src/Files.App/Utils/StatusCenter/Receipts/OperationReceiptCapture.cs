// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Files.App.Data.Enums;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Files.App.Utils.StatusCenter.Receipts;

public sealed class OperationReceiptCapture
{
	private readonly object gate = new();
	private readonly Guid id = Guid.NewGuid();
	private readonly FileOperationType operation;
	private readonly string[] source;
	private readonly string[] destination;
	private ReturnResult? failure;
	private long itemCount;
	private long totalBytes;
	public DateTimeOffset StartedAtUtc { get; } = DateTimeOffset.UtcNow;
	public OperationReceipt? Receipt { get; private set; }
	public OperationReceiptCapture(FileOperationType operation, IEnumerable<string> source, IEnumerable<string> destination)
	{
		this.operation = operation;
		this.source = source.Select(OperationReceipt.SanitizePath).ToArray();
		this.destination = destination.Select(OperationReceipt.SanitizePath).ToArray();
	}
	public void ObserveProgress(ReturnResult status, long itemCount, long totalBytes)
	{
		lock (gate)
		{
			if (Receipt is not null) return;
			if (status is not ReturnResult.InProgress and not ReturnResult.Success and not ReturnResult.Cancelled)
				failure ??= status;
			this.itemCount = Math.Max(this.itemCount, itemCount);
			this.totalBytes = Math.Max(this.totalBytes, totalBytes);
		}
	}
	public OperationReceipt? Complete(ReturnResult finalResult)
	{
		lock (gate)
		{
			if (Receipt is not null) return null;
			if (finalResult != ReturnResult.Cancelled && failure is { } failed) finalResult = failed;
			if (finalResult == ReturnResult.InProgress) finalResult = ReturnResult.UnknownException;
			Receipt = new OperationReceipt(id, StartedAtUtc, DateTimeOffset.UtcNow, operation, finalResult, source, destination,
				itemCount, totalBytes, failure?.ToString() ?? (finalResult is ReturnResult.Success or ReturnResult.Cancelled ? null : finalResult.ToString()));
			return Receipt;
		}
	}
}
