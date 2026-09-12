# FolderSail retained fixture image identity

Windows run `34724016098` failed the second real-child case (`foreign-record`) in both jobs. Immediately after refusal, Instrumented PID 5844/handle 2308 and Consumer PID 9048/handle 2260 were live with valid open handles. Both reported the exact expected `C:\Program Files\PowerShell\7\pwsh.EXE`, no observation or cleanup errors, constructor time zero, and `.NET 10.0.11` / `System.IO.FileStream`. The original log remains `/private/tmp/foldersail-34724016098-failed.log`.

This rules out the previously proposed blocked-constructor explanation for this run. The original first property value was not retained, so the precise initial null is still an inference. However, [PowerShell 7.6.6's actual Process.Path definition](https://github.com/PowerShell/PowerShell/blob/v7.6.6/src/System.Management.Automation/engine/TypeTable_Types_Ps1Xml.cs#L1029) is `$this.Mainmodule.FileName`, not a retained-handle executable query. The actual-child regression reproduces the same refusal and subsequent live/correct-path observations by making this property unavailable on its first read.

The existing source-hashed diagnostic assembly now exposes one bounded [QueryFullProcessImageNameW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew) call using the original `Process.SafeHandle`, flags zero for a Win32 path, and a fixed 32,768-character buffer. It checks live/open/valid state before and after the query and rejects API failure or invalid output length. It does not reopen a PID or enumerate modules. The existing immediate gate compares the returned path to the exact expected host path, retaining that original queried path in `fixture.retained_image_path`.

The live cleanup gate uses the same retained-handle query. Existing diagnostic `Path` observations remain available as secondary facts. Foreign, exited, invalid and unqueryable targets still fail; no identity fallback, readiness retry, delay, input replay or acceptance change was added. The original ten-second readiness deadline and all source/proxy/window/pattern/nonce/result/cleanup requirements remain unchanged.

Targeted checks on macOS with source-local PowerShell 7.6.6:

- `test-uia-child-diagnostics.ps1 -OriginalModulePath`: expected failure at the real late-path child, identical primary `Native UIA fixture process could not be retained.`, then live/valid/exact-path facts. This test-only switch substitutes the former property expression in memory.
- Normal script: all six actual child-process cases pass (original bounded output, foreign nonce, oversized record, already-exited child, late Path and foreign image). The late property is never queried by the corrected gate. A foreign image is refused immediately, with the only subsequent image query at owned cleanup. Exact pipe bytes/hashes and original rejection/cleanup assertions remain intact.
- Production blocking-prefix collector still passes.
- Existing fixture suite: 23 policy cases, exact missing-host-provider refusal, actual SDK 10.0.401 locked fixture build and assembly mutation rejection pass.
- `git diff --check` passes.

The Windows test executes the real new Win32 method. Local macOS process tests substitute only that unavailable native image-query I/O with the live process's MainModule filename; they do not prove Windows API behavior or native UIA readiness. Fresh Windows verification is required.

## Follow-up: Windows 34724594633 fixture-only comparison

Both jobs passed the original failed-child cases using the native handle query, then stopped at the late-path fixture's combined zero-read / case-sensitive path assertion. Original logs are retained in `/private/tmp/foldersail-34724594633-review/`. The original combined message did not distinguish the two predicates, so it does not itself prove a Path read occurred. No UIA readiness, installed qualification, Store export or marketing binding was reached.

The fixture now compares both late and deliberately foreign image spellings with the production Windows `-ieq` semantics. Its late case varies only the casing of the real query result, which reproduced the old misleading assertion failure locally. Zero Path reads remains a separate strict assertion, and failure messages retain actual/expected image names and the read count. The existing real-child script passes all six cases after this correction; its production collector check also passes. No production code, readiness timing, ownership check or action changed. Windows continuation remains pending.
