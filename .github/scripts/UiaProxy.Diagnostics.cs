// Copyright 2026 Trieflow LLC. Licensed under the MIT License.
using System;
using System.IO;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace FileQuayQualification
{
    public static class FixtureProcessImage
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageNameW(SafeProcessHandle process, uint flags,
            StringBuilder image, ref uint size);

        public static string Read(Process process)
        {
            // Use the original retained process handle, never reopen a PID or
            // enumerate startup modules through PowerShell's Path property.
            SafeProcessHandle handle = process.SafeHandle;
            RequireLive(process, handle);
            var image = new StringBuilder(32768);
            uint size = (uint)image.Capacity;
            if (!QueryFullProcessImageNameW(handle, 0, image, ref size))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Retained fixture image query failed.");
            RequireLive(process, handle);
            if (size == 0 || size >= image.Capacity || image.Length != size)
                throw new InvalidOperationException("Retained fixture image query returned an invalid length.");
            return image.ToString();
        }
        private static void RequireLive(Process process, SafeProcessHandle handle)
        {
            if (process.HasExited || handle.IsInvalid || handle.IsClosed)
                throw new InvalidOperationException("Native UIA fixture process could not be retained.");
        }
    }

    // Observation only: continuously drain both pipes without retaining unlimited
    // output or waiting for EOF on the native readiness/input thread.
    public sealed class FixtureChildOutput
    {
        public sealed class Output
        {
            public string text, raw_base64, sha256, read_error;
            public long observed_bytes;
            public int retained_bytes;
            public bool truncated, completed;
        }
        private sealed class Reader
        {
            private readonly object gate = new object();
            private readonly MemoryStream retained = new MemoryStream();
            private long observed;
            private string error;
            private bool completed;
            public readonly Task Reading;
            // An async method can run synchronously before its first yielding await.
            // Queue each entire drain so construction never waits for a stream read.
            public Reader(Stream stream) { Reading = Task.Run(() => Read(stream)); }
            private async Task Read(Stream stream)
            {
                var buffer = new byte[1024];
                try
                {
                    int count;
                    while ((count = await stream.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) != 0)
                    {
                        lock (gate)
                        {
                            observed += count;
                            int keep = Math.Min(count, 8192 - (int)retained.Length);
                            if (keep > 0) retained.Write(buffer, 0, keep);
                        }
                    }
                    lock (gate) completed = true;
                }
                catch (Exception ex) { lock (gate) error = ex.GetType().Name; }
            }
            public Output Snapshot()
            {
                lock (gate)
                {
                    byte[] bytes = retained.ToArray();
                    return new Output { text = Encoding.UTF8.GetString(bytes),
                        raw_base64 = Convert.ToBase64String(bytes), sha256 = Convert.ToHexString(SHA256.HashData(bytes)), observed_bytes = observed,
                        retained_bytes = bytes.Length, truncated = observed > bytes.Length,
                        completed = completed, read_error = error };
                }
            }
        }
        private readonly Reader stdout, stderr;
        public FixtureChildOutput(Stream output, Stream error)
        { stdout = new Reader(output); stderr = new Reader(error); }
        public bool Finish(int timeoutMilliseconds)
        {
            if (timeoutMilliseconds < 0 || timeoutMilliseconds > 1000) throw new ArgumentOutOfRangeException(nameof(timeoutMilliseconds));
            return Task.WhenAll(stdout.Reading, stderr.Reading).Wait(timeoutMilliseconds);
        }
        public Output Stdout() { return stdout.Snapshot(); }
        public Output Stderr() { return stderr.Snapshot(); }
    }
}
