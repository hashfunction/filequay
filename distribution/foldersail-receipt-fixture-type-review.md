# Receipt replay type isolation

Run 34695825453 used public source
1c85cb4fada7c2851574d082d1512c4d1c5c2dc9. Its Instrumented job passed. The
Consumer job failed at 2026-09-12T13:16:32Z in the receipt replay test, after the
real UIA proxy preflight, unit tests, 36 Python packaging tests and 44 independent
consumer file/CSV checks had passed. Consumer application build/install and the
full UI workflow were not reached. Its metadata artifact is only 10,987 bytes;
there is no installation-result.json or new Consumer failure screenshot.

The actual error at ConsumerWorkflow.Ui.ps1:159 is an ExpandCollapsePattern cast
between identically named System.Windows.Automation types from different
assemblies. The replay declared its fake providers inside Microsoft's namespace.
Windows could resolve the production cast to the real Microsoft class while the
fixture returned its own class. The differing job outcomes are consistent with
type resolution/load order; no new product UI failure is inferred.

The retained actual preflight is passed=true, cleanup_errors=[], 9,871 bytes,
SHA-256 94ba17670f876e157e4eebd68215c31a24effb461815eb76e85dc3d9800b2a1f.
The full failed log and downloaded metadata remain in
/private/tmp/foldersail-34695825453-failed.log and
/private/tmp/foldersail-34695825453-review.

## Fixture correction and reproduction

The replay types now have the unique FileQuayReceiptReplay.Automation namespace.
Its loader changes only bracketed UIA type references in an in-memory copy of the
current production script. All production action/reader/ownership logic and the
17 existing scenario assertions remain. No production source or installed
qualification policy changes in this commit.

Before loading the replay, Windows explicitly loads the real UIAutomationClient
ExpandCollapsePattern type from PSHOME. Other hosts emit a separate assembly with
the same Microsoft-qualified name to reproduce the collision without claiming a
native Windows provider. The replay asserts its own type remains distinct.

Before the repair, the emitted collision reproduced the exact observed Windows
cast exception at production line 159. After the repair, the collision is present
through all 17 scenarios and they pass: actual captured range transitions, scoped
receipt IDs/paths, typed provider failures, no action replay, foreign/hidden
refusal and the original finite observation budgets.

```sh
TMPDIR=/private/tmp .tools/powershell-7.6.6/pwsh -NoProfile -File tests/packaging/test-consumer-receipt-scroll.ps1
```

Fresh local result: 17 scenarios passed. The 44 independent consumer file/CSV
checks also pass. Windows' real-type branch and the entire Consumer installed
workflow still require a fresh native run. Earlier acceptance is not promoted.
