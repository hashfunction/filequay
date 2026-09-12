"""Real isolated files exercise capture cleanup, never fabricate app acceptance."""
# Copyright 2026 Trieflow LLC. MIT.
import csv
import copy
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest

import capture_files as f


class CaptureFiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.parent = Path(self.temp.name).resolve()
        self.state = f.create(self.parent / 'FolderSail Demo')
        self.root = Path(self.state['root'])

    def move_fixture(self):
        shutil.copyfile(self.root / f.SOURCE, self.root / f.COPIED)
        self.assertEqual(f.verify(self.state, 'Copied')['phase'], 'Copied')
        (self.root / f.COPIED).rename(self.root / f.MOVED)

    def receipts(self):
        return [dict(id='12345678-1234-1234-1234-' + suffix, schemaVersion=1,
                     startedAtUtc='2026-09-12T12:00:00.1234567+00:00',
                     completedAtUtc='2026-09-12T12:00:01.1234567+00:00',
                     fileOperationType=operation, returnResult=1, failureCode=None,
                     itemCount=1, totalBytes=self.state['payload']['bytes'],
                     sourcePaths=[str(self.root / source)], destinationPaths=[str(self.root / destination)])
                for suffix, operation, source, destination in
                [('000000000003', 3, f.SOURCE, f.COPIED), ('000000000004', 4, f.COPIED, f.MOVED)]]

    def write_export(self):
        rows = self.receipts()
        stream = io.StringIO(newline='')
        writer = csv.writer(stream, lineterminator='\r\n')
        writer.writerow(f.COLUMNS)
        for row in rows:
            writer.writerow([row['id'], row['startedAtUtc'], row['completedAtUtc'],
                             'Copy' if row['fileOperationType'] == 3 else 'Move', 'Success',
                             row['itemCount'], row['totalBytes'], row['sourcePaths'][0], row['destinationPaths'][0], ''])
        recovery = self.root / (f.CSV + '.' + 'a' * 32 + '.filequay-original')
        (self.root / f.CSV).rename(recovery)
        (self.root / f.CSV).write_bytes(stream.getvalue().encode())
        return rows, recovery

    def test_original_friendly_content_and_exclusive_creation(self):
        self.assertEqual(f.verify(self.state, 'Initial')['phase'], 'Initial')
        self.assertIn(b'Garden workshop', (self.root / f.SOURCE).read_bytes())
        self.assertFalse(any('quay' in p.lower() for p in self.state['originals']))
        with self.assertRaisesRegex(ValueError, 'Existing'):
            f.create(self.root)

    def test_real_copy_move_and_exact_csv_rows(self):
        self.move_fixture()
        rows, recovery = self.write_export()
        exported = f.register_export(self.state, rows, str(recovery))
        self.assertEqual(exported['rows'], 2)
        self.assertEqual(f.verify(self.state, 'Exported')['phase'], 'Exported')
        self.assertEqual(f.digest(recovery), self.state['previous_csv'])

    def test_csv_must_match_real_receipt_paths_and_ids(self):
        self.move_fixture()
        rows, recovery = self.write_export()
        for field, replacement in [('sourcePaths', [str(self.parent / 'foreign')]), ('id', '0' * 36), ('returnResult', 0)]:
            changed = copy.deepcopy(rows)
            changed[0][field] = replacement
            with self.subTest(field=field), self.assertRaises(ValueError):
                f.register_export(self.state, changed, str(recovery))

    def test_mutated_protected_or_unknown_file_is_preserved(self):
        (self.root / 'Inbox/Workshop agenda.txt').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Original'):
            f.verify(self.state, 'Initial')
        self.assertEqual((self.root / 'Inbox/Workshop agenda.txt').read_bytes(), b'changed')

    def test_links_foreign_recovery_and_unknown_outputs_refuse(self):
        outside = self.parent / 'foreign'; outside.write_bytes(b'keep')
        (self.root / 'alias').symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'link|Link'):
            f.verify(self.state, 'Initial')
        (self.root / 'alias').unlink()
        self.move_fixture(); rows, recovery = self.write_export()
        with self.assertRaisesRegex(ValueError, 'recovery'):
            f.register_export(self.state, rows, str(outside))
        self.assertEqual(outside.read_bytes(), b'keep')
        (self.root / 'unknown.txt').write_text('preserve')
        with self.assertRaisesRegex(ValueError, 'Unexpected'):
            f.seal(self.state, True)

    def test_cleanup_requires_stopped_and_unchanged_sealed_files(self):
        seal = f.seal(self.state, True)
        with self.assertRaisesRegex(ValueError, 'stopped'):
            f.cleanup(self.state, seal, False)
        (self.root / 'Receipts/unknown.txt').write_text('preserve')
        with self.assertRaises(ValueError):
            f.cleanup(self.state, seal, True)
        self.assertTrue((self.root / 'Receipts/unknown.txt').is_file())
        (self.root / 'Receipts/unknown.txt').unlink()
        self.assertTrue(f.cleanup(self.state, seal, True)['removed'])

    def test_marker_mutation_refuses_before_any_deletion(self):
        seal = f.seal(self.state, True)
        (self.root / f.MARKER).write_text('foreign')
        with self.assertRaisesRegex(ValueError, 'ownership'):
            f.cleanup(self.state, seal, True)
        self.assertTrue((self.root / f.SOURCE).is_file())


if __name__ == '__main__':
    unittest.main()
