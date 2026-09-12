// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using OpenQA.Selenium;
using OpenQA.Selenium.Appium;
using OpenQA.Selenium.Appium.Windows;
using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;

namespace Files.InteractionTests.Tests;

[TestClass]
public sealed class OperationReceiptTests
{
	private static string HistoryPath => Path.Combine(Environment.GetEnvironmentVariable("FILEQUAY_TEST_LOCAL_STATE")
		?? throw new InvalidOperationException("Set FILEQUAY_TEST_LOCAL_STATE to the installed test package LocalState directory."), "OperationReceipts", "v1.json");

	[TestMethod]
	public void UnicodeCopyHasOneInspectableReceiptAndExportsCsv()
	{
		string root = Path.Combine(TestHelper.TestDataRootPath, Guid.NewGuid().ToString("N"));
		string source = Path.Combine(root, "résumé,2026"); string destination = Path.Combine(root, "destination");
		Directory.CreateDirectory(source); Directory.CreateDirectory(destination);
		File.WriteAllText(Path.Combine(source, "原稿.txt"), "keep this original");
		CopyThroughUi(root, "résumé,2026", destination);
		WaitFor(() => MatchingReceipts(source, 1) == 1, "one successful receipt for the copy");
		Assert.AreEqual("keep this original", File.ReadAllText(Path.Combine(source, "原稿.txt")));
		Assert.AreEqual("keep this original", File.ReadAllText(Path.Combine(destination, "résumé,2026", "原稿.txt")));
		TestHelper.InvokeButtonById("ShowStatusCenterButton"); TestHelper.InvokeButtonByName("Receipts");
		var expander = TestHelper.GetElementById("ReceiptDetailsExpander");
		Assert.IsFalse(string.IsNullOrWhiteSpace(expander.GetAttribute("Name")));
		expander.SendKeys(Keys.Space);
		StringAssert.Contains(TestHelper.GetElementById("ReceiptSourcePaths").Text, source);
		StringAssert.Contains(TestHelper.GetElementById("ReceiptDestinationPaths").Text, destination);
		AxeHelper.AssertNoAccessibilityErrors();
		var exportButton = TestHelper.GetElementById("ReceiptExportButton"); exportButton.SendKeys(Keys.Tab);
		Assert.IsTrue(string.Equals("true", TestHelper.GetElementById("ReceiptClearButton").GetAttribute("HasKeyboardFocus"), StringComparison.OrdinalIgnoreCase));
		exportButton.Click();
		string csvPath = Path.Combine(root, "receipts.csv");
		var options = new AppiumOptions(); options.AddAdditionalCapability("app", "Root"); options.AddAdditionalCapability("deviceName", "WindowsPC");
		using (var desktop = new WindowsDriver<WindowsElement>(new Uri("http://127.0.0.1:4723"), options))
		{
			WaitFor(() => desktop.FindElementsByAccessibilityId("1001").Count > 0, "native save picker filename field");
			var filename = desktop.FindElementByAccessibilityId("1001"); filename.Clear(); filename.SendKeys(csvPath);
			desktop.FindElementByAccessibilityId("1").Click();
		}
		TestHelper.InvokeDialogPrimaryButton("Export receipts…");
		WaitFor(() => File.Exists(csvPath) && new FileInfo(csvPath).Length > 0, "CSV export");
		StringAssert.Contains(File.ReadAllText(csvPath), source);
		StringAssert.Contains(File.ReadAllText(csvPath), "\"Copy\",\"Success\"");
		Assert.AreEqual(1, MatchingReceipts(source, 1));
	}

	[TestMethod]
	public void CancelledBatchRetainsOriginalsAndOneCancelledReceipt()
	{
		string root = Path.Combine(TestHelper.TestDataRootPath, Guid.NewGuid().ToString("N"));
		string source = Path.Combine(root, "cancel-batch"); string destination = Path.Combine(root, "destination");
		Directory.CreateDirectory(source); Directory.CreateDirectory(destination);
		byte[] bytes = Enumerable.Repeat((byte)0x51, 256 * 1024).ToArray();
		for (int i = 0; i < 3000; i++) File.WriteAllBytes(Path.Combine(source, i + ".bin"), bytes);
		CopyThroughUi(root, "cancel-batch", destination);
		TestHelper.InvokeButtonById("ShowStatusCenterButton"); TestHelper.InvokeButtonByName("Live");
		TestHelper.InvokeButtonById("CancelOperationButton");
		WaitFor(() => MatchingReceipts(source, 8) == 1, "one cancelled receipt");
		Assert.AreEqual(3000, Directory.GetFiles(source).Length);
		CollectionAssert.AreEqual(bytes, File.ReadAllBytes(Path.Combine(source, "0.bin")));
		CollectionAssert.AreEqual(bytes, File.ReadAllBytes(Path.Combine(source, "2999.bin")));
		TestHelper.InvokeButtonByName("Receipts");
		TestHelper.GetElementById("ReceiptDetailsExpander").SendKeys(Keys.Space);
		StringAssert.Contains(TestHelper.GetElementById("ReceiptSourcePaths").Text, source);
		AxeHelper.AssertNoAccessibilityErrors();
	}

