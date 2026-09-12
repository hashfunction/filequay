// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Files.App.Utils.StatusCenter.Receipts;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text;

namespace Files.App.UnitTests.StatusCenter;

[TestClass]
public class JsonOperationReceiptStoreTests
{
	private string directory = null!;
	[TestInitialize] public void Initialize() => directory = Path.Combine(Path.GetTempPath(), "FileQuay-收据-" + Guid.NewGuid());
	[TestCleanup] public void Cleanup() { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
	private JsonOperationReceiptStore Store() => new(directory);

	[TestMethod]
	public async Task AppendReloadDeduplicatesAndOrdersNewestFirst()
	{
		var store = Store(); var first = OperationReceiptCodecTests.Sample(); var last = OperationReceiptCodecTests.Sample(1);
		await store.AppendAsync(first); await store.AppendAsync(last); await store.AppendAsync(first);
		CollectionAssert.AreEqual(new[] { last.Id, first.Id }, (await Store().LoadAsync()).Select(r => r.Id).ToArray());
	}

	[TestMethod]
	public async Task RenamedAppLoadsExistingV1HistoryWithoutRewritingOrChangingPaths()
	{
		// The pre-rename v1 wire format is fixed here, independent of the current encoder.
		byte[] existing = Encoding.UTF8.GetBytes("""
			{"schemaVersion":1,"receipts":[{"schemaVersion":1,"id":"290f7c43-c358-4327-b6a6-c2ff07a64d03","startedAtUtc":"2026-09-11T10:00:00+00:00","completedAtUtc":"2026-09-11T10:00:01+00:00","fileOperationType":3,"returnResult":1,"sourcePaths":["C:\\FileQuay notes\\résumé.txt"],"destinationPaths":["D:\\收据"],"itemCount":1,"totalBytes":4096,"failureCode":null}]}
			""");
		string receiptDirectory = Path.Combine(directory, "OperationReceipts");
		Directory.CreateDirectory(receiptDirectory);
		string history = Path.Combine(receiptDirectory, "v1.json");
		await File.WriteAllBytesAsync(history, existing);
		var store = new JsonOperationReceiptStore(receiptDirectory);
		Assert.AreEqual(history, store.HistoryPath);
		var original = (await store.LoadAsync()).Single();
		Assert.AreEqual(Guid.Parse("290f7c43-c358-4327-b6a6-c2ff07a64d03"), original.Id);
		Assert.AreEqual(@"C:\FileQuay notes\résumé.txt", original.SourcePaths.Single());
		CollectionAssert.AreEqual(existing, await File.ReadAllBytesAsync(history));
		await store.AppendAsync(OperationReceiptCodecTests.Sample(1));
		var reopened = (await new JsonOperationReceiptStore(receiptDirectory).LoadAsync()).Single(r => r.Id == original.Id);
		Assert.AreEqual(original.TotalBytes, reopened.TotalBytes);
		CollectionAssert.AreEqual(original.SourcePaths.ToArray(), reopened.SourcePaths.ToArray());
		CollectionAssert.AreEqual(original.DestinationPaths.ToArray(), reopened.DestinationPaths.ToArray());
		string export = Path.Combine(directory, "FolderSail-receipts.csv");
		await store.ExportCsvAsync(export);
		StringAssert.Contains(await File.ReadAllTextAsync(export), @"C:\FileQuay notes\résumé.txt");
	}

	[TestMethod]
	public async Task ConcurrentStoreInstancesDoNotLoseAppends()
	{
		var receipts = Enumerable.Range(0, 40).Select(i => OperationReceiptCodecTests.Sample(i)).ToArray();
		await Task.WhenAll(receipts.Select(r => Store().AppendAsync(r)));
		CollectionAssert.AreEquivalent(receipts.Select(r => r.Id).ToArray(), (await Store().LoadAsync()).Select(r => r.Id).ToArray());
	}

	[TestMethod]
	public async Task RetainsNewest500AndClearsOnlyMetadata()
	{
		var store = Store(); Directory.CreateDirectory(directory);
		var receipts = Enumerable.Range(0, 500).Select(i => OperationReceiptCodecTests.Sample(i)).ToArray();
		await File.WriteAllBytesAsync(store.HistoryPath, OperationReceiptCodec.Encode(receipts));
		await store.AppendAsync(OperationReceiptCodecTests.Sample(500));
		var history = await Store().LoadAsync(); Assert.HasCount(500, history);
		Assert.IsFalse(history.Any(r => r.Id == receipts[0].Id));
		var original = Path.Combine(directory, "user-original.txt"); await File.WriteAllTextAsync(original, "untouched");
		await store.ClearAsync(); Assert.IsEmpty(await Store().LoadAsync()); Assert.AreEqual("untouched", await File.ReadAllTextAsync(original));
	}

	[TestMethod]
	public async Task CancellationImmediatelyBeforeCommitPreservesPreviousBytesAndRemovesTemp()
	{
		var store = Store(); await store.AppendAsync(OperationReceiptCodecTests.Sample());
		var before = await File.ReadAllBytesAsync(store.HistoryPath); using var cancellation = new CancellationTokenSource();
		var interrupted = new JsonOperationReceiptStore(directory, beforeCommit: () => cancellation.Cancel());
		await Assert.ThrowsExactlyAsync<OperationCanceledException>(() => interrupted.AppendAsync(OperationReceiptCodecTests.Sample(1), cancellation.Token));
		CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(store.HistoryPath));
		Assert.IsEmpty(Directory.GetFiles(directory, "*.tmp"));
	}

