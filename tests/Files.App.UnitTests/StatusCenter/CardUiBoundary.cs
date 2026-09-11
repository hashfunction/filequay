// Copyright (c) Trieflow LLC. Licensed under the MIT License.
// Test-only WinUI/localization host. The helper and queue card are linked production files.
global using Files.App.Data.Enums;
global using Files.App.Utils.StatusCenter;
global using Files.App.UnitTests.StatusCenter;
global using System.Collections.ObjectModel;
global using CommunityToolkit.Mvvm.ComponentModel;
global using CommunityToolkit.Mvvm.Input;
using System.Xml.Linq;

namespace Microsoft.UI.Xaml.Media { public sealed class SolidColorBrush { } }
namespace Files.App { public sealed class App
{
	public static App Current { get; } = new();
	public Dictionary<string, object> Resources { get; } = new() { ["App.Theme.FillColorAttentionBrush"] = new Microsoft.UI.Xaml.Media.SolidColorBrush() };
} }
namespace Files.App.UnitTests.StatusCenter
{
	public sealed class Ioc
	{
		public static Ioc Default { get; } = new();
		private readonly StatusCenterViewModel model = new();
		public T GetRequiredService<T>() where T : class => (model as T)!;
	}
	public sealed class StatusCenterViewModel
	{
		public void NotifyChanges() { }
		public StatusCenterItem AddItem(string header, string subheader, ReturnResult result, FileOperationType operation,
			IEnumerable<string>? source, IEnumerable<string>? destination, bool progress, long count = 0, long bytes = 0, CancellationTokenSource? cancellation = null)
			=> new(header, subheader, result, operation, source, destination, progress, count, bytes, cancellation);
	}
	public interface IStorageItemWithPath { string Path { get; } }
	public static class PathNormalization { public static string GetParentDir(string? value) => Path.GetDirectoryName(value) ?? string.Empty; }
	public static class Strings
	{
		public const string DiscoveringItems = "DiscoveringItems", ProcessingItems = "ProcessingItems", Canceling = "Canceling";
		public const string StatusCenter_ProcessedItems_Header = "StatusCenter_ProcessedItems_Header", StatusCenter_ProcessedSize_Header = "StatusCenter_ProcessedSize_Header";
	}
	public static class ResourceHost
	{
		private static readonly Dictionary<string, string> strings = XDocument.Load(Path.Combine(AppContext.BaseDirectory, "Resources.resw"))
			.Descendants("data").ToDictionary(x => (string)x.Attribute("name")!, x => x.Element("value")!.Value);
		public static string GetLocalizedResource(this string key) => strings.TryGetValue(key, out var value) ? value : key;
		public static string GetLocalizedFormatResource(this string key, params object[] args) => string.Format(key.GetLocalizedResource(), args);
		public static IEnumerable<T> CreateEnumerable<T>(this T value) => [value];
		public static string ToSizeString(this long value) => value.ToString();
		public static string ToSizeString(this double value) => value.ToString();
		public static ReturnResult ToStatus(this FileSystemStatusCode code) => (ReturnResult)code;
	}
	public enum FileSystemStatusCode { InProgress, Success }
	public sealed class StatusCenterItemProgressModel(IProgress<StatusCenterItemProgressModel> progress, FileSystemStatusCode status)
	{
		public IProgress<StatusCenterItemProgressModel> Progress { get; } = progress;
		public FileSystemStatusCode? Status { get; set; } = status;
		public long ItemsCount { get; set; }
		public long TotalSize { get; set; }
		public double? Percentage { get; set; }
		public string? FileName { get; set; }
		public long ProcessedItemsCount { get; set; }
		public long ProcessedSize { get; set; }
		public double ProcessingSizeSpeed { get; set; }
		public double ProcessingItemsCountSpeed { get; set; }
		public bool EnumerationCompleted { get; set; }
	}
}
