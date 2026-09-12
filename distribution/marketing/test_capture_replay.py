"""Real exported-archive/lifecycle replay with existing validator fixtures.

Native binaries, Git and public network endpoints are separate fixture seams;
these tests never emit capture/Windows acceptance or touch app history.
"""
# Copyright 2026 Trieflow LLC. MIT.
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

import capture_checks as c
sys.path.insert(0, str(c.ROOT / 'tests/packaging'))
import test_store_export as fixture
import store_runtime as runtime


class CaptureReplay(unittest.TestCase):
    def prepare(self, root):
        source, prior, store, package = fixture.StoreExportTests().fixture(root)
        publication_folder = source / 'distribution/corresponding-source'
        publication_folder.mkdir(parents=True)
        (publication_folder / 'reviewed.json').write_text('{"fixture":"original publication bytes"}')
        for name in c.HELPERS:
            target = source / name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(c.ROOT / name, target)
        # Native runtime verification owns these framework facts. Keep the
        # fixture boundary explicit, while actual lifecycle and file replay runs.
        path = store / 'installation-result.json'
        value = json.loads(path.read_text()); value['frameworks'] = [{'fixture': 'native framework boundary'}]
        path.write_text(json.dumps(value))
        publication = dict(application_source=dict(source_commit=fixture.fixtures.CONTEXT['source_commit'], git_tree='c'*40),
                           source_page='https://foldersail.trieflow.com/source',
                           source_publication_inputs={'reviewed.json': c.digest(publication_folder/'reviewed.json')})
        inputs = root / 'inputs'; inputs.mkdir()
        original_notices = fixture.n.verify_packaged_notices
        with patch.object(fixture.x, 'verify_current_source', return_value='c'*40), \
             patch.object(fixture.x, 'verify_public_sources', return_value=publication), \
             patch.object(fixture.x, 'verify_native_evidence', return_value={'fixture': 'native boundary'}), \
             patch.object(fixture.x, 'verify_packaged_notices', side_effect=lambda source, read: original_notices(c.ROOT, read)):
            fixture.x.export(source, prior, store, inputs/'store', fixture.fixtures.CONTEXT)
        metadata = inputs/'metadata'; metadata.mkdir()
        for key, origin in [('Consumer', prior/'FolderSail-Windows-Consumer-qualification'),
                            ('Instrumented', prior/'FolderSail-Windows-Instrumented-qualification'), ('Store', store.parent)]:
            shutil.copytree(origin, metadata/key)
        bound = dict(**fixture.fixtures.CONTEXT, package=c.digest(inputs/'store'/c.PACKAGE_NAME),
                     readiness_receipt=c.digest(inputs/'store/release-ready.json'),
                     artifacts=dict(store=11, Consumer=12, Instrumented=13, Store=14))
        run = dict(id=100, head_sha=bound['source_commit'], run_attempt=1, conclusion='success',
                   repository=dict(full_name=c.REPOSITORY), path='.github/workflows/windows.yml')
        return source, inputs, bound, run, original_notices

    def test_exact_three_original_receipts_archive_and_notice_bytes_replay(self):
        with tempfile.TemporaryDirectory() as temporary:
            source, inputs, bound, run, notices = self.prepare(Path(temporary).resolve())
            with patch.object(c, 'assert_checkout', return_value='c'*40), \
                 patch.object(c, 'qualified_api', return_value=(fixture.fixtures.e, runtime, fixture.n)), \
                 patch.object(runtime, 'verify_native_evidence', return_value={'fixture': 'native boundary'}) as native, \
                 patch.object(fixture.n, 'verify_packaged_notices', side_effect=lambda source, read: notices(c.ROOT, read)):
                result = c.verify_inputs(inputs, source, bound, run)
                self.assertEqual(native.call_count, 3)
                self.assertFalse(result['consumer_acceptance'])
                self.assertEqual(result['package'], c.digest(inputs/'store'/c.PACKAGE_NAME))
                self.assertEqual(set(result['qualified_helpers']), set(c.HELPERS))

    def test_each_original_receipt_mutation_and_package_mutation_refuses(self):
        for key in ('Consumer', 'Instrumented', 'Store', 'package', 'publication'):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                source, inputs, bound, run, notices = self.prepare(Path(temporary).resolve())
                if key in ('Consumer', 'Instrumented', 'Store'):
                    path = inputs/'metadata'/key/('Store-Consumer' if key == 'Store' else key)/'installation-result.json'
                    value = json.loads(path.read_text()); value['uninstall_verified'] = False; path.write_text(json.dumps(value))
                elif key == 'package':
                    with (inputs/'store'/c.PACKAGE_NAME).open('ab') as stream: stream.write(b'changed')
                else:
                    (source/'distribution/corresponding-source/reviewed.json').write_text('{"changed":true}')
                with patch.object(c, 'assert_checkout', return_value='c'*40), \
                     patch.object(c, 'qualified_api', return_value=(fixture.fixtures.e, runtime, fixture.n)), \
                     patch.object(runtime, 'verify_native_evidence', return_value={'fixture': 'native boundary'}), \
                     patch.object(fixture.n, 'verify_packaged_notices', side_effect=lambda source, read: notices(c.ROOT, read)):
                    with self.assertRaises(ValueError): c.verify_inputs(inputs, source, bound, run)


if __name__ == '__main__': unittest.main()
