# Copyright 2026 Trieflow LLC. MIT.
"""Recheck existing FolderSail qualification evidence without replacing its UI tests."""
import csv
from datetime import datetime
import base64
import hashlib
import io
import json
from pathlib import Path, PureWindowsPath
import re
import stat
import xml.etree.ElementTree as ET
import zipfile

NS = '{http://schemas.microsoft.com/appx/manifest/foundation/windows10}'
CONTEXT = ('source_commit', 'workflow_run_id', 'workflow_run_attempt')
FIXTURE_TEXT = 'FolderSail owned Unicode fixture. Keep the original.\r\nOriginal: 原稿 / résumé.\r\n'


def require(value, message):
    if not value:
        raise ValueError(message)


def regular(path):
    path = Path(path).absolute()
    for item in (path, *path.parents):
        info = item.lstat()
        require(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400,
                'Linked/reparse release input: ' + str(item))
    require(path.is_file(), 'Expected regular release input')
    return path


def digest(data):
    return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())


def file_record(path):
    path = regular(path)
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return dict(bytes=path.stat().st_size, sha256=h.hexdigest())


def load(path):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            require(key not in value, 'Duplicate evidence JSON key')
            value[key] = item
        return value
    raw = regular(path).read_bytes()
    require(len(raw) <= 16 * 1024 * 1024, 'Oversized release evidence')
    return json.loads(raw.decode('utf-8-sig'), object_pairs_hook=unique)


def identity(mode):
    require(mode in ('Qualification', 'Store'), 'Unknown identity mode')
    store = mode == 'Store'
    return dict(name='1659hashfunction.FileQuay' if store else 'Trieflow.FileQuay.Qualification',
                publisher='CN=B6A2631A-FD32-45CC-AE12-82466975F528' if store else 'CN=FileQuay-CI-Qualification',
                publisher_display_name='hashfunction' if store else 'Trieflow LLC',
                family='1659hashfunction.FileQuay_r3hxytd7jt6c4' if store else 'Trieflow.FileQuay.Qualification_2b9rgm65gdcnr',
                version='1.0.1.0', application_id='App')


def normalized(value):
    value = value.replace('\\', '/')
    require(value and all(p not in ('', '.', '..') and ':' not in p and p.rstrip(' .') == p for p in value.split('/')),
            'Unsafe package/evidence member')
    return value


def inventory(rows):
    result = {}
    for row in rows:
        name = normalized(row['path']).casefold()
        require(name not in result and type(row['bytes']) is int and row['bytes'] >= 0
                and re.fullmatch('[0-9a-fA-F]{64}', row['sha256']), 'Ambiguous or invalid payload inventory')
        result[name] = dict(bytes=row['bytes'], sha256=row['sha256'].lower())
    require(bool(result), 'Empty payload inventory')
    return result


def verify_archive(package, files, mode):
    expected = identity(mode); seen = {}; manifest = None
    with zipfile.ZipFile(regular(package)) as archive:
        for entry in archive.infolist():
            name = normalized(entry.filename).casefold()
            require(name not in seen and not entry.is_dir() and not entry.flag_bits & 1
                    and stat.S_IFMT(entry.external_attr >> 16) != stat.S_IFLNK,
                    'Ambiguous, linked or encrypted package member')
            require(entry.file_size <= 256 * 1024 * 1024, 'Oversized package member')
            require(name != 'appxsignature.p7x', 'Only the original unsigned Store package can be retained')
            # MakeAppx unpack omits the OPC content-types member. Every application
            # and other container member must match the actual SDK unpack inventory.
            data = archive.read(entry)
            seen[name] = digest(data)
            if name == 'appxmanifest.xml':
                require(b'<!DOCTYPE' not in data.upper() and b'<!ENTITY' not in data.upper(), 'Unsafe package XML')
                manifest = ET.fromstring(data)
        require(set(seen) == set(files) | {'[content_types].xml'}, 'Archive and semantic unpack inventory differ')
        require(all(seen[name] == facts for name, facts in files.items()), 'Package bytes changed after semantic validation')
    require(manifest is not None, 'Missing package manifest')
    node = manifest.find(NS + 'Identity')
    require(node is not None and all(node.get(key) == value for key, value in
            dict(Name=expected['name'], Publisher=expected['publisher'], Version=expected['version'], ProcessorArchitecture='x64').items()),
            'Wrong Store package identity')
    apps = manifest.findall(NS + 'Applications/' + NS + 'Application')
    require(len(apps) == 1 and apps[0].get('Id') == 'App' and apps[0].get('Executable') == 'FolderSail.exe', 'Changed compatible application entry point')
    require(manifest.findtext(NS + 'Properties/' + NS + 'DisplayName') == 'FolderSail'
            and manifest.findtext(NS + 'Properties/' + NS + 'PublisherDisplayName') == expected['publisher_display_name'], 'Wrong package branding')
    return file_record(package)


