# FolderSail Store export source-status observation

Run `34726130956` / public source `a665a1e3ac98ad8ea88eb1702ca6064c74215ff1` passed the two temporary-identity jobs and the assigned Store installed qualification. The Store job then failed the exporter's first source gate: `Source changed after the qualified build`. The original failure omitted the porcelain rows; metadata contains no changed-path list. Originals are retained under `/private/tmp/foldersail-34726130956-review`. No final unsigned export was uploaded or bound for marketing.

The likely direct writers were inspected: the manifest restores its original bytes in finally; the five hash-verified vendor outputs are explicitly ignored; Python caches and qualification/test artifacts are ignored; temporary startup files are owned and removed; app package auto-increment is disabled. Restore/build-generated changes remain possible, but no specific path is proven. No deletion, ignore exception, restore command, or source-clean gate relaxation is justified yet.

Immediately before the existing rejection, the exporter now reports JSON containing the original porcelain status and `git diff --no-ext-diff --name-only HEAD --`. Each byte stream is capped at 4,096 bytes with an explicit truncation flag; only filenames/status are exposed, never file contents. A secondary diff-query or stderr-write failure cannot replace the original ValueError. The clean-source predicate, current source/run/attempt requirements, package/evidence/source checks, and success-only output remain unchanged.

Focused verification:

- Existing real-Git dirty/untracked regression first failed because no diagnostic was retained, then passed with exact tracked/untracked names and unchanged rejection text.
- All five Store exporter cases pass, including diagnostic bounds and secondary query/output failures.
- The unchanged public source's `verify_installation` and `verify_native_evidence` replayed all three original metadata lifecycles successfully. This validates their existing background-process close/cleanup policy; it does not claim `normal_process_exit_verified`, which is false in the original receipts.
- Original Store fixture readiness is now recorded at 834 ms with the 30-second allowance. Actual Value/Invoke and lifecycle acceptance passed.
- Full commit whitespace check passes. No full app build, binary download, push or rerun was performed.

A fresh native export attempt must identify the exact dirty paths before a source-producing step can be repaired. Original MSIX/container and public source export validation remain pending because the original unsigned export does not exist.
