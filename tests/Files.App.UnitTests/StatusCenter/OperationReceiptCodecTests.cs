// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Files.App.Data.Enums;
using Files.App.Utils.StatusCenter.Receipts;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text;

namespace Files.App.UnitTests.StatusCenter;

[TestClass]
public class OperationReceiptCodecTests
{
	internal static OperationReceipt Sample(int seconds = 0, string[]? paths = null) => new(
		Guid.NewGuid(), new DateTimeOffset(2026, 9, 11, 12, 0, 0, TimeSpan.FromHours(2)),
		new DateTimeOffset(2026, 9, 11, 12, 0, 1, TimeSpan.FromHours(2)).AddSeconds(seconds),
		FileOperationType.Copy, ReturnResult.Success, paths ?? ["C:\\résumé,2026\\\"line\"\nnext"], ["D:\\收据"], 2, 4096);

	[TestMethod]
	public void RoundTripPreservesUnicodeEscapesEnumsAndUtc()
	{
		var receipt = Sample();
		var encoded = OperationReceiptCodec.Encode([receipt]);
		var json = Encoding.UTF8.GetString(encoded);
		StringAssert.Contains(json, "2026-09-11T10:00:00+00:00");
		var decoded = OperationReceiptCodec.Decode(encoded).Single();
		Assert.AreEqual(receipt.Id, decoded.Id);
		Assert.AreEqual(FileOperationType.Copy, decoded.FileOperationType);
		Assert.AreEqual(ReturnResult.Success, decoded.ReturnResult);
		CollectionAssert.AreEqual(receipt.SourcePaths.ToArray(), decoded.SourcePaths.ToArray());
		CollectionAssert.AreEqual(receipt.DestinationPaths.ToArray(), decoded.DestinationPaths.ToArray());
		Assert.AreEqual(4096L, decoded.TotalBytes);
		Assert.AreEqual(TimeSpan.Zero, decoded.StartedAtUtc.Offset);
	}

	[TestMethod]
	public void SnapshotCopiesInputsAndRedactsUriCredentialsAndQuery()
	{
		string[] paths = ["ftp://user:secret@example.com/a?token=hidden#secret", "C:\\folder"];
		var receipt = Sample(paths: paths);
		paths[1] = "changed";
		Assert.AreEqual("C:\\folder", receipt.SourcePaths[1]);
		Assert.AreEqual("ftp://example.com/a", receipt.SourcePaths[0]);
		Assert.ThrowsExactly<NotSupportedException>(() => ((IList<string>)receipt.SourcePaths)[1] = "changed");
	}

	[TestMethod]
	public void CsvQuotesUnicodeNewlinesAndNeutralizesSpreadsheetFormulas()
	{
		var receipt = Sample(paths: ["=HYPERLINK(\"bad\")", "résumé,\"2026\"\nnext"]);
		var csv = OperationReceiptCodec.ToCsv([receipt]);
		StringAssert.Contains(csv, "\"'=HYPERLINK(\"\"bad\"\")\nrésumé,\"\"2026\"\"\nnext\"");
		Assert.IsTrue(csv.StartsWith("Id,StartedAtUtc,CompletedAtUtc,Operation,Result,ItemCount,TotalBytes,SourcePaths,DestinationPaths,FailureCode\r\n"));
		Assert.IsTrue(csv.EndsWith("\r\n"));
	}

	[TestMethod]
	public void RejectsUnknownSchemaAndInvalidRecordWithoutPartialRead()
	{
		var json = Encoding.UTF8.GetString(OperationReceiptCodec.Encode([Sample()]));
		Assert.ThrowsExactly<InvalidDataException>(() => OperationReceiptCodec.Decode(Encoding.UTF8.GetBytes(json.Replace("\"schemaVersion\":1", "\"schemaVersion\":99"))));
		Assert.ThrowsExactly<InvalidDataException>(() => OperationReceiptCodec.Decode(Encoding.UTF8.GetBytes(json.Replace("2026-09-11T10:00:01+00:00", "2026-09-10T10:00:01+00:00"))));
		Assert.ThrowsExactly<InvalidDataException>(() => OperationReceiptCodec.Decode("{}"u8.ToArray()));
	}

	[TestMethod]
	public void RejectsInProgressUnknownEnumsNegativeCountsAndReversedTime()
	{
		var r = Sample();
		Assert.ThrowsExactly<ArgumentException>(() => new OperationReceipt(r.Id, r.CompletedAtUtc, r.StartedAtUtc, r.FileOperationType, r.ReturnResult, [], [], 0, 0));
		Assert.ThrowsExactly<ArgumentException>(() => new OperationReceipt(r.Id, r.StartedAtUtc, r.CompletedAtUtc, r.FileOperationType, ReturnResult.InProgress, [], [], 0, 0));
		Assert.ThrowsExactly<ArgumentException>(() => new OperationReceipt(r.Id, r.StartedAtUtc, r.CompletedAtUtc, (FileOperationType)200, r.ReturnResult, [], [], 0, 0));
		Assert.ThrowsExactly<ArgumentException>(() => new OperationReceipt(r.Id, r.StartedAtUtc, r.CompletedAtUtc, r.FileOperationType, r.ReturnResult, [], [], -1, 0));
	}
}