def timestamp(value):
    # DateTimeOffset's round-trip serializer uses up to seven fractional digits.
    # Preserve the final 100 ns digit instead of truncating it to Python usec.
    match = re.fullmatch(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,7}))?(Z|\+00:00)', value or '')
    require(match is not None, 'Receipt/CSV timestamp is not UTC round-trip text')
    datetime.fromisoformat(match[1] + '+00:00')
    return match[1], (match[2] or '').ljust(7, '0')


def verify_consumer(record):
    w = record['consumer_workflow']
    require(w.get('schema_version') == 1 and w.get('passed') is True and w.get('cleanup_verified') is True
            and w.get('cancelled_export_preserved_previous_bytes') is True and not w.get('error'), 'Incomplete real consumer workflow')
    trees = {key: inventory([dict(path=p, **v) for p, v in w[key].items()])
             for key in ('initial_files', 'copy_files', 'move_files', 'final_files')}
    original = digest(FIXTURE_TEXT.encode('utf-8'))
    source = 'source/résumé,原稿.txt'; copied = 'copy/résumé,原稿.txt'; moved = 'move/résumé,原稿.txt'
    initial = trees['initial_files']
    require(initial[source] == original and len(initial) == 5, 'Original Unicode fixture changed')
    require(trees['copy_files'] == {**initial, copied: original}
            and trees['move_files'] == {**initial, moved: original}, 'Copy/move bytes or protected sentinels differ')
    final = dict(trees['move_files'])
    recovery = PureWindowsPath(w['csv_recovery']['path'])
    fixture_root = PureWindowsPath(w['fixture_root'])
    require(recovery.parent == fixture_root / 'export' and re.fullmatch('receipts.csv\\.[0-9a-f]{32}\\.filequay-original', recovery.name), 'Foreign CSV recovery path')
    require(w['csv_recovery']['file'] == w['initial_files']['export\\receipts.csv'], 'Original CSV recovery bytes differ')
    csv_bytes = base64.b64decode(w['csv_bytes_base64'], validate=True)
    require(digest(csv_bytes) == dict(bytes=w['csv']['bytes'], sha256=w['csv']['sha256'].lower()), 'Saved CSV content differs from verified bytes')
    final['export/receipts.csv'] = digest(csv_bytes)
    final['export/' + recovery.name] = initial['export/receipts.csv']
    require(trees['final_files'] == final, 'Final original/source/recovery bytes differ')
    receipts = w['receipts']; visible = w['visible_receipts']
    require(len(receipts) == len(visible) == 2 and {r['fileOperationType'] for r in receipts} == {3, 4}
            and len({r['id'] for r in receipts}) == 2, 'Copy/move receipts are not unique')
    for receipt in receipts:
        old, new, label = (source, copied, 'Copy') if receipt['fileOperationType'] == 3 else (copied, moved, 'Move')
        require(receipt['returnResult'] == 1 and receipt['failureCode'] is None
                and receipt['sourcePaths'] == [str(fixture_root / old)] and receipt['destinationPaths'] == [str(fixture_root / new)],
                'Persisted receipt results/paths differ')
        require(dict(id=receipt['id'], title=label + ' · Completed', source=receipt['sourcePaths'][0], destination=receipt['destinationPaths'][0]) in visible,
                'Actual visible receipt differs')
    reader = csv.DictReader(io.StringIO(csv_bytes.decode('utf-8-sig'), newline=''), strict=True)
    require(reader.fieldnames == ['Id','StartedAtUtc','CompletedAtUtc','Operation','Result','ItemCount','TotalBytes','SourcePaths','DestinationPaths','FailureCode'], 'CSV header differs')
    csv_rows = list(reader)
    require(all(len(row) == 10 and all(isinstance(v, str) for v in row.values()) for row in csv_rows), 'CSV row width differs')
    require(len(csv_rows) == 2 and len({row['Id'] for row in csv_rows}) == 2, 'CSV row count/identity differs')
    for row in csv_rows:
        matches = [r for r in receipts if r['id'] == row['Id']]
        require(len(matches) == 1, 'CSV receipt is foreign')
        r = matches[0]
        require(timestamp(row['StartedAtUtc']) == timestamp(r['startedAtUtc'])
                and timestamp(row['CompletedAtUtc']) == timestamp(r['completedAtUtc']), 'CSV timestamp differs')
        require(row['Operation'] == ('Copy' if r['fileOperationType'] == 3 else 'Move') and row['Result'] == 'Success'
                and row['ItemCount'] == str(r['itemCount']) and row['TotalBytes'] == str(r['totalBytes'])
                and row['SourcePaths'] == r['sourcePaths'][0] and row['DestinationPaths'] == r['destinationPaths'][0]
                and row['FailureCode'] == '', 'CSV rows differ from persisted receipts')
    require(w['cleared_history']['schemaVersion'] == 1 and w['cleared_history']['receipts'] == [], 'Persisted receipt metadata was not cleared')


