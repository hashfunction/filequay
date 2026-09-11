// Copyright (c) Files Community
// Licensed under the MIT License.

using CommunityToolkit.WinUI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;

namespace Files.App.UserControls.StatusCenter
{
	public sealed partial class StatusCenter : UserControl
	{
		public StatusCenterViewModel ViewModel;

		public StatusCenter()
		{
			ViewModel = Ioc.Default.GetRequiredService<StatusCenterViewModel>();
			InitializeComponent();
		}

		private void OperationViews_SelectionChanged(object sender, SelectionChangedEventArgs e)
		{
			if (CloseAllItemsButton is not null && sender is Pivot pivot) CloseAllItemsButton.Visibility = pivot.SelectedIndex == 0 ? Visibility.Visible : Visibility.Collapsed;
		}

		private async void ExportReceipts_Click(object sender, RoutedEventArgs e)
		{
			var affectedPath = ViewModel.ReceiptHistoryPath;
			try
			{
				var picker = new FileSavePicker { SuggestedFileName = "FileQuay-receipts", DefaultFileExtension = ".csv" };
				picker.FileTypeChoices.Add("CSV", new List<string> { ".csv" });
				WinRT.Interop.InitializeWithWindow.Initialize(picker, MainWindow.Instance.WindowHandle);
				var file = await picker.PickSaveFileAsync();
				if (file is null) return;
				affectedPath = file.Path;
				// The platform picker may create an empty file. Confirm the exact selected path before replacing it.
				var confirmation = new ContentDialog
				{
					XamlRoot = MainWindow.Instance.Content.XamlRoot,
					Title = "ReceiptExport".GetLocalizedResource(),
					Content = "ReceiptExportConfirm".GetLocalizedResource() + "\n" + file.Path,
					PrimaryButtonText = "ReceiptExport".GetLocalizedResource(),
					CloseButtonText = Strings.Cancel.GetLocalizedResource(),
					DefaultButton = ContentDialogButton.Close
				};
				if (await confirmation.TryShowAsync() == ContentDialogResult.Primary)
					await ViewModel.ExportReceiptsAsync(file.Path, true);
			}
			catch (Exception) { await ViewModel.ShowReceiptErrorAsync(affectedPath); }
		}

		private async void ClearReceipts_Click(object sender, RoutedEventArgs e)
		{
			var confirmation = new ContentDialog
			{
				XamlRoot = MainWindow.Instance.Content.XamlRoot,
				Title = "ReceiptClear".GetLocalizedResource(),
				Content = "ReceiptClearConfirm".GetLocalizedResource(),
				PrimaryButtonText = "ReceiptClear".GetLocalizedResource(),
				CloseButtonText = Strings.Cancel.GetLocalizedResource(),
				DefaultButton = ContentDialogButton.Close
			};
			if (await confirmation.TryShowAsync() == ContentDialogResult.Primary) await ViewModel.ClearReceiptsAsync();
		}

		private void CloseAllItemsButton_Click(object sender, RoutedEventArgs e)
		{
			ViewModel.RemoveAllCompletedItems();
		}

		private void CloseItemButton_Click(object sender, RoutedEventArgs e)
		{
			if (sender is Button button && button.DataContext is StatusCenterItem item)
				ViewModel.RemoveItem(item);
		}

		private void ExpandCollapseChevronItemButton_Click(object sender, RoutedEventArgs e)
		{
			if (sender is Button button && button.DataContext is StatusCenterItem item)
			{
				var buttonAnimatedIcon = button.FindDescendant<AnimatedIcon>();

				if (buttonAnimatedIcon is not null)
					AnimatedIcon.SetState(buttonAnimatedIcon, item.IsExpanded ? "NormalOff" : "NormalOn");

				item.IsExpanded = !item.IsExpanded;
			}
		}
	}
}
