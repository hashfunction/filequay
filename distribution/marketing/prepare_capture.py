"""Download immutable originals for capture; do not compile the application."""
# Copyright 2026 Trieflow LLC. MIT.
import argparse
import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import subprocess
import urllib.parse
import urllib.request
import zipfile
import capture_checks as c

RUNTIME_ARCHIVE = Path(__file__).with_name('runtime-archive.json')


def gh_json(endpoint):
    result = subprocess.run(['gh', 'api', endpoint], check=True, capture_output=True, timeout=30)
    c.require(len(result.stdout) <= 1048576, 'GitHub metadata exceeds bound')
    import json
    return json.loads(result.stdout)


def extract_artifact(archive, output, maximum, exact=None):
    c.no_links(output); c.require(not os.path.lexists(output), 'Existing artifact output preserved')
    with zipfile.ZipFile(archive) as incoming:
        entries = incoming.infolist(); names = [c.relative_path(e.filename) for e in entries]
        c.require(len(entries) <= 1200 and len(set(n.casefold() for n in names)) == len(names) and
                  sum(e.file_size for e in entries) <= maximum and
                  all(not e.is_dir() and not e.flag_bits & 1 and not stat.S_ISLNK(e.external_attr >> 16) for e in entries),
                  'Ambiguous, linked or oversized original artifact')
        if exact is not None:
            c.require(set(names) == set(exact), 'Store artifact has unexpected members')
        output.mkdir()
        for entry in entries:
            target = output / entry.filename; target.parent.mkdir(parents=True, exist_ok=True)
            with incoming.open(entry) as source, target.open('xb') as destination:
                shutil.copyfileobj(source, destination, 1048576)


def artifact(key, output, bound):
    maximum = 800000000 if key == 'store' else 128000000
    endpoint = f"repos/{c.REPOSITORY}/actions/artifacts/{bound['artifacts'][key]}"
    info = gh_json(endpoint); expected = c.validate_artifact(info, key, bound, maximum)
    archive = output.with_suffix('.zip')
    with archive.open('xb') as stream:
        subprocess.run(['gh', 'api', endpoint + '/zip'], stdout=stream, check=True, timeout=180)
    facts = c.digest(archive)
    c.require(facts == dict(bytes=info['size_in_bytes'], sha256=expected), 'Original GitHub artifact bytes differ')
    extract_artifact(archive, output, maximum, [c.PACKAGE_NAME, 'release-ready.json'] if key == 'store' else None)
    # Only this freshly downloaded, digest-verified transport copy is discarded.
    archive.unlink()
    return dict(metadata=info, downloaded=facts)


def extract_framework(archive, output, archive_sha512, original_sha256):
    c.no_links(output); c.require(not os.path.lexists(output), 'Existing framework preserved')
    h = hashlib.sha512()
    with archive.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''): h.update(block)
    c.require(base64.b64encode(h.digest()).decode() == archive_sha512, 'Original Runtime NuGet bytes differ')
    with zipfile.ZipFile(archive) as incoming:
        entries = [e for e in incoming.infolist() if e.filename.lower().endswith('.msix')]
        c.require(0 < len(entries) <= 32 and sum(e.file_size for e in entries) <= 800000000, 'Runtime MSIX inventory exceeds bound')
        matches = []
        for entry in entries:
            c.relative_path(entry.filename)
            c.require(not stat.S_ISLNK(entry.external_attr >> 16) and not entry.flag_bits & 1 and entry.file_size <= 256000000,
                      'Unsafe Runtime MSIX member')
            sha = hashlib.sha256()
            with incoming.open(entry) as stream:
                for block in iter(lambda: stream.read(1048576), b''): sha.update(block)
            if sha.hexdigest() == original_sha256:
                matches.append(entry)
        c.require(len(matches) == 1, 'Original qualified framework member missing or ambiguous')
        selected = matches[0]
        with incoming.open(selected) as stream, output.open('xb') as destination:
            shutil.copyfileobj(stream, destination, 1048576)
    facts = c.digest(output)
    c.require(facts['sha256'] == original_sha256, 'Extracted original framework changed')
    return dict(member=selected.filename, package= facts, original_archive_sha512=archive_sha512)


