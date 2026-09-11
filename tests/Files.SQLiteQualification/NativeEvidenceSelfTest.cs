// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using System.Text.Json;

internal static class NativeEvidenceSelfTest
{
	internal static void Run()
	{
		var results = new List<string>();
		void Check(bool condition, string label)
		{
			if (!condition) throw new Exception("Native library evidence regression: " + label);
			results.Add(label);
		}
		var native = @"C:\owned\e_sqlite3.dll";
		var modules = new[] { native, @"C:\owned\SQLitePCLRaw.provider.e_sqlite3.dll", @"C:\owned\other_e_sqlite3.dll", @"C:\owned\Microsoft.Data.Sqlite.dll" };
		Check(Native.SelectSQLite(modules, true).SequenceEqual(new[] { native }), "managed provider is not counted as a native library");
		Check(Native.SelectSQLite(new[] { "C:/owned/E_SQLITE3.DLL" }, true).Length == 1, "Windows filename case is accepted");
		Check(Native.SelectSQLite(new[] { native, @"C:\unexpected\e_sqlite3.dll" }, true).Length == 2, "duplicate native libraries remain visible to the caller");
		Check(Native.SelectSQLite(modules.Skip(1), true).Length == 0, "missing native library is not replaced by provider suffix");
		Check(Native.SelectSQLite(new[] { "/owned/libe_sqlite3.dylib", "/owned/LIBE_SQLITE3.DYLIB", "/owned/otherlibe_sqlite3.dylib" }, false).SequenceEqual(new[] { "/owned/libe_sqlite3.dylib" }), "macOS exact native basename is preserved");
		var output = Path.Combine(Path.GetTempPath(), "FileQuay-module-evidence-output");
		Check(Native.IsWithinOutput(Path.Combine(output, "e_sqlite3.dll"), output), "library inside output is accepted");
		Check(Native.IsWithinOutput(Path.Combine(output, "native", "e_sqlite3.dll"), output), "nested output library is accepted");
		Check(!Native.IsWithinOutput(Path.Combine(output + "-other", "e_sqlite3.dll"), output), "sibling with the same path prefix is rejected");
		Check(!Native.IsWithinOutput(Path.Combine(output, "..", "e_sqlite3.dll"), output), "normalized parent escape is rejected");
		Check(!Native.IsWithinOutput(output, output), "the output directory is not a library path");
		Console.WriteLine(JsonSerializer.Serialize(new { results, checksPassed = results.Count }));
	}
}
