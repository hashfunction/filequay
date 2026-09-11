// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Files.App.UnitTests.StatusCenter;

[TestClass]
public sealed class EmptyRecycleBinCardTests
{
	[TestMethod]
	public void UnsupportedCancelCannotChangeEmptyBinCompletion()
	{
		foreach (var expectedResult in new[] { ReturnResult.Success, ReturnResult.Failed })
		{
			var card = StatusCenterHelper.AddCard_EmptyRecycleBin(ReturnResult.InProgress);
			Assert.IsFalse(card.IsCancelable, "The real empty-bin service has no cancellation hook.");
			card.CancelCommand.Execute(null);
			Assert.IsFalse(card.CancellationToken.IsCancellationRequested);
			Assert.IsTrue(card.Complete(expectedResult));
			Assert.AreEqual(expectedResult, card.CompletedReceipt!.ReturnResult);
			Assert.AreEqual(expectedResult, card.FileSystemOperationReturnResult);
			Assert.IsFalse(card.Complete(ReturnResult.Cancelled));
		}
	}

	[TestMethod]
	public void EmptyBinCancellationHeaderResolvesAnExistingResource()
	{
		var card = StatusCenterHelper.AddCard_EmptyRecycleBin(ReturnResult.InProgress);
		card.Complete(ReturnResult.Cancelled);
		Assert.AreEqual("StatusCenter_EmptyRecycleBinCancel_Header", card.HeaderStringResource);
		Assert.AreNotEqual(card.HeaderStringResource, card.Header);
	}
}
