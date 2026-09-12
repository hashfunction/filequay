# Copyright 2026 Trieflow LLC. MIT.
"""Verify exact versioned runtime notices and the files retained with the package."""
import argparse
import json
from pathlib import Path
from store_evidence import require, file_record, load, digest, normalized

from release_terms import verify_original_eula, TERMS_SOURCE, TERMS_PACKAGED

TARGET='.NETCoreApp,Version=v10.0/win-x64'
FOLDER='distribution/corresponding-source'
PACKAGED='Licenses/CorrespondingSource'
RECORDS=('README.md','runtime-notices.json','source-release-assets.json','source-derivation.json','native-source-publication.json','prepare_source.py')


def package_files(source):
    folder=Path(source)/FOLDER
    paths=[folder/name for name in RECORDS]+sorted((folder/'notices').rglob('*'))
    for name in RECORDS:file_record(folder/name)
    result = {PACKAGED+'/'+path.relative_to(folder).as_posix():path.read_bytes()
            for path in paths if path.is_file() and file_record(path)}
    result[TERMS_PACKAGED]=(Path(source)/TERMS_SOURCE).read_bytes()
    return result


def verify_notice_sources(source):
    folder=Path(source)/FOLDER; lock=load(folder/'runtime-notices.json'); seen={}
    require(lock['schema_version']==1 and lock['product']=='FolderSail','Unexpected notice inventory')
    for row in list(lock['packages'].values())+list(lock['additional_native_components'].values()):
        require(row['notices'],'Runtime dependency has no original notice')
        for notice in row['notices']:
            name=normalized(notice['path']); require(name.startswith('notices/'),'Notice is outside source notices')
            facts={k:notice[k] for k in ('bytes','sha256')}
            require(file_record(folder/name)==facts,'Original notice bytes changed: '+name)
            require(name not in seen or seen[name]==facts,'Conflicting notice inventory')
            seen[name]=facts
    return dict(runtime_packages=len(lock['packages']),notice_files=len(seen))


def verify_dependency_notices(deps,lock):
    require(deps['runtimeTarget']['name']==TARGET,'Unexpected runtime target for notices')
    found={}
    for key,row in deps['targets'][TARGET].items():
        assets={kind:sorted(row[kind]) for kind in ('runtime','native') if row.get(kind)}
        if not assets or deps['libraries'].get(key,{}).get('type')=='project':continue
        name,version=key.rsplit('/',1); name=name.removeprefix('runtimepack.')
        require(name not in found and name in lock['packages'],'Unaudited runtime dependency: '+key)
        expected=lock['packages'][name]
        require(version==expected['version'] and assets=={k:sorted(v) for k,v in expected['assets'].items()},
                'Runtime source/notice version or assets changed: '+key)
        found[name]=version
    require(set(found)==set(lock['packages']),'Runtime notice package set differs')
    return len(found)


def verify_packaged_notices(source,read):
    result=verify_notice_sources(source); files=package_files(source)
    require(len(files)>result['notice_files'],'Missing packaged source records')
    for name,data in files.items():
        require(read(name)==data,'Packaged original notice/source record changed: '+name)
    return dict(**result,packaged_notice_files=len(files),win2d_original_terms=verify_original_eula(source,read))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path);parser.add_argument('--package-root',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path);args=parser.parse_args()
    result=verify_packaged_notices(args.source,lambda name:(args.package_root/name).read_bytes())
    result['verified_runtime_packages']=verify_dependency_notices(load(args.package_root/'FolderSail.deps.json'),load(args.source/FOLDER/'runtime-notices.json'))
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