	[TestMethod]
	public void PersistenceFailureLeavesCompletedQueueRowAndOriginalsVisible()
	{
		string root = Path.Combine(TestHelper.TestDataRootPath, Guid.NewGuid().ToString("N"));
		string source = Path.Combine(root, "write-error-source"); string destination = Path.Combine(root, "target-" + Guid.NewGuid().ToString("N"));
		Directory.CreateDirectory(source); Directory.CreateDirectory(destination);
		File.WriteAllText(Path.Combine(source, "original.txt"), "preserve");
		Directory.CreateDirectory(Path.GetDirectoryName(HistoryPath)!);
		if (!File.Exists(HistoryPath)) File.WriteAllText(HistoryPath, "{\"schemaVersion\":1,\"receipts\":[]}");
		byte[] prior = File.ReadAllBytes(HistoryPath);
		using (var lockedHistory = new FileStream(HistoryPath, FileMode.Open, FileAccess.Read, FileShare.None))
		{
			CopyThroughUi(root, "write-error-source", destination);
			WaitFor(() => File.Exists(Path.Combine(destination, "write-error-source", "original.txt")), "file operation despite receipt write failure");
			TestHelper.InvokeButtonById("ShowStatusCenterButton"); TestHelper.InvokeButtonByName("Live");
			Assert.IsTrue(TestHelper.GetElementById("ReceiptStorageErrorBar").Displayed);
			Assert.IsTrue(TestHelper.GetElementsOfTypeWithContent("Text", Path.GetFileName(destination)).Count > 0, "Completed queue row remains visible.");
			Assert.AreEqual("preserve", File.ReadAllText(Path.Combine(source, "original.txt")));
		}
		CollectionAssert.AreEqual(prior, File.ReadAllBytes(HistoryPath));
	}

