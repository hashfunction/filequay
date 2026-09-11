#!/usr/bin/env python3
# Copyright (c) Trieflow LLC. Licensed under the MIT License.
"""Verify SQLite's selected Windows graph and bytes; never infer native execution."""
import argparse
import hashlib
import json
from pathlib import Path


class SQLiteAssetError(ValueError):
    pass


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8-sig'))
    except (OSError, ValueError) as error:
        raise SQLiteAssetError(f'Cannot read dependency evidence: {path}') from error


def check_hash(path, expected):
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise SQLiteAssetError(f'Missing or linked SQLite input: {path}')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise SQLiteAssetError(f'SQLite SHA-256 mismatch: {path}')
    return expected


def verify(assets_path, package_cache, package_root=None, lock_path=None):
    lock_path = lock_path or Path(__file__).with_name('sqlite-dependencies.lock.json')
    lock = read_json(lock_path)
    if lock.get('schemaVersion') != 1:
        raise SQLiteAssetError('Unsupported SQLite dependency lock schema')
    assets = read_json(assets_path)
    targets = [name for name in assets.get('targets', {})
               if name.startswith('net10.0-windows') and name.endswith('/win-x64')]
    if len(targets) != 1:
        raise SQLiteAssetError('Expected exactly one net10.0-windows/win-x64 target')
    selected = assets['targets'][targets[0]]
    expected = {f"{name}/{value['version']}" for name, value in lock['packages'].items()}
    actual = {name for name in selected if 'sqlite' in name.casefold()}
    if actual != expected:
        raise SQLiteAssetError(f'SQLite graph differs from lock: {sorted(actual)}')
    records = []
    cache = Path(package_cache)
    root = Path(package_root) if package_root is not None else None
    for name, item in lock['packages'].items():
        key = f"{name}/{item['version']}"
        if assets.get('libraries', {}).get(key, {}).get('sha512') != item['nugetContentHash']:
            raise SQLiteAssetError(f'NuGet content hash differs for {key}')
        paths = selected[key].get(item['assetKind'], {})
        if set(paths) != {item['asset']}:
            raise SQLiteAssetError(f'Unexpected {item["assetKind"]} asset for {key}: {sorted(paths)}')
        folder = cache / name.lower() / item['version']
        archive = folder / f"{name.lower()}.{item['version']}.nupkg"
        check_hash(archive, item['archiveSha256'])
        check_hash(folder / item['asset'], item['assetSha256'])
        if root is not None:
            candidates = [p for p in root.rglob('*') if p.name.casefold() == item['packagedName'].casefold()]
            if len(candidates) != 1 or candidates[0] != root / item['packagedName']:
                raise SQLiteAssetError(f'Missing, duplicate or misplaced packaged SQLite file: {item["packagedName"]}')
            check_hash(candidates[0], item['assetSha256'])
        records.append({'package': key, 'asset': item['asset'], 'archiveSha256': item['archiveSha256'],
                        'assetSha256': item['assetSha256'], 'packagedName': item['packagedName']})
    if root is not None:
        check_hash(root / 'Licenses/SQLite/sqlite-dependencies.lock.json', hashlib.sha256(Path(lock_path).read_bytes()).hexdigest())
        for filename, expected_hash in lock['notices'].items():
            check_hash(root / 'Licenses/SQLite' / filename, expected_hash)
    return {'passed': True, 'target': targets[0], 'packages': records,
            'packagedFilesVerified': root is not None, 'nativeExecutionTested': False,
            'nativeBuildProvenance': lock['nativeBuildProvenance']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', required=True, type=Path)
    parser.add_argument('--package-cache', required=True, type=Path)
    parser.add_argument('--package-root', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.assets, args.package_cache, args.package_root)
    except SQLiteAssetError as error:
        parser.exit(1, str(error) + '\n')
    text = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    else:
        print(text, end='')


if __name__ == '__main__': main()
