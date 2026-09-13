# FolderSail source checkpoints and rejected input state

Run `34727745434`, public source `40a40f77f3b59a83f2e59d6e4c9f413317d263cd`, passed both disposable qualification jobs. Store installation failed before the exporter at 00:53:13 UTC. Original log and metadata remain under `/private/tmp/foldersail-34727745434-review`; no final package was downloaded.

The Store receipt verifies the exact filename, one Save Space input, and discovery of the owned `Confirm Save As` task dialog: main PID 9048/HWND 1901034, picker PID 1900/HWND 66098, confirmation HWND 131806, owner chain `[131806,66098,1901034]`. The observed Yes control is `CommandButton_6`/`CCPushButton`, with real Invoke support. The next generic target-state refusal occurs before any Yes focus/input trace. Its rejected state was not retained, so neither an exact failed member nor a UI behavior repair is justified. Owned process cleanup, fixture cleanup, uninstall and trust removal are true; cleanup errors are empty. This is not a successful Store consumer workflow or normal-process-exit claim.

Two read-only source-status checkpoints now call the existing bounded reporter: after the build's original manifest restoration and in the installed invocation's finally block. Both log the phase, UTC time, original porcelain output and tracked name-only diff; each text stream retains the existing 4,096-byte limit and truncation flag. Git/diagnostic failures remain secondary, and the original native exit code is restored. A failed build or installed workflow therefore still exposes source paths. The final exporter clean-source check and exact original refusal remain unchanged.

At the original target guard, failure now attaches a fixed set of already-observed booleans, PIDs and HWNDs, the expected scope IDs, and at most eight owner-chain entries plus the original count to the same RuntimeException. The consumer's existing failure catch copies this record before its existing observations. No UI/process reads, retries, input, acceptance predicate changes or cleanup changes are added. Diagnostic failure preserves the original exception type/message and rejection.

Focused local verification on macOS:

- Six Store exporter tests pass; the new checkpoint test first failed against the previous production module. Existing real-Git dirty/untracked, package/lifecycle/publication and diagnostic failure/bounds cases remain passing.
- Six actual target-guard cases plus the original consumer catch replay pass. The new test first reproduced absent rejected-state retention, then verified unchanged RuntimeException/message, bounded owner chain, unknown-field exclusion, secondary failure and no action following refusal.
- The production qualifier function and original build/installation finally blocks pass restoration, original-failure, diagnostic-command and native-exit-code checks.
- Existing 44 consumer workflow boundary and 21 consumer diagnostic checks pass. The new PowerShell cases are wired into Windows qualification.
- Actual local read-only checkpoint logs the current tracked/untracked WIP paths. Whitespace verification passes.

No Windows UI fix, final unsigned export, marketing binding, source push or rerun is claimed. A fresh native run must establish the dirty source paths and, if this guard recurs, the exact rejected member.
