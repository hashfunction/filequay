// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Files.App.Data.Enums;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace Files.App.Utils.StatusCenter.Receipts;

public static class OperationReceiptCodec
{
	private static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
	public static byte[] Encode(IEnumerable<OperationReceipt> receipts) => JsonSerializer.SerializeToUtf8Bytes(
		new { SchemaVersion = OperationReceipt.CurrentSchemaVersion, Receipts = receipts }, Options);

	public static IReadOnlyList<OperationReceipt> Decode(byte[] bytes)
	{
		try
		{
			using var doc = JsonDocument.Parse(bytes);
			var root = doc.RootElement;
			if (root.GetProperty("schemaVersion").GetInt32() != OperationReceipt.CurrentSchemaVersion)
				throw new InvalidDataException("Unsupported receipt history version.");
			var receipts = new List<OperationReceipt>();
			foreach (var r in root.GetProperty("receipts").EnumerateArray())
			{
				if (r.GetProperty("schemaVersion").GetInt32() != OperationReceipt.CurrentSchemaVersion)
					throw new InvalidDataException("Unsupported receipt version.");
				receipts.Add(new OperationReceipt(r.GetProperty("id").GetGuid(), r.GetProperty("startedAtUtc").GetDateTimeOffset(),
					r.GetProperty("completedAtUtc").GetDateTimeOffset(), (FileOperationType)r.GetProperty("fileOperationType").GetByte(),
					(ReturnResult)r.GetProperty("returnResult").GetByte(),
					r.GetProperty("sourcePaths").EnumerateArray().Select(p => p.GetString() ?? throw new InvalidDataException("Null source path.")),
					r.GetProperty("destinationPaths").EnumerateArray().Select(p => p.GetString() ?? throw new InvalidDataException("Null destination path.")),
					r.GetProperty("itemCount").GetInt64(), r.GetProperty("totalBytes").GetInt64(), r.GetProperty("failureCode").GetString()));
			}
			if (receipts.Select(r => r.Id).Distinct().Count() != receipts.Count)
				throw new InvalidDataException("Duplicate receipt identity.");
			return receipts.AsReadOnly();
		}
		catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
		{
			throw new InvalidDataException("Invalid receipt history; no records were loaded.", e);
		}
	}

	public static string ToCsv(IEnumerable<OperationReceipt> receipts)
	{
		var csv = new StringBuilder("Id,StartedAtUtc,CompletedAtUtc,Operation,Result,ItemCount,TotalBytes,SourcePaths,DestinationPaths,FailureCode\r\n");
		foreach (var r in receipts)
			csv.AppendJoin(',', new[] { r.Id.ToString(), r.StartedAtUtc.ToString("O", CultureInfo.InvariantCulture),
				r.CompletedAtUtc.ToString("O", CultureInfo.InvariantCulture), r.FileOperationType.ToString(), r.ReturnResult.ToString(),
				r.ItemCount.ToString(CultureInfo.InvariantCulture), r.TotalBytes.ToString(CultureInfo.InvariantCulture),
				string.Join('\n', r.SourcePaths), string.Join('\n', r.DestinationPaths), r.FailureCode ?? "" }.Select(CsvCell)).Append("\r\n");
		return csv.ToString();
	}

	private static string CsvCell(string value)
	{
		// Quoting alone does not prevent Excel from evaluating a formula.
		var start = value.TrimStart(' ', '\t', '\r', '\n');
		if (start.Length > 0 && "=+-@".Contains(start[0]) || value.StartsWith('\t') || value.StartsWith('\r'))
			value = "'" + value;
		return "\"" + value.Replace("\"", "\"\"") + "\"";
	}
}
