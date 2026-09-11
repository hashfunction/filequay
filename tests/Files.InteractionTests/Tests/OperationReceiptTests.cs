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
