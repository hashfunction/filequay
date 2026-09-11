# Copyright (c) Trieflow LLC. Licensed under the MIT License.
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('sqlite_assets', SOURCE / 'distribution/verify-sqlite-assets.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SQLiteAssetsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.cache = self.root / 'cache'
        self.package = self.root / 'package'
        self.package.mkdir()
        self.lock = json.loads((SOURCE / 'distribution/sqlite-dependencies.lock.json').read_text())
        self.assets = {'targets': {'net10.0-windows10.0.26100.0/win-x64': {}}, 'libraries': {}}
        for name, value in self.lock['packages'].items():
            folder = self.cache / name.lower() / value['version']
            archive = folder / f"{name.lower()}.{value['version']}.nupkg"
            asset = folder / value['asset']
            asset.parent.mkdir(parents=True)
            archive.write_bytes(('archive:' + name).encode())
            asset.write_bytes(('asset:' + name).encode())
            value['archiveSha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
            value['assetSha256'] = hashlib.sha256(asset.read_bytes()).hexdigest()
            (self.package / value['packagedName']).write_bytes(asset.read_bytes())
            key = name + '/' + value['version']
            self.assets['libraries'][key] = {'sha512': value['nugetContentHash']}
            self.assets['targets']['net10.0-windows10.0.26100.0/win-x64'][key] = {
                value['assetKind']: {value['asset']: {}}}
        for name in self.lock['notices']:
            path = self.package / 'Licenses/SQLite' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
            self.lock['notices'][name] = hashlib.sha256(path.read_bytes()).hexdigest()

    def verify(self):
        assets = self.root / 'project.assets.json'
        lock = self.root / 'lock.json'
        assets.write_text(json.dumps(self.assets))
        lock.write_text(json.dumps(self.lock))
        (self.package / 'Licenses/SQLite/sqlite-dependencies.lock.json').write_bytes(lock.read_bytes())
        return MODULE.verify(assets, self.cache, self.package, lock)

    def test_accepts_exact_selected_graph_and_packaged_files(self):
        self.assertTrue(self.verify()['passed'])

    def test_rejects_legacy_native_in_selected_graph(self):
        self.assets['targets']['net10.0-windows10.0.26100.0/win-x64']['SQLitePCLRaw.lib.e_sqlite3/2.1.11'] = {}
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_wrong_windows_provider_asset(self):
        item = self.assets['targets']['net10.0-windows10.0.26100.0/win-x64']['SQLitePCLRaw.provider.e_sqlite3/3.0.5']
        item['runtime'] = {'lib/net8.0/SQLitePCLRaw.provider.e_sqlite3.dll': {}}
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_archive_substitution(self):
        (self.cache / 'sqlite/3.53.4/sqlite.3.53.4.nupkg').write_bytes(b'substituted')
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_package_content_hash_mismatch(self):
        self.assets['libraries']['SQLite/3.53.4']['sha512'] = 'unrecognized'
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_stale_packaged_native(self):
        (self.package / 'e_sqlite3.dll').write_bytes(b'old native')
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_changed_packaged_managed_provider(self):
        (self.package / 'SQLitePCLRaw.provider.e_sqlite3.dll').write_bytes(b'other provider')
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_duplicate_native_even_in_subdirectory(self):
        (self.package / 'stale').mkdir()
        (self.package / 'stale/e_sqlite3.dll').write_bytes(b'other native')
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_missing_notice(self):
        (self.package / 'Licenses/SQLite/SQLite-LICENSE.txt').unlink()
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()

    def test_rejects_missing_or_ambiguous_windows_target(self):
        other = copy.deepcopy(self.assets['targets']['net10.0-windows10.0.26100.0/win-x64'])
        self.assets['targets']['net10.0-windows10.0.19041.0/win-x64'] = other
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()
        self.assets['targets'] = {}
        with self.assertRaises(MODULE.SQLiteAssetError): self.verify()


if __name__ == '__main__': unittest.main()
