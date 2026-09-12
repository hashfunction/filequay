# FileQuay installed-package qualification

The workflow runs two independent `windows-2025-vs2026` jobs from fresh
checkouts. `Instrumented` compiles `FileQuayCIQualification=true` and retains the
existing packaged `StartMonitor` client/server test. `Consumer` compiles the
ordinary release with `FileQuayCIQualification=false` and never supplies the CI
probe argument. Both jobs use the disposable qualification identity; neither is
a Store-identity or publication test.

The requested build kind does not establish what was built. The qualifier reads
the actual packaged `FileQuay.dll` with `PEReader`, without loading or executing
the assembly, and requires the exact
`Files.App.Utils.Qualification.CiComActivationProbe` type to be present only in
`Instrumented`. It repeats that check against the installed assembly and binds
both observations to SHA-256. A mislabeled package fails. AppX discovery and
validation are confined to a fresh, build-kind-specific output directory.

Both kinds retain the package, SQLite archive, notice, manifest, framework,
self-contained .NET runtime and unpack checks. `DependencyMode=RequireClean`
remains the workflow default: a compatible pre-existing framework causes a
failure, and each supplied framework must be newly registered. The explicit
`AllowPreinstalled` dispatch remains diagnostic dependency-resolution evidence;
it never claims a clean framework installation.

## Consumer observation

The consumer qualifier signs only a temporary copy with an ephemeral,
nonexportable key and installs it with the validated framework archives. It
broker-activates the package with an empty argument string, retains the returned
live process handle, and verifies the installed executable path, executable hash
and `GetPackageFullName` result before establishing process cleanup ownership.
It then requires a stable main window, a visible `ShowStatusCenterButton`, the
packaged root `coreclr.dll`, a bounded UI Automation tree and a screenshot of the
owned window. Evidence records the actual title and bounds; screenshot failures
remain qualification failures. An error placeholder is not a captured tree: the
tree must contain a successfully observed window root and the source-backed
Status Center control. Partial provider errors stay in the record without
turning an otherwise empty or rootless observation into success.

Release builds default `LeaveAppRunning` to true. The normal close request can
therefore hide the final window while the verified process stays alive. The
record keeps window disappearance, wait completion, exit code, observation
errors and remaining background state as separate facts. A background outcome
sets `process_exit_acceptance_pending=true` and does not claim a natural process
exit. Cleanup terminates only the retained owned process handle; it does not
sweep by name or PID. Package removal uses only the exact registration captured
after `Add-AppxPackage`. A UI Automation exception during close observation is
recorded and cannot stand in for `IsOffscreen=true`; disappearance requires an
observed offscreen state, process exit, or a zero main-window handle.

The unsigned package is hashed again after cleanup. Changed or unreadable input
is an evidence failure and keeps the overall result false. Final evidence is
written to a unique flushed stage and moved into place without replacement. A
prior or raced `installation-result.json` is preserved, and the thrown failure
retains primary, cleanup, evidence and reporting errors together.

The instrumented branch preserves the existing independent probe activation,
generated `StartMonitor` call, exact packaged server/CoreCLR checks, and natural
zero client/server exits. Consumer acceptance does not require or claim those COM
checks. `normal_store_binary_installation_tested` becomes true only after the
metadata-proven consumer package passes installation, broker identity, genuine
UI, the consumer workflow below, close observation, exact owned process and
fixture cleanup, package removal and trust cleanup.

## Consumer file and receipt workflow

Before the normal close request, the existing retained consumer process performs
Copy and Cut/Paste Move on one generated Unicode/comma-named file. A unique
marker-owned fixture contains separate source/copy/move/export directories and
protected sentinels. Independent file hashes prove the copy, the move's removal
of its prior source, and preservation of the original and sentinels.

The qualifier requires an initially absent or empty receipt history in the
exact installed package's LocalState. It independently parses the persisted JSON
and requires one successful Copy and one successful Move receipt, distinct IDs,
the expected selected paths, valid operation timestamps and nonnegative reported
counts. It expands both real Status Center receipt cards, using their existing
automation properties, and checks the visible operation/result and selected
paths. Reported totals are not treated as a per-file audit trail.

