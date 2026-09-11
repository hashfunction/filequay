// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Files.App.Utils.StatusCenter.Receipts;

namespace Files.App.UnitTests.StatusCenter;

[TestClass]
public sealed class ReceiptExportPublicationTests
{
	private string directory = null!, path = null!;
	[TestInitialize] public async Task Initialize()
	{
		directory = Path.Combine(Path.GetTempPath(), "FileQuay-export-收据-" + Guid.NewGuid());
		Directory.CreateDirectory(directory); path = Path.Combine(directory, "résumé,2026.csv");
		await new JsonOperationReceiptStore(directory).AppendAsync(OperationReceiptCodecTests.Sample());
	}
	[TestCleanup] public void Cleanup() { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
	private Task<ReceiptExportTarget> Choose() => ReceiptExportTarget.CaptureAsync(path, ExportFileIdentityForTests.Read);

	[TestMethod]
	public async Task NewDestinationCreatedAfterSelectionIsNeverOverwritten()
	{
		var selected = await Choose();
		var store = new JsonOperationReceiptStore(directory, () => File.WriteAllText(path, "late new file"));
		await Assert.ThrowsAsync<IOException>(() => store.ExportCsvAsync(path, selected));
		Assert.AreEqual("late new file", await File.ReadAllTextAsync(path));
	}

	[TestMethod]
	public async Task ConfirmedReplacementRetainsTheOriginalAtReportedRecoveryPath()
	{
		await File.WriteAllTextAsync(path, "original content"); var selected = await Choose();
		string? recovery = await new JsonOperationReceiptStore(directory).ExportCsvAsync(path, selected);
		Assert.IsNotNull(recovery); Assert.AreEqual("original content", await File.ReadAllTextAsync(recovery));
		StringAssert.Contains(await File.ReadAllTextAsync(path), "CompletedAtUtc");
	}

	[TestMethod]
	public async Task SameContentAndTimestampsStillRequireTheSelectedFileIdentity()
	{
		await File.WriteAllTextAsync(path, "same bytes"); var selected = await Choose();
		DateTime written = File.GetLastWriteTimeUtc(path), created = File.GetCreationTimeUtc(path);
		File.Move(path, path + ".original"); await File.WriteAllTextAsync(path, "same bytes");
		File.SetCreationTimeUtc(path, created); File.SetLastWriteTimeUtc(path, written);
		await Assert.ThrowsAsync<IOException>(() => new JsonOperationReceiptStore(directory).ExportCsvAsync(path, selected));
		Assert.AreEqual("same bytes", await File.ReadAllTextAsync(path));
	}

	[TestMethod]
	public async Task SameIdentityAndRestoredTimestampStillRequireTheConfirmedContent()
	{
		await File.WriteAllTextAsync(path, "old bytes"); var selected = await Choose(); var written = File.GetLastWriteTimeUtc(path);
		await File.WriteAllTextAsync(path, "new bytes"); File.SetLastWriteTimeUtc(path, written);
		await Assert.ThrowsAsync<IOException>(() => new JsonOperationReceiptStore(directory).ExportCsvAsync(path, selected));
		Assert.AreEqual("new bytes", await File.ReadAllTextAsync(path));
	}

	[TestMethod]
	public async Task SubstitutionAfterPrecheckIsRestoredWithoutPublishingCsv()
	{
		await File.WriteAllTextAsync(path, "confirmed"); var selected = await Choose(); int boundary = 0;
		var store = new JsonOperationReceiptStore(directory, () =>
		{
			if (++boundary == 2) { File.Move(path, path + ".original"); File.WriteAllText(path, "substitution"); }
		});
		await Assert.ThrowsAsync<IOException>(() => store.ExportCsvAsync(path, selected));
		Assert.AreEqual("substitution", await File.ReadAllTextAsync(path));
		Assert.AreEqual("confirmed", await File.ReadAllTextAsync(path + ".original"));
	}

	[TestMethod]
	public async Task LateFileAfterDisplacementIsPreservedWithOriginalRecoveryPath()
	{
		await File.WriteAllTextAsync(path, "confirmed"); var selected = await Choose(); int boundary = 0;
		var store = new JsonOperationReceiptStore(directory, () => { if (++boundary == 3) File.WriteAllText(path, "late file"); });
		var error = await Assert.ThrowsExactlyAsync<ReceiptExportConflictException>(() => store.ExportCsvAsync(path, selected));
		Assert.IsNotNull(error.RecoveryPath); Assert.AreEqual("confirmed", await File.ReadAllTextAsync(error.RecoveryPath));
		Assert.AreEqual("late file", await File.ReadAllTextAsync(path));
		Assert.IsEmpty(Directory.GetFiles(directory, "*.tmp"));
	}

	[TestMethod]
	public async Task ChangedDisplacedFileCannotBecomeASuccessfulReplacement()
	{
		await File.WriteAllTextAsync(path, "confirmed"); var selected = await Choose(); int boundary = 0;
		var store = new JsonOperationReceiptStore(directory, () =>
		{
			if (++boundary == 3) File.WriteAllText(Directory.GetFiles(directory, "*.filequay-original").Single(), "edited old file");
		});
		await Assert.ThrowsAsync<IOException>(() => store.ExportCsvAsync(path, selected));
		Assert.IsTrue(File.Exists(path));
		Assert.IsFalse((await File.ReadAllTextAsync(path)).Contains("CompletedAtUtc"));
	}

	[TestMethod]
	public async Task CancellationAfterDisplacementRestoresTheOriginal()
	{
		await File.WriteAllTextAsync(path, "confirmed"); var selected = await Choose(); int boundary = 0;
		using var cancellation = new CancellationTokenSource();
		var store = new JsonOperationReceiptStore(directory, () => { if (++boundary == 3) cancellation.Cancel(); });
		await Assert.ThrowsExactlyAsync<OperationCanceledException>(() => store.ExportCsvAsync(path, selected, cancellation.Token));
		Assert.AreEqual("confirmed", await File.ReadAllTextAsync(path));
		Assert.IsEmpty(Directory.GetFiles(directory, "*.tmp"));
	}

	[TestMethod]
	public async Task ApprovalCannotBeUsedForAnotherPathOrASymbolicLink()
	{
		await File.WriteAllTextAsync(path, "confirmed"); var selected = await Choose();
		await Assert.ThrowsAsync<IOException>(() => new JsonOperationReceiptStore(directory).ExportCsvAsync(path + ".other", selected));
		// Windows symbolic-link creation requires a developer-mode/elevation fixture; Unix can exercise it here.
		if (!OperatingSystem.IsWindows())
		{
			File.CreateSymbolicLink(path + ".link", path);
			await Assert.ThrowsAsync<IOException>(() => ReceiptExportTarget.CaptureAsync(path + ".link", ExportFileIdentityForTests.Read));
			Assert.AreEqual("confirmed", await File.ReadAllTextAsync(path));
		}
	}
}
