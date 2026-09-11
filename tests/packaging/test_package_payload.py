# Copyright (c) Trieflow LLC. Licensed under the MIT License.
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[2] / "distribution" / "verify-package-payload.py"
spec = importlib.util.spec_from_file_location("payload", MODULE)
payload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(payload)


def pe(machine=0x8664):
    data = bytearray(160); data[:2] = b"MZ"; struct.pack_into("<I", data, 60, 80)
    data[80:84] = b"PE\0\0"; struct.pack_into("<H", data, 84, machine)
    return bytes(data)


class PackagePayloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="FileQuay-package-")
        self.addCleanup(self.temporary.cleanup); self.root = Path(self.temporary.name)
        self.write("AppxManifest.xml", """<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"><Dependencies><PackageDependency Name="Microsoft.WindowsAppRuntime.2.4" Publisher="CN=Microsoft" MinVersion="2.4.0.0" /></Dependencies><Applications><Application Id="App" Executable="FileQuay.exe" /></Applications><Extensions><Extension><OutOfProcessServer><Path>Files.App.Server\\Files.App.Server.exe</Path></OutOfProcessServer></Extension></Extensions></Package>""")
        for folder, stem in [("", "FileQuay"), ("Files.App.Server", "Files.App.Server")]:
            base = self.root / folder; base.mkdir(exist_ok=True)
            for name in [stem + ".exe", stem + ".dll", "coreclr.dll", "clrjit.dll", "hostfxr.dll", "hostpolicy.dll", "System.Private.CoreLib.dll", "System.Runtime.dll", "dependency.dll"]:
                (base / name).write_bytes(pe())
            for name in ["Licenses/DotNetRuntime/LICENSE.TXT", "Licenses/DotNetRuntime/THIRD-PARTY-NOTICES.TXT"]: self.write(str(Path(folder) / name), "runtime notice")
            frameworks = [{"name": "Microsoft.NETCore.App", "version": "10.0.12"}]
            packs = {"runtimepack.Microsoft.NETCore.App.Runtime.win-x64/10.0.12": {"runtime": {"System.Private.CoreLib.dll": {}, "System.Runtime.dll": {}}, "native": {"coreclr.dll": {}, "clrjit.dll": {}}}, stem + "/1.0.0": {"runtime": {stem + ".dll": {}, "dependency.dll": {}}}}
            if not folder:
                frameworks.append({"name": "Microsoft.WindowsDesktop.App", "version": "10.0.12"})
                packs["runtimepack.Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.12"] = {"runtime": {"System.Windows.Forms.dll": {}}}
                (base / "System.Windows.Forms.dll").write_bytes(pe()); self.write("Licenses/WindowsDesktop/LICENSE", "desktop notice")
            self.write(str(Path(folder) / (stem + ".runtimeconfig.json")), json.dumps({"runtimeOptions": {"includedFrameworks": frameworks}}))
            self.write(str(Path(folder) / (stem + ".deps.json")), json.dumps({"runtimeTarget": {"name": ".NETCoreApp,Version=v10.0/win-x64"}, "targets": {".NETCoreApp,Version=v10.0/win-x64": packs}}))

    def write(self, relative, content):
        path = self.root / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(content)

    def test_accepts_both_self_contained_entrypoints_and_declared_assets(self):
        result = payload.verify(self.root, "10.0.12")
        self.assertEqual(2, len(result["entrypoints"]))
        self.assertFalse(result["startup_verified"])

    def test_rejects_absent_windows_app_runtime_dependency(self):
        p = self.root / "AppxManifest.xml"
        p.write_text(p.read_text().replace('<PackageDependency Name="Microsoft.WindowsAppRuntime.2.4" Publisher="CN=Microsoft" MinVersion="2.4.0.0" />', ''))
        with self.assertRaisesRegex(payload.PayloadError, "Windows App Runtime"):
            payload.verify(self.root, "10.0.12")

    def test_rejects_missing_declared_server_even_when_winmd_exists(self):
        (self.root / "Files.App.Server/Files.App.Server.exe").unlink(); self.write("Files.App.Server.winmd", "metadata only")
        with self.assertRaisesRegex(payload.PayloadError, "Files.App.Server.exe"): payload.verify(self.root, "10.0.12")

    def test_rejects_missing_app_runtime(self):
        (self.root / "coreclr.dll").unlink()
        with self.assertRaisesRegex(payload.PayloadError, "coreclr.dll"): payload.verify(self.root, "10.0.12")

    def test_rejects_framework_dependent_server(self):
        self.write("Files.App.Server/Files.App.Server.runtimeconfig.json", json.dumps({"runtimeOptions": {"framework": {"name": "Microsoft.NETCore.App", "version": "10.0.12"}}}))
        with self.assertRaisesRegex(payload.PayloadError, "framework-dependent"): payload.verify(self.root, "10.0.12")

    def test_rejects_old_runtime_patch(self):
        p = self.root / "FileQuay.runtimeconfig.json"; p.write_text(p.read_text().replace("10.0.12", "10.0.2"))
        with self.assertRaisesRegex(payload.PayloadError, "runtime version"): payload.verify(self.root, "10.0.12")

    def test_rejects_missing_runtime_pack_asset(self):
        (self.root / "Files.App.Server/System.Runtime.dll").unlink()
        with self.assertRaisesRegex(payload.PayloadError, "System.Runtime.dll"): payload.verify(self.root, "10.0.12")

    def test_rejects_missing_application_dependency(self):
        (self.root / "Files.App.Server/dependency.dll").unlink()
        with self.assertRaisesRegex(payload.PayloadError, "dependency.dll"): payload.verify(self.root, "10.0.12")

    def test_rejects_wrong_native_architecture(self):
        (self.root / "Files.App.Server/coreclr.dll").write_bytes(pe(0xAA64))
        with self.assertRaisesRegex(payload.PayloadError, "x64"): payload.verify(self.root, "10.0.12")

    def test_rejects_traversing_manifest_executable(self):
        p = self.root / "AppxManifest.xml"; p.write_text(p.read_text().replace("FileQuay.exe", "../FileQuay.exe"))
        with self.assertRaisesRegex(payload.PayloadError, "Unsafe"): payload.verify(self.root, "10.0.12")

    def test_rejects_absent_runtime_notice(self):
        (self.root / "Licenses/DotNetRuntime/THIRD-PARTY-NOTICES.TXT").unlink()
        with self.assertRaisesRegex(payload.PayloadError, "THIRD-PARTY-NOTICES"): payload.verify(self.root, "10.0.12")

    def test_inventory_rejects_observed_metadata_only_server(self):
        with self.assertRaisesRegex(payload.PayloadError, "Files.App.Server/Files.App.Server.exe"):
            payload.verify_required_names(["FileQuay.exe", "FileQuay.dll", "Files.App.Server.winmd", "FileQuay.runtimeconfig.json"])


if __name__ == "__main__": unittest.main()
