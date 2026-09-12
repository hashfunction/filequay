"""Reproduce source-only archives from exact upstream originals; never edits them."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile

INPUTS = {
 'taglibsharp': {
  'original': 'taglibsharp-b5ae84f2e84087bf160bb0471420200dd2b5d809.tar.gz',
  'sha256': '2e54eb7382991caeafd2ac414ca5ab6ca2a4d2b5fe9bba4d8abff3fc1b308195',
  'bytes': 102053634,
  'root': 'taglib-sharp-b5ae84f2e84087bf160bb0471420200dd2b5d809',
  'omit_data_prefixes': ['src/TaglibSharp.Tests/samples/', 'src/TaglibSharp.Tests/raw-samples/'],
  'keep_data_notices': ['src/TaglibSharp.Tests/samples/LICENSE'],
  'required_source': ['COPYING','src/TaglibSharp/TaglibSharp.csproj'],
 },
 'utf-unknown': {
  'original': 'utf-unknown-7e69ebbdd6ef96a3625fcaf39df42429b8eb0463.tar.gz',
  'sha256': '2df5101f3bd5dd4f9257214339f1a4e634ed7829ed756fc728f494ebbceaa258',
  'bytes': 436288,
  'root': 'UTF-unknown-7e69ebbdd6ef96a3625fcaf39df42429b8eb0463',
  'omit_data_prefixes': ['tests/Data/'],
  'keep_data_notices': ['tests/Data/README.md'],
  'required_source': ['src/UTF-unknown.csproj','license/MPL-1.1.txt','license/lgpl-2.1.txt','license/gpl-2.0.txt'],
 },
}


def derive(input_directory, output_directory):
 output_directory.mkdir(parents=True, exist_ok=False)
 records=[]
 for name, spec in INPUTS.items():
  source=input_directory/spec['original']
  if source.stat().st_size != spec['bytes'] or hashlib.sha256(source.read_bytes()).hexdigest() != spec['sha256']:
   raise ValueError('Original source archive differs: '+name)
  destination=output_directory/(name+'-'+spec['root'].rsplit('-',1)[1]+'-source-only.tar')
  kept=[];omitted=[];seen=set()
  with tarfile.open(source) as archive, tarfile.open(destination,'x',format=tarfile.USTAR_FORMAT) as output:
   for entry in sorted(archive.getmembers(), key=lambda item:item.name):
    path=PurePosixPath(entry.name)
    if path.is_absolute() or '..' in path.parts or path.parts[0] != spec['root']:
     raise ValueError('Unsafe or unexpected source path: '+entry.name)
    if entry.isdir(): continue
    if not entry.isfile() or entry.name in seen: raise ValueError('Nonregular or duplicate source entry.')
    seen.add(entry.name)
    relative=path.relative_to(spec['root']).as_posix()
    data=archive.extractfile(entry).read()
    receipt={'path':relative,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'mode':entry.mode & 0o777}
    if any(relative.startswith(prefix) for prefix in spec['omit_data_prefixes']) and relative not in spec['keep_data_notices']:
     omitted.append(receipt);continue
    info=tarfile.TarInfo(entry.name);info.size=len(data);info.mode=receipt['mode'];info.mtime=0;info.uid=0;info.gid=0;info.uname='';info.gname=''
    output.addfile(info,io.BytesIO(data));kept.append(receipt)
  if not set(spec['required_source']).issubset({item['path'] for item in kept}): raise ValueError('Required library source or license missing.')
  records.append({'component':name,'original':spec,'derived':{'filename':destination.name,'bytes':destination.stat().st_size,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),'format':'POSIX ustar, sorted regular files, original file modes and bytes, zero uid/gid/mtime, empty owner names'},'retained_files':kept,'omitted_test_data':omitted})
 (output_directory/'source-derivation.json').write_text(json.dumps({'schema_version':1,'components':records},indent=2)+'\n',encoding='utf-8',newline='\n')
 return records


if __name__ == '__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--input-directory',required=True,type=Path)
 parser.add_argument('--output-directory',required=True,type=Path)
 args=parser.parse_args()
 for record in derive(args.input_directory,args.output_directory):
  print(json.dumps({'component':record['component'],'derived':record['derived'],'retained_files':len(record['retained_files']),'omitted_test_data_files':len(record['omitted_test_data'])}))
