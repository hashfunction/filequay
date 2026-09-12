"""Bind marketing to one existing qualified Store export; an unbound draft refuses."""
# Copyright 2026 Trieflow LLC. MIT.
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys

from capture_files import no_links, require

ROOT = Path(__file__).resolve().parents[2]
BINDING = Path(__file__).with_name('binding.json')
REPOSITORY = 'hashfunction/filequay'
PACKAGE_NAME = 'FolderSail_1.0.1.0_x64.msix'
ARTIFACT_NAMES = dict(store='FolderSail-Store-unsigned', Consumer='FolderSail-Windows-Consumer-qualification',
                      Instrumented='FolderSail-Windows-Instrumented-qualification', Store='FolderSail-Windows-Store-qualification')
IDENTITY = dict(name='1659hashfunction.FileQuay', publisher='CN=B6A2631A-FD32-45CC-AE12-82466975F528',
                publisher_display_name='hashfunction', family='1659hashfunction.FileQuay_r3hxytd7jt6c4',
                version='1.0.1.0', application_id='App')
HELPERS = ['.github/scripts/'+name for name in (
    'InstallationQualification.Helpers.ps1', 'PackageIdentity.Helpers.ps1', 'ConsumerWorkflow.Helpers.ps1',
    'ConsumerWorkflow.Ui.ps1', 'ConsumerWorkflow.Native.cs', 'ConsumerWorkflow.Adapter.ps1',
    'ConsumerWorkflow.PickerDiagnostic.ps1', 'UiaProxy.Helpers.ps1', 'UiaProxy.Fixture.ps1',
    'UiaProxy.Register.cs', 'Invoke-UiaProxyFixtureChild.ps1')]


def relative_path(name):
    require(isinstance(name, str) and name and '\\' not in name and ':' not in name and not name.startswith('/') and
            all(p not in ('', '.', '..') and p.rstrip(' .') == p and
                not re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', p, re.I) for p in name.split('/')) and
            str(PurePosixPath(name)) == name, 'Unsafe artifact/evidence path')
    return name


def digest(path):
    path = Path(path); no_links(path); info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_size <= 800000000, 'Invalid bounded capture input')
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            h.update(block)
    final = path.lstat()
    require((info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns) ==
            (final.st_dev, final.st_ino, final.st_size, final.st_mtime_ns), 'Capture input changed while hashing')
    return dict(bytes=info.st_size, sha256=h.hexdigest())


def read_json(path):
    require(digest(path)['bytes'] <= 16000000, 'Oversized capture JSON')
    def unique(pairs):
        value = {}
        for key, entry in pairs:
            require(key not in value, 'Duplicate JSON key'); value[key] = entry
        return value
    return json.loads(Path(path).read_text(encoding='utf-8-sig'), object_pairs_hook=unique)


def write_json(path, value):
    no_links(Path(path))
    with Path(path).open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, indent=2); stream.write('\n')


def validate_binding(value):
    require(value.get('schema_version') == 1 and value.get('product') == 'FolderSail' and
            isinstance(value.get('qualified'), dict), 'Capture needs a reviewed successful Store package binding')
    b = value['qualified']
    require(set(b) == {'source_commit', 'workflow_run_id', 'workflow_run_attempt', 'package', 'readiness_receipt', 'artifacts'},
            'Exact capture binding fields required')
    require(isinstance(b['source_commit'], str) and re.fullmatch('[0-9a-f]{40}', b['source_commit']) and
            all(isinstance(b[k], str) and re.fullmatch('[1-9][0-9]*', b[k]) for k in ('workflow_run_id', 'workflow_run_attempt')),
            'Invalid exact source/run binding')
    for key in ('package', 'readiness_receipt'):
        row = b[key]
        require(isinstance(row, dict) and set(row) == {'bytes', 'sha256'} and type(row['bytes']) is int and row['bytes'] > 0 and
                isinstance(row['sha256'], str) and re.fullmatch('[0-9a-f]{64}', row['sha256']), 'Invalid exact byte binding')
    require(isinstance(b['artifacts'], dict) and set(b['artifacts']) == set(ARTIFACT_NAMES) and
            all(type(v) is int and v > 0 for v in b['artifacts'].values()) and len(set(b['artifacts'].values())) == 4,
            'Four distinct original artifact IDs required')
    return b


def binding():
    return validate_binding(read_json(BINDING))


def git(source, *args):
    return subprocess.check_output(['git', '-C', str(source), *args], timeout=30)


def assert_checkout(source, commit):
    require(isinstance(commit, str) and re.fullmatch('[0-9a-f]{40}', commit), 'Exact source commit required')
    require(git(source, 'rev-parse', 'HEAD').decode().strip() == commit and
            not git(source, 'status', '--porcelain=v1', '--untracked-files=all'), 'Exact clean source checkout required')
    return git(source, 'show', '-s', '--format=%T', 'HEAD').decode().strip()


def validate_run(run, bound):
    require(run.get('id') == int(bound['workflow_run_id']) and run.get('head_sha') == bound['source_commit'] and
            type(run.get('run_attempt')) is int and run['run_attempt'] == int(bound['workflow_run_attempt']) and
            run.get('conclusion') == 'success' and run.get('repository', {}).get('full_name') == REPOSITORY and
            run.get('path') == '.github/workflows/windows.yml', 'Original successful Windows run differs')


