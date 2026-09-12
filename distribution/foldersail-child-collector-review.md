# FolderSail child collector and retention observation

## Original evidence and scope

Windows run `34723232432` on `ece49a35` failed in both jobs while testing the real failed child, before the UIA fixture or consumer could qualify. The original primary was `Native UIA fixture process could not be retained.`; the test expected the later readiness refusal. Original log: `/private/tmp/foldersail-34723232432-failed.log`. It did not retain which immediate process predicate failed. No successful Windows readiness or consumer claim follows from this change.

The reader now queues the entire async drain with `Task.Run`, independently for stdout and stderr. This proves the constructor cannot execute a stream's synchronous `ReadAsync` prefix on its caller. Retained output stays capped at 8,192 bytes per stream, excess output is drained, and completion/error/byte/hash evidence is unchanged.

## Primary-source limit

.NET's [Windows Process implementation](https://github.com/dotnet/runtime/blob/v10.0.4/src/libraries/System.Diagnostics.Process/src/System/Diagnostics/Process.Windows.cs) creates redirected `FileStream` instances with synchronous handles. However, the corresponding [Windows RandomAccess implementation](https://github.com/dotnet/runtime/blob/v10.0.4/src/libraries/System.Private.CoreLib/src/System/IO/RandomAccess.Windows.cs) uses [AsyncOverSyncWithIoCancellation](https://github.com/dotnet/runtime/blob/v10.0.4/src/libraries/Common/src/System/Threading/AsyncOverSyncWithIoCancellation.cs), whose `InvokeAsync` explicitly force-yields before executing synchronous I/O. These inspected sources therefore do **not** prove that the actual Windows pipe blocked this constructor. The failed run's exact runtime/stream implementation was not recorded. The new stream fixture proves the collector contract, not that proposed Windows root cause.

## Refusal observation

The original immediate boolean guard and error text remain unchanged. Only on its refusal, independent bounded reads retain PID, HasExited, actual/expected executable path, SafeHandle invalid/closed/value, exit code when available, framework, stdout/stderr stream types and timestamp. Missing values remain null; per-field observation errors stay secondary and cap at 512 characters, text fields at 4,096. Constructor elapsed milliseconds are also retained. No readiness budget, retry, action, UIA pattern, ownership, or cleanup policy changes.

Failed-child test errors now include those compact facts and existing ready/cleanup observations. They do not dump child output or permit another input attempt.

## Targeted verification

Host: macOS, source-local `.tools/powershell-7.6.6/pwsh` (`.NET 10.0.12`); fixture build uses the existing `.tools/dotnet-10.0.401/dotnet` and source lock.

- `test-uia-output-collector.ps1 -OriginalSynchronousReader`: expected failure, `Production collector constructor blocked before ReadAsync returned its Task`.
- Same exact production collector with queued readers: pass. Two streams synchronously block before returning their Task; constructor returns, both drains enter, no completion/output is fabricated while blocked, then all 20,000/24,000 bytes drain with exact retained bounds.
- `test-uia-child-diagnostics.ps1`: pass. Four actual subprocess cases cover bounded original errors, foreign nonce, oversized record and already-exited retained child. Original refusal messages, both pipe bytes/hashes, source/result binding and owned cleanup remain enforced. Live process observation plus unavailable handle/null path and bounded observation failures also pass.
- `test-uia-proxy-fixture.ps1`: 23 readiness/pattern policy cases, missing exact-host-provider refusal, actual locked fixture build and post-build mutation rejection pass.
- `git diff --check`: pass.

The local tests do not provide native Windows UIA support or reproduce Windows pipe behavior. A fresh Windows run must confirm whether the constructor change resolves the original failure; otherwise the next immediate refusal carries the facts needed to diagnose it without weakening the guard.
