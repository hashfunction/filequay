# Copyright 2026 Trieflow LLC. MIT.
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'distribution'))
import source_notices as n

class SourceNoticeTests(unittest.TestCase):
    def test_current_all_original_notice_bytes(self):
        result=n.verify_notice_sources(ROOT)
        self.assertEqual(result['runtime_packages'],87)
        self.assertGreater(result['notice_files'],90)

    def test_actual_baseline_dependency_graph_with_approved_sdk(self):
        lock=json.loads((ROOT/'distribution/corresponding-source/runtime-notices.json').read_text())
        deps=json.loads((ROOT/'tests/packaging/fixtures/foldersail-runtime-deps-34694585269.json').read_text(encoding='utf-8-sig'))
        # Actual retained Windows payload metadata. The only approved graph
        # change is the independently audited stable SDK projection package key.
        with self.assertRaises(ValueError):n.verify_dependency_notices(deps,lock)
        old='runtimepack.Microsoft.Windows.SDK.NET.Ref/10.0.26100.67-preview'
        new='runtimepack.Microsoft.Windows.SDK.NET.Ref/10.0.26100.70'
        deps['targets'][n.TARGET][new]=deps['targets'][n.TARGET].pop(old)
        deps['libraries'][new]=deps['libraries'].pop(old)
        self.assertEqual(n.verify_dependency_notices(deps,lock),87)
        for mutation in ('version','extra','asset','missing'):
            changed=copy.deepcopy(deps)
            if mutation=='version':
                key=next(iter(changed['targets'][n.TARGET]));changed['targets'][n.TARGET][key+'/changed']=changed['targets'][n.TARGET].pop(key)
            if mutation=='extra':
                changed['targets'][n.TARGET]['Unaudited/1.0']={'runtime':{'unknown.dll':{}}};changed['libraries']['Unaudited/1.0']={'type':'package'}
            if mutation=='asset':changed['targets'][n.TARGET]['UTF.Unknown/2.6.0']['native']={'foreign.dll':{}}
            if mutation=='missing':del changed['targets'][n.TARGET]['UTF.Unknown/2.6.0']
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):n.verify_dependency_notices(changed,lock)

    def test_payload_exact_notice_and_source_records(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)
            for relative,data in n.package_files(ROOT).items():
                dest=output/relative;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
            n.verify_packaged_notices(ROOT,lambda name:(output/name).read_bytes())
            path=next(p for p in output.rglob('*') if p.is_file() and p.suffix=='.txt')
            path.write_bytes(path.read_bytes()+b'changed')
            with self.assertRaises(ValueError):n.verify_packaged_notices(ROOT,lambda name:(output/name).read_bytes())

    def test_actual_msbuild_links_all_required_notice_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            project=Path(tmp)/'notice-items.proj'
            props=ROOT/'distribution/FileQuay.CorrespondingSource.props'
            project.write_text('<Project><Import Project="'+str(props)+'" /></Project>')
            result=subprocess.check_output(['dotnet','msbuild',str(project),'-nologo','-getItem:Content'],cwd=ROOT)
            rows=json.loads(result)['Items']['Content']
            actual={row['Link'].replace('\\','/'):Path(row['FullPath']).read_bytes() for row in rows}
            self.assertEqual(len(rows),len(actual))
            self.assertEqual(actual,n.package_files(ROOT))
            self.assertTrue(all(row['CopyToOutputDirectory']=='PreserveNewest' for row in rows))

    def test_real_git_checkout_preserves_imported_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp); repo=tmp/'source';repo.mkdir()
            for command in (['init','-q'],['config','core.autocrlf','true'],['config','user.email','fixture@example.invalid'],['config','user.name','Fixture']):
                subprocess.run(['git','-C',str(repo),*command],check=True,capture_output=True)
            (repo/'.gitattributes').write_bytes((ROOT/'.gitattributes').read_bytes())
            inputs=list((ROOT/'distribution/corresponding-source/notices').rglob('*'))
            inputs+=[ROOT/'distribution/corresponding-source/source-release-assets.json',ROOT/'distribution/store-license-terms.txt']
            originals={}
            for path in inputs:
                if not path.is_file():continue
                name=path.relative_to(ROOT);dest=repo/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(path.read_bytes());originals[name]=path.read_bytes()
            subprocess.run(['git','-C',str(repo),'add','.'],check=True,capture_output=True)
            subprocess.run(['git','-C',str(repo),'commit','-qm','fixture'],check=True,capture_output=True)
            for name in originals:(repo/name).unlink()
            subprocess.run(['git','-C',str(repo),'checkout','HEAD','--','.'],check=True,capture_output=True)
            for name,data in originals.items():self.assertEqual((repo/name).read_bytes(),data,str(name))

if __name__=='__main__':unittest.main()
