# FolderSail preexisting UIA type fixture repair

Run 34699864301 used public source `77963c802d95ac50197828d67b99f6127d774a80`. Both jobs stopped in the new structural fixture before application build, package validation or installation. The exact primary error was `Preload replay requires a fresh process: AutomationElement` at `tests/packaging/test-uia-replay-preload.ps1:25`. Instrumented failed at 14:41:08 UTC and Consumer at 14:41:29 UTC on 2026-09-12. The Consumer native Win32 proxy preflight independently passed with no error and `cleanup_errors: []`.

The test incorrectly assumed a fresh `pwsh -NoProfile` host could not already resolve a Microsoft UIA type. The actual Windows record disproves that assumption. Locally, preloading a type with the observed `System.Windows.Automation.AutomationElement` name reproduces the exact failure before any helper action. No application or provider failure is implied by this harness setup error.

The structural replay now uses `FileQuayCompanionReplay.Automation` for its own types and the in-memory helper lookup prefix. It deliberately retains the existing Microsoft `AutomationElement` binding, loading only the actual PSHOME Client assembly if needed on Windows, or creating the observed real-named collision on non-Windows hosts. It verifies that this binding is unchanged after the replay. Only the private replay namespace must be fresh; the actual framework namespace has no emptiness requirement.

The real helper Windows branch still runs, with only its host file-loading boundary doubled. Both exact PSHOME filenames must be requested exactly once, and actual PowerShell type discovery must resolve client/property replay types from the separate expected assemblies. Production collision helper, UIA registration, native provider/input, source identity, ownership, bytes and cleanup gates are unchanged.

Verification using `.tools/powershell-7.6.6/pwsh -NoProfile -File`:

- `tests/packaging/test-uia-replay-preload.ps1`: passed with the deliberately retained preexisting binding.
- A separate process preloading the exact observed real-named `AutomationElement` then invoking that same test: failed before repair, passed after repair.
- `tests/packaging/test-consumer-picker-diagnostics.ps1`: 59 checks passed.
- `tests/packaging/test-uia-proxy.ps1`: 24 policy checks plus actual compiled exception/stack replay and three caller-binding refusals passed.

The native run originals are retained privately under `/private/tmp/foldersail-34699864301-review` with the failed log beside that directory. A fresh Windows run is still required. Store/source integration remains a separate preceding commit; this repair makes no Store readiness or redistribution-clearance claim.
