# Copyright 2026 Trieflow LLC. MIT.
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'distribution'))
import export_store as x
import source_notices as n
import test_store_evidence as fixtures
from store_evidence import digest,identity,NS,file_record

class StoreExportTests(unittest.TestCase):
    def fixture(self,root):
        source=root/'repo';source.mkdir();prior=root/'prior';store=root/'qualification/Store-Consumer'
        values={}
        for mode,kind,name in [('Qualification','Consumer','Consumer'),('Qualification','Instrumented','Instrumented'),('Store','Consumer','Store-Consumer')]:
            folder=store if mode=='Store' else prior/('FolderSail-Windows-'+name+'-qualification')/name
            values[name]=fixtures.evidence(folder,mode,kind)
        ident=identity('Store')
        xml=f'<Package xmlns="{NS[1:-1]}"><Identity Name="{ident["name"]}" Publisher="{ident["publisher"]}" Version="1.0.1.0" ProcessorArchitecture="x64"/><Properties><DisplayName>FolderSail</DisplayName><PublisherDisplayName>hashfunction</PublisherDisplayName></Properties><Applications><Application Id="App" Executable="FolderSail.exe"/></Applications></Package>'.encode()
        entries={name:name.encode() for name in ('FolderSail.exe','FolderSail.dll','coreclr.dll')}
        entries.update(n.package_files(ROOT));entries['AppxManifest.xml']=xml;entries['[Content_Types].xml']=b'OPC'
        package=source/'artifacts/appx/Store-Consumer/FolderSail.msix';package.parent.mkdir(parents=True)
        with zipfile.ZipFile(package,'w',compression=zipfile.ZIP_DEFLATED) as z:
            for name,data in entries.items():z.writestr(name,data)
        files=[dict(path=name,**digest(data)) for name,data in entries.items() if name!='[Content_Types].xml']
        (store/'Store-Consumer.files.json').write_text(json.dumps(files))
        hashes=file_record(package)
        for name,keys in [('build-result.json',['package_sha256']),('installation-result.json',['unsigned_package_sha256','unsigned_package_final_sha256']),('Store-Consumer.validation.json',['package_sha256'])]:
            record=values['Store-Consumer'][name]
            for key in keys:record[key]=hashes['sha256']
            if name=='build-result.json':record['package_path']=str(package.relative_to(source))
            (store/name).write_text(json.dumps(record))
        return source,prior,store,package

    def test_export_only_after_all_current_lifecycles_and_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();source,prior,store,package=self.fixture(root);output=root/'upload'
            # Public downloads/current Git and native-record verification are
            # independently exercised in their focused tests. All lifecycle,
            # original ZIP, notice-byte, final-copy and evidence logic is real.
            with patch.object(x,'verify_current_source',return_value='c'*40),patch.object(x,'verify_public_sources',return_value={'application_source':{'git_tree':'c'*40},'source_page':'https://foldersail.trieflow.com/source'}),patch.object(x,'verify_native_evidence',return_value={'fixture':'native evidence boundary'}) as native,patch.object(x,'verify_packaged_notices',side_effect=lambda source,read:n.verify_packaged_notices(ROOT,read)):
                result=x.export(source,prior,store,output,fixtures.CONTEXT)
                self.assertEqual(native.call_count,3)
                self.assertTrue(result['store_upload_ready'])
                self.assertEqual(file_record(output/x.PACKAGE_NAME),file_record(package))
                self.assertEqual({p.name for p in output.iterdir()},{x.PACKAGE_NAME,'release-ready.json'})
                self.assertEqual(result['identity']['application_id'],'App')
                with self.assertRaises(ValueError):x.export(source,prior,store,output,fixtures.CONTEXT)

    def test_each_failed_lifecycle_blocks_before_publication_or_copy(self):
        for kind in ('Consumer','Instrumented','Store-Consumer'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp).resolve();source,prior,store,package=self.fixture(root);folder=store if kind=='Store-Consumer' else prior/('FolderSail-Windows-'+kind+'-qualification')/kind
                path=folder/'installation-result.json';record=json.loads(path.read_text());record['uninstall_verified']=False;path.write_text(json.dumps(record))
                with patch.object(x,'verify_current_source',return_value='c'*40),patch.object(x,'verify_native_evidence',return_value={}),patch.object(x,'verify_public_sources') as public:
                    with self.assertRaises(ValueError):x.export(source,prior,store,root/'upload',fixtures.CONTEXT)
                    public.assert_not_called();self.assertFalse((root/'upload').exists())

    def test_package_or_publication_mutation_never_gets_ready_receipt(self):
        for mutation in ('signed','publication','changed-during-publication'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp).resolve();source,prior,store,package=self.fixture(root)
                if mutation=='signed':
                    with zipfile.ZipFile(package,'a') as z:z.writestr('AppxSignature.p7x',b'signed')
                def public(*args):
                    if mutation=='publication':raise ValueError('Public source bytes differ')
                    with package.open('ab') as f:f.write(b'changed after review')
                    return {'application_source':{'git_tree':'c'*40}}
                with patch.object(x,'verify_current_source',return_value='c'*40),patch.object(x,'verify_native_evidence',return_value={}),patch.object(x,'verify_public_sources',side_effect=public),patch.object(x,'verify_packaged_notices',side_effect=lambda source,read:n.verify_packaged_notices(ROOT,read)):
                    with self.assertRaises(ValueError):x.export(source,prior,store,root/'upload',fixtures.CONTEXT)
                    self.assertFalse((root/'upload/release-ready.json').exists())

    def test_actual_git_context_rejects_stale_dirty_untracked(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp).resolve()
            def git(*args):return subprocess.check_output(['git','-C',str(source),*args],stderr=subprocess.PIPE)
            git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
            (source/'file').write_bytes(b'original');git('add','.');git('commit','-qm','fixture')
            context={**fixtures.CONTEXT,'source_commit':git('rev-parse','HEAD').decode().strip()}
            x.verify_current_source(source,context)
            with self.assertRaises(ValueError):x.verify_current_source(source,fixtures.CONTEXT)
            (source/'file').write_bytes(b'changed')
            with self.assertRaises(ValueError):x.verify_current_source(source,context)
            git('checkout','--','file');(source/'foreign').write_bytes(b'new')
            with self.assertRaises(ValueError):x.verify_current_source(source,context)

if __name__=='__main__':unittest.main()
