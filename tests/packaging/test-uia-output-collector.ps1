# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
param([switch]$OriginalSynchronousReader)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$source=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$code=Get-Content (Join-Path $source '.github/scripts/UiaProxy.Diagnostics.cs') -Raw
if($OriginalSynchronousReader){$code=$code.Replace('Reading = Task.Run(() => Read(stream));','Reading = Read(stream);')}
Add-Type -TypeDefinition $code
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
public static class SynchronousPrefixCollectorTest {
    private sealed class BlockingStream : MemoryStream {
        public readonly ManualResetEventSlim Entered = new ManualResetEventSlim();
        public readonly ManualResetEventSlim Release = new ManualResetEventSlim();
        public BlockingStream(char value, int count) : base(Encoding.UTF8.GetBytes(new string(value,count))) {}
        public override Task<int> ReadAsync(byte[] buffer,int offset,int count,CancellationToken token) {
            Entered.Set();
            if(!Release.Wait(5000)) throw new TimeoutException("Fixture stream release missing");
            return Task.FromResult(Read(buffer,offset,count));
        }
    }
    private static void Require(bool condition,string message) { if(!condition) throw new Exception(message); }
    public static void Run(Type collector) {
        using(var output = new BlockingStream('O',20000))
        using(var error = new BlockingStream('E',24000)) {
            // A dedicated constructor caller lets the fixture detect blocking and
            // release its own streams in finally even against the original code.
            var construction=Task.Factory.StartNew(()=>Activator.CreateInstance(collector,output,error),
                CancellationToken.None,TaskCreationOptions.LongRunning,TaskScheduler.Default);
            try {
                Require(construction.Wait(1000),"Production collector constructor blocked before ReadAsync returned its Task");
                Require(output.Entered.Wait(1000) && error.Entered.Wait(1000),"Both independent stream drains did not enter");
                object value=construction.Result;
                Require(!(bool)collector.GetMethod("Finish").Invoke(value,new object[]{0}),"Blocked streams falsely completed");
                foreach(string channel in new[]{"Stdout","Stderr"}) {
                    object snapshot=collector.GetMethod(channel).Invoke(value,null);Type type=snapshot.GetType();
                    Require((long)type.GetField("observed_bytes").GetValue(snapshot)==0 && !(bool)type.GetField("completed").GetValue(snapshot),"Blocked stream fabricated output");
                }
                output.Release.Set();error.Release.Set();
                Require((bool)collector.GetMethod("Finish").Invoke(value,new object[]{1000}),"Released streams did not drain within collector bound");
                foreach(string channel in new[]{"Stdout","Stderr"}) {
                    object snapshot=collector.GetMethod(channel).Invoke(value,null);Type type=snapshot.GetType();
                    char character=channel=="Stdout"?'O':'E';long count=channel=="Stdout"?20000:24000;
                    Require((long)type.GetField("observed_bytes").GetValue(snapshot)==count &&
                        (int)type.GetField("retained_bytes").GetValue(snapshot)==8192 &&
                        (bool)type.GetField("truncated").GetValue(snapshot) &&
                        (bool)type.GetField("completed").GetValue(snapshot) &&
                        type.GetField("read_error").GetValue(snapshot)==null &&
                        (string)type.GetField("text").GetValue(snapshot)==new string(character,8192),"Stream bytes/bounds/completion changed");
                }
            } finally {
                output.Release.Set();error.Release.Set();
                if(!construction.Wait(5000)) throw new Exception("Fixture constructor did not finish after release");
                collector.GetMethod("Finish").Invoke(construction.Result,new object[]{1000});
            }
        }
    }
}
'@
[SynchronousPrefixCollectorTest]::Run([FileQuayQualification.FixtureChildOutput])
'PASS actual production collector: constructor returns while both ReadAsync prefixes block; both streams drain within unchanged output bounds.'
