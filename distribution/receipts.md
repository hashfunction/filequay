# FileQuay receipt implementation and qualification

The approved intent is one accurate terminal record per operation. Source inspection corrected the original plan: inner progress reports can report per-file success and reuse a mutable model, while outer helpers originally removed a live row and added a new terminal row. `ObservedOperationProgress` observes status synchronously, retaining a batch failure before UI dispatch. `CompleteItem`/`StatusCenterItem.Complete` now finish that same row exactly once. Completion scopes preserve a terminal failure when an outer await throws. Copy, move, delete/recycle, compression/extraction, clone, font install and empty-recycle-bin outer entrypoints use this boundary. Low-level filesystem implementations are unchanged. Preparation cards are temporary discovery UI and are not persisted as completed file operations.

Receipts copy selected source/destination paths at operation start, retain reported total counts/bytes and final outcome, and normalize timestamps to UTC. Counts describe scope; they do not claim that every item succeeded in a partial operation. URL user information, query and fragments are removed. No contents or exception messages are stored. Later conflict renames are not represented as a per-file audit trail. A receipt is not an undo operation.

The local store is `LocalState/OperationReceipts/v1.json`, up to the newest 500 records within 32 MiB. A semaphore and cross-process exclusive lock serialize modifications. Writes flush a sibling file before atomic replacement; cancellation before commit leaves the prior document unchanged. Corrupt documents are renamed to unique `.corrupt` evidence; clear never removes that evidence or user files. CSV uses UTF-8, CRLF records, quoted cells and formula neutralization. Export requires a selected destination and explicit replacement confirmation.

Persistence errors leave the completed live row visible and show the affected history/export path. An unsuccessful append is not claimed as persisted. A process exit while the file operation is still active may leave no terminal receipt; receipts are history, not a recovery journal. Interactive Windows qualification must verify the UI and failure path, including app shutdown during writes. A hard power-loss guarantee beyond flushed data and filesystem atomic replacement is not claimed.

## Portable tests

The test target compiles the exact production receipt files and enum sources without a reference to the Windows application. This is necessary for meaningful temporary-file and codec tests on macOS. It does not test WinUI or COM. Run:

```powershell
dotnet test --project tests/Files.App.UnitTests/Files.App.UnitTests.csproj -c Release --report-trx --results-directory artifacts/qualification/unit-tests
```

## Installed Windows interaction tests

Use a disposable Windows test account and the owned test package. Set `FILEQUAY_TEST_APP_ID` to its actual AUMID and `FILEQUAY_TEST_LOCAL_STATE` to its LocalState directory. Start WinAppDriver on localhost:4723. The tests use real copy commands, native save picker, persisted JSON, CSV, cancellation and an exclusive history-file lock to exercise write failure. The cancellation test creates about 750 MiB in an isolated test directory. A host that completes the batch before the UI can cancel must increase the test workload; do not skip or relabel it passing.

```powershell
dotnet test --project tests/Files.InteractionTests/Files.InteractionTests.csproj -c Release -p:Platform=x64 --treenode-filter '/*/*/OperationReceiptTests/*'
```

The test methods are `UnicodeCopyHasOneInspectableReceiptAndExportsCsv`, `CancelledBatchRetainsOriginalsAndOneCancelledReceipt`, and `PersistenceFailureLeavesCompletedQueueRowAndOriginalsVisible`.

Run at 100%, 150% and 200% scaling and light/dark/high contrast. The native picker accessibility IDs and focus sequence require confirmation on the actual Windows image. No interaction run is claimed from source inspection, syntax parsing, HTML import or portable tests.

## Packaging

Use `distribution/build-filequay.ps1 -Identity <owned-name> -Publisher <owned-distinguished-name>` from a clean committed Windows checkout. It uses unsigned output and stops on failures. The plan's `MakeAppx validate` command does not exist: the verifier uses `MakeAppx unpack` without `/nv`, which retains documented semantic validation. This is limited validation, not WACK or successful installation. Microsoft reference: https://learn.microsoft.com/en-us/windows/win32/appxpkg/make-appx-package--makeappx-exe-

Generated SPDX inventories require resolved application assets. `NOASSERTION` entries, native 7-Zip/unRAR/SevenZipSharp inputs, assets/fonts/native winmd provenance and corresponding source remain release review gates. No package is cleared for distribution by these scripts. Original MIT/MPL notices remain in history and are included in the package. The public vendor download recipe is maintained by the release coordinator.
