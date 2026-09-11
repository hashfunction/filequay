# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]


class ServerRuntimeConfigurationTests(unittest.TestCase):
    def test_com_probe_is_compiled_only_for_the_explicit_qualification_property(self):
        for enabled in (False, True):
            with self.subTest(enabled=enabled):
                result = subprocess.run([os.environ.get('FILEQUAY_DOTNET', 'dotnet'), 'msbuild',
                    str(SOURCE / 'src/Files.App/Files.App.csproj'), '-p:Platform=x64', '-p:Configuration=Release',
                    '-p:EnableWindowsTargeting=true', '-p:FileQuayCIQualification=' + str(enabled).lower(),
                    '-getProperty:DefineConstants', '-nologo'], cwd=SOURCE, capture_output=True, text=True)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertEqual(enabled, 'FILEQUAY_CI_QUALIFICATION' in result.stdout.split(';'))

    def test_executable_name_wins_after_actual_cswinrt_authoring_import(self):
        candidates = [Path(os.environ.get('NUGET_PACKAGES', Path.home() / '.nuget/packages')) /
            'microsoft.windows.cswinrt/2.2.0/build/Microsoft.Windows.CsWinRT.Authoring.targets',
            SOURCE / '.tools/qualification-deps/cswinrt/build/Microsoft.Windows.CsWinRT.Authoring.targets']
        authoring = next((p for p in candidates if p.exists()), None)
        self.assertIsNotNone(authoring, 'Restore the exact Microsoft.Windows.CsWinRT 2.2.0 package before this test')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'runtimeconfig-path.txt'
            target = SOURCE / 'distribution/FileQuay.ServerRuntime.targets'
            harness = root / 'server.proj'
            harness.write_text(f'''<Project><PropertyGroup><AssemblyName>Files.App.Server</AssemblyName>
                <TargetDir>{root}/</TargetDir><ProjectRuntimeConfigFilePath>{root}/WinRT.Host.runtimeconfig.json</ProjectRuntimeConfigFilePath>
                <GenerateRuntimeConfigurationFiles>true</GenerateRuntimeConfigurationFiles></PropertyGroup>
                <Import Project="{target}" Condition="Exists('{target}')" />
                <Import Project="{authoring}" />
                <Target Name="GenerateBuildRuntimeConfigurationFiles"><WriteLinesToFile File="{output}"
                    Lines="$(ProjectRuntimeConfigFileName);$(ProjectRuntimeConfigFilePath)" Overwrite="true" /></Target></Project>''')
            result = subprocess.run([os.environ.get('FILEQUAY_DOTNET', 'dotnet'), 'msbuild', str(harness),
                '-t:GenerateBuildRuntimeConfigurationFiles', '-nologo', '-v:quiet'], cwd=SOURCE, capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertEqual(['Files.App.Server.runtimeconfig.json', (root / 'Files.App.Server.runtimeconfig.json').as_posix()],
                             output.read_text().replace('\\', '/').splitlines())


if __name__ == '__main__': unittest.main()