def verify_installation(folder, context, mode, kind):
    folder = Path(folder); expected = identity(mode)
    build = load(folder / 'build-result.json'); install = load(folder / 'installation-result.json')
    validation = load(folder / (folder.name + '.validation.json'))
    files = inventory(load(folder / (folder.name + '.files.json')))
    managed = load(folder / 'managed-build-kind.json')
    for record in (build, install):
        require(all(record.get(key) == context[key] for key in CONTEXT), 'Stale source/run/attempt evidence')
        require(record.get('identity_mode') == mode and record.get('identity') == expected['name']
                and record.get('publisher') == expected['publisher'] and record.get('requested_build_kind') == kind
                and record.get('actual_build_kind') == kind and record.get('dependency_mode') == 'RequireClean', 'Wrong identity/build/dependency mode')
    for field in ('native_build', 'installation_qualification_passed', 'managed_build_kind_verified', 'clean_framework_installation_gate_passed'):
        require(build.get(field) is True, 'Native build gate failed: ' + field)
    for field in ('installed', 'main_window_verified', 'managed_build_kind_verified', 'dependency_artifacts_verified', 'framework_registration_verified',
                  'registration_ownership_established', 'add_appx_completed', 'uninstall_verified', 'trust_removed', 'installation_qualification_passed',
                  'unsigned_package_unchanged', 'dependency_installation_from_artifacts_verified'):
        require(install.get(field) is True, 'Installed gate failed: ' + field)
    require(all(install.get(key) == [] for key in ('cleanup_errors', 'evidence_errors', 'reporting_errors', 'preflight_package_full_names', 'residual_package_full_names'))
            and not install.get('error'), 'Incomplete ownership, cleanup or reporting')
    full_name = expected['name'] + '_' + expected['version'] + '_x64__' + expected['family'].rsplit('_', 1)[1]
    require(install.get('owned_package_full_name') == install.get('installed_package_full_name') == full_name
            and install.get('aumid') == expected['family'] + '!App', 'Installed package ownership differs')
    hashes = [build.get('package_sha256'), validation.get('package_sha256'), install.get('unsigned_package_sha256'), install.get('unsigned_package_final_sha256')]
    require(all(isinstance(v, str) and re.fullmatch('[0-9a-fA-F]{64}', v) for v in hashes) and len({v.lower() for v in hashes}) == 1, 'Unsigned qualified package hashes differ')
    require(validation.get('semantic_unpack_passed') is True and validation.get('identity_mode') == mode
            and validation.get('identity') == expected['name'] and validation.get('publisher') == expected['publisher']
            and validation.get('payload_inspection', {}).get('payload_inspection_passed') is True, 'Native semantic/payload validation missing')
    require(managed.get('actual_build_kind') == kind and managed.get('expected_build_kind') == kind
            and managed.get('ci_probe_type_present') is (kind == 'Instrumented') and install.get('ci_probe_type_present') is (kind == 'Instrumented'), 'Wrong compiled probe kind')
    dll_hash = files['foldersail.dll']['sha256']
    require(all(isinstance(v, str) and v.lower() == dll_hash for v in
                (managed.get('assembly_sha256'), install.get('packaged_managed_assembly_sha256'), install.get('installed_managed_assembly_sha256'))), 'Installed managed assembly changed')
    root = PureWindowsPath(install['installed_location'])
    require(root.is_absolute() and root.name == full_name and root.parent.name.casefold() == 'windowsapps', 'Foreign installed location')
    modules = load(folder / 'installed-modules.json'); seen = set()
    require(len(modules) == install.get('packaged_module_count') and len(modules) > 0, 'Missing installed module evidence')
    for row in modules:
        path = PureWindowsPath(row['path'])
        require(path.is_relative_to(root) and '..' not in path.parts and path not in seen, 'Foreign or duplicate installed module')
        seen.add(path); name = path.relative_to(root).as_posix().casefold()
        require(name in files and row['sha256'].lower() == files[name]['sha256'], 'Loaded module differs from package')
    require(root / 'FolderSail.exe' in seen and root / 'coreclr.dll' in seen, 'Required actual loaded runtime missing')
    require(install['executable_sha256'].lower() == files['foldersail.exe']['sha256']
            and install['packaged_coreclr_sha256'].lower() == files['coreclr.dll']['sha256'], 'Loaded executable/runtime hash differs')
    if kind == 'Consumer':
        for key in ('broker_process_identity_verified', 'ui_tree_captured', 'screenshot_captured', 'window_close_requested', 'window_disappeared',
                    'consumer_process_outcome_accepted', 'owned_process_cleanup_verified', 'consumer_workflow_verified',
                    'consumer_fixture_cleanup_verified', 'consumer_native_adapter_verified', 'consumer_uia_proxy_verified'):
            require(install.get(key) is True, 'Consumer gate failed: ' + key)
        require(install.get('consumer_com_probe_invoked') is False and install.get('consumer_activation_arguments') == ''
                and install.get('activated_package_full_name') == full_name, 'Consumer was not normal owned activation')
        require(install.get('normal_process_exit_verified') is True or install.get('consumer_background_process_observed') is True, 'Consumer close outcome missing')
        verify_consumer(install)
        regular(folder / 'main-window.png'); regular(folder / 'ui-automation-tree.json')
    else:
        require(mode == 'Qualification' and install.get('com_activation_verified') is True
                and install.get('server_natural_exit_verified') is True, 'Independent Instrumented COM lifecycle missing')
        for key in ('client_exit', 'server_exit'):
            require(install.get(key, {}).get('normal_exit') is True and install[key].get('exit_code') == 0, 'Instrumented process exit failed')
    return dict(files=files, build=build, install=install, validation=validation)
