// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Microsoft.Win32.SafeHandles;
using System;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace Files.App.Utils.StatusCenter.Receipts;

public sealed class ReceiptExportTarget
{
	public string Path { get; }
	public bool Existed { get; }
	private readonly Func<SafeFileHandle, string> readIdentity;
	private readonly string? identity, digest;
	private readonly long length, written;

	private ReceiptExportTarget(string path, Func<SafeFileHandle, string> readIdentity, string? identity = null, string? digest = null, long length = 0, long written = 0)
	{
		Path = path; this.readIdentity = readIdentity; this.identity = identity; this.digest = digest;
		this.length = length; this.written = written; Existed = identity is not null;
	}

	public static async Task<ReceiptExportTarget> CaptureAsync(string path, Func<SafeFileHandle, string> readIdentity, CancellationToken cancellationToken = default)
	{
		ArgumentNullException.ThrowIfNull(readIdentity);
		cancellationToken.ThrowIfCancellationRequested();
		path = System.IO.Path.GetFullPath(path);
		try { return await CaptureExistingAsync(path, readIdentity, cancellationToken).ConfigureAwait(false); }
		catch (FileNotFoundException) { return new ReceiptExportTarget(path, readIdentity); }
	}

	internal bool IsFor(string path) => string.Equals(Path, System.IO.Path.GetFullPath(path), OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);

	internal async Task<bool> MatchesAsync(string path, CancellationToken cancellationToken)
		=> Matches(await CaptureExistingAsync(path, readIdentity, cancellationToken).ConfigureAwait(false));

	private bool Matches(ReceiptExportTarget current)
		=> Existed && current.identity == identity && current.length == length && current.written == written && current.digest == digest;

	internal async Task<FileStream> OpenVerifiedAsync(string path, CancellationToken cancellationToken)
	{
		RequireOrdinaryFile(path);
		// Windows denies writers and renames while the displaced original is verified and publication finishes.
		var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, FileOptions.Asynchronous | FileOptions.SequentialScan);
		try
		{
			if (!await MatchesOpenAsync(stream, cancellationToken).ConfigureAwait(false)) throw new IOException("The export target was substituted before publication.");
			return stream;
		}
		catch { await stream.DisposeAsync().ConfigureAwait(false); throw; }
	}

	internal async Task<bool> MatchesOpenAsync(FileStream stream, CancellationToken cancellationToken)
		=> Matches(await ReadOpenAsync(stream, readIdentity, cancellationToken).ConfigureAwait(false));

	private static void RequireOrdinaryFile(string path)
	{
		if ((File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
			throw new IOException("Receipt export requires an ordinary file, not a link or directory.");
	}

	private static async Task<ReceiptExportTarget> CaptureExistingAsync(string path, Func<SafeFileHandle, string> readIdentity, CancellationToken cancellationToken)
	{
		RequireOrdinaryFile(path);
		await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete, 65536, FileOptions.Asynchronous | FileOptions.SequentialScan);
		return await ReadOpenAsync(stream, readIdentity, cancellationToken).ConfigureAwait(false);
	}

	private static async Task<ReceiptExportTarget> ReadOpenAsync(FileStream stream, Func<SafeFileHandle, string> readIdentity, CancellationToken cancellationToken)
	{
		string identity = readIdentity(stream.SafeFileHandle);
		if (string.IsNullOrEmpty(identity)) throw new IOException("The selected file identity is unavailable.");
		long length = stream.Length, written = File.GetLastWriteTimeUtc(stream.SafeFileHandle).Ticks;
		stream.Position = 0;
		string digest = Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken).ConfigureAwait(false));
		if (length != stream.Length || written != File.GetLastWriteTimeUtc(stream.SafeFileHandle).Ticks)
			throw new IOException("The selected file changed while confirming export.");
		return new ReceiptExportTarget(stream.Name, readIdentity, identity, digest, length, written);
	}
}
