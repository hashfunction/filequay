# Copyright 2026 Trieflow LLC. MIT.
"""Require the recovered original binary EULA and its concrete downstream terms."""
import base64
import hashlib
from html.parser import HTMLParser
from pathlib import Path
from store_evidence import load, require, file_record, digest

EULA_PATH='notices/native-Microsoft.Win2D/eula_win2d_10012014.htm'
EULA_BYTES=44042
EULA_SHA256='7b10b2c7d15a3062037d3820bfd5528235f8a287ded3d131e22c2f5286e61633'
EULA_CDX='T472OIPFCTEW25XVAQGV6KFWFTSPG4PV'
PACKAGE_SHA256='80557bf78a05f40831e97946f6624b02d8d1abf60b58ddb7c617113cf62ee0ad'
DECLARED_URL='http://www.microsoft.com/web/webpi/eula/eula_win2d_10012014.htm'
TERMS_SOURCE='distribution/store-license-terms.txt'
TERMS_PACKAGED='FolderSail-License-Terms.txt'


def eula_text(raw):
    # Reproduce all readable original English and French terms from the exact
    # windows-1252 Microsoft HTML; ignore only stylesheet/script contents.
    class OriginalText(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True); self.skip=0; self.parts=[]
        def handle_starttag(self,tag,attrs):
            if tag in ('style','script'): self.skip+=1
        def handle_endtag(self,tag):
            if tag in ('style','script'): self.skip-=1
        def handle_data(self,data):
            if not self.skip and data.strip(): self.parts.append(data.strip())
    parser=OriginalText(); parser.feed(raw.decode('windows-1252'))
    return '\n'.join(parser.parts).replace('\r\n','\n')


def packaged_terms(source):
    source=Path(source)
    return {'Licenses/CorrespondingSource/'+EULA_PATH:(source/'distribution/corresponding-source'/EULA_PATH).read_bytes(),
            TERMS_PACKAGED:(source/TERMS_SOURCE).read_bytes()}


def verify_original_eula(source,read):
    source=Path(source);row=load(source/'distribution/corresponding-source/runtime-notices.json')['packages']['Microsoft.Graphics.Win2D']
    review=row.get('redistribution_review',{})
    require(row.get('version')=='1.3.2' and row.get('provenance',{}).get('sha256')==PACKAGE_SHA256
            and row.get('declared_license',{}).get('license_url')==DECLARED_URL,
            'Win2D original binary/license declaration changed')
    require(review.get('status')=='original-eula-reviewed' and review.get('license_notice_path')==EULA_PATH
            and review.get('original_package_sha256')==PACKAGE_SHA256 and review.get('original_declared_url')==DECLARED_URL,
            'Applicable original Win2D binary redistribution terms are unverified')
    captures=review.get('captures',[])
    require(len(captures)==2 and {x.get('timestamp') for x in captures}=={'20210507221235','20250113180923'},'Independent original Microsoft captures missing')
    expected=dict(bytes=EULA_BYTES,sha256=EULA_SHA256)
    for capture in captures:
        require(capture.get('archive_url')=='https://web.archive.org/web/'+capture['timestamp']+'id_/https://www.microsoft.com/web/webpi/eula/eula_win2d_10012014.htm'
                and capture.get('cdx_sha1_base32')==EULA_CDX and all(capture.get(k)==v for k,v in expected.items()),'Original EULA archive provenance differs')
    eula=source/'distribution/corresponding-source'/EULA_PATH
    require(file_record(eula)==expected and base64.b32encode(hashlib.sha1(eula.read_bytes()).digest()).decode()==EULA_CDX,
            'Original Microsoft EULA differs from archived/CDX bytes')
    terms=review.get('downstream_terms',{})
    require(terms.get('source_file')==TERMS_SOURCE and terms.get('package_file')==TERMS_PACKAGED
            and file_record(source/TERMS_SOURCE)=={k:terms.get(k) for k in ('bytes','sha256')}
            and review.get('store_license_terms_delivery_required') is True,'Required downstream license terms missing or changed')
    terms_text=(source/TERMS_SOURCE).read_bytes().decode('utf-8')
    require(len(terms_text.encode('utf-16-le'))//2 <= 10000
            and terms_text.replace('\r\n','\n').rstrip('\n').endswith(eula_text(eula.read_bytes())),
            'Store terms exceed the real field limit or omit original English/French terms')
    for name,data in packaged_terms(source).items():require(read(name)==data,'Packaged original EULA/downstream terms differ: '+name)
    return dict(original_eula=expected,original_package_sha256=PACKAGE_SHA256,
                store_terms=dict(filename=TERMS_PACKAGED,bytes=terms['bytes'],sha256=terms['sha256']),
                store_license_terms_delivery_required=True,source_revision_public=False)
