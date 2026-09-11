// Copyright 2026 Trieflow LLC. Licensed under the MIT License.
#if FILEQUAY_CI_QUALIFICATION
using System.IO;
using Windows.ApplicationModel;
using Windows.Storage;

namespace Files.App.Utils.Qualification;

// Compiled only into instrumented qualification builds. The client projection
// comes from the actual Files.App.Server.winmd already consumed by this project.
internal static class CiComActivationProbe
{
    internal static bool TryRun(string? arguments)
    {
        const string prefix = "--filequay-ci-com-probe=";
        if (arguments is null || !arguments.StartsWith(prefix, StringComparison.Ordinal))
            return false;
        var identity = Package.Current.Id;
        if (identity.Name != "Trieflow.FileQuay.Qualification" || identity.Publisher != "CN=FileQuay-CI-Qualification")
            throw new InvalidOperationException("COM qualification requires the exact disposable CI package identity and publisher.");
        if (!Guid.TryParseExact(arguments[prefix.Length..], "N", out var nonce))
            throw new ArgumentException("A canonical qualification nonce is required.");
        string stem = Path.Combine(ApplicationData.Current.LocalFolder.Path, "com-probe-" + nonce.ToString("N"));
        using var stdout = new StreamWriter(stem + ".stdout.txt", append: false) { AutoFlush = true };
        using var stderr = new StreamWriter(stem + ".stderr.txt", append: false) { AutoFlush = true };
        var result = new Dictionary<string, object?>
        {
            ["instrumented_qualification_build"] = true,
            ["package_full_name"] = identity.FullName,
            ["client_process_id"] = Environment.ProcessId,
            ["activation_class"] = "Files.App.Server.AppInstanceMonitor",
            ["method"] = "StartMonitor",
            ["activation_succeeded"] = false,
            ["activation_hresult"] = null
        };
        void Save()
        {
            File.WriteAllText(stem + ".json.tmp", JsonSerializer.Serialize(result));
            File.Move(stem + ".json.tmp", stem + ".json", overwrite: true);
        }
        try
        {
            stdout.WriteLine($"Requesting the generated static WinRT interface for live client PID {Environment.ProcessId}.");
            Server.AppInstanceMonitor.StartMonitor(Environment.ProcessId);
            result["activation_succeeded"] = true;
            result["activation_hresult"] = 0;
            Save();
            stdout.WriteLine("StartMonitor returned successfully; waiting for the qualifier to release this client.");
            var timeout = Stopwatch.StartNew();
            while (!File.Exists(stem + ".release"))
            {
                if (timeout.Elapsed > TimeSpan.FromSeconds(120))
                    throw new TimeoutException("Qualifier did not release the monitored client.");
                Thread.Sleep(100);
            }
            result["client_exit_requested"] = true;
            stdout.WriteLine("Release received; monitored client is exiting normally.");
            Save();
        }
        catch (Exception error)
        {
            result["error"] = error.ToString();
            if (!(bool)result["activation_succeeded"]!) result["activation_hresult"] = error.HResult;
            stderr.WriteLine(error);
            Save();
            Environment.ExitCode = 1;
        }
        return true;
    }
}
#endif
