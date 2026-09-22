# FolderSail capture framework registration observation

Actual screenshot-only run `35702908425`, public source `95527f1c2ae08871b11626eb332594fdf2643abf`, passed original input/archive/member verification, native input/proxy preparation, temporary signing, assigned app installation and installed payload validation. It stopped at `Original framework registration differs` before activation or any screenshot. Artifact `10683815141` contains no PNGs.

The original app registration was acquired and subsequently removed. Original inputs, profile absence, demo removal, trust/key removal, temporary cleanup and restoration from the actual supported 1920×1080 mode to 1024×768 all passed. No application UI or successful capture is claimed.

Original evidence is retained unchanged in `/private/tmp/foldersail-capture-35702908425-review/`: `capture-job.log` and the five JSON files under `artifact/`.

The expected framework full name exactly matches the original qualified receipt: `Microsoft.WindowsAppRuntime.2_2.4.0.0_x64__8wekyb3d8bbwe`. The downloaded original framework SHA256 also matches, `a3ce5b76713133dfd3b378e81c43a89954c664fcd70fd0c070e409ed3de03ebf`. However, capture did not retain the actual framework query count or properties. The exact failed predicate cannot be determined from that receipt.

Capture explicitly imports Appx using `-UseWindowsPowerShell`; its original Windows log confirms deserialized compatibility-session results. The original installed qualifier instead uses Appx commands directly. Real local PowerShell `PSSerializer` roundtrip of the valid package identity still passes the original matcher, as does the exact retained requirement loaded with `ConvertFrom-Json -AsHashtable`. Thus remoting is an observed context difference, not an established root cause. Microsoft's [Get-AppxPackage documentation](https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage?view=windowsserver2025-ps) also confirms frameworks are included by default; no package-type filter workaround is justified.

The capture-only change records the already-returned framework candidates immediately before the unchanged guard: exact total count, first eight candidate identities/property types, full name, framework/status fields, expected identity, original matcher result and PowerShell version. Text is bounded to 1024 characters per property; secondary diagnostic errors to eight records of 2048 message characters. It performs no extra registration query, retries, installation, input or cleanup action. Observation errors do not replace the original refusal. Original qualification helpers and package binding remain unchanged.

Focused verification:

- The new actual Install-operation fixture first failed because framework evidence was absent.
- Seven cases pass using the original registration ownership/matching helpers and actual capture lifecycle: exact identity, real serialized identity, missing registration, foreign full name, incompatible requirement, ten returned candidates and a secondary matcher exception.
- The fixture checks identical original refusal text, no activation on refusal, one install attempt, bounded retained observations and completion of the original cleanup sequence.
- Existing capture lifecycle/real retained-process cleanup and helper integration tests pass. Whitespace checks pass.

A fresh Windows capture is required to identify the actual differing registration property. This commit adds failure evidence only; it does not claim to repair the unresolved registration mismatch.