def prepare_framework(output, source, verified):
    lock = c.read_json(source / 'src/Files.App/packages.lock.json')
    candidates = [v['Microsoft.WindowsAppSDK.Runtime'] for v in lock['dependencies'].values() if 'Microsoft.WindowsAppSDK.Runtime' in v]
    c.require(candidates and all(v == candidates[0] for v in candidates) and candidates[0]['resolved'] == '2.4.0',
              'Qualified Runtime NuGet source lock differs')
    row = candidates[0]; url = 'https://api.nuget.org/v3-flatcontainer/microsoft.windowsappsdk.runtime/2.4.0/microsoft.windowsappsdk.runtime.2.4.0.nupkg'
    # NuGet's signed-package contentHash excludes signing data. The reviewed
    # signed ZIP has a separate exact byte/hash pin bound to that content hash.
    pin = c.read_json(RUNTIME_ARCHIVE)
    c.require(pin.get('schema_version') == 1 and pin.get('package_id') == 'Microsoft.WindowsAppSDK.Runtime' and
              pin.get('version') == row['resolved'] and pin.get('url') == url and
              pin.get('nuget_content_hash') == row['contentHash'], 'Reviewed Runtime archive differs from qualified source lock')
    archive = output / 'windows-app-runtime.nupkg'
    with urllib.request.urlopen(url, timeout=60) as response, archive.open('xb') as stream:
        target = urllib.parse.urlsplit(response.url)
        c.require(target.scheme == 'https' and target.hostname in ('api.nuget.org', 'globalcdn.nuget.org'), 'Unexpected public NuGet redirect')
        count = 0
        while block := response.read(1048576):
            count += len(block); c.require(count <= 400000000, 'Runtime NuGet download exceeds bound'); stream.write(block)
    c.require(c.digest(archive) == pin['archive'], 'Reviewed signed Runtime archive bytes differ')
    folder = output / 'framework'; folder.mkdir()
    result = extract_framework(archive, folder / 'Microsoft.WindowsAppRuntime.2.msix', pin['archive_sha512'],
                               verified['framework']['artifact_sha256'].lower())
    result.update(url=url, archive=c.digest(archive), qualified_nuget_content_hash=row['contentHash'])
    c.require(result['archive'] == pin['archive'], 'Reviewed Runtime archive changed during extraction')
    spec = importlib.util.spec_from_file_location('capture_original_payload', source / 'distribution/verify-package-payload.py')
    api = importlib.util.module_from_spec(spec); spec.loader.exec_module(api)
    matching = api.match_framework_archives(api.archive_manifest(output/'store'/c.PACKAGE_NAME), folder)
    c.require(matching['supplied_archive_count'] == 1 and len(matching['frameworks']) == 1 and
              matching['frameworks'][0]['identity'] == verified['framework']['artifact_identity'] and
              matching['frameworks'][0]['requirement'] == verified['framework']['requirement'], 'Original framework identity differs')
    archive.unlink()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True); parser.add_argument('--qualified-source', type=Path, required=True)
    args = parser.parse_args(); bound = c.binding()
    c.require(os.name == 'nt' and os.environ.get('CI') == 'true' and os.environ.get('GITHUB_REPOSITORY') == c.REPOSITORY,
              'Capture inputs require isolated FolderSail Windows CI')
    c.assert_checkout(c.ROOT, os.environ.get('GITHUB_SHA')); c.assert_checkout(args.qualified_source, bound['source_commit'])
    c.no_links(args.output); args.output.mkdir(); (args.output/'metadata').mkdir()
    run = gh_json(f"repos/{c.REPOSITORY}/actions/runs/{bound['workflow_run_id']}"); c.validate_run(run, bound)
    artifacts = {}
    for key in c.ARTIFACT_NAMES:
        output = args.output / 'store' if key == 'store' else args.output / 'metadata' / key
        artifacts[key] = artifact(key, output, bound)
    c.write_json(args.output/'qualified-run.json', run)
    verified = c.verify_inputs(args.output, args.qualified_source, bound, run)
    framework = prepare_framework(args.output, args.qualified_source, verified)
    c.write_json(args.output/'verified-inputs.json', verified)
    c.write_json(args.output/'capture-inputs.json', dict(schema_version=1, purpose='marketing capture only', consumer_acceptance=False,
                 capture_source_commit=os.environ['GITHUB_SHA'], capture_run_id=os.environ['GITHUB_RUN_ID'],
                 capture_run_attempt=os.environ['GITHUB_RUN_ATTEMPT'], qualified=bound, artifacts=artifacts, framework=framework))


if __name__ == '__main__': main()
