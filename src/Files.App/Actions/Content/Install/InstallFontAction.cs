// Copyright (c) Files Community
// Licensed under the MIT License.

using Files.Shared.Helpers;

namespace Files.App.Actions
{
	[GeneratedRichCommand]
	internal sealed partial class InstallFontAction : ObservableObject, IAction
	{
		private readonly IContentPageContext context;
		private static readonly StatusCenterViewModel StatusCenterViewModel = Ioc.Default.GetRequiredService<StatusCenterViewModel>();

		public string Label
			=> Strings.InstallFont.GetLocalizedResource();

		public string Description
			=> Strings.InstallFontDescription.GetLocalizedFormatResource(context.SelectedItems.Count);

		public RichGlyph Glyph
			=> new(themedIconStyle: "App.ThemedIcons.Actions.FontInstall");

		public ActionCategory Category
			=> ActionCategory.Install;

		public bool IsExecutable =>
			context.SelectedItems.Any() &&
			context.SelectedItems.All(x => FileExtensionHelpers.IsFontFile(x.FileExtension)) &&
			context.PageType != ContentPageTypes.RecycleBin &&
			context.PageType != ContentPageTypes.ZipFolder;

		public InstallFontAction()
		{
			context = Ioc.Default.GetRequiredService<IContentPageContext>();

			context.PropertyChanged += Context_PropertyChanged;
		}

		public async Task ExecuteAsync(object? parameter = null)
		{
			if (context.ShellPage?.ShellViewModel?.WorkingDirectory is not { } workingDirectory)
				return;

			var paths = context.SelectedItems.Select(item => item.ItemPath!).ToArray();
			var banner = StatusCenterHelper.AddCard_InstallFont(paths, ReturnResult.InProgress, paths.Length);
			using var completion = StatusCenterViewModel.TrackCompletion(banner);
			banner.IsCancelable = false;

			await Win32Helper.InstallFontsAsync(paths, false);

			StatusCenterViewModel.CompleteItem(banner, ReturnResult.Success);
		}

		public void Context_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
		{
			switch (e.PropertyName)
			{
				case nameof(IContentPageContext.SelectedItems):
				case nameof(IContentPageContext.PageType):
					OnPropertyChanged(nameof(IsExecutable));
					break;
			}
		}
	}
}
