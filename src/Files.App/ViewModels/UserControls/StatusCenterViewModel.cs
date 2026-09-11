// Copyright (c) Files Community
// Licensed under the MIT License.

using Files.App.Utils.StatusCenter.Receipts;
using CommunityToolkit.WinUI;

namespace Files.App.ViewModels.UserControls
{
	public sealed partial class StatusCenterViewModel : ObservableObject
	{
		private readonly Files.App.Storage.TaskbarManager _taskbar = Files.App.Storage.TaskbarManager.Default;

		public ObservableCollection<StatusCenterItem> StatusCenterItems { get; } = [];

		private int _AverageOperationProgressValue = 0;
		public int AverageOperationProgressValue
		{
			get => _AverageOperationProgressValue;
			private set => SetProperty(ref _AverageOperationProgressValue, value);
		}

		public int InProgressItemCount
		{
			get
			{
				int count = 0;

				foreach (var item in StatusCenterItems)
				{
					if (item.IsInProgress)
						count++;
				}

				return count;
			}
		}

		public bool HasAnyItemInProgress
		{
			get
			{
				if (InProgressItemCount > 0)
					ShowProgressRing = true;

				return InProgressItemCount > 0;
			}
		}

		public bool HasAnyItem
			=> StatusCenterItems.Any();


		private bool _ShowProgressRing = false;
		public bool ShowProgressRing
		{
			get => _ShowProgressRing;
			private set => SetProperty(ref _ShowProgressRing, value);

		}

		public int InfoBadgeState
		{
			get
			{
				var anyFailure = StatusCenterItems.Any(i =>
					i.FileSystemOperationReturnResult != ReturnResult.InProgress &&
					i.FileSystemOperationReturnResult != ReturnResult.Success);

				return (anyFailure, HasAnyItemInProgress) switch
				{
					(false, false) => 0, // All successful
					(false, true) => 1,  // In progress
					(true, true) => 2,   // In progress with an error
					(true, false) => 3   // Completed with an error
				};
			}
		}

		public int InfoBadgeValue
			=> InProgressItemCount > 0 ? InProgressItemCount : -1;

		public event EventHandler<StatusCenterItem>? NewItemAdded;

		private readonly IOperationReceiptStore receiptStore;
		public ObservableCollection<OperationReceiptViewModel> OperationReceipts { get; } = [];
		private string? receiptError;
		public string? ReceiptError { get => receiptError; private set => SetProperty(ref receiptError, value); }
		public bool HasReceiptError => !string.IsNullOrWhiteSpace(ReceiptError);
		public string ReceiptHistoryPath => receiptStore.HistoryPath;
		public bool HasReceipts => OperationReceipts.Count > 0;

		public StatusCenterViewModel(IOperationReceiptStore receiptStore)
		{
			this.receiptStore = receiptStore;
			StatusCenterItems.CollectionChanged += (s, e) => OnPropertyChanged(nameof(HasAnyItem));
		}

		public void OnStatusCenterFlyoutOpened()
		{
			ShowProgressRing = HasAnyItemInProgress || InfoBadgeState == 3;
			_ = LoadReceiptsAsync();
		}

		public StatusCenterItem AddItem(
			string headerResource,
			string subHeaderResource,
			ReturnResult status,
			FileOperationType operation,
			IEnumerable<string>? source,
			IEnumerable<string>? destination,
			bool canProvideProgress = true,
			long itemsCount = 0,
			long totalSize = 0,
			CancellationTokenSource? cancellationTokenSource = null)
		{
			var banner = new StatusCenterItem(
				headerResource,
				subHeaderResource,
				status,
				operation,
				source,
				destination,
				canProvideProgress,
				itemsCount,
				totalSize,
				cancellationTokenSource);

			banner.Completed += OnItemCompleted;
			StatusCenterItems.Insert(0, banner);
			if (status != ReturnResult.InProgress) banner.Complete(status);
			NewItemAdded?.Invoke(this, banner);

			NotifyChanges();

			return banner;
		}

		public void CompleteItem(StatusCenterItem item, ReturnResult result)
		{
			item.Complete(item.CancellationToken.IsCancellationRequested ? ReturnResult.Cancelled : result);
			NotifyChanges();
		}

