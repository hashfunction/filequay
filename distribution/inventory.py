#!/usr/bin/env python3
"""Inventory resolved packages and source assets; unreviewed licenses remain release gates."""
import argparse, csv, datetime, hashlib, json, pathlib, uuid
parser = argparse.ArgumentParser()
parser.add_argument('--package-root', type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'distribution'
assets = sorted((root / 'src').glob('**/obj/project.assets.json'))
packages = {}
for file in assets:
    doc = json.loads(file.read_text(encoding='utf-8-sig'))
    for key, value in doc.get('libraries', {}).items():
        if value.get('type') != 'package': continue
        name, version = key.rsplit('/', 1)
        packages[key] = {'SPDXID': 'SPDXRef-' + hashlib.sha256(key.encode()).hexdigest()[:24],
            'name': name, 'versionInfo': version, 'downloadLocation': f'https://www.nuget.org/api/v2/package/{name}/{version}',
            'filesAnalyzed': False, 'licenseConcluded': 'NOASSERTION', 'licenseDeclared': 'NOASSERTION',
            'externalRefs': [{'referenceCategory': 'PACKAGE-MANAGER', 'referenceType': 'purl', 'referenceLocator': f'pkg:nuget/{name}@{version}'}]}
spdx = {'spdxVersion': 'SPDX-2.3', 'dataLicense': 'CC0-1.0', 'SPDXID': 'SPDXRef-DOCUMENT',
    'name': 'FileQuay resolved NuGet inventory', 'documentNamespace': f'https://filequay.trieflow.com/spdx/{uuid.uuid4()}',
    'creationInfo': {'creators': ['Organization: Trieflow LLC'], 'created': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')},
    'documentComment': f'{len(assets)} application/source project asset files read. NOASSERTION licenses and missing assets require review before release.',
    'packages': sorted(packages.values(), key=lambda p: p['name'].lower())}
(out / 'dependencies.spdx.json').write_text(json.dumps(spdx, indent=2)+'\n', newline='\r\n')
files = set((root / 'src/Files.App/Assets').rglob('*')) | set((root / 'src').glob('**/*.dll'))
if args.package_root: files |= set(args.package_root.rglob('*'))
with (out / 'resources.csv').open('w', encoding='utf-8', newline='') as stream:
    writer = csv.writer(stream)
    writer.writerow(['path','sha256','origin','license','notice','inclusion_decision'])
    for file in sorted(files):
        if not file.is_file() or any(part in ('obj','bin') for part in file.parts): continue
        owned = '/Assets/FileQuay/' in file.as_posix()
        try: path = file.relative_to(root).as_posix()
        except ValueError: path = 'PACKAGE/' + file.relative_to(args.package_root).as_posix()
        writer.writerow([path, hashlib.sha256(file.read_bytes()).hexdigest(), 'Trieflow LLC' if owned else 'Files baseline 99951c66928c4da714da8b1dd46039421182cbab; verify package-specific origin',
            'MIT' if owned else 'NOASSERTION', 'src/Files.App/Assets/FileQuay/NOTICE.md' if owned else 'REVIEW_REQUIRED',
            'include' if owned else 'excluded' if '/AppTiles/' in path or '/FilesOpenDialog/' in path else 'REVIEW_REQUIRED'])
print(f'Inventoried {len(packages)} resolved packages from {len(assets)} source project assets. License review remains required.')
