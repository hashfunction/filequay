// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Files.App.Utils.StatusCenter.Receipts;

public interface IOperationReceiptStore
{
	string HistoryPath { get; }
	string? RecoveryPath { get; }
	Task<IReadOnlyList<OperationReceipt>> LoadAsync(CancellationToken cancellationToken = default);
	Task AppendAsync(OperationReceipt receipt, CancellationToken cancellationToken = default);
	Task ExportCsvAsync(string destinationPath, bool replaceExisting = false, CancellationToken cancellationToken = default);
	Task ClearAsync(CancellationToken cancellationToken = default);
}
