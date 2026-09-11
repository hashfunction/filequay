// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Files.App.Data.Enums;
using Files.App.Utils.StatusCenter.Receipts;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Files.App.UnitTests.StatusCenter;

[TestClass]
public class StatusCenterReceiptCaptureTests
{
	[TestMethod]
	public void OnlyOuterCompletionEmitsAndDuplicateCompletionIsIgnored()
	{
		var capture = new OperationReceiptCapture(FileOperationType.Copy, ["source"], ["destination"]);
		capture.ObserveProgress(ReturnResult.Success, 2, 80);
		Assert.IsNull(capture.Receipt);
		var receipt = capture.Complete(ReturnResult.Success);
		Assert.IsNotNull(receipt); Assert.AreEqual(2L, receipt.ItemCount); Assert.AreEqual(80L, receipt.TotalBytes);
		Assert.IsNull(capture.Complete(ReturnResult.Failed)); Assert.AreSame(receipt, capture.Receipt);
	}
	[TestMethod]
	public void CancellationRetainsOriginalPathsAndCountsEvenAfterProgressStops()
	{
		string[] source = ["C:\\résumé,2026"]; string[] destination = ["D:\\收据"];
		var capture = new OperationReceiptCapture(FileOperationType.Move, source, destination);
		source[0] = "moved"; destination[0] = "mutated";
		capture.ObserveProgress(ReturnResult.InProgress, 8, 4096);
		var receipt = capture.Complete(ReturnResult.Cancelled)!;
		Assert.AreEqual(ReturnResult.Cancelled, receipt.ReturnResult);
		CollectionAssert.AreEqual(new[] { "C:\\résumé,2026" }, receipt.SourcePaths.ToArray());
		CollectionAssert.AreEqual(new[] { "D:\\收据" }, receipt.DestinationPaths.ToArray());
	}
	[TestMethod]
	public async Task RealBatchPartialFailureCannotBeOverwrittenByLaterSuccess()
	{
		string directory = Path.Combine(Path.GetTempPath(), "FileQuay-batch-" + Guid.NewGuid()); Directory.CreateDirectory(directory);
		try
		{
			string original = Path.Combine(directory, "résumé,2026"); await File.WriteAllTextAsync(original, "original");
			string copied = Path.Combine(directory, "copy"); string blocked = Path.Combine(directory, "existing"); await File.WriteAllTextAsync(blocked, "keep");
			var capture = new OperationReceiptCapture(FileOperationType.Copy, [original, original], [blocked, copied]);
			try { File.Copy(original, blocked, false); }
			catch (IOException) { capture.ObserveProgress(ReturnResult.Failed, 2, 16); }
			File.Copy(original, copied, false); capture.ObserveProgress(ReturnResult.Success, 2, 16);
			var receipt = capture.Complete(ReturnResult.Success)!;
			Assert.AreEqual(ReturnResult.Failed, receipt.ReturnResult);
			Assert.AreEqual("keep", await File.ReadAllTextAsync(blocked)); Assert.AreEqual("original", await File.ReadAllTextAsync(copied));
			Assert.AreEqual("original", await File.ReadAllTextAsync(original));
		}
		finally { Directory.Delete(directory, true); }
	}
	[TestMethod]
	public void ProgressObserverFreezesFailureBeforeMutableReportIsReused()
	{
		var capture = new OperationReceiptCapture(FileOperationType.Copy, [], []);
		var progress = new ObservedOperationProgress<MutableProgress>(p => capture.ObserveProgress(p.Status, 1, 1), _ => { });
		var model = new MutableProgress { Status = ReturnResult.AccessUnauthorized };
		((IProgress<MutableProgress>)progress).Report(model);
		model.Status = ReturnResult.Success;
		((IProgress<MutableProgress>)progress).Report(model);
		Assert.AreEqual(ReturnResult.AccessUnauthorized, capture.Complete(ReturnResult.Success)!.ReturnResult);
	}
	[TestMethod]
	public void ImmediateFailureAndUnknownIncompleteResultAreTerminal()
	{
		var failed = new OperationReceiptCapture(FileOperationType.Copy, ["source"], []);
		Assert.AreEqual(ReturnResult.AccessUnauthorized, failed.Complete(ReturnResult.AccessUnauthorized)!.ReturnResult);
		var unfinished = new OperationReceiptCapture(FileOperationType.Copy, [], []);
		Assert.AreEqual(ReturnResult.UnknownException, unfinished.Complete(ReturnResult.InProgress)!.ReturnResult);
	}
	private sealed class MutableProgress { public ReturnResult Status { get; set; } }
}
