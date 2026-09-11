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
UI, close observation, exact owned process cleanup, package removal and trust
cleanup.

## Current evidence and remaining gates

Windows run `34603033361` at source
`63851b8ca976177ecc82866c01779a26a7f44744` is retained evidence for the strict
instrumented path. The consumer path added after that run has only local parser,
fixture and process-test evidence so far; it must run on Windows before any
normal-package success claim.

Local verification on macOS used the repository's pinned .NET 10.0.401 and
PowerShell 7.6.6 tools:

```text
34 packaging tests passed.
Managed metadata: real consumer/instrumented assemblies passed; two coherent
mislabeled cases and malformed input were rejected.
Acceptance dispatch: consumer and instrumented success fixtures passed; six
required-gate mutations were rejected.
Installer failure fixtures: primary+cleanup aggregation, preinstalled framework,
failed-Add registration race, final package mutation, and raced result
publication passed. Existing result bytes were preserved.
Consumer observation helpers: error-only and rootless trees were rejected; a
successful root plus Status Center was accepted; UIA failure with a live process
and nonzero HWND was not treated as disappearance.
Actual processes: exit 0, exit 7, live timeout and retained-handle cleanup passed.
PowerShell parser and workflow YAML checks passed.
```

Store identity, interactive workspace workflows, upgrade behavior, WACK, native
license/source delivery and publication remain separate gates. The current
`SQLitePCLRaw.bundle_green` 2.1.11 provider also remains an open shipping gate:
the [reviewed advisory](https://github.com/advisories/GHSA-2m69-gcr7-jv3q)
calls for SQLite 3.50.2 or later and lists no patched version of that legacy
package. This qualification does not suppress that requirement.
