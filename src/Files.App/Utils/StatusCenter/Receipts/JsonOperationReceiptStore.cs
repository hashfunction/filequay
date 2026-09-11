// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Files.App.Utils.StatusCenter.Receipts;

public sealed class JsonOperationReceiptStore : IOperationReceiptStore
{
	public const int MaximumReceipts = 500;
	public const int MaximumHistoryBytes = 32 * 1024 * 1024;
	private readonly string directory;
	private readonly SemaphoreSlim gate = new(1, 1);
	private readonly Action? beforeCommit;
	public string HistoryPath => Path.Combine(directory, "v1.json");
	public string? RecoveryPath { get; private set; }
	public JsonOperationReceiptStore(string directory) : this(directory, null) { }
	internal JsonOperationReceiptStore(string directory, Action? beforeCommit)
	{
		this.directory = Path.GetFullPath(directory);
		this.beforeCommit = beforeCommit;
	}

	public async Task<IReadOnlyList<OperationReceipt>> LoadAsync(CancellationToken cancellationToken = default)
	{
		await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
		try
		{
			using var fileLock = await LockAsync(cancellationToken).ConfigureAwait(false);
			return await ReadAsync(cancellationToken).ConfigureAwait(false);
		}
		finally { gate.Release(); }
	}

	public async Task AppendAsync(OperationReceipt receipt, CancellationToken cancellationToken = default)
	{
		ArgumentNullException.ThrowIfNull(receipt);
		await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
		try
		{
			using var fileLock = await LockAsync(cancellationToken).ConfigureAwait(false);
			var history = await ReadAsync(cancellationToken).ConfigureAwait(false);
			if (history.Any(r => r.Id == receipt.Id)) return;
			var next = history.Append(receipt).OrderByDescending(r => r.CompletedAtUtc).ThenBy(r => r.Id).Take(MaximumReceipts).ToList();
			if (OperationReceiptCodec.Encode([receipt]).Length > MaximumHistoryBytes)
				throw new IOException("This receipt exceeds the local history size limit.");
			byte[] bytes = OperationReceiptCodec.Encode(next);
			while (bytes.Length > MaximumHistoryBytes)
			{
				next.RemoveAt(next.Count - 1);
				bytes = OperationReceiptCodec.Encode(next);
			}
			await AtomicWriteAsync(HistoryPath, bytes, true, cancellationToken).ConfigureAwait(false);
		}
		finally { gate.Release(); }
	}

	public async Task ClearAsync(CancellationToken cancellationToken = default)
	{
		await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
		try
		{
			using var fileLock = await LockAsync(cancellationToken).ConfigureAwait(false);
			await ReadAsync(cancellationToken).ConfigureAwait(false);
			await AtomicWriteAsync(HistoryPath, OperationReceiptCodec.Encode([]), true, cancellationToken).ConfigureAwait(false);
		}
		finally { gate.Release(); }
	}

	public async Task ExportCsvAsync(string destinationPath, bool replaceExisting = false, CancellationToken cancellationToken = default)
	{
		cancellationToken.ThrowIfCancellationRequested();
		string destination = Path.GetFullPath(destinationPath);
		if (string.Equals(destination, HistoryPath, StringComparison.OrdinalIgnoreCase)
			|| string.Equals(destination, Path.Combine(directory, ".lock"), StringComparison.OrdinalIgnoreCase)
			|| destination.StartsWith(HistoryPath + ".", StringComparison.OrdinalIgnoreCase))
			throw new IOException("Export cannot replace receipt history or recovery evidence.");
		var history = await LoadAsync(cancellationToken).ConfigureAwait(false);
		await AtomicWriteAsync(destination, new UTF8Encoding(false).GetBytes(OperationReceiptCodec.ToCsv(history)), replaceExisting, cancellationToken).ConfigureAwait(false);
	}

	private async Task<FileStream> LockAsync(CancellationToken cancellationToken)
	{
		cancellationToken.ThrowIfCancellationRequested();
		Directory.CreateDirectory(directory);
		// Packaged applications can have several processes. A semaphore alone loses writes across instances.
		var started = Environment.TickCount64;
		while (true)
		{
			cancellationToken.ThrowIfCancellationRequested();
			try { return new FileStream(Path.Combine(directory, ".lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
			catch (IOException) when (Environment.TickCount64 - started < 10000)
			{
				await Task.Delay(20, cancellationToken).ConfigureAwait(false);
			}
		}
	}

	private async Task<IReadOnlyList<OperationReceipt>> ReadAsync(CancellationToken cancellationToken)
	{
		if (!File.Exists(HistoryPath)) return Array.Empty<OperationReceipt>();
		try
		{
			if (new FileInfo(HistoryPath).Length > MaximumHistoryBytes) throw new InvalidDataException("Receipt history exceeds its size limit.");
			var decoded = OperationReceiptCodec.Decode(await File.ReadAllBytesAsync(HistoryPath, cancellationToken).ConfigureAwait(false));
			if (decoded.Count > MaximumReceipts) throw new InvalidDataException("Receipt history exceeds its count limit.");
			return decoded.OrderByDescending(r => r.CompletedAtUtc).ThenBy(r => r.Id).ToArray();
		}
		catch (InvalidDataException)
		{
			cancellationToken.ThrowIfCancellationRequested();
			var recovery = HistoryPath + "." + DateTimeOffset.UtcNow.ToString("yyyyMMddTHHmmssfffffffZ") + "." + Guid.NewGuid().ToString("N") + ".corrupt";
			File.Move(HistoryPath, recovery, false);
			RecoveryPath = recovery;
			return Array.Empty<OperationReceipt>();
		}
	}

	private async Task AtomicWriteAsync(string destination, byte[] bytes, bool replaceExisting, CancellationToken cancellationToken)
	{
		string temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
		try
		{
			cancellationToken.ThrowIfCancellationRequested();
			await using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous | FileOptions.WriteThrough))
			{
				await stream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
				await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
				stream.Flush(flushToDisk: true);
			}
			beforeCommit?.Invoke();
			cancellationToken.ThrowIfCancellationRequested();
			File.Move(temporary, destination, replaceExisting);
		}
		finally
		{
			// An uncommitted sibling can never be loaded as receipt history.
			if (File.Exists(temporary)) File.Delete(temporary);
		}
	}
}
