# FolderSail original Windows marketing capture

This separate capture pipeline is bound to the independently verified unsigned
Store export from [Windows run 34730460036](https://github.com/hashfunction/filequay/actions/runs/34730460036),
attempt 1, source `7d2eff788f9dc15e0e695606da2963a1fc8450d3`. It has not yet
produced Windows screenshots and does not add consumer qualification evidence. The
application, its immutable assigned Store identity, and the existing native
qualification workflow are unchanged.

The manual `marketing-screenshots.yml` job refuses while `binding.json` contains
`qualified: null`. The current reviewed binding records the public source commit,
workflow run and attempt, exact unsigned
`FolderSail_1.0.1.0_x64.msix` and `release-ready.json` sizes/SHA256, and four
distinct GitHub artifact IDs:

- `store`: `FolderSail-Store-unsigned`
- `Instrumented`: `FolderSail-Windows-Instrumented-qualification`
- `Consumer`: `FolderSail-Windows-Consumer-qualification`
- `Store`: `FolderSail-Windows-Store-qualification`

Use these exact keys under `qualified`: `source_commit`, `workflow_run_id`,
`workflow_run_attempt`, `package`, `readiness_receipt`, `artifacts`. Run IDs and
attempts are decimal strings; artifact IDs are integers. Each byte record has
`bytes` and lowercase `sha256`. Do not bind a failed run, disposable-identity
package, a diagnostic dependency run, or a newly rebuilt substitute. GitHub
artifact expiration requires retaining the originals or a separately reviewed
transport change; it does not justify substituting other bytes.

The input step verifies GitHub's original run/artifact metadata, downloaded ZIP
hashes and sizes, safe ZIP members, both original disposable-identity lifecycles
and the assigned Store Consumer lifecycle. It replays the exact original
source's installation, package, runtime and notice validators. The original
public-source receipt and source input hashes remain bound; capture does not
claim a fresh download of every public corresponding-source archive. The
current capture checkout and original qualified checkout must each remain clean
at their exact commits. Only the original independent IL input adapter and
native UIA proxy fixture are compiled; no app binary is rebuilt.

The clean disposable runner receives the exact original framework MSIX from
the reviewed Runtime NuGet archive. Its whole-file size/SHA256/SHA512 pin is
bound to the qualified lock's distinct NuGet content hash; the extracted member
must match the original installed qualification's SHA256 and framework identity. A temporary copy of the original Store
package is signed with an exclusively created certificate. The original
unsigned bytes are preserved and all installed payload files are compared.
An existing Store registration, profile, demo folder, output folder, or compatible
framework blocks capture. The framework is retained until disposable runner
teardown, matching qualification's existing policy.

## Three actual scenes

| Original PNG | Normal app scene | Caption |
| --- | --- | --- |
| `01-folder-workspace.png` | Maximized Inbox with a selected original Garden workshop brief and tidy agenda, budget and reference notes | Keep project files together in a clear folder workspace. |
| `02-operation-receipts.png` | Completed Copy and Move headers, with Move source and destination details expanded | Review completed Copy and Move operations and their source and destination paths. |
| `03-export-receipts.png` | Actual CSV export confirmation naming `C:\FolderSail Demo\Receipts\Workshop receipts.csv` | Confirm where to save receipt history as a CSV file. |

All demo content is original and lives under exclusively marker-owned
`C:\FolderSail Demo`. The app copies the brief from **Inbox** to **Working drafts**,
then moves that copy to **Ready to share**. Both operations are verified by
independent file bytes, original protected files, persisted app receipts and
visible receipt fields. No operation history, setting or profile is injected.

Scene 03 is a **confirmation**, not a completed export claim. Immediately after
capture, the ordinary confirmation action must commit the CSV; all ten columns
and both actual receipt rows are checked independently. The original CSV must
survive at the app's real recovery path. That compatibility filename contains
`.filequay-original`; it appears in retained metadata, not the proposed captured
scene or caption. No visible demo path uses `.filequay`, CI or qualification
folders.

Pixels come directly from `Graphics.CopyFromScreen` over the complete visible
DWM window frame. There is no compositing, mock UI, pixel editing or post-capture
resizing. Each PNG has an original SHA256/size receipt with the exact package,
source/run, process/window, foreground, bounds, display/DPI and required visible
content before and after capture. The original input helpers retain every
PID/window/focus/native picker guard. Required receipt details must fit the
actual list viewport. Native supported display modes may be tested/applied for
readability; the retained original mode is restored and independently read back.

The app receives its ordinary Close action. A disappearing window is recorded
separately from process exit: Release's `LeaveAppRunning=true` may keep the app
in the background. Retained owned process cleanup, uninstall, absent app profile,
unchanged sealed demo bytes, marker removal, temporary trust/private-key removal,
and display restoration are all required for a complete capture receipt. No
normal process-exit claim is invented. Changed or unexpected demo content is
preserved and causes failure. The capture never deletes an existing profile;
if uninstall leaves the fresh profile behind, capture fails for review.

## Review and validation

Run from the source root:

```powershell
python -m unittest discover -s distribution/marketing -p 'test_*.py' -v
foreach ($name in @('frame','display','lifecycle','complete','native','integration')) {
    pwsh -NoProfile -File "distribution/marketing/test_capture_$name.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Capture $name test failed" }
}
```

The tests exercise real temporary files, original lifecycle/archive validators,
UTF-8/CSV fields and path preservation; malformed metadata, changed original
files, foreign recovery targets, markers, reparse paths and cleanup failures
refuse. The managed observer compiles. Scalar native/frame and display fixtures
do not represent a Windows capture. Fixture-only Git/network/native seams are
explicit in `test_capture_replay.py`.

Actual Windows exploration remains pending, especially the receipt flyout's
final composition, fresh-profile removal on uninstall, and the complete normal
native filename delivery from the newly qualified package. An unproved input,
clipped required field or cleanup failure remains a failed marketing capture;
it cannot produce a completed receipt or replace original consumer acceptance.

After binding and native review, dispatch the separate manual workflow. Review
all three original PNGs and `marketing-capture.json` before copying to Store/site
marketing. The artifact contains only original PNGs and metadata JSON; it
contains no MSIX, framework, app profile, signing key, or private build log.
