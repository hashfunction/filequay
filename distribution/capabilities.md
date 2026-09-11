# FileQuay package capability qualification

The source manifest is intentionally unconfigured. Supply owned identity and
publisher through Configure-AppxManifest.ps1. No Store identity is invented.

Retained for Windows testing: runFullTrust for the desktop application/COM server;
broadFileSystemAccess for user-selected file management; allowElevation for
explicit protected-folder operations; unvirtualizedResources and disabled
FileSystemWriteVirtualization for editing real user-selected AppData paths.
These restricted capabilities still require runtime and Store justification.

Removed before first FileQuay build: packageManagement/update task, removableStorage,
internetClient, privateNetworkClientServer, startup registration, file associations,
upstream preview-extension host, execution alias and protocol. Protocol/alias may
only be added by explicit packaging inputs; neither changes system defaults.
Core tabs/panes/local search/file operations must be exercised in the reduced
manifest on Windows. Do not restore capabilities based on assumption alone.

The out-of-process Files.App.Server COM activation remains an internal code name
required by existing app-instance monitoring. Package identity and visible product
marks are independent. Explorer/default-dialog registration is excluded.
