# Copyright 2026 Trieflow LLC. MIT.
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'distribution'))
import release_terms as t

class OriginalTermsTests(unittest.TestCase):
    def test_original_eula_and_concrete_downstream_terms(self):
        result=t.verify_original_eula(ROOT,lambda name:t.packaged_terms(ROOT)[name])
        self.assertEqual(result['original_eula']['bytes'],44042)
        self.assertEqual(result['original_eula']['sha256'],'7b10b2c7d15a3062037d3820bfd5528235f8a287ded3d131e22c2f5286e61633')
        self.assertEqual(result['store_terms']['filename'],'FolderSail-License-Terms.txt')
        self.assertTrue(result['store_license_terms_delivery_required'])

    def test_store_field_limit_and_full_original_including_french(self):
        terms=(ROOT/t.TERMS_SOURCE).read_bytes().decode('utf-8')
        original=t.eula_text((ROOT/'distribution/corresponding-source'/t.EULA_PATH).read_bytes())
        self.assertEqual(len(original),8772)
        self.assertIn('EFFET JURIDIQUE.',original)
        self.assertLessEqual(len(terms.encode('utf-16-le'))//2,10000)
        self.assertTrue(terms.replace('\r\n','\n').rstrip('\n').endswith(original))

    def test_unknown_terms_later_mit_wrong_binary_and_packaged_mutation_refuse(self):
        actual=t.load(ROOT/'distribution/corresponding-source/runtime-notices.json')
        for mutation in ('review','later-mit','binary','declared-url','capture'):
            bad=copy.deepcopy(actual);row=bad['packages']['Microsoft.Graphics.Win2D'];review=row['redistribution_review']
            if mutation=='review':review['status']='unresolved'
            if mutation=='later-mit':review['license_notice_path']=row['notices'][0]['path']
            if mutation=='binary':row['provenance']['sha256']='0'*64
            if mutation=='declared-url':row['declared_license']['license_url']='https://example.invalid/license'
            if mutation=='capture':review['captures'][0]['sha256']='0'*64
            with self.subTest(mutation=mutation),patch.object(t,'load',return_value=bad),self.assertRaises(ValueError):t.verify_original_eula(ROOT,lambda name:t.packaged_terms(ROOT)[name])
        for name in t.packaged_terms(ROOT):
            with self.subTest(name=name),self.assertRaises(ValueError):t.verify_original_eula(ROOT,lambda key:t.packaged_terms(ROOT)[key]+(b'changed' if key==name else b''))

if __name__=='__main__':unittest.main()
