# Copyright 2026 Trieflow LLC. MIT.
import base64
import copy
import csv
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PureWindowsPath
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('store_evidence', ROOT / 'distribution/store_evidence.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
CONTEXT = dict(source_commit='a' * 40, workflow_run_id='100', workflow_run_attempt='1')


def workflow():
    root = PureWindowsPath('D:/owned/consumer-workflow-' + 'a' * 32)
    source, copied, moved = (str(root / name / 'résumé,原稿.txt') for name in ('source', 'copy', 'move'))
    payload = e.digest(e.FIXTURE_TEXT.encode())
    initial = {r'source\résumé,原稿.txt': payload, r'export\receipts.csv': e.digest(b'previous')}
    initial.update({name + r'\protected.txt': e.digest(name.encode()) for name in ('source', 'copy', 'move')})
    receipts = [dict(schemaVersion=1, id=f'{kind:08d}-1111-4111-8111-111111111111', fileOperationType=kind,
                     returnResult=1, failureCode=None, sourcePaths=[old], destinationPaths=[new], itemCount=1, totalBytes=84,
                     startedAtUtc='2026-09-12T10:00:00Z', completedAtUtc='2026-09-12T10:00:01Z')
                for kind, old, new in ((3, source, copied), (4, copied, moved))]
    text = io.StringIO(newline=''); writer = csv.writer(text)
    writer.writerow(['Id','StartedAtUtc','CompletedAtUtc','Operation','Result','ItemCount','TotalBytes','SourcePaths','DestinationPaths','FailureCode'])
    for r in receipts:
        writer.writerow([r['id'],r['startedAtUtc'],r['completedAtUtc'],'Copy' if r['fileOperationType'] == 3 else 'Move','Success',1,84,r['sourcePaths'][0],r['destinationPaths'][0],''])
    csv_bytes = b'\xef\xbb\xbf' + text.getvalue().encode('utf-8')
    recovery = 'receipts.csv.' + 'b' * 32 + '.filequay-original'
    return dict(schema_version=1, passed=True, cleanup_verified=True, cancelled_export_preserved_previous_bytes=True,
                fixture_root=str(root), initial_files=initial, copy_files={**initial, r'copy\résumé,原稿.txt':payload},
                move_files={**initial, r'move\résumé,原稿.txt':payload},
                final_files={**initial,r'move\résumé,原稿.txt':payload,r'export\receipts.csv':e.digest(csv_bytes),'export\\'+recovery:initial[r'export\receipts.csv']},
                csv=e.digest(csv_bytes),csv_bytes_base64=base64.b64encode(csv_bytes).decode(),
                csv_recovery=dict(path=str(root/'export'/recovery),file=initial[r'export\receipts.csv']), receipts=receipts,
                visible_receipts=[dict(id=r['id'],title=('Copy' if r['fileOperationType']==3 else 'Move')+' · Completed',source=r['sourcePaths'][0],destination=r['destinationPaths'][0]) for r in receipts],
                cleared_history=dict(schemaVersion=1,receipts=[]))


def evidence(folder, mode, kind):
    folder.mkdir(parents=True)
    ident = e.identity(mode); full = ident['name']+'_1.0.1.0_x64__'+ident['family'].rsplit('_',1)[1]
    root = PureWindowsPath('C:/Program Files/WindowsApps')/full
    files = {name:e.digest(name.encode()) for name in ('FolderSail.exe','FolderSail.dll','coreclr.dll')}
    common = {**CONTEXT, 'identity':ident['name'], 'publisher':ident['publisher'], 'identity_mode':mode,
              'requested_build_kind':kind,'actual_build_kind':kind,'dependency_mode':'RequireClean','managed_build_kind_verified':True,'installation_qualification_passed':True}
    build = {**common,'native_build':True,'clean_framework_installation_gate_passed':True,'package_sha256':'b'*64}
    install = dict(**common, **{key:True for key in ('installed','main_window_verified','dependency_artifacts_verified','framework_registration_verified','registration_ownership_established','add_appx_completed','uninstall_verified','trust_removed','unsigned_package_unchanged','dependency_installation_from_artifacts_verified')},
               **{key:[] for key in ('cleanup_errors','evidence_errors','reporting_errors','preflight_package_full_names','residual_package_full_names')},
               owned_package_full_name=full, installed_package_full_name=full, aumid=ident['family']+'!App',
               unsigned_package_sha256='b'*64,unsigned_package_final_sha256='b'*64,ci_probe_type_present=kind=='Instrumented',
               packaged_managed_assembly_sha256=files['FolderSail.dll']['sha256'],installed_managed_assembly_sha256=files['FolderSail.dll']['sha256'],
               installed_location=str(root),packaged_module_count=2,executable_sha256=files['FolderSail.exe']['sha256'],packaged_coreclr_sha256=files['coreclr.dll']['sha256'])
    if kind == 'Consumer':
        install.update({key:True for key in ('broker_process_identity_verified','ui_tree_captured','screenshot_captured','window_close_requested','window_disappeared','consumer_process_outcome_accepted','owned_process_cleanup_verified','consumer_workflow_verified','consumer_fixture_cleanup_verified','consumer_native_adapter_verified','consumer_uia_proxy_verified','consumer_background_process_observed')})
        install.update(consumer_com_probe_invoked=False,consumer_activation_arguments='',activated_package_full_name=full,consumer_workflow=workflow())
        (folder/'main-window.png').write_bytes(b'real image boundary fixture')
        (folder/'ui-automation-tree.json').write_text('[]')
    else:
        install.update(com_activation_verified=True,server_natural_exit_verified=True,client_exit=dict(normal_exit=True,exit_code=0),server_exit=dict(normal_exit=True,exit_code=0))
    values = {'build-result.json':build,'installation-result.json':install,
              folder.name+'.validation.json':dict(identity=ident['name'],publisher=ident['publisher'],identity_mode=mode,package_sha256='b'*64,semantic_unpack_passed=True,payload_inspection=dict(payload_inspection_passed=True)),
              folder.name+'.files.json':[dict(path=name,**facts) for name,facts in files.items()],
              'managed-build-kind.json':dict(actual_build_kind=kind,expected_build_kind=kind,ci_probe_type_present=kind=='Instrumented',assembly_sha256=files['FolderSail.dll']['sha256']),
              'installed-modules.json':[dict(path=str(root/name),sha256=files[name]['sha256']) for name in ('FolderSail.exe','coreclr.dll')]}
    for name, value in values.items(): (folder/name).write_text(json.dumps(value),encoding='utf-8')
    return values


class StoreEvidenceTests(unittest.TestCase):
    def test_bom_unicode_csv_and_owned_recovery(self):
        e.verify_consumer(dict(consumer_workflow=workflow()))

    def test_workflow_mutations(self):
        for field, value in [('passed',False),('cleanup_verified',False),('cancelled_export_preserved_previous_bytes',False),('receipts',[]),('visible_receipts',[]),('cleared_history',dict(schemaVersion=1,receipts=[{}]))]:
            with self.subTest(field=field):
                w=workflow();w[field]=value
                with self.assertRaises(ValueError):e.verify_consumer(dict(consumer_workflow=w))
        for field in ('copy_files','move_files','final_files'):
            with self.subTest(field=field):
                w=workflow();w[field][r'source\résumé,原稿.txt']['sha256']='0'*64
                with self.assertRaises(ValueError):e.verify_consumer(dict(consumer_workflow=w))
        for mutation in ('csv','recovery','receipt-path','visible-title'):
            with self.subTest(mutation=mutation):
                w=workflow()
                if mutation=='csv':w['csv_bytes_base64']=base64.b64encode(b'changed').decode()
                if mutation=='recovery':w['csv_recovery']['path']='C:/foreign/receipts.csv.'+'b'*32+'.filequay-original'
                if mutation=='receipt-path':w['receipts'][0]['sourcePaths']=['C:/foreign/file']
                if mutation=='visible-title':w['visible_receipts'][0]['title']='Wrong'
                with self.assertRaises(ValueError):e.verify_consumer(dict(consumer_workflow=w))

    def test_csv_header_width_and_exact_timestamp_refusals(self):
        for mutation in ('header','extra-column','timestamp'):
            with self.subTest(mutation=mutation):
                w=workflow();raw=base64.b64decode(w['csv_bytes_base64'])
                if mutation=='header':raw=raw.replace(b'Id,StartedAtUtc',b'ForeignId,StartedAtUtc',1)
                if mutation=='extra-column':raw=raw.replace(b'FailureCode',b'FailureCode,Extra',1)
                if mutation=='timestamp':raw=raw.replace(b'10:00:00Z',b'10:00:00.0000001Z',1)
                w['csv_bytes_base64']=base64.b64encode(raw).decode();w['csv']=e.digest(raw);w['final_files'][r'export\receipts.csv']=e.digest(raw)
                with self.assertRaises(ValueError):e.verify_consumer(dict(consumer_workflow=w))

    def test_three_independent_build_modes(self):
        with tempfile.TemporaryDirectory() as tmp:
            for mode,kind,name in [('Qualification','Instrumented','Instrumented'),('Qualification','Consumer','Consumer'),('Store','Consumer','Store-Consumer')]:
                folder=Path(tmp)/name;evidence(folder,mode,kind)
                e.verify_installation(folder,CONTEXT,mode,kind)

    def test_lifecycle_source_identity_tamper(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)/'Store-Consumer';values=evidence(folder,'Store','Consumer')
            mutations={'source_commit':'c'*40,'workflow_run_id':'99','workflow_run_attempt':'2','identity_mode':'Qualification','actual_build_kind':'Instrumented','ci_probe_type_present':True,
                       'cleanup_errors':['foreign'],'residual_package_full_names':['foreign'],'window_disappeared':False,'consumer_workflow_verified':False,'consumer_fixture_cleanup_verified':False,
                       'owned_process_cleanup_verified':False,'consumer_com_probe_invoked':True,'unsigned_package_final_sha256':'d'*64,'consumer_background_process_observed':False,'aumid':'foreign!App'}
            for key,value in mutations.items():
                with self.subTest(key=key):
                    changed=copy.deepcopy(values['installation-result.json']);changed[key]=value
                    (folder/'installation-result.json').write_text(json.dumps(changed))
                    with self.assertRaises(ValueError):e.verify_installation(folder,CONTEXT,'Store','Consumer')
            (folder/'installation-result.json').write_text(json.dumps(values['installation-result.json']))
            bad=copy.deepcopy(values['installed-modules.json']);bad[0]['path']='C:/foreign/FolderSail.exe'
            (folder/'installed-modules.json').write_text(json.dumps(bad))
            with self.assertRaises(ValueError):e.verify_installation(folder,CONTEXT,'Store','Consumer')

    def test_archive_current_bytes_unsigned_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'store.msix';ident=e.identity('Store')
            xml=f'<Package xmlns="{e.NS[1:-1]}"><Identity Name="{ident["name"]}" Publisher="{ident["publisher"]}" Version="1.0.1.0" ProcessorArchitecture="x64"/><Properties><DisplayName>FolderSail</DisplayName><PublisherDisplayName>hashfunction</PublisherDisplayName></Properties><Applications><Application Id="App" Executable="FolderSail.exe"/></Applications></Package>'.encode()
            entries={'AppxManifest.xml':xml,'FolderSail.exe':b'fixture','[Content_Types].xml':b'OPC'}
            files={name.casefold():e.digest(data) for name,data in entries.items() if name!='[Content_Types].xml'}
            def write(extra=None):
                with zipfile.ZipFile(path,'w') as z:
                    for n,b in {**entries,**(extra or {})}.items():z.writestr(n,b)
            write();self.assertEqual(e.verify_archive(path,files,'Store'),e.file_record(path))
            for extra in ({'FolderSail.exe':b'changed'},{'AppxSignature.p7x':b'signed'},{'../foreign':b'foreign'},{'EXTRA.dll':b'extra'}):
                write(extra)
                with self.assertRaises(ValueError):e.verify_archive(path,files,'Store')
            write()
            with self.assertRaises(ValueError):e.verify_archive(path,files,'Qualification')


if __name__=='__main__':unittest.main()
