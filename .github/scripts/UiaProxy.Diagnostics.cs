// Copyright 2026 Trieflow LLC. Licensed under the MIT License.
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace FileQuayQualification
{
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
