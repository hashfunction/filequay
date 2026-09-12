# FolderSail known non-scrollable receipt range — 2026-09-12

Actual Windows run `34694585269`, public source
`ffeedc1c61a6fd0f09268380aea5a154d4f05f47` (local `fc65d4a1`), passed
Instrumented qualification and failed Consumer qualification before CSV export.
The actual Consumer receipt is 152,466 bytes, SHA-256
`6d234688bf6a8980c5efcc45f63d709a07ec842ed30e78584aa2d99ba5428c49`.
Artifacts remain under `/private/tmp/foldersail-34694585269-review`.

Copy and Move completed with the original protected 84-byte Unicode file and
both persisted successful receipts. The owned status-center popup was HWND
10617370, main HWND 393522, process 7932, owner chain `[10617370,393522]`.
Move expanded at 13:00:47.1686684Z and collapsed at 13:00:47.8769267Z.
The first scroll attempt at 13:00:48.1092864Z now records **both before and
after**: vertical scrollable false, view size 100%, scroll percentage -1.
The driver nevertheless requested SmallIncrement and received the actual typed
UIA InvalidOperationException. Microsoft documents that an unsupported scroll
direction causes this exception:
[ScrollPattern.Scroll](https://learn.microsoft.com/en-us/dotnet/api/system.windows.automation.scrollpattern.scroll?view=windowsdesktop-10.0).

The later strict target assertion failed, but that queried state was not retained.
Which ownership/foreground/UI-state bit changed is therefore unproven. The later
actual bounded tree still shows the enabled visible receipt list and both Copy
and Move rows. Only the earlier Home screenshot was retained and viewed; it is
not an image of the later failure. This repair does not infer an unseen bit or
relax the target assertion.

## Narrow repair

After the existing fresh native ownership/foreground gate, the scroll branch
checks its freshly recorded vertical range. If false, it sends no Scroll call and
records `not-sent-not-scrollable`, then returns to the existing bounded fresh
receipt observation loop. The result is never recorded as completed input.
The 16-attempt/30-second bounds, actual visible receipt IDs/paths, Expand/Collapse,
Copy/Move, CSV/overwrite/recovery, file bytes and cleanup remain mandatory.
A still-hidden or foreign result cannot pass. A later real Scroll failure retains
the previous typed-exception/no-replay behavior and every strict ownership gate.

The existing target query immediately before sending is retained in its attempt
receipt. On post-failure list/detail re-observation, the already-queried target
state is recorded before the unchanged assertion. This adds no input or native
query; the existing 96-entry trace bound applies. A future refusal can identify
the actual failed field while preserving the original Scroll exception.

## Focused red/green verification

The new compact fixture retains the actual run/source/hash, before/after range,
input state, bounded receipt nodes, persisted IDs/paths and exact failure text.
The earlier scrollable discovery state is explicitly identified as a replay
transition inferred from the executed production branch. No unrecorded failed
foreground/ownership value is presented as native evidence.

The production fixture failed on the old code with `Known non-scrollable provider
was called or other actions replayed.` It passes after the narrow guard:

- 17 receipt/provider scenarios: all previous 14, plus the actual false-range
  transition with zero Scroll calls and both visible receipts, a still-hidden
  receipt refusal, and a foreign target refusal. Failed ownership state is now
  verified to remain in the trace before rejection.
- Existing production PowerShell regressions pass: 25 picker input, 22 scope
  discovery plus 39 selector/ownership checks, 59 picker diagnostics, 44 file/CSV
  boundary checks, 21 failure diagnostics, 19 toolbar cases, and observation
  error/disappearance checks.
- Changed text retains CRLF working-tree endings; `git diff --check` passes.

Commands, from this source repository:

```text
TMPDIR=/private/tmp .tools/powershell-7.6.6/pwsh -NoProfile -File tests/packaging/test-consumer-receipt-scroll.ps1
```

The same PowerShell command was also run for `test-consumer-picker-input.ps1`,
`test-consumer-picker-scope.ps1`, `test-consumer-picker-diagnostics.ps1`,
`test-consumer-workflow.ps1`, `test-consumer-workflow-diagnostics.ps1`,
`test-consumer-toolbar.ps1` and `test-consumer-observation.ps1`.

This is local production-path fixture evidence. Fresh Windows Consumer execution
is required; the full native CSV Save/Space/overwrite flow remains pending.
Run 34694585269 did preserve the unsigned package and complete owned fixture,
process, uninstall and trust cleanup with no residual packages or cleanup errors.
Consumer acceptance and Store readiness remain false. The Store/source WIP was
not restored during this repair and remains in its named git stash.
