# Assigned Store fixture readiness evidence

Run 34712207079, public `339a32a0921c6e4ceee8121ca952ca55e9b08950`, passed the
CI-identity consumer job. Its assigned Store job failed before installation or
product input, in the native standard-control UIA fixture. The separate fixture
preflight had already passed on that runner at 19:02 UTC. The installation
fixture later failed with the original error:

`Native UIA fixture did not expose its owned window before the deadline.`

Original artifact 10304640519 is retained privately under
`/private/tmp/foldersail-34712207079-review/Store`. The failed installation
receipt names fixture PID 7536, start time `2026-09-12T19:14:56.3204742Z`,
`close_requested=true`, cleanup exit code 1, verified process cleanup and no
forced termination. There is no retained child ready/result record or stderr.
The cleanup exit code does **not** establish an early child exit: the cleanup
code only requests close while the retained process is still live. The
original receipt does not establish the reason readiness was absent. No
transport, product or transient-startup cause is asserted.

This candidate adds bounded observation only:

- At the original refusal, record read timestamp, elapsed time, process exit
  state/code and ready-file existence before cleanup. Keep the exact original
  error and 10-second condition.
- Drain both child pipes concurrently, retaining at most 8 KiB per stream,
  original prefix bytes in base64, SHA256, decoded text, observed byte count,
  truncation and EOF/read-error facts. Waiting for pipe completion is limited
  to one second after the existing process cleanup.
- Only after proven child stop, hash/read the two exact owned diagnostic files
  `ready.json` and `result.json`, capped at 4 KiB each with the original nonce.
  Later records are diagnostics only; they cannot satisfy readiness or pass
  the fixture. Diagnostic read failures are separate from the original error.

The collector is included in the existing source-input hash binding. Native
fixture controls, proxy setup, foreground/PID/HWND checks, one Value/Invoke,
normal-exit acceptance, package input, trust/install order and cleanup remain
unchanged. No input retry, readiness extension or same-source rerun is claimed.

Focused verification:

- New actual-parent/real-child subprocess test first failed because the original
  producer did not retain either pipe. After the change, three child cases pass:
  exact failed result, foreign nonce and oversized result. Each child emits
  20,000 stdout and 24,000 stderr bytes; both streams drain while retaining
  exactly 8,192 bytes, then the original readiness refusal and exit 7 remain.
  No proxy/window acceptance is simulated. On non-Windows only the STA command
  flag is omitted from the real child test host.
- Existing native fixture boundary: 23 cases, exact locked CsWin32 build,
  missing-provider and changed-assembly refusals passed.
- Actual installer failure-path test passed, including primary-error retention,
  certificate cleanup and preflight refusal before install/trust mutation.

Fresh Windows observation remains required to establish the original cause.