	[TestMethod]
	public void EmptyRecycleBinDisablesCancelAndRecordsActualCompletion()
	{
		if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Installed FolderSail tests require Windows.");
		Assert.AreEqual("1", Environment.GetEnvironmentVariable("FILEQUAY_TEST_DISPOSABLE_RECYCLE_BIN"),
			"Run only in a disposable Windows account whose Recycle Bin may be emptied.");
		dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application")!);
		dynamic bin = shell.NameSpace(10);
		Assert.AreEqual(0, (int)bin.Items().Count, "Start with an empty disposable Recycle Bin.");
		string root = Path.Combine(TestHelper.TestDataRootPath, Guid.NewGuid().ToString("N"));
		string fixture = Path.Combine(root, "empty-bin-fixture"); Directory.CreateDirectory(fixture);
		string sentinel = Path.Combine(root, "keep-original.txt"); File.WriteAllText(sentinel, "keep this original");
		byte[] bytes = Enumerable.Repeat((byte)0x51, 64 * 1024).ToArray();
		for (int i = 0; i < 12000; i++) File.WriteAllBytes(Path.Combine(fixture, i + ".bin"), bytes);
		Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(fixture, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs,
			Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
		Assert.IsTrue((int)bin.Items().Count > 0);
		var before = ReadReceiptRecords().Select(r => r.GetProperty("id").GetGuid()).ToHashSet();
		TestHelper.ContextClickElementByName("Recycle Bin"); TestHelper.InvokeButtonByName("Empty Recycle Bin");
		TestHelper.InvokeDialogPrimaryButton("Yes");
		TestHelper.InvokeButtonById("ShowStatusCenterButton"); TestHelper.InvokeButtonByName("Live");
		TestHelper.WaitForElementByName("Emptying Recycle Bin");
		var cancel = TestHelper.GetElementById("CancelOperationButton"); Assert.IsFalse(cancel.Enabled);
		try { cancel.Click(); } catch (WebDriverException) { /* Disabled controls may reject the attempted click. */ }
		WaitFor(() => ReadReceiptRecords().Count(r => !before.Contains(r.GetProperty("id").GetGuid()) && r.GetProperty("fileOperationType").GetInt32() == 8) == 1,
			"one terminal empty-bin receipt");
		var receipt = ReadReceiptRecords().Single(r => !before.Contains(r.GetProperty("id").GetGuid()) && r.GetProperty("fileOperationType").GetInt32() == 8);
		Assert.AreEqual(1, receipt.GetProperty("returnResult").GetInt32());
		Assert.AreEqual(0, (int)bin.Items().Count);
		Assert.AreEqual("keep this original", File.ReadAllText(sentinel));
		TestHelper.WaitForElementByName("Emptied Recycle Bin"); AxeHelper.AssertNoAccessibilityErrors();
	}

	[TestMethod]
	public void ExportRefusesSubstitutionWhileConfirmationIsOpen()
	{
		string root = Path.Combine(TestHelper.TestDataRootPath, Guid.NewGuid().ToString("N"));
		string source = Path.Combine(root, "export-race"); string destination = Path.Combine(root, "destination");
		Directory.CreateDirectory(source); Directory.CreateDirectory(destination);
		File.WriteAllText(Path.Combine(source, "original.txt"), "keep this original");
		CopyThroughUi(root, "export-race", destination);
		WaitFor(() => MatchingReceipts(source, 1) == 1, "a receipt to export");
		TestHelper.InvokeButtonById("ShowStatusCenterButton"); TestHelper.InvokeButtonByName("Receipts");
		TestHelper.InvokeButtonById("ReceiptExportButton"); string csvPath = Path.Combine(root, "race.csv");
		var options = new AppiumOptions(); options.AddAdditionalCapability("app", "Root"); options.AddAdditionalCapability("deviceName", "WindowsPC");
		using (var desktop = new WindowsDriver<WindowsElement>(new Uri("http://127.0.0.1:4723"), options))
		{
			WaitFor(() => desktop.FindElementsByAccessibilityId("1001").Count > 0, "native save picker");
			var filename = desktop.FindElementByAccessibilityId("1001"); filename.Clear(); filename.SendKeys(csvPath);
			desktop.FindElementByAccessibilityId("1").Click();
		}
		var confirmation = TestHelper.GetElementById("ReceiptExportConfirmationDialog");
		AppiumWebElement primary = null;
		WaitFor(() =>
		{
			primary = confirmation.FindElementsByAccessibilityId("PrimaryButton").FirstOrDefault(button => button.Displayed && button.Enabled);
			return confirmation.Displayed && primary is not null
				&& confirmation.FindElementsByTagName("Text").Any(text => text.Displayed && text.Text.Contains(csvPath, StringComparison.Ordinal));
		}, "snapshot completed and the selected path is shown in the export confirmation dialog");
		Assert.IsTrue(File.Exists(csvPath), "Qualify the Windows picker-created destination fixture.");
		File.Move(csvPath, csvPath + ".selected"); File.WriteAllText(csvPath, "unapproved replacement");
		primary.Click();
		WaitFor(() => TestHelper.GetElementById("ReceiptStorageErrorBar").Displayed && TestHelper.GetElementsOfTypeWithContent("Text", csvPath).Count > 0, "export conflict and affected path shown");
		Assert.AreEqual("unapproved replacement", File.ReadAllText(csvPath));
		Assert.AreEqual("keep this original", File.ReadAllText(Path.Combine(source, "original.txt")));
	}

	private static JsonElement[] ReadReceiptRecords()
	{
		if (!File.Exists(HistoryPath)) return [];
		using var doc = JsonDocument.Parse(File.ReadAllBytes(HistoryPath));
		return doc.RootElement.GetProperty("receipts").EnumerateArray().Select(r => r.Clone()).ToArray();
	}

	private static void CopyThroughUi(string root, string sourceName, string destination)
	{
		TestHelper.NavigateToPath(root); TestHelper.InvokeButtonByName(sourceName);
		TestHelper.InvokeButtonById("InnerNavigationToolbarCopyButton"); TestHelper.NavigateToPath(destination);
		TestHelper.InvokeButtonById("InnerNavigationToolbarPasteButton");
	}
	private static int MatchingReceipts(string source, int result)
	{
		if (!File.Exists(HistoryPath)) return 0;
		using var doc = JsonDocument.Parse(File.ReadAllBytes(HistoryPath));
		var matches = doc.RootElement.GetProperty("receipts").EnumerateArray().Where(r => r.GetProperty("sourcePaths").EnumerateArray().Any(p => p.GetString() == source)).ToArray();
		Assert.IsTrue(matches.Length <= 1, "Duplicate final receipt at the application integration boundary.");
		return matches.Count(r => r.GetProperty("returnResult").GetInt32() == result);
	}
	private static void WaitFor(Func<bool> predicate, string description)
	{
		var deadline = DateTime.UtcNow.AddSeconds(60);
		while (DateTime.UtcNow < deadline) { if (predicate()) return; Thread.Sleep(100); }
		Assert.Fail("Timed out waiting for " + description);
	}
}