def validate_artifact(info, key, bound, maximum):
    require(info.get('id') == bound['artifacts'][key] and info.get('name') == ARTIFACT_NAMES[key] and info.get('expired') is False and
            type(info.get('size_in_bytes')) is int and 0 < info['size_in_bytes'] <= maximum and
            info.get('workflow_run', {}).get('id') == int(bound['workflow_run_id']) and
            info.get('workflow_run', {}).get('head_sha') == bound['source_commit'] and
            isinstance(info.get('digest'), str) and re.fullmatch('sha256:[0-9a-f]{64}', info['digest']),
            'Original artifact identity/hash/size differs')
    return info['digest'].removeprefix('sha256:')


def qualified_api(source):
    # This is reviewed source from the exact original qualified Git commit.
    # Never load the current checkout's evolving runtime/consumer validators.
    folder = Path(source).resolve() / 'distribution'
    sys.path.insert(0, str(folder))
    modules = []
    for name in ('store_evidence', 'store_runtime', 'source_notices'):
        module = importlib.import_module(name)
        require(Path(module.__file__).resolve() == folder / (name + '.py'), 'Mixed qualified validator source')
        modules.append(module)
    return modules


def verify_inputs(inputs, source, bound, run):
    inputs = Path(inputs); source = Path(source); tree = assert_checkout(source, bound['source_commit'])
    validate_run(run, bound)
    package = inputs / 'store' / PACKAGE_NAME; receipt_path = inputs / 'store/release-ready.json'
    require(digest(package) == bound['package'] and digest(receipt_path) == bound['readiness_receipt'], 'Original package/readiness bytes differ')
    ready = read_json(receipt_path)
    require(ready.get('schema_version') == 1 and ready.get('product') == 'FolderSail' and ready.get('version') == '1.0.1.0' and
            ready.get('identity') == IDENTITY and ready.get('store_upload_ready') is True and ready.get('submitted') is False and
            ready.get('package') == dict(filename=PACKAGE_NAME, unsigned=True, **bound['package']) and ready.get('git_tree') == tree and
            all(ready.get(k) == bound[k] for k in ('source_commit', 'workflow_run_id', 'workflow_run_attempt')),
            'Original qualified Store export receipt differs')
    rows = ready.get('three_native_lifecycles')
    require(isinstance(rows, list) and len(rows) == 3 and
            [(row['identity_mode'], row['build_kind']) for row in rows] ==
            [('Qualification', 'Instrumented'), ('Qualification', 'Consumer'), ('Store', 'Consumer')], 'Original three lifecycles absent')
    evidence, runtime, notices = qualified_api(source)
    context = {k: bound[k] for k in ('source_commit', 'workflow_run_id', 'workflow_run_attempt')}
    store_result = None
    for row, key, folder_name in zip(rows, ('Instrumented', 'Consumer', 'Store'), ('Instrumented', 'Consumer', 'Store-Consumer')):
        require(row.get('installation_qualified') is True and isinstance(row.get('files'), dict) and row['files'], 'Incomplete original lifecycle')
        root = inputs / 'metadata' / key
        actual = {p.relative_to(root).as_posix(): digest(p) for p in root.rglob('*') if p.is_file()}
        require(actual == row['files'], 'Original retained lifecycle files changed: ' + key)
        result = evidence.verify_installation(root / folder_name, context, row['identity_mode'], row['build_kind'])
        require(runtime.verify_native_evidence(source, root / folder_name, result['files'], result['validation'], result['install']) == row['native'],
                'Original native runtime/source evidence differs')
        require(result['build']['package_sha256'].lower() == row['package_sha256'], 'Original lifecycle package differs')
        if key == 'Store':
            store_result = result
    require(evidence.verify_archive(package, store_result['files'], 'Store') == bound['package'], 'Original unsigned payload differs')
    import zipfile
    with zipfile.ZipFile(package) as archive:
        require(notices.verify_packaged_notices(source, archive.read) == ready['packaged_notices'], 'Original packaged notices differ')
    publication = ready['public_sources']
    require(publication['application_source']['source_commit'] == bound['source_commit'] and
            publication['application_source']['git_tree'] == tree and publication['source_page'] == 'https://foldersail.trieflow.com/source',
            'Original published source binding differs')
    expected_publication = {p.name: digest(p) for p in (source / 'distribution/corresponding-source').glob('*.json')}
    require(expected_publication and publication.get('source_publication_inputs') == expected_publication,
            'Original source publication inputs changed')
    helpers = {name: digest(source / name) for name in HELPERS}
    require(assert_checkout(source, bound['source_commit']) == tree and digest(package) == bound['package'], 'Inputs changed during verification')
    return dict(schema_version=1, purpose='marketing capture only', consumer_acceptance=False, identity=IDENTITY,
                package=bound['package'], payload=store_result['files'], framework=store_result['install']['frameworks'][0],
                qualified_helpers=helpers, qualified_source_tree=tree)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binding-output', type=Path); parser.add_argument('--inputs', type=Path)
    parser.add_argument('--qualified-source', type=Path); parser.add_argument('--verified-output', type=Path)
    args = parser.parse_args(); bound = binding()
    assert_checkout(ROOT, os.environ.get('GITHUB_SHA'))
    if args.binding_output:
        with args.binding_output.open('a', encoding='utf-8') as stream:
            stream.write('qualified_source=' + bound['source_commit'] + '\n')
    else:
        require(args.inputs and args.qualified_source, 'Exact prepared inputs and original qualified source required')
        result = verify_inputs(args.inputs, args.qualified_source, bound, read_json(args.inputs / 'qualified-run.json'))
        if args.verified_output:
            write_json(args.verified_output, result)
        else:
            require(read_json(args.inputs / 'verified-inputs.json') == result, 'Prepared verification metadata changed')
        print('Verified original unsigned Store export and three original native lifecycles; marketing only.')


if __name__ == '__main__':
    main()
