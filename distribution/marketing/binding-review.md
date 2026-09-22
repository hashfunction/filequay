# FolderSail original Store export binding

The capture binding now names successful Windows run `34730460036`, attempt `1`, public source `7d2eff788f9dc15e0e695606da2963a1fc8450d3`, tree `47b52acef1b6dedc12caa82355cee3c3b154183d`. This changes capture configuration and documentation only. No application, qualification, input, module, ownership or cleanup helper changed; no capture has been dispatched or screenshot claimed.

Original downloaded inputs are retained under `/private/tmp/foldersail-34730460036-review`. Exactly four GitHub artifacts were downloaded; every transport ZIP matched its original API ID/name/run/source, byte count and SHA256, then its original members were safely extracted. Only these verified transport copies were discarded.

| Binding key | Original artifact ID | Transport bytes | Transport SHA256 |
| --- | --- | ---: | --- |
| store | 10309826198 | 185153629 | `753b8d05043527e43117ea25b044e11ec06f4e09b18da911b4a0c6d8c11c001c` |
| Consumer | 10309660508 | 336546 | `2cc1768129ece25265ae8e8effff97028228c55e487ebf35d3fee9afeaeaff2a` |
| Instrumented | 10309585137 | 263795 | `9b49dbf075ef0fc5e2db99d9c6e3d440a93836cb9c6ecb5b554ed622fb89a5bd` |
| Store | 10309274982 | 1044776 | `46e686bfc082dc52a6afac01ff594a93582c6ae9873c1387cea217d125ef293e` |

The Store artifact contains exactly these two originals:

- `store/FolderSail_1.0.1.0_x64.msix`: **188141651 bytes**, SHA256 `512276cde0684d45155707db561837b5b3cc7ef47ec320ee41dac639ffcaf5d1`.
- `store/release-ready.json`: **55329 bytes**, SHA256 `45d9902666bbea50f4bd7206505526663f348206d43c085f5ffb6921c1f2c283`.

The unchanged production `capture_checks.verify_inputs` passed the exact successful run/source/tree binding, all three complete original lifecycle snapshots, each original installation and native runtime/source validator, the 1010-file unsigned package payload, 107 packaged notices/source records, original publication bindings and original helper hashes. The package manifest independently reads `FolderSail` for both display names, `1659hashfunction.FileQuay`, version `1.0.1.0`, assigned publisher, `Application Id="App"` and `FolderSail.exe`.

The two Consumer records verify the real workflow, ordinary Close request/window disappearance, accepted background-process outcome, retained owned-process/fixture cleanup, uninstall and trust removal. Both have empty cleanup/evidence errors. `normal_process_exit_verified` is false under the established `LeaveAppRunning` policy; it is not presented as normal process exit. Instrumented acceptance retains its separate scope.

The first macOS replay correctly refused the CRLF packaged CorrespondingSource README against the LF checkout. A separate local shared clone at `/private/tmp/foldersail-34730460036-windows-source`, exact same commit/tree and `core.autocrlf=true`, reproduces the original Windows checkout bytes and passes the unchanged validator. The canonical public checkout, MSIX and original receipts were not modified, and no normalization exception was added to a validator.

Durable local review outputs:

- `qualified-run.json`: original GitHub successful run record.
- `artifact-downloads.json`: four original API records and verified transport hashes.
- `verified-inputs.json`: unchanged production verification output, 173922 bytes, SHA256 `7ae05a52830267328263b69abaf1b9c2c86412642a0912ba6dd9662b8b28b78d`.
- `metadata/{Instrumented,Consumer,Store}/`: extracted original retained lifecycle evidence.

Focused verification: 6 capture-binding/source-context tests, 3 artifact/framework extraction tests and 2 actual lifecycle/package replay tests pass (11 total). The persisted binding parses successfully and whitespace verification passes. No corresponding-source archives were downloaded again, no application was rebuilt, and no native helper test suite was repeated for this configuration-only change.

Parent review and a fresh actual screenshot-only Windows run remain required. Store terms delivery and submission are separate from this capture binding; the original readiness receipt requires the packaged Win2D license terms in the Store license field.
