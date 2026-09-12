# Copyright (c) Trieflow LLC. Licensed under the MIT License.
import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

SOURCE = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('windows_sdk_policy', SOURCE / 'distribution/windows_sdk_policy.py')
POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLICY)


class WindowsSdkPolicyTests(unittest.TestCase):
    def setUp(self):
        self.props = b'<Project><PropertyGroup><WindowsSdkPackageVersion>10.0.26100.70</WindowsSdkPackageVersion></PropertyGroup></Project>'
        self.key = 'runtimepack.Microsoft.Windows.SDK.NET.Ref/10.0.26100.70'
        self.target = '.NETCoreApp,Version=v10.0/win-x64'
        self.deps = {'runtimeTarget': {'name': self.target},
                     'libraries': {self.key: {'type': 'runtimepack'}},
                     'targets': {self.target: {self.key: {'runtime': {
                         'Microsoft.Windows.SDK.NET.dll': {'assemblyVersion': '10.0.26100.69', 'fileVersion': '10.0.26100.69'},
                         'WinRT.Runtime.dll': {'assemblyVersion': '2.2.0.0', 'fileVersion': '2.2.0.48161'}}}}}}

    def test_accepts_exact_stable_source_and_packaged_projection(self):
        result = POLICY.verify_package_sdk(self.props, self.deps)
        self.assertEqual('10.0.26100.70', result['version'])

    def test_refuses_preview_missing_duplicate_or_conditional_source_pin(self):
        cases = [self.props.replace(b'10.0.26100.70', b'10.0.26100.67-preview'),
                 self.props.replace(b'10.0.26100.70', b'10.0.26100.69'),
                 b'<Project/>', self.props.replace(b'</PropertyGroup>', b'<WindowsSdkPackageVersion>10.0.26100.70</WindowsSdkPackageVersion></PropertyGroup>'),
                 self.props.replace(b'<PropertyGroup>', b'<PropertyGroup Condition="false">'),
                 self.props.replace(b'<WindowsSdkPackageVersion>', b'<WindowsSdkPackageVersion Condition="false">')]
        for props in cases:
            with self.subTest(props=props), self.assertRaises(POLICY.WindowsSdkError):
                POLICY.verify_package_sdk(props, self.deps)

    def test_refuses_stale_preview_package_even_with_stable_source(self):
        for version in ['10.0.26100.67-preview', '10.0.26100.69']:
            deps = copy.deepcopy(self.deps)
            stale = 'runtimepack.Microsoft.Windows.SDK.NET.Ref/' + version
            deps['libraries'][stale] = deps['libraries'].pop(self.key)
            deps['targets'][self.target][stale] = deps['targets'][self.target].pop(self.key)
            with self.subTest(version=version), self.assertRaises(POLICY.WindowsSdkError):
                POLICY.verify_package_sdk(self.props, deps)

    def test_refuses_inconsistent_or_missing_runtime_records(self):
        cases = []
        for section in ['libraries', 'targets']:
            deps = copy.deepcopy(self.deps)
            deps[section] = {}
            cases.append(deps)
        for name, field in [('Microsoft.Windows.SDK.NET.dll', 'assemblyVersion'), ('WinRT.Runtime.dll', 'fileVersion')]:
            deps = copy.deepcopy(self.deps)
            deps['targets'][self.target][self.key]['runtime'][name][field] = '0.0.0.0'
            cases.append(deps)
        deps = copy.deepcopy(self.deps)
        deps['runtimeTarget']['name'] = '.NETCoreApp,Version=v10.0/win-arm64'
        cases.append(deps)
        deps = copy.deepcopy(self.deps)
        deps['libraries']['runtimepack.Microsoft.Windows.SDK.NET.Ref/10.0.26100.67-preview'] = {'type': 'runtimepack'}
        cases.append(deps)
        for index, deps in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(POLICY.WindowsSdkError):
                POLICY.verify_package_sdk(self.props, deps)

    def test_cli_refuses_preview_before_publication_without_writing_receipt(self):
        self.assert_cli_refused(self.props.replace(b'10.0.26100.70', b'10.0.26100.67-preview'), 'preview or unaudited pins')

    def test_cli_refuses_changed_original_nuget_archive(self):
        self.assert_cli_refused(self.props, 'NuGet archive differs')

    def assert_cli_refused(self, props, expected_error):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'props.xml').write_bytes(props)
            (root / 'package.deps.json').write_text(json.dumps(self.deps))
            archive = root / 'microsoft.windows.sdk.net.ref/10.0.26100.70/microsoft.windows.sdk.net.ref.10.0.26100.70.nupkg'
            archive.parent.mkdir(parents=True)
            archive.write_bytes(b'changed archive')
            output = root / 'sdk-result.json'
            result = subprocess.run([sys.executable, str(SOURCE / 'distribution/windows_sdk_policy.py'),
                '--props', str(root / 'props.xml'), '--deps', str(root / 'package.deps.json'),
                '--package-cache', str(root), '--output', str(output)], capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn(expected_error, result.stderr)
            self.assertFalse(output.exists())

    def test_product_pin_selects_audited_stable_net8_projection(self):
        root = ET.parse(SOURCE / 'Directory.Build.props').getroot()
        self.assertEqual(['10.0.26100.70'], [node.text for node in root.iter('WindowsSdkPackageVersion')])


if __name__ == '__main__':
    unittest.main()