	[TestMethod]
	public async Task CorruptionIsPreservedAndNeverPartiallyLoaded()
	{
		var store = Store(); Directory.CreateDirectory(directory); byte[] corrupt = Encoding.UTF8.GetBytes("{bad json 收据");
		await File.WriteAllBytesAsync(store.HistoryPath, corrupt);
		Assert.IsEmpty(await store.LoadAsync()); Assert.IsNotNull(store.RecoveryPath);
		CollectionAssert.AreEqual(corrupt, await File.ReadAllBytesAsync(store.RecoveryPath));
		await store.AppendAsync(OperationReceiptCodecTests.Sample()); Assert.HasCount(1, await Store().LoadAsync());
		Assert.IsTrue(File.Exists(store.RecoveryPath));
	}

	[TestMethod]
	public async Task ExportRefusesExistingDestinationUnlessExplicitAndCancelledExportPreservesIt()
	{
		var store = Store(); await store.AppendAsync(OperationReceiptCodecTests.Sample());
		string path = Path.Combine(directory, "résumé,2026.csv"); await File.WriteAllTextAsync(path, "original");
		await Assert.ThrowsExactlyAsync<IOException>(() => store.ExportCsvAsync(path));
		Assert.AreEqual("original", await File.ReadAllTextAsync(path));
		var confirmed = await ReceiptExportTarget.CaptureAsync(path, ExportFileIdentityForTests.Read);
		using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
		await Assert.ThrowsExactlyAsync<OperationCanceledException>(() => store.ExportCsvAsync(path, confirmed, cancellation.Token));
		Assert.AreEqual("original", await File.ReadAllTextAsync(path));
		await store.ExportCsvAsync(path, confirmed); StringAssert.Contains(await File.ReadAllTextAsync(path), "CompletedAtUtc");
	}

	[TestMethod]
	public async Task ConfirmedExportRefusesAReplacementArrivingImmediatelyBeforeCommit()
	{
		var store = Store(); await store.AppendAsync(OperationReceiptCodecTests.Sample());
		string path = Path.Combine(directory, "confirmed.csv"); await File.WriteAllTextAsync(path, "confirmed original");
		var confirmed = await ReceiptExportTarget.CaptureAsync(path, ExportFileIdentityForTests.Read);
		var exporter = new JsonOperationReceiptStore(directory, beforeCommit: () =>
		{
			File.Move(path, path + ".original", false);
			File.WriteAllText(path, "unapproved replacement");
		});
		await Assert.ThrowsAsync<IOException>(() => exporter.ExportCsvAsync(path, confirmed));
		Assert.AreEqual("unapproved replacement", await File.ReadAllTextAsync(path));
	}

	[TestMethod]
	public async Task ExportCannotReplaceHistoryOrItsLockAndWriteErrorsPreserveHistory()
	{
		var store = Store(); await store.AppendAsync(OperationReceiptCodecTests.Sample());
		var before = await File.ReadAllBytesAsync(store.HistoryPath);
		await Assert.ThrowsExactlyAsync<IOException>(() => store.ExportCsvAsync(store.HistoryPath));
		await Assert.ThrowsExactlyAsync<IOException>(() => store.ExportCsvAsync(Path.Combine(directory, ".lock")));
		await Assert.ThrowsExactlyAsync<DirectoryNotFoundException>(() => store.ExportCsvAsync(Path.Combine(directory, "missing", "file.csv")));
		CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(store.HistoryPath));
	}
}
