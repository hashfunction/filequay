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

## Required owned activation protocol

Source inspection found that new-window, dragged-tab, restart and tray activation use a URI protocol. Qualification explicitly passes `-Protocol filequay` and all active launcher entrypoints now use `filequay:`. This narrowly retained declaration preserves existing core navigation; it does not replace Explorer, register file associations, add an execution alias, or start the app at login. The configurator still requires an explicit protocol argument. Entry points: `NavigationHelpers`, `BaseOpenInNewWindowAction`, `GeneralViewModel`, `SystemTrayIcon` and crash restart in `AppLifecycleHelper`; routing remains in `MainWindow.InitializeApplicationAsync`. Malformed empty protocol queries are ignored. Test new windows, tab tear-off and restart on the installed Windows package.
