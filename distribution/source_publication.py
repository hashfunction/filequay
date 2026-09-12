# Copyright 2026 Trieflow LLC. MIT.
"""Bind reviewed native sources and the exact current public application tree."""
import hashlib
import json
import re
import subprocess
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from store_evidence import file_record, load

SOURCE_PAGE = 'https://foldersail.trieflow.com/source'
RELEASE_URL = 'https://github.com/hashfunction/filequay/releases/tag/native-sources-2026-09-12'
DOWNLOAD_ROOT = RELEASE_URL.replace('/tag/', '/download/') + '/'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def utc(value):
    require(isinstance(value, str), 'Missing UTC publication verification time')
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        require(parsed.tzinfo is not None and parsed.utcoffset().total_seconds() == 0, 'Verification time must be UTC')
    except ValueError as error:
        raise ValueError('Invalid UTC publication verification time') from error



def download(url, destination, limit):
    """Unauthenticated HTTPS bytes, bounded in size and time; never reuse HEAD metadata."""
    require(urlsplit(url).scheme == 'https', 'Source download requires HTTPS')
    started = time.monotonic()
    digest = hashlib.sha256(); size = 0
    with urlopen(Request(url, headers={'User-Agent': 'FolderSail-source-verification'}), timeout=30) as response:
        require(response.status == 200 and urlsplit(response.url).scheme == 'https', 'Anonymous source download failed')
        with destination.open('xb') as target:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                require(size <= limit and time.monotonic() - started < 180, 'Source download exceeded bound')
                target.write(chunk); digest.update(chunk)
        redirect_host = urlsplit(response.url).hostname
    return dict(url=url, redirect_host=redirect_host, bytes=size, sha256=digest.hexdigest(),
                verified_at_utc=datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'))


def git(source, *arguments):
    return subprocess.check_output(['git', '-C', str(source), *arguments], timeout=30)


def verify_application_archive(archive, source, commit):
    require(re.fullmatch('[0-9a-f]{40}', commit or ''), 'Current source needs an exact Git commit')
    expected = {}
    for row in git(source, 'ls-tree', '-rz', '--full-tree', commit).split(b'\0'):
        if not row: continue
        metadata, raw_name = row.split(b'\t', 1)
        mode, kind, blob = metadata.decode().split(' ')
        require(kind == 'blob' and mode in ('100644', '100755', '120000'), 'Unsupported source tree entry')
        expected[raw_name.decode('utf-8')] = (mode, blob)
    seen = set(); prefix = None; total = 0
    with tarfile.open(archive, 'r:gz') as stream:
        for member in stream:
            parts = PurePosixPath(member.name).parts
            require(parts and not member.name.startswith('/') and '..' not in parts, 'Unsafe source archive path')
            prefix = prefix or parts[0]
            require(parts[0] == prefix, 'Source archive has multiple roots')
            if member.isdir(): continue
            name = '/'.join(parts[1:])
            require(name in expected and name not in seen, 'Missing, extra or duplicate source archive member')
            mode, blob = expected[name]
            if mode == '120000':
                require(member.issym(), 'Source archive symlink mode changed')
                data = member.linkname.encode('utf-8')
            else:
                require(member.isfile() and bool(member.mode & 0o111) == (mode == '100755'), 'Source file mode changed')
                require(0 <= member.size <= 64 * 1024 * 1024, 'Oversized application source member')
                data = stream.extractfile(member).read()
            total += len(data)
            require(total <= 256 * 1024 * 1024, 'Application source archive is too large')
            actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            require(actual == blob, 'Public application source bytes differ from Git: ' + name)
            seen.add(name)
    require(seen == set(expected) and bool(seen), 'Public application archive omits tracked source')
    return dict(source_commit=commit, git_tree=git(source, 'rev-parse', commit+'^{tree}').decode().strip(),
                verified_tracked_files=len(seen), verified_source_bytes=total)


def validate_publication(record, plan_path):
    plan = load(plan_path)
    require(plan.get('schema_version') == 1 and plan.get('product') == 'FolderSail'
            and plan.get('release_url') == RELEASE_URL, 'Unexpected native source plan')
    require(record.get('schema_version') == 1 and record.get('product') == 'FolderSail'
            and record.get('publication_verified') is True and record.get('source_page') == SOURCE_PAGE
            and record.get('release_url') == RELEASE_URL, 'Native sources are not publicly verified')
    utc(record.get('verified_at_utc'))
    components = {row['component']: row['version'] for row in plan['assets']}
    require(components == {'7zip': '26.00', 'sevenzipsharp': '1.0.3', 'taglibsharp': '2.3.0',
            'libgit2': 'a418d9d4ab87bae16b87d8f37143a4687ae0e4b2', 'libgit2-native-build': '2.0.322',
            'utf-unknown': '2.6.0'}, 'Native corresponding source version set changed')
    for row in plan['assets']:
        require(re.fullmatch('[A-Za-z0-9][A-Za-z0-9._-]*', row.get('filename', '')) and type(row.get('bytes')) is int
                and 0 < row['bytes'] <= 64 * 1024 * 1024 and re.fullmatch('[0-9a-f]{64}', row.get('sha256', '')),
                'Unsafe or invalid native source asset')
    expected = {row['filename']: {key: row[key] for key in ('bytes', 'sha256')} for row in plan['assets']}
    require(len(expected) == len(plan['assets']) == 6, 'Expected six unique reviewed source assets')
    expected['source-release-assets.json'] = file_record(plan_path)
    items = [record.get('manifest', {})] + record.get('assets', [])
    require(len(items) == 7 and {row.get('filename') for row in items} == set(expected), 'Published source set is missing, extra or duplicated')
    for row in items:
        name = row['filename']; host = row.get('redirect_host', '')
        require(row.get('url') == DOWNLOAD_ROOT + name and all(row.get(key) == value for key, value in expected[name].items())
                and 'final_url' not in row and re.fullmatch('[a-z0-9.-]+', host) and '.' in host,
                'Published source URL/bytes differ: ' + name)
        utc(row.get('verified_at_utc'))
    return plan


def verify_public_sources(source, commit):
    folder = source / 'distribution/corresponding-source'
    publication = load(folder / 'native-source-publication.json')
    plan = validate_publication(publication, folder / 'source-release-assets.json')
    inputs = {path.name: file_record(path) for path in folder.glob('*.json')}
    with tempfile.TemporaryDirectory(prefix='foldersail-public-source-') as temporary:
        temporary = Path(temporary).resolve()
        fetched = []
        for row in [publication['manifest']] + publication['assets']:
            target = temporary / row['filename']
            result = download(row['url'], target, row['bytes'])
            require({key: result[key] for key in ('bytes', 'sha256')} == {key: row[key] for key in ('bytes', 'sha256')},
                    'Public corresponding-source bytes changed: ' + row['filename'])
            fetched.append(result)
            target.unlink()
        archive = temporary / 'current-app.tar.gz'
        current = download('https://github.com/hashfunction/filequay/archive/' + commit + '.tar.gz', archive, 64 * 1024 * 1024)
        current.update(verify_application_archive(archive, source, commit))
    require(inputs == {path.name: file_record(path) for path in folder.glob('*.json')}, 'Source publication inputs changed during verification')
    return dict(application_source=current, source_page=SOURCE_PAGE, source_publication_inputs=inputs,
                native_source_assets=fetched, source_release=RELEASE_URL)
