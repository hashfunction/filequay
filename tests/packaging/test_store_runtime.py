# Copyright 2026 Trieflow LLC. MIT.
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'distribution'))
import store_runtime as r
import windows_sdk_policy as sdk
import source_notices as notices
from store_evidence import digest

def fixture(folder):
    lock=json.loads((ROOT/'distribution/corresponding-source/runtime-notices.json').read_text())
    target={}; libraries={}
    for name,row in lock['packages'].items():
        prefix='runtimepack.' if name in ('Microsoft.NETCore.App.Runtime.win-x64','Microsoft.WindowsDesktop.App.Runtime.win-x64','Microsoft.Windows.SDK.NET.Ref') else ''
        key=prefix+name+'/'+row['version'];target[key]={k:{p:{} for p in v} for k,v in row['assets'].items()};libraries[key]={'type':'runtimepack' if prefix else 'package'}
    target[sdk.PACKAGE_PREFIX+sdk.VERSION]['runtime']=sdk.RUNTIME
    deps={'runtimeTarget':{'name':sdk.TARGET},'targets':{sdk.TARGET:target},'libraries':libraries}
    (folder/'package-runtime-metadata').mkdir();data=json.dumps(deps).encode();(folder/'package-runtime-metadata/FolderSail.deps.json').write_bytes(data)
    files={'foldersail.deps.json':digest(data)}
    for key,row in r.NATIVE.items():files[key]=copy.deepcopy(row)
    runtime=[]
    for prefix in ('','Files.App.Server/'):
        for name in ('coreclr.dll','clrjit.dll','hostfxr.dll','hostpolicy.dll'):
            path=prefix+name;files[path.casefold()]=digest(path.encode());runtime.append(dict(path=path,sha256=files[path.casefold()]['sha256'],runtime_pack_sha256=files[path.casefold()]['sha256'],runtime_pack='Microsoft.NETCore.App.Runtime.win-x64',runtime_pack_version='10.0.12'))
    q=json.loads((ROOT/'distribution/sqlite-dependencies.lock.json').read_text());rows=[]
    for name,item in q['packages'].items():
        files[item['packagedName'].casefold()]={'bytes':1,'sha256':item['assetSha256']}
        rows.append(dict(package=name+'/'+item['version'],**{k:item[k] for k in ('asset','archiveSha256','assetSha256','packagedName')}))
    requirement={'Name':'Microsoft.WindowsAppRuntime.2','Publisher':r.MICROSOFT,'MinVersion':'2.4.0.0'};identity=dict(Name=requirement['Name'],Publisher=r.MICROSOFT,ProcessorArchitecture='x64',Version='2.4.0.0')
    framework={'requirement':requirement,'identity':identity,'sha256':'a'*64}
    payload=dict(runtime_version='10.0.12',architecture='x64',declared_msix_dependencies=[requirement],framework_artifact_validation=dict(manifest_to_artifact_matching_passed=True,frameworks=[framework]))
    installed={'frameworks':[dict(requirement=requirement,artifact_identity=identity,artifact_sha256='a'*64,compatible_preexisting_full_names=[],artifact_registered=True,newly_registered_full_names=['Microsoft.WindowsAppRuntime.2_2.4.0.0_x64__8wekyb3d8bbwe'],resolved_full_names=['Microsoft.WindowsAppRuntime.2_2.4.0.0_x64__8wekyb3d8bbwe'])]}
    records={'windows-sdk-package.json':dict(sdk.verify_package_sdk((ROOT/'Directory.Build.props').read_bytes(),deps),archive=dict(bytes=sdk.ARCHIVE_BYTES,sha256=sdk.ARCHIVE_SHA256)),
             'sqlite-package-assets.json':dict(passed=True,packagedFilesVerified=True,packages=rows),
             'source-notices.json':dict(verified_runtime_packages=87),
             '../sqlite-execution.json':dict(version=q['nativeVersion'],sourceId=q['nativeSourceId'],sdkRuntime='.NET 10.0.12',architecture='X64',nativeSha256=q['packages']['SQLite']['assetSha256'],results=['exact executed native bytes','managed callback provider ABI','read-only reopen','copied WAL integrity','malformed database handled as SQLite error'])}
    for name,row in records.items():(folder/name).write_text(json.dumps(row))
    return files,dict(runtime_binaries=runtime,payload_inspection=payload),installed,records

class StoreRuntimeTests(unittest.TestCase):
    def test_current_actual_runtime_source_and_native_bindings(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)/'Consumer';folder.mkdir();files,validation,installed,records=fixture(folder)
            r.verify_native_evidence(ROOT,folder,files,validation,installed)
            for name in ('windows-sdk-package.json','sqlite-package-assets.json','../sqlite-execution.json','source-notices.json'):
                path=folder/name;original=path.read_bytes();path.write_text('{}')
                with self.subTest(name=name),self.assertRaises((ValueError,KeyError)):r.verify_native_evidence(ROOT,folder,files,validation,installed)
                path.write_bytes(original)
            for path in ('7z64.dll','git2-a418d9d.dll','microsoft.graphics.canvas.dll','coreclr.dll','e_sqlite3.dll','foldersail.deps.json'):
                original=files[path]['sha256'];files[path]['sha256']='f'*64
                with self.subTest(path=path),self.assertRaises(ValueError):r.verify_native_evidence(ROOT,folder,files,validation,installed)
                files[path]['sha256']=original
            for key,value in [('compatible_preexisting_full_names',['foreign']),('artifact_registered',False),('artifact_sha256','f'*64),('resolved_full_names',['foreign'])]:
                bad=copy.deepcopy(installed);bad['frameworks'][0][key]=value
                with self.subTest(key=key),self.assertRaises(ValueError):r.verify_native_evidence(ROOT,folder,files,validation,bad)

if __name__=='__main__':unittest.main()
