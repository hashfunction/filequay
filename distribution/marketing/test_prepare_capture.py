# Copyright 2026 Trieflow LLC. MIT.
import base64
import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile
import prepare_capture as p


class PrepareCapture(unittest.TestCase):
    def test_archive_validation_precedes_writes(self):
        for entries in ([('ok.json', b'{}'), ('../foreign', b'x')], [('same.json', b'1'), ('SAME.json', b'2')]):
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve(); archive = root/'input.zip'
                with zipfile.ZipFile(archive, 'w') as z:
                    for name, data in entries: z.writestr(name, data)
                with self.assertRaises(ValueError): p.extract_artifact(archive, root/'out', 1000)
                self.assertFalse((root/'out').exists())

    def test_extract_exact_regular_artifact_members(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); archive = root/'input.zip'
            with zipfile.ZipFile(archive, 'w') as z: z.writestr('Consumer/original.json', b'{"original":true}')
            p.extract_artifact(archive, root/'out', 1000)
            self.assertEqual((root/'out/Consumer/original.json').read_bytes(), b'{"original":true}')

    def test_framework_requires_original_archive_and_unique_exact_member(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); archive = root/'runtime.nupkg'; original = b'original framework fixture'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('tools/MSIX/x64/framework.msix', original)
                z.writestr('tools/MSIX/arm64/framework.msix', b'other architecture')
            sha512 = base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()
            expected = hashlib.sha256(original).hexdigest()
            result = p.extract_framework(archive, root/'framework.msix', sha512, expected)
            self.assertEqual(result['member'], 'tools/MSIX/x64/framework.msix')
            self.assertEqual((root/'framework.msix').read_bytes(), original)
            for archive_hash, member_hash in [('invalid', expected), (sha512, '0'*64)]:
                with self.assertRaises(ValueError): p.extract_framework(archive, root/'absent.msix', archive_hash, member_hash)
                self.assertFalse((root/'absent.msix').exists())


if __name__ == '__main__': unittest.main()
