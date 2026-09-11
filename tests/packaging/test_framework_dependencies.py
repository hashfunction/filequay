# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
import hashlib
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from test_package_payload import payload

NS = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'


class FrameworkArtifactsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.main = ET.fromstring(f'<Package xmlns="{NS}"><Identity Name="FileQuay" ProcessorArchitecture="x64" />'
            '<Dependencies><PackageDependency Name="Microsoft.WindowsAppRuntime.2.4" Publisher="CN=Microsoft" MinVersion="2.4.1.0" />'
            '</Dependencies></Package>')

    def archive(self, filename='runtime.msix', name='Microsoft.WindowsAppRuntime.2.4', publisher='CN=Microsoft',
                version='2.4.1.0', architecture='x64', framework='true'):
        path = self.root / filename
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('AppxManifest.xml', f'<Package xmlns="{NS}"><Identity Name="{name}" Publisher="{publisher}"'
                f' Version="{version}" ProcessorArchitecture="{architecture}" /><Properties><Framework>{framework}</Framework></Properties></Package>')
        return path

    def test_matches_exact_manifest_identity_and_retains_archive_hash(self):
        path = self.archive(version='2.4.10.0')
        result = payload.match_framework_archives(self.main, self.root)
        self.assertTrue(result['manifest_to_artifact_matching_passed'])
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), result['frameworks'][0]['sha256'])
        self.assertEqual('2.4.10.0', result['frameworks'][0]['identity']['Version'])
        self.assertFalse(result['framework_registration_tested'])

    def test_all_declared_frameworks_require_their_own_archive(self):
        self.archive()
        ET.SubElement(self.main.find(f'{{{NS}}}Dependencies'), f'{{{NS}}}PackageDependency',
                      Name='Microsoft.VCLibs.140.00', Publisher='CN=Microsoft', MinVersion='14.0.0.0')
        with self.assertRaisesRegex(payload.PayloadError, 'Microsoft.VCLibs'): payload.match_framework_archives(self.main, self.root)
        self.archive('vclibs.appx', name='Microsoft.VCLibs.140.00', version='14.0.1.0')
        self.assertEqual(2, len(payload.match_framework_archives(self.main, self.root)['frameworks']))

    def test_unrelated_wrong_publisher_old_version_and_wrong_architecture_are_rejected(self):
        for changes in [dict(name='Unrelated'), dict(publisher='CN=Other'), dict(version='2.4.0.65535'), dict(architecture='x86')]:
            with self.subTest(changes=changes):
                self.archive(**changes)
                with self.assertRaisesRegex(payload.PayloadError, 'exactly one'): payload.match_framework_archives(self.main, self.root)

    def test_neutral_architecture_is_compatible(self):
        self.archive(architecture='neutral')
        self.assertTrue(payload.match_framework_archives(self.main, self.root)['manifest_to_artifact_matching_passed'])

    def test_multiple_compatible_archives_are_ambiguous(self):
        self.archive(); self.archive('second.msix')
        with self.assertRaisesRegex(payload.PayloadError, 'found 2'): payload.match_framework_archives(self.main, self.root)

    def test_nonframework_and_malformed_versions_are_rejected(self):
        for changes in [dict(framework='false'), dict(version='2.4'), dict(version='2.4.99999.0')]:
            with self.subTest(changes=changes):
                self.archive(**changes)
                with self.assertRaises(payload.PayloadError): payload.match_framework_archives(self.main, self.root)

    def test_empty_directory_is_not_qualified_by_runner_state(self):
        with self.assertRaisesRegex(payload.PayloadError, 'found 0'): payload.match_framework_archives(self.main, self.root)


if __name__ == '__main__': unittest.main()