The real save picker selects an existing fixture CSV with known previous bytes.
After any native replacement prompt, the app's explicit confirmation must show
the exact selected path and enabled primary action. Cancelling that confirmation
must preserve every fixture file. A second selection is confirmed; an independent
CSV parser compares every column of both rows to the persisted receipts, and the
previous CSV must remain byte-identical at the recovery path displayed by the
app. Clearing receipts through its confirmation must leave an empty JSON/UI
history while preserving the source, moved file, CSV, recovery and sentinels.

Input targets are rebound to their actual native window and checked against the
retained consumer process, exact main HWND, native owner chain, UIA process and
ancestor, foreground, visibility and enabled state before each action. The small
native adapter compiles its existing API subset into the independent
`FileQuay.Qualification.Native` assembly with the same centrally pinned CsWin32
package and customer generator options. Before certificate/trust or installation
mutation, qualification builds it in fresh output, verifies the SDK/source/lock
inputs, rejects any managed native header or non-BCL reference, and loads the
exact inspected IL bytes. It never loads a published customer assembly into
PowerShell. The customer composite ReadyToRun configuration is unchanged. The
installation receipt binds the loaded adapter hash and source inputs; consumer
acceptance requires its successful preflight. A broker-hosted picker
is usable only after its live process handle and owner chain back to the exact
main HWND are proved. Those observer handles are disposed without terminating a
shared broker process. An unproved picker relationship fails qualification and
retains bounded observations; there is no unrestricted desktop picker fallback.

The consumer process is stopped through the existing owned-handle cleanup before
fixture deletion. Cleanup checks the marker, allowed paths, file hashes and
absence of links/reparse points before removing anything. Changed ownership or
unexpected bytes/entries cause preservation and a cleanup failure; package and
certificate cleanup still run. Evidence contains only the generated fixture's
metadata, operation records and bounded UI observations, not its raw payloads or
the app profile. Both workflow and fixture-cleanup gates are mandatory for
consumer acceptance. The instrumented COM branch is unchanged.

## Current evidence and remaining gates

Windows run `34609580070` at public source
`131729f8e5be66487535853b39b5505b463b2380` passed both strict installation jobs.
The consumer record includes an empty-argument broker activation, exact package
identity, 80 observed UI nodes, screenshot and background-close outcome with
owned cleanup. The instrumented client/server both exited zero. That run predates
the file/receipt workflow above; the added workflow still requires execution on
Windows before claiming interactive feature success.

Local verification on macOS used the repository's pinned .NET 10.0.401 and
PowerShell 7.6.6 tools:

```text
34 packaging tests passed.
44 independent consumer-workflow boundary checks passed: exact file bytes and
move absence, JSON/CSV correspondence, foreign target rejection, actual link
refusal, marker ownership and cleanup after process stop.
Focused CsWin32 build succeeded; the native input adapter compiled against the
actual generated assembly. No Win32 input API was invoked on macOS.
Managed metadata: real consumer/instrumented assemblies passed; two coherent
mislabeled cases and malformed input were rejected.
Acceptance dispatch: consumer and instrumented success fixtures passed, including
rejection when workflow or fixture-cleanup evidence is absent.
Installer failure fixtures: primary+cleanup aggregation, preinstalled framework,
failed-Add registration race, final package mutation, and raced result
publication passed. Existing result bytes were preserved.
Consumer observation helpers: error-only and rootless trees were rejected; a
successful root plus Status Center was accepted; UIA failure with a live process
and nonzero HWND was not treated as disappearance.
Actual processes: exit 0, exit 7, live timeout and retained-handle cleanup passed.
PowerShell parser and workflow YAML checks passed.
```

Store identity, execution of this interactive workflow, cancellation and partial
failure cases, substituted export destinations, tabs/panes, upgrade behavior,
WACK, full native license/source delivery and publication remain separate gates.
The legacy SQLite package has since been replaced by the pinned SQLite 3.53.4
inputs in `distribution/sqlite-dependencies.lock.json`; this does not establish
clearance for every other native dependency.
