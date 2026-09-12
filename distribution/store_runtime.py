# Copyright 2026 Trieflow LLC. MIT.
"""Bind original native/runtime qualification records to current payload bytes."""
from pathlib import Path
from store_evidence import require, load, file_record, normalized
import windows_sdk_policy as sdk
from source_notices import verify_dependency_notices

MICROSOFT='CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
# Exact observed original native inputs; managed ReadyToRun outputs are bound to
# each new build inventory, never assumed byte-identical to their NuGet originals.
NATIVE={
    '7z64.dll':dict(bytes=1908736,sha256='bbd705e3b58ca7677c1e9e67473f166a6712da034dcb567d571fbb67507a443f'),
    'git2-a418d9d.dll':dict(bytes=1745408,sha256='39df774f9600e929b2ffa314372f54b9afac32cbf362a90f9a350faccc2d8a5f'),
    'microsoft.graphics.canvas.dll':dict(bytes=1729568,sha256='813c714a54df82227fb02fa295dea8379061c3c408b57bff18532f7953118dbf'),
}


def verify_native_evidence(source,folder,files,validation,installed):
    source=Path(source);folder=Path(folder)
    for name,facts in NATIVE.items():require(files.get(name)==facts,'Original native/source binding changed: '+name)
    deps_path=folder/'package-runtime-metadata/FolderSail.deps.json'
    require(file_record(deps_path)==files['foldersail.deps.json'],'Retained runtime graph differs from packaged bytes')
    deps=load(deps_path);expected_sdk=sdk.verify_package_sdk((source/'Directory.Build.props').read_bytes(),deps)
    require(load(folder/'windows-sdk-package.json')==dict(expected_sdk,archive=dict(bytes=sdk.ARCHIVE_BYTES,sha256=sdk.ARCHIVE_SHA256)),
            'Actual restored stable SDK archive/projection evidence differs')
    count=verify_dependency_notices(deps,load(source/'distribution/corresponding-source/runtime-notices.json'))
    require(load(folder/'source-notices.json').get('verified_runtime_packages')==count,'Current package notice verification missing')
    runtime=validation.get('runtime_binaries',[])
    paths={prefix+name for prefix in ('','files.app.server/') for name in ('coreclr.dll','clrjit.dll','hostfxr.dll','hostpolicy.dll')}
    require(len(runtime)==len(paths) and {normalized(row['path']).casefold() for row in runtime}==paths,'Missing native runtime-pack byte checks')
    for row in runtime:
        name=normalized(row['path']).casefold()
        require(row.get('runtime_pack')=='Microsoft.NETCore.App.Runtime.win-x64' and row.get('runtime_pack_version')=='10.0.12'
                and row['sha256'].lower()==row['runtime_pack_sha256'].lower()==files[name]['sha256'],'Runtime differs from audited runtime-pack bytes')
    payload=validation['payload_inspection']
    require(payload.get('runtime_version')=='10.0.12' and payload.get('architecture')=='x64','Wrong runtime architecture/version')
    requirement=dict(Name='Microsoft.WindowsAppRuntime.2',Publisher=MICROSOFT,MinVersion='2.4.0.0')
    require(payload.get('declared_msix_dependencies')==[requirement],'Unexpected framework dependency')
    framework=payload.get('framework_artifact_validation',{})
    require(framework.get('manifest_to_artifact_matching_passed') is True and len(framework.get('frameworks',[]))==1
            and len(installed.get('frameworks',[]))==1,'Missing framework artifact/registration evidence')
    original=framework['frameworks'][0];actual=installed['frameworks'][0]
    ident=dict(Name=requirement['Name'],Publisher=MICROSOFT,Version='2.4.0.0',ProcessorArchitecture='x64')
    full_name='Microsoft.WindowsAppRuntime.2_2.4.0.0_x64__8wekyb3d8bbwe'
    require(original['requirement']==actual['requirement']==requirement and original['identity']==actual['artifact_identity']==ident
            and original['sha256'].lower()==actual['artifact_sha256'].lower() and actual.get('compatible_preexisting_full_names')==[]
            and actual.get('artifact_registered') is True and actual.get('resolved_full_names')==[full_name]
            and actual.get('newly_registered_full_names')==[full_name],'Framework was not installed from the exact fresh owned dependency')
    lock=load(source/'distribution/sqlite-dependencies.lock.json');sqlite=load(folder/'sqlite-package-assets.json')
    require(sqlite.get('passed') is True and sqlite.get('packagedFilesVerified') is True,'SQLite packaged-byte verification missing')
    expected=[]
    for name,item in lock['packages'].items():
        expected.append(dict(package=name+'/'+item['version'],**{k:item[k] for k in ('asset','archiveSha256','assetSha256','packagedName')}))
        require(files[item['packagedName'].casefold()]['sha256']==item['assetSha256'],'SQLite packaged bytes changed')
    require(sqlite.get('packages')==expected,'SQLite original NuGet/native source binding differs')
    execution=load(folder.parent/'sqlite-execution.json')
    require(execution.get('version')==lock['nativeVersion'] and execution.get('sourceId')==lock['nativeSourceId']
            and execution.get('sdkRuntime')=='.NET 10.0.12' and execution.get('architecture')=='X64'
            and execution.get('nativeSha256')==lock['packages']['SQLite']['assetSha256'],'Actual executed SQLite bytes/source differ')
    require({'exact executed native bytes','managed callback provider ABI','read-only reopen','copied WAL integrity','malformed database handled as SQLite error'}
            <=set(execution.get('results',[])),'Actual SQLite production-query/ABI tests missing')
    return dict(runtime_packages=count,stable_windows_sdk=expected_sdk,native_source_bytes=NATIVE,
                sqlite_source_id=lock['nativeSourceId'],framework=ident)
