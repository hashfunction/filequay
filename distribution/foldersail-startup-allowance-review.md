# FolderSail native fixture startup allowance

Run `34724904741` / public source `23f8da16a3f122ea751950f95f723c04c2771bbe` passed both temporary-identity jobs. Its separate assigned Store job failed the native UIA fixture before application build. Original metadata and logs are retained under `/private/tmp/foldersail-34724904741-review`; no package/export or marketing binding resulted.

The Store record proves PID 8200 remained live with the exact retained `pwsh.exe` image at 10,095 ms, but `ready.json` was absent. Both output streams were empty; no child records or diagnostic errors were available. Cleanup requested normal close, then stopped only the retained process (`forced_cleanup:true`, exit -1, no cleanup errors). This does not identify where child startup stalled or prove that 30 seconds will succeed.

The successful Consumer child started at 23:16:28.1818003Z. The next post-preflight vendor-input log appeared at 23:16:31.1185095Z, bounding that entire readiness/Value/Invoke/normal-close flow below 2.94 seconds. Its exact readiness duration was not previously recorded. Thus the same source already demonstrated real native support, while the new Store runner exhausted its fixed ten-second startup allowance.

The parent-approved correction uses one fixed 30-second monotonic startup budget, still polling only readiness every 100 ms. It records the allowance and actual readiness/refusal elapsed time. There is no restart or input retry. The original immediate retained image/handle checks, nonce/PID/HWND validation, actual supported Value/Invoke operations, native fixture lifetime timer, success predicates and cleanup remain unchanged. Readiness-file presence alone still cannot qualify anything.

Four fixed diagnostic files now mark `child-entered`, `assembly-verified`, `assembly-loaded`, and `native-entry`. Each is written once using CreateNew in the original owned fixture directory. They contain only schema, nonce, PID, phase and UTC time; write failures emit a bounded type-only secondary diagnostic. After original process cleanup, the parent retains only those four allowlisted names, with the existing 4,096-byte/file and stable original hash checks plus exact nonce/PID/phase checks. They have no acceptance role; missing or refused observations cannot turn failure into success.

Targeted local verification (PowerShell 7.6.6 on macOS):

- Real process/file/clock startup fixture: readiness published after 11 seconds proceeds; a live child without readiness is rejected at the single 30-second deadline with the unchanged original error. Both test children are cleaned up by retained process handle. These test only the waiting boundary, not native UIA success.
- Exact production phase writer: all four records have original bounded identity/time data; a second write preserves the original file and reports a bounded secondary error.
- Existing real failed-child parent now also retains the actual phase writer's record and rejects a foreign phase PID while preserving the original failure/result. Concurrent pipe bounds, foreign nonce, oversized result, exited child, late module Path and foreign image checks remain enforced.
- Existing proxy suite: 23 readiness/pattern cases, missing exact-host-provider refusal, actual SDK 10.0.401 locked fixture build and assembly-mutation rejection pass.
- `git diff --check` passes.

A fresh Windows run remains necessary to establish whether the larger bounded startup allowance resolves the observed Store-runner delay. The phase records will identify the last reached startup boundary if it does not.
