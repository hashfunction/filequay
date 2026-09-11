// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Files.App.Utils.StatusCenter.Receipts;
namespace Files.App.ViewModels.UserControls;

public sealed class OperationReceiptViewModel(OperationReceipt receipt)
{
	public string Title => ("ReceiptOperation" + receipt.FileOperationType).GetLocalizedResource() + " · " + ("ReceiptResult" + receipt.ReturnResult).GetLocalizedResource();
	public string Completed => receipt.CompletedAtUtc.ToLocalTime().ToString("g");
	public string Counts => "ReceiptCounts".GetLocalizedFormatResource(receipt.ItemCount, receipt.TotalBytes.ToSizeString());
	public string SourcePaths => string.Join("\n", receipt.SourcePaths);
	public string DestinationPaths => string.Join("\n", receipt.DestinationPaths);
	public string FailureCode => receipt.FailureCode ?? string.Empty;
	public string Identity => receipt.Id.ToString();
}
