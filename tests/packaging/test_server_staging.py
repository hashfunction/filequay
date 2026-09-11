# Copyright (c) Trieflow LLC. Licensed under the MIT License.
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]
DOTNET = os.environ.get("FILEQUAY_DOTNET", "dotnet")


class ServerStagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="FileQuay-server-target-")
        self.addCleanup(self.temporary.cleanup); self.root = Path(self.temporary.name)
        self.output = self.root / "server-output"
        self.output.mkdir(); (self.output / "stale.dll").write_text("previous publish")
        self.fake = self.root / "server.proj"
        self.fake.write_text('''<Project><Target Name="Publish"><MakeDir Directories="$(PublishDir)/fr"/><WriteLinesToFile File="$(PublishDir)/Files.App.Server.exe" Lines="server fixture"/><WriteLinesToFile File="$(PublishDir)/Files.App.Server.dll" Lines="dll fixture"/><WriteLinesToFile File="$(PublishDir)/Files.App.Server.runtimeconfig.json" Lines="runtime config fixture"/><WriteLinesToFile File="$(PublishDir)/Files.App.Server.deps.json" Lines="deps fixture"/><WriteLinesToFile File="$(PublishDir)/fr/dependency.resources.dll" Lines="satellite fixture"/></Target></Project>''')
        self.harness = self.root / "harness.proj"
        self.harness.write_text(f'''<Project><PropertyGroup><Configuration>Release</Configuration><Platform>x64</Platform><FileQuayRuntimeVersion>10.0.12</FileQuayRuntimeVersion><FileQuayServerProject>{self.fake}</FileQuayServerProject><FileQuayServerPublishDirectory>{self.output}/</FileQuayServerPublishDirectory></PropertyGroup><Import Project="{SOURCE / 'distribution/FileQuay.Server.targets'}"/><Target Name="AssignTargetPaths"/><Target Name="Probe" DependsOnTargets="AssignTargetPaths"><WriteLinesToFile File="{self.root / 'items.txt'}" Lines="@(Content->'%(Link)')" Overwrite="true"/></Target></Project>''')

    def run_build(self):
        return subprocess.run([DOTNET, "msbuild", str(self.harness), "-t:Probe", "-v:quiet", "-nologo"], cwd=SOURCE, capture_output=True, text=True)

    def test_publishes_before_item_collection_and_keeps_server_subdirectory(self):
        result = self.run_build(); self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        items = (self.root / "items.txt").read_text().replace("\\", "/").splitlines()
        self.assertIn("Files.App.Server/Files.App.Server.exe", items)
        self.assertIn("Files.App.Server/fr/dependency.resources.dll", items)
        self.assertFalse((self.output / "stale.dll").exists())

    def test_stops_when_publish_did_not_emit_server_executable(self):
        self.fake.write_text('<Project><Target Name="Publish"><MakeDir Directories="$(PublishDir)"/></Target></Project>')
        result = self.run_build(); self.assertNotEqual(0, result.returncode)
        self.assertIn("Files.App.Server.exe", result.stdout + result.stderr)


if __name__ == "__main__": unittest.main()
