# FileQuay

FileQuay is Trieflow LLC’s Windows file manager with tabs, panes, an operation queue and local operation receipts. Receipts show final results, reported totals and selected paths, with explicit CSV export. They do not undo operations. FileQuay does not replace Explorer or change system defaults.

- Product: https://filequay.trieflow.com
- Privacy: https://filequay.trieflow.com/privacy
- Support: https://filequay.trieflow.com/support

## Source and license

Based on [Files Community / Files](https://github.com/files-community/Files) v4.2.9 at `99951c66928c4da714da8b1dd46039421182cbab`, with original history retained. Copyright notices remain in their source files. The source contains both [MIT](LICENSE-MIT) and [MPL-2.0](LICENSE-MPL) material. Read [third-party notices](.github/NOTICE.md) for additional dependency and asset terms. FileQuay modifications and the original FileQuay icon are copyright 2026 Trieflow LLC.

## Build and verification

Use Windows with the exact toolchain in [distribution/toolchain.md](distribution/toolchain.md). Package inputs must be explicitly owned; no Store identity or certificate is included. Run `distribution/build-filequay.ps1` from a clean committed checkout with `-Identity` and `-Publisher`. It creates unsigned qualification output. The vendor-input bootstrap downloads immutable, hash-verified upstream inputs; it is not license clearance.

Portable receipt tests: `dotnet test --project tests/Files.App.UnitTests/Files.App.UnitTests.csproj -c Release`.

[Receipt behavior and Windows interaction instructions](distribution/receipts.md) describe supported capture entrypoints and limits. The core tests compile exact production receipt sources without WinUI. Windows build, installed interaction tests, scaling, upgrade/uninstall, WACK, current dependency support and all unresolved source/native/asset license checks remain separate release gates. Local portable tests or an unsigned CI build do not establish Store certification.

## Data behavior

Receipt history is stored in the app’s own LocalState directory and retains the newest 500 records within 32 MiB. Clearing receipts affects metadata only. No file contents, URL credentials, telemetry or remote update service are used for receipts. Existing user-invoked network file access remains part of the file manager; automatic upstream telemetry, reverse-geocoding and GitHub sign-in have been removed.
