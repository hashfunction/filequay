# Copyright 2026 Trieflow LLC. MIT.
import base64
import hashlib
import io
import json
import shutil
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import prepare_capture as p


class PrepareCapture(unittest.TestCase):
    def test_archive_validation_precedes_writes(self):
        for entries in ([('ok.json', b'{}'), ('../foreign', b'x')], [('same.json', b'1'), ('SAME.json', b'2')]):
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve(); archive = root/'input.zip'
                with zipfile.ZipFile(archive, 'w') as z:
                    for name, data in entries: z.writestr(name, data)
                with self.assertRaises(ValueError): p.extract_artifact(archive, root/'out', 1000)
                self.assertFalse((root/'out').exists())

    def test_extract_exact_regular_artifact_members(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); archive = root/'input.zip'
            with zipfile.ZipFile(archive, 'w') as z: z.writestr('Consumer/original.json', b'{"original":true}')
            p.extract_artifact(archive, root/'out', 1000)
            self.assertEqual((root/'out/Consumer/original.json').read_bytes(), b'{"original":true}')

    def test_preparation_joins_content_hash_to_reviewed_archive_and_original_framework(self):
        for mutation in (None, 'content_hash', 'archive_hash', 'archive_sha512', 'member'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root=Path(temporary).resolve();source=root/'source';output=root/'output';output.mkdir()
                (source/'src/Files.App').mkdir(parents=True);(source/'distribution').mkdir()
                shutil.copyfile(p.c.ROOT/'distribution/verify-package-payload.py',source/'distribution/verify-package-payload.py')
                content_hash=base64.b64encode(b'c'*64).decode()
                (source/'src/Files.App/packages.lock.json').write_text(json.dumps({'dependencies':{'fixture':{
                    'Microsoft.WindowsAppSDK.Runtime':{'resolved':'2.4.0','contentHash':content_hash}}}}))
                identity=dict(Name='Microsoft.WindowsAppRuntime.2',Publisher='CN=Microsoft Corporation',ProcessorArchitecture='x64',Version='2.4.0.0')
                requirement=dict(Name=identity['Name'],Publisher=identity['Publisher'],MinVersion='2.4.0.0')
                ns='http://schemas.microsoft.com/appx/manifest/foundation/windows10'
                attrs=lambda value:' '.join(k+'="'+v+'"' for k,v in value.items())
                frame=io.BytesIO()
                with zipfile.ZipFile(frame,'w') as z:
                    z.writestr('AppxManifest.xml','<Package xmlns="'+ns+'"><Identity '+attrs(identity)+'/>'+
                               '<Properties><Framework>true</Framework></Properties></Package>')
                original=frame.getvalue();data=io.BytesIO()
                with zipfile.ZipFile(data,'w') as z:z.writestr('tools/MSIX/win10-x64/framework.msix',original)
                archive=data.getvalue();sha512=base64.b64encode(hashlib.sha512(archive).digest()).decode()
                pin=dict(schema_version=1,package_id='Microsoft.WindowsAppSDK.Runtime',version='2.4.0',
                         url='https://api.nuget.org/v3-flatcontainer/microsoft.windowsappsdk.runtime/2.4.0/microsoft.windowsappsdk.runtime.2.4.0.nupkg',
                         nuget_content_hash=content_hash,archive=dict(bytes=len(archive),sha256=hashlib.sha256(archive).hexdigest()),archive_sha512=sha512)
                verified={'framework':dict(artifact_identity=identity,requirement=requirement,artifact_sha256=hashlib.sha256(original).hexdigest())}
                if mutation=='content_hash':pin['nuget_content_hash']='changed'
                elif mutation=='archive_hash':pin['archive']['sha256']='0'*64
                elif mutation=='archive_sha512':pin['archive_sha512']='changed'
                elif mutation=='member':verified['framework']['artifact_sha256']='0'*64
                pinpath=root/'pin.json';pinpath.write_text(json.dumps(pin))
                (output/'store').mkdir()
                with zipfile.ZipFile(output/'store'/p.c.PACKAGE_NAME,'w') as z:
                    z.writestr('AppxManifest.xml','<Package xmlns="'+ns+'"><Identity ProcessorArchitecture="x64"/>'+
                               '<Dependencies><PackageDependency '+attrs(requirement)+'/></Dependencies></Package>')
                response=io.BytesIO(archive);response.url=pin['url']
                with patch.object(p,'RUNTIME_ARCHIVE',pinpath,create=True),patch.object(p.urllib.request,'urlopen',return_value=response):
                    if mutation:
                        with self.assertRaises(ValueError):p.prepare_framework(output,source,verified)
                        self.assertFalse((output/'framework/Microsoft.WindowsAppRuntime.2.msix').exists())
                    else:
                        result=p.prepare_framework(output,source,verified)
                        self.assertEqual(result['original_archive_sha512'],sha512)
                        self.assertEqual(result['qualified_nuget_content_hash'],content_hash)
                        self.assertNotEqual(sha512,content_hash)
                        self.assertEqual((output/'framework/Microsoft.WindowsAppRuntime.2.msix').read_bytes(),original)

    def test_framework_requires_original_archive_and_unique_exact_member(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); archive = root/'runtime.nupkg'; original = b'original framework fixture'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('tools/MSIX/x64/framework.msix', original)
                z.writestr('tools/MSIX/arm64/framework.msix', b'other architecture')
            sha512 = base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()
            expected = hashlib.sha256(original).hexdigest()
            result = p.extract_framework(archive, root/'framework.msix', sha512, expected)
            self.assertEqual(result['member'], 'tools/MSIX/x64/framework.msix')
            self.assertEqual((root/'framework.msix').read_bytes(), original)
            for archive_hash, member_hash in [('invalid', expected), (sha512, '0'*64)]:
                with self.assertRaises(ValueError): p.extract_framework(archive, root/'absent.msix', archive_hash, member_hash)
                self.assertFalse((root/'absent.msix').exists())


if __name__ == '__main__': unittest.main()
