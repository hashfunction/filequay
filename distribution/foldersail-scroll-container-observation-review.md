# FolderSail scroll-container refusal observation

Run **34709436446**, reviewed source `0c2635898a699c1f0b66989ce684037d76545218`,
failed before CSV export. Its original Consumer installation receipt is
147,938 bytes, SHA256
`610002bec44a3849712142115e26a95d5f03bb9c818f8b3b8c2712417faaebde`.
Artifacts remain under `/private/tmp/foldersail-34709436446-review`.

Actual Copy/Move and both persisted receipts passed. The Move receipt expanded,
its exact paths were read, and it collapsed at 18:04:38.308 UTC. The subsequent
offscreen-card lookup failed with the original message:
`Offscreen receipt detail has no visible owned scroll container.`
There was no Scroll call or Copy expansion. The later bounded tree shows the
receipt list and both ListViewItem headers, but does not reach the actual
expander/details beneath its depth limit. Its `hwnd` values describe observation
scope and cannot establish each control's native handle. Neither a settled
Copy detail nor an animation/native-window mismatch is proved by that tree.

The original refusal can mean a mismatched native ancestor window, hidden
ancestors, no ScrollPattern, or a currently non-scrollable range. This change
only records that existing discovery walk. `ReceiptScrollContainerRefusal`
retains the exact requested card/part, expected scope PID/HWND, initially read
offscreen predicate, up to the original 24 ancestors, actual inspected native
windows and matched-ancestor metadata/ranges, elapsed time and UTC read bounds.
`control_native_hwnd` remains distinct from the resolved ancestor window and
expected scope HWND. A native-window mismatch stops immediately; provider
fields and scroll range beyond that refusal are deliberately not queried.
Unavailable metadata properties retain bounded errors instead of guessed data.

Observations are captured while the original walk runs, not by walking again
after failure. Existing Current/range objects and predicate values are reused;
logging does not re-read ScrollPattern.Current. Only a refusal is attached to
the existing 96-entry trace. Names/errors keep the existing 1,024-character
limit. The original exception survives an unavailable diagnostic sink. The
same native-window predicate, visibility/scrollability requirements, action
ownership checks, 16-attempt/30-second bounds, and original failure remain.
No new retry or input is introduced. Marketing uses this same shared helper.

The focused production replay first failed because refusal metadata was absent.
All **21** receipt-scroll scenarios now pass, preserving the prior 17 cases and
adding non-scrollable discovery, wrong native window, original range-getter
failure, and unavailable diagnostic sink. They verify zero input/retry on
refusal, one range read, no foreign range query, timestamps, bounded optional
property errors and round-trip serialization at the original receipt depth 9.
These explicit provider-state simulations do not claim which unrecorded state
caused the native failure. `git diff --check` passes.

Run `tests/packaging/test-consumer-receipt-scroll.ps1` with the existing pinned
PowerShell. It already runs before native qualification. The next evidence
should come from one ordinary qualification run; no separate diagnostic mode
or duplicate job is added. Windows cause and complete consumer acceptance
remain pending. The new after-export history reopen was not reached in this
original run and is not evaluated by it.
