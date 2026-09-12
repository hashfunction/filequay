# Copyright 2026 Trieflow LLC. MIT.
import copy
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'distribution'))
import source_publication as p

class SourcePublicationTests(unittest.TestCase):
    def test_exact_published_collection_and_mutations(self):
        folder=ROOT/'distribution/corresponding-source';record=p.load(folder/'native-source-publication.json');plan=folder/'source-release-assets.json'
        self.assertEqual(len(p.validate_publication(record,plan)['assets']),6)
        for mutation in ('missing','bytes','hash','url','unpublished','timestamp','manifest'):
            bad=copy.deepcopy(record)
            if mutation=='missing':bad['assets'].pop()
            if mutation=='bytes':bad['assets'][0]['bytes']+=1
            if mutation=='hash':bad['assets'][0]['sha256']='a'*64
            if mutation=='url':bad['assets'][0]['url']='https://github.com/other/source.tar'
            if mutation=='unpublished':bad['publication_verified']=False
            if mutation=='timestamp':bad['verified_at_utc']='2026-09-12T01:00:00'
            if mutation=='manifest':bad['manifest']['sha256']='b'*64
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):p.validate_publication(bad,plan)

    def test_public_receipt_rejects_signed_redirect_query(self):
        folder=ROOT/'distribution/corresponding-source';record=p.load(folder/'native-source-publication.json')
        record['assets'][0]['final_url']='https://release-assets.githubusercontent.com/asset?sig=fixture-secret'
        with self.assertRaises(ValueError):p.validate_publication(record,folder/'source-release-assets.json')

    def test_exact_git_blob_archive_with_windows_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();repo=root/'repo';repo.mkdir()
            def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.PIPE)
            git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');git('config','core.autocrlf','true')
            (repo/'.gitattributes').write_bytes(b'*.txt text\r\n');(repo/'source.txt').write_bytes(b'original\r\nsource\r\n')
            git('add','.');git('commit','-qm','fixture');commit=git('rev-parse','HEAD').decode().strip()
            archive=root/'public.tar.gz';archive.write_bytes(git('-c','core.autocrlf=false','-c','core.eol=lf','archive','--format=tar.gz','--prefix=public/',commit))
            self.assertEqual(p.verify_application_archive(archive,repo,commit)['verified_tracked_files'],2)
            for mutation in ('missing','changed','foreign','mode'):
                with tarfile.open(archive,'w:gz') as t:
                    for name,data in [('.gitattributes',b'*.txt text\n'),('source.txt',b'original\nsource\n')]:
                        if mutation=='missing' and name=='source.txt':continue
                        if mutation=='changed' and name=='source.txt':data=b'changed'
                        info=tarfile.TarInfo('public/'+name);info.size=len(data);info.mode=0o755 if mutation=='mode' else 0o644;t.addfile(info,io.BytesIO(data))
                    if mutation=='foreign':
                        info=tarfile.TarInfo('public/foreign');info.size=1;t.addfile(info,io.BytesIO(b'x'))
                with self.subTest(mutation=mutation),self.assertRaises(ValueError):p.verify_application_archive(archive,repo,commit)

    def test_public_source_byte_mismatch_refuses_before_application(self):
        with patch.object(p,'download',return_value={'bytes':1,'sha256':'0'*64}) as download:
            with self.assertRaises(ValueError):p.verify_public_sources(ROOT,'a'*40)
            self.assertEqual(download.call_count,1)

if __name__=='__main__':unittest.main()
