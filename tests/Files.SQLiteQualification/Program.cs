// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using Microsoft.Data.Sqlite;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Reflection;
using System.Text.RegularExpressions;

if (args.SequenceEqual(new[] { "--native-evidence-self-test" }))
{
	NativeEvidenceSelfTest.Run();
	return;
}

string Resource(string name)
{
	using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name) ?? throw new Exception("Missing qualification resource: " + name);
	using var reader = new StreamReader(stream);
	return reader.ReadToEnd();
}
using var dependencyLock = JsonDocument.Parse(Resource("sqlite-dependencies.lock.json"));
var results = new List<string>();
void Check(bool ok, string label) { if (!ok) throw new Exception("SQLite qualification failed: " + label); results.Add(label); }
void Exec(SqliteConnection c, string sql) { using var q = c.CreateCommand(); q.CommandText = sql; q.ExecuteNonQuery(); }
object? Scalar(SqliteConnection c, string sql) { using var q = c.CreateCommand(); q.CommandText = sql; return q.ExecuteScalar(); }
var root = Path.Combine(Path.GetTempPath(), "FileQuay-owned-sqlite-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
	SQLitePCL.Batteries_V2.Init();
	SQLitePCL.Batteries_V2.Init();
	using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = Path.Combine(root, "fixture.db"), Pooling = false }.ToString());
	db.Open();
	var version = (string)Scalar(db, "SELECT sqlite_version()")!;
	var sourceId = (string)Scalar(db, "SELECT sqlite_source_id()")!;
	Check(version == dependencyLock.RootElement.GetProperty("nativeVersion").GetString(), "exact native version");
	Check(sourceId == dependencyLock.RootElement.GetProperty("nativeSourceId").GetString(), "exact upstream source ID");
	var modules = Native.LoadedSQLite();
	Check(modules.Length == 1, "one loaded e_sqlite3 library; observed: " + JsonSerializer.Serialize(modules));
	Check(Native.IsWithinOutput(modules[0], AppContext.BaseDirectory), "native library loaded from owned output");
	var runtimeId = RuntimeInformation.RuntimeIdentifier;
	var nativeHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(modules[0]))).ToLowerInvariant();
	Check(nativeHash == dependencyLock.RootElement.GetProperty("nativeExecutionSha256").GetProperty(runtimeId).GetString(), "exact executed native bytes");
	Exec(db, "CREATE TABLE roots(last_seen_absolute_path TEXT,title TEXT); CREATE TABLE media(last_mount_point TEXT,name TEXT,fs_type INTEGER); CREATE TABLE connection_table(id TEXT,conn_type INTEGER,host_name TEXT); CREATE TABLE session_table(conn_id TEXT,sync_folder TEXT);");
	using (var q = db.CreateCommand())
	{
		q.CommandText = "INSERT INTO roots VALUES ($path,$name); INSERT INTO media VALUES ($path,$name,10); INSERT INTO media VALUES ('excluded','excluded',9); INSERT INTO connection_table VALUES ('id1',1,'Synology'); INSERT INTO session_table VALUES ('id1',$path)";
		q.Parameters.AddWithValue("$path", @"C:\資料\O'Brien"); q.Parameters.AddWithValue("$name", "日本語 O'Brien"); q.ExecuteNonQuery();
	}
	using (var q = new SqliteCommand("SELECT * FROM roots", db)) using (var r = q.ExecuteReader()) { Check(r.Read() && r["last_seen_absolute_path"].ToString() == @"C:\資料\O'Brien" && r["title"].ToString() == "日本語 O'Brien" && !r.Read(), "Google roots exact query and Unicode"); }
	using (var q = new SqliteCommand("SELECT * FROM media WHERE fs_type=10", db)) using (var r = q.ExecuteReader()) { Check(r.Read() && r["name"].ToString() == "日本語 O'Brien" && !r.Read(), "Google media exact filter"); }
	using (var q = new SqliteCommand("SELECT * FROM connection_table", db)) using (var r = q.ExecuteReader()) { Check(r.Read() && r["id"].ToString() == "id1" && r["conn_type"].ToString() == "1", "Synology connections exact query"); }
	using (var q = new SqliteCommand("SELECT * FROM session_table", db)) using (var r = q.ExecuteReader()) { Check(r.Read() && r["conn_id"].ToString() == "id1" && r["sync_folder"].ToString() == @"C:\資料\O'Brien", "Synology sessions exact query"); }
	using (var q = new SqliteCommand("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY 1", db)) using (var r = await q.ExecuteReaderAsync()) { var names = new List<string>(); while (await r.ReadAsync()) names.Add(r.GetString(0)); Check(names.SequenceEqual(new[] { "connection_table", "media", "roots", "session_table" }), "Google async schema inspection"); }
	// Execute the SQL strings embedded from the actual detector sources. Schema/WinRT copying remains outside this host.
	var expectedRows = new Dictionary<string, int>
	{
		["SELECT * FROM roots"] = 1,
		["SELECT * FROM media WHERE fs_type=10"] = 1,
		["SELECT * FROM media"] = 2,
		["SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY 1"] = 4,
		["SELECT * FROM connection_table"] = 1,
		["SELECT * FROM session_table"] = 1
	};
	foreach (var detector in new[] { "GoogleDriveCloudDetector.cs", "SynologyDriveCloudDetector.cs" })
	{
		var matches = Regex.Matches(Resource(detector), "\"(SELECT [^\"]+)\"").Select(m => m.Groups[1].Value).Distinct().ToArray();
		Check(matches.Length == (detector.StartsWith("Google") ? 4 : 2), detector + " SQL captured from production");
		foreach (var sql in matches)
		{
			Check(expectedRows.ContainsKey(sql), "owned fixture covers production SQL: " + sql);
			using var command = new SqliteCommand(sql, db); using var rows = await command.ExecuteReaderAsync();
			int count = 0; while (await rows.ReadAsync()) count++;
			Check(count == expectedRows[sql], "production SQL result: " + sql);
		}
	}
	Exec(db, "BEGIN; INSERT INTO roots VALUES ('rollback','rollback'); ROLLBACK;");
	Check((long)Scalar(db, "SELECT count(*) FROM roots")! == 1, "transaction rollback preserved fixture");
	db.CreateFunction<string, string>("owned_identity", x => x);
	Check((string)Scalar(db, "SELECT owned_identity('資料')")! == "資料", "managed callback provider ABI");
	using (var ro = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = db.DataSource, Mode = SqliteOpenMode.ReadOnly, Pooling = false }.ToString()))
	{
		ro.Open(); Check((long)Scalar(ro, "SELECT count(*) FROM roots")! == 1, "read-only reopen");
		try { Exec(ro, "DELETE FROM roots"); throw new Exception("read-only write unexpectedly succeeded"); } catch (SqliteException e) { Check(e.SqliteErrorCode == 8, "read-only write rejected"); }
	}
	var walPath = Path.Combine(root, "wal.db");
	using (var wal = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = walPath, Pooling = false }.ToString()))
	{
		wal.Open(); Check((string)Scalar(wal, "PRAGMA journal_mode=WAL")! == "wal", "WAL available");
		Exec(wal, "PRAGMA wal_autocheckpoint=0; CREATE TABLE roots(last_seen_absolute_path TEXT,title TEXT); INSERT INTO roots VALUES ('owned-wal-path','owned-wal-title');");
		Check(File.Exists(walPath + "-wal") && new FileInfo(walPath + "-wal").Length > 0, "fixture has committed WAL frames");
		var copy = Path.Combine(root, "copied.db"); File.Copy(walPath, copy); File.Copy(walPath + "-wal", copy + "-wal");
		using var copied = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = copy, Pooling = false }.ToString()); copied.Open();
		Check((string)Scalar(copied, "SELECT title FROM roots")! == "owned-wal-title", "copied database and WAL are read together");
		Check((string)Scalar(copied, "PRAGMA integrity_check")! == "ok", "copied WAL integrity");
	}
	var malformed = Path.Combine(root, "malformed.db"); File.WriteAllText(malformed, new string('x', 1024));
	try { using var bad = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = malformed, Pooling = false }.ToString()); bad.Open(); Scalar(bad, "SELECT name FROM sqlite_master"); throw new Exception("malformed database accepted"); } catch (SqliteException e) { Check(e.SqliteErrorCode == 26, "malformed database handled as SQLite error"); }
	var evidence = new { version, sourceId, sdkRuntime = RuntimeInformation.FrameworkDescription, architecture = RuntimeInformation.ProcessArchitecture.ToString(), nativePath = modules[0], nativeSha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(modules[0]))).ToLowerInvariant(), results };
	Console.WriteLine(JsonSerializer.Serialize(evidence, new JsonSerializerOptions { WriteIndented = true }));
}
finally { SqliteConnection.ClearAllPools(); Directory.Delete(root, true); }
static class Native
{
	[DllImport("/usr/lib/libSystem.B.dylib")] static extern uint _dyld_image_count();
	[DllImport("/usr/lib/libSystem.B.dylib")] static extern IntPtr _dyld_get_image_name(uint index);
	internal static string[] LoadedSQLite()
	{
		if (OperatingSystem.IsMacOS()) return SelectSQLite(Enumerable.Range(0, (int)_dyld_image_count()).Select(i => Marshal.PtrToStringUTF8(_dyld_get_image_name((uint)i))!), false);
		return SelectSQLite(Process.GetCurrentProcess().Modules.Cast<ProcessModule>().Select(m => m.FileName), true);
	}
	internal static string[] SelectSQLite(IEnumerable<string> paths, bool windows) => paths.Where(p =>
		string.Equals(Path.GetFileName(windows ? p.Replace('\\', '/') : p), windows ? "e_sqlite3.dll" : "libe_sqlite3.dylib",
			windows ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)).ToArray();
	internal static bool IsWithinOutput(string module, string output)
	{
		var relative = Path.GetRelativePath(Path.GetFullPath(output), Path.GetFullPath(module));
		return relative != "." && relative != ".." && !relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) && !Path.IsPathRooted(relative);
	}
}