		public IDisposable TrackCompletion(StatusCenterItem item) => new CompletionScope(this, item);
		private sealed class CompletionScope(StatusCenterViewModel owner, StatusCenterItem item) : IDisposable
		{
			public void Dispose()
			{
				if (item.CompletedReceipt is null) owner.CompleteItem(item, ReturnResult.UnknownException);
			}
		}

		private void OnItemCompleted(object? sender, StatusCenterItemCompletedEventArgs e)
		{
			if (sender is StatusCenterItem item) item.Completed -= OnItemCompleted;
			_ = SaveReceiptAsync(e.Receipt);
		}

		private async Task SaveReceiptAsync(OperationReceipt receipt)
		{
			try
			{
				await Task.Run(() => receiptStore.AppendAsync(receipt));
				await LoadReceiptsAsync();
			}
			catch (Exception) { await ShowReceiptErrorAsync(receiptStore.HistoryPath); }
		}

		public async Task LoadReceiptsAsync()
		{
			try
			{
				var history = await Task.Run(() => receiptStore.LoadAsync());
				await MainWindow.Instance.DispatcherQueue.EnqueueOrInvokeAsync(() =>
				{
					OperationReceipts.Clear();
					foreach (var receipt in history) OperationReceipts.Add(new OperationReceiptViewModel(receipt));
					OnPropertyChanged(nameof(HasReceipts));
				});
				if (receiptStore.RecoveryPath is { } recovery) await ShowReceiptErrorAsync(recovery);
			}
			catch (Exception) { await ShowReceiptErrorAsync(receiptStore.HistoryPath); }
		}

		public Task ShowReceiptErrorAsync(string path) => MainWindow.Instance.DispatcherQueue.EnqueueOrInvokeAsync(() =>
		{
			ReceiptError = "ReceiptStorageError".GetLocalizedResource() + "\n" + path;
			OnPropertyChanged(nameof(HasReceiptError));
		});

		public async Task ExportReceiptsAsync(string path, bool replaceExisting)
		{
			try { await Task.Run(() => receiptStore.ExportCsvAsync(path, replaceExisting)); }
			catch (Exception) { await ShowReceiptErrorAsync(path); }
		}

		public async Task ClearReceiptsAsync()
		{
			try { await Task.Run(() => receiptStore.ClearAsync()); await LoadReceiptsAsync(); }
			catch (Exception) { await ShowReceiptErrorAsync(receiptStore.HistoryPath); }
		}

		public bool RemoveItem(StatusCenterItem card)
		{
			if (!StatusCenterItems.Contains(card))
				return false;

			StatusCenterItems.Remove(card);

			NotifyChanges();

			return true;
		}

		public void RemoveAllCompletedItems()
		{
			for (var i = StatusCenterItems.Count - 1; i >= 0; i--)
			{
				if (!StatusCenterItems[i].IsInProgress)
					StatusCenterItems.RemoveAt(i);
			}

			NotifyChanges();
		}

		public void NotifyChanges()
		{
			OnPropertyChanged(nameof(InProgressItemCount));
			OnPropertyChanged(nameof(HasAnyItemInProgress));
			OnPropertyChanged(nameof(HasAnyItem));
			OnPropertyChanged(nameof(InfoBadgeState));
			OnPropertyChanged(nameof(InfoBadgeValue));

			UpdateAverageProgressValue();
			UpdateTaskbarProgress();
		}

		public void UpdateAverageProgressValue()
		{
			if (HasAnyItemInProgress)
				AverageOperationProgressValue = (int)StatusCenterItems.Where((item) => item.IsInProgress).Average(x => x.ProgressPercentage);
			else
				AverageOperationProgressValue = 0;
		}

		private void UpdateTaskbarProgress()
		{
			try
			{
				var hwnd = new Windows.Win32.Foundation.HWND(MainWindow.Instance.WindowHandle);

				if (HasAnyItemInProgress)
				{
					_taskbar.SetProgressState(hwnd, Windows.Win32.UI.Shell.TBPFLAG.TBPF_NORMAL);
					_taskbar.SetProgressValue(hwnd, (ulong)Math.Clamp(AverageOperationProgressValue, 0, 100), 100);
				}
				else
				{
					_taskbar.SetProgressState(hwnd, Windows.Win32.UI.Shell.TBPFLAG.TBPF_NOPROGRESS);
				}
			}
			catch
			{
				// Ignore taskbar update failures to avoid interrupting status updates.
			}
		}
	}
}
