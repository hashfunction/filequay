// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace Files.App.Utils.StatusCenter.Receipts;

internal static class ReceiptExportPublication
{
	internal static async Task<string?> PublishAsync(string destination, byte[] bytes, ReceiptExportTarget? confirmed, CancellationToken cancellationToken, Action? beforeCommit)
	{
		if (confirmed is not null && !confirmed.IsFor(destination)) throw new IOException("Export confirmation belongs to another path.");
		string temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
		try
		{
			await using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous | FileOptions.WriteThrough))
			{
				await stream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
				await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
				stream.Flush(flushToDisk: true);
			}
			beforeCommit?.Invoke();
			cancellationToken.ThrowIfCancellationRequested();
			if (confirmed?.Existed != true)
			{
				File.Move(temporary, destination, overwrite: false);
				return null;
			}

			if (!await confirmed.MatchesAsync(destination, cancellationToken).ConfigureAwait(false))
				throw new IOException("The confirmed export target changed. Select it again to review replacement.");
			string recovery = destination + "." + Guid.NewGuid().ToString("N") + ".filequay-original";
			beforeCommit?.Invoke();
			cancellationToken.ThrowIfCancellationRequested();
			File.Move(destination, recovery, overwrite: false);
			try
			{
				// Inspect what was actually displaced, rather than assuming the precheck was a compare-and-swap.
				await using var verifiedOriginal = await confirmed.OpenVerifiedAsync(recovery, cancellationToken).ConfigureAwait(false);
				beforeCommit?.Invoke();
				cancellationToken.ThrowIfCancellationRequested();
				if (!await confirmed.MatchesOpenAsync(verifiedOriginal, cancellationToken).ConfigureAwait(false))
					throw new IOException("The displaced original changed before publication.");
				File.Move(temporary, destination, overwrite: false);
				// Never delete the user's prior file. Report this sibling even after successful replacement.
				return recovery;
			}
			catch (Exception failure)
			{
				try { File.Move(recovery, destination, overwrite: false); }
				catch (Exception restoreFailure) when (restoreFailure is IOException or UnauthorizedAccessException)
				{
					throw new ReceiptExportConflictException(recovery, failure);
				}
				throw;
			}
		}
		finally
		{
			try { if (File.Exists(temporary)) File.Delete(temporary); }
			catch (IOException) { /* Preserve the publication error and its recovery path if staging cleanup is blocked. */ }
			catch (UnauthorizedAccessException) { }
		}
	}
}
