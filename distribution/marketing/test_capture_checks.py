"""Capture-only bindings refuse stale, unqualified or substituted inputs."""
# Copyright 2026 Trieflow LLC. MIT.
import copy
from pathlib import Path
import subprocess
import tempfile
import unittest
import capture_checks as c


def binding():
    return dict(schema_version=1, product='FolderSail', qualified=dict(
        source_commit='a'*40, workflow_run_id='42', workflow_run_attempt='1',
        package=dict(bytes=8, sha256='b'*64), readiness_receipt=dict(bytes=9, sha256='c'*64),
        artifacts=dict(store=11, Consumer=12, Instrumented=13, Store=14)))


class CaptureChecks(unittest.TestCase):
    def test_unbound_candidate_refuses(self):
        with self.assertRaisesRegex(ValueError, 'reviewed'):
            c.validate_binding(dict(schema_version=1, product='FolderSail', qualified=None))

    def test_exact_context_and_positive_byte_bindings(self):
        original = binding()
        self.assertEqual(c.validate_binding(original), original['qualified'])
        for key, value in [('source_commit', 'main'), ('workflow_run_attempt', '0'), ('package', {'bytes': True, 'sha256': 'b'*64}),
                           ('artifacts', {'store': 11, 'Consumer': 12, 'Store': 14})]:
            bad = copy.deepcopy(original); bad['qualified'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                c.validate_binding(bad)

    def test_artifact_metadata_must_name_original_run_and_bytes(self):
        bound = c.validate_binding(binding())
        info = dict(id=11, name=c.ARTIFACT_NAMES['store'], expired=False, size_in_bytes=42,
                    digest='sha256:'+'d'*64, workflow_run=dict(id=42, head_sha='a'*40))
        self.assertEqual(c.validate_artifact(info, 'store', bound, 100), 'd'*64)
        for key, value in [('expired', True), ('id', 99), ('digest', None), ('size_in_bytes', 101),
                           ('workflow_run', dict(id=41, head_sha='a'*40))]:
            bad = copy.deepcopy(info); bad[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                c.validate_artifact(bad, 'store', bound, 100)

    def test_failed_wrong_attempt_or_wrong_repository_run_refuses(self):
        bound = c.validate_binding(binding())
        run = dict(id=42, head_sha='a'*40, run_attempt=1, conclusion='success',
                   repository=dict(full_name=c.REPOSITORY), path='.github/workflows/windows.yml')
        c.validate_run(run, bound)
        for key, value in [('run_attempt', 2), ('conclusion', 'failure'), ('repository', {'full_name': 'other/repo'}), ('head_sha', 'f'*40)]:
            bad = copy.deepcopy(run); bad[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                c.validate_run(bad, bound)

    def test_safe_paths_refuse_traversal_windows_aliases_and_links(self):
        for name in ('../secret', '/absolute', 'C:drive', 'a\\b', 'a//b', 'a/./b', 'a. /file', 'CON/file'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                c.relative_path(name)
        self.assertEqual(c.relative_path('Store-Consumer/build-result.json'), 'Store-Consumer/build-result.json')

    def test_actual_git_source_is_clean_and_exact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.STDOUT)
            git('init', '-q'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid')
            (root/'owned.txt').write_bytes(b'original\n'); git('add', '.'); git('commit', '-qm', 'fixture')
            head = git('rev-parse', 'HEAD').decode().strip()
            c.assert_checkout(root, head)
            with self.assertRaises(ValueError):
                c.assert_checkout(root, 'b'*40)
            (root/'owned.txt').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                c.assert_checkout(root, head)
            self.assertEqual((root/'owned.txt').read_bytes(), b'changed')


if __name__ == '__main__':
    unittest.main()
