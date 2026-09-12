# Copyright (c) Trieflow LLC. Licensed under the MIT License.
"""Require the audited release Windows projection in source and actual package metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

VERSION = '10.0.26100.70'
PACKAGE_PREFIX = 'runtimepack.Microsoft.Windows.SDK.NET.Ref/'
TARGET = '.NETCoreApp,Version=v10.0/win-x64'
ARCHIVE_SHA256 = 'e15559b82ccbcda51c897be9da3aa190887dba3ecb0d1bd9525130aaa9132f0d'
ARCHIVE_BYTES = 10639646
RUNTIME = {
    'Microsoft.Windows.SDK.NET.dll': {'assemblyVersion': '10.0.26100.69', 'fileVersion': '10.0.26100.69'},
    'WinRT.Runtime.dll': {'assemblyVersion': '2.2.0.0', 'fileVersion': '2.2.0.48161'},
}


class WindowsSdkError(ValueError):
    pass


def verify_source_pin(props):
    try:
        root = ET.fromstring(props)
    except ET.ParseError as error:
        raise WindowsSdkError('Invalid SDK property XML.') from error
    nodes = list(root.iter('WindowsSdkPackageVersion'))
    parents = {child: parent for parent in root.iter() for child in parent}
    if len(nodes) != 1 or nodes[0].text != VERSION:
        raise WindowsSdkError('Windows SDK must use the audited stable pin ' + VERSION + '; preview or unaudited pins cannot be exported.')
    node = nodes[0]
    while node is not None:
        if 'Condition' in node.attrib:
            raise WindowsSdkError('Windows SDK pin must be unconditional.')
        node = parents.get(node)
    return VERSION


def verify_package_sdk(props, deps):
    verify_source_pin(props)
    key = PACKAGE_PREFIX + VERSION
    libraries = deps.get('libraries', {})
    selected = [name for name in libraries if name.casefold().startswith(PACKAGE_PREFIX.casefold())]
    if selected != [key] or libraries[key].get('type') != 'runtimepack':
        raise WindowsSdkError('Packaged SDK runtime pack differs from the audited stable source pin.')
    if deps.get('runtimeTarget', {}).get('name') != TARGET:
        raise WindowsSdkError('Packaged SDK runtime target differs from the qualified Windows x64 target.')
    target = deps.get('targets', {}).get(TARGET, {})
    if [name for name in target if name.casefold().startswith(PACKAGE_PREFIX.casefold())] != [key]:
        raise WindowsSdkError('Packaged SDK runtime target has missing or conflicting projection records.')
    if target[key].get('runtime') != RUNTIME:
        raise WindowsSdkError('Packaged SDK projection or WinRT assembly metadata differs from the audited release.')
    return {'version': VERSION, 'runtime_target': TARGET, 'runtime': RUNTIME}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--props', type=Path, required=True)
    parser.add_argument('--deps', type=Path, required=True)
    parser.add_argument('--package-cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify_package_sdk(args.props.read_bytes(), json.loads(args.deps.read_text(encoding='utf-8-sig')))
    name = 'microsoft.windows.sdk.net.ref'
    archive = args.package_cache / name / VERSION / (name + '.' + VERSION + '.nupkg')
    if archive.stat().st_size != ARCHIVE_BYTES or hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise WindowsSdkError('Resolved Windows SDK NuGet archive differs from the audited original.')
    result['archive'] = {'bytes': ARCHIVE_BYTES, 'sha256': ARCHIVE_SHA256}
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
