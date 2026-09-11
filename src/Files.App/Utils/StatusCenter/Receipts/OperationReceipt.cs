// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Files.App.Data.Enums;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Files.App.Utils.StatusCenter.Receipts;

public sealed class OperationReceipt
{
	public const int CurrentSchemaVersion = 1;
	public int SchemaVersion => CurrentSchemaVersion;
	public Guid Id { get; }
	public DateTimeOffset StartedAtUtc { get; }
	public DateTimeOffset CompletedAtUtc { get; }
	public FileOperationType FileOperationType { get; }
	public ReturnResult ReturnResult { get; }
	public IReadOnlyList<string> SourcePaths { get; }
	public IReadOnlyList<string> DestinationPaths { get; }
	public long ItemCount { get; }
	public long TotalBytes { get; }
	public string? FailureCode { get; }

	public OperationReceipt(Guid id, DateTimeOffset startedAtUtc, DateTimeOffset completedAtUtc,
		FileOperationType fileOperationType, ReturnResult returnResult, IEnumerable<string> sourcePaths,
		IEnumerable<string> destinationPaths, long itemCount, long totalBytes, string? failureCode = null)
	{
		if (id == Guid.Empty || completedAtUtc < startedAtUtc || !Enum.IsDefined(fileOperationType)
			|| !Enum.IsDefined(returnResult) || returnResult == ReturnResult.InProgress || itemCount < 0 || totalBytes < 0)
			throw new ArgumentException("Invalid terminal operation receipt.");
		// Codes are identifiers, never exception messages, user data or credentials.
		if (failureCode is not null && (failureCode.Length > 80 || failureCode.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '_')))
			throw new ArgumentException("Failure code must be a neutral identifier.");
		Id = id;
		StartedAtUtc = startedAtUtc.ToUniversalTime();
		CompletedAtUtc = completedAtUtc.ToUniversalTime();
		FileOperationType = fileOperationType;
		ReturnResult = returnResult;
		SourcePaths = Array.AsReadOnly(sourcePaths.Select(SanitizePath).ToArray());
		DestinationPaths = Array.AsReadOnly(destinationPaths.Select(SanitizePath).ToArray());
		ItemCount = itemCount;
		TotalBytes = totalBytes;
		FailureCode = failureCode;
	}

	internal static string SanitizePath(string path)
	{
		ArgumentNullException.ThrowIfNull(path);
		if (Uri.TryCreate(path, UriKind.Absolute, out var uri) && !uri.IsFile && path.Contains("://", StringComparison.Ordinal))
			return new UriBuilder(path.Split('?', '#')[0]) { UserName = "", Password = "", Query = "", Fragment = "" }.Uri.AbsoluteUri;
		return path;
	}
}
