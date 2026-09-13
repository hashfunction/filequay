# Copyright 2026 Trieflow LLC. MIT.
"""Retain the unchanged unsigned Store MSIX after three current native lifecycles."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import sys
import zipfile
from store_evidence import require, regular, file_record, load, identity, normalized, verify_installation, verify_archive
from store_runtime import verify_native_evidence
from source_notices import verify_packaged_notices
from source_publication import git, verify_public_sources

PACKAGE_NAME='FolderSail_1.0.1.0_x64.msix'


def report_source_changes(source,status,phase=None,diagnostic_errors=()):
    def bounded(value):
        return dict(text=value[:4096].decode('utf-8',errors='replace'),truncated=len(value)>4096)
    observation=dict(porcelain=bounded(status),diagnostic_errors=list(diagnostic_errors))
    if phase is not None:observation.update(phase=phase,generated_at_utc=datetime.now(timezone.utc).isoformat())
    try:observation['tracked_diff_names']=bounded(git(source,'diff','--no-ext-diff','--name-only','HEAD','--'))
    except Exception as error:observation['diagnostic_errors'].append(type(error).__name__[:128])
    try:print('FolderSail source diagnostic: '+json.dumps(observation,ensure_ascii=True),file=sys.stderr)
    except Exception:pass  # A secondary observation cannot replace the original refusal.


def observe_source_status(source,phase):
    require(phase in ('after-build','after-installation'),'Unexpected source observation phase')
    errors=[]
    try:status=git(source,'status','--porcelain=v1','--untracked-files=all')
    except Exception as error:status=b'';errors.append(type(error).__name__[:128])
    report_source_changes(source,status,phase,errors)


def verify_current_source(source,context):
    require(re.fullmatch('[0-9a-f]{40}',context.get('source_commit','')) is not None
            and all(re.fullmatch('[1-9][0-9]*',context.get(key,'')) for key in ('workflow_run_id','workflow_run_attempt')),
            'Export requires exact source/run/attempt')
    require(git(source,'rev-parse','HEAD').decode().strip()==context['source_commit'],'Build is not from the current source commit')
    status=git(source,'status','--porcelain=v1','--untracked-files=all')
    if status.strip():report_source_changes(source,status)
    require(not status.strip(),'Source changed after the qualified build')
    return git(source,'rev-parse','HEAD^{tree}').decode().strip()


def snapshot(folder):
    require(folder.is_dir() and not folder.is_symlink(),'Missing or linked qualification directory')
    return {path.relative_to(folder).as_posix():file_record(path) for path in sorted(folder.rglob('*')) if path.is_file()}


def export(source,prior,store,output,context):
    source=Path(source).absolute();prior=Path(prior).absolute();store=Path(store).absolute();output=Path(output).absolute()
    require(not output.exists(),'Store export destination must be new')
    tree=verify_current_source(source,context)
    folders=[(prior/'FolderSail-Windows-Instrumented-qualification'/'Instrumented','Qualification','Instrumented'),
             (prior/'FolderSail-Windows-Consumer-qualification'/'Consumer','Qualification','Consumer'),
             (store,'Store','Consumer')]
    before={str(folder):snapshot(folder.parent) for folder,_,_ in folders};evidence=[];qualified=None
    for folder,mode,kind in folders:
        result=verify_installation(folder,context,mode,kind)
        native=verify_native_evidence(source,folder,result['files'],result['validation'],result['install'])
        evidence.append(dict(identity_mode=mode,build_kind=kind,package_sha256=result['build']['package_sha256'].lower(),
                             installation_qualified=True,native=native,files=before[str(folder)]))
        if mode=='Store':qualified=result
    relative=normalized(qualified['build']['package_path'])
    require(relative.casefold().startswith('artifacts/appx/store-consumer/') and relative.casefold().endswith(('.msix','.appx')),
            'Store package was not built in its dedicated output')
    package=regular(source/relative)
    original=verify_archive(package,qualified['files'],'Store')
    require(original['sha256']==qualified['build']['package_sha256'].lower(),'Original Store archive differs from installed qualification')
    with zipfile.ZipFile(package) as archive:
        notices=verify_packaged_notices(source,archive.read)
    publication=verify_public_sources(source,context['source_commit'])
    require(publication['application_source']['git_tree']==tree,'Published application tree differs from qualified source')
    require(verify_current_source(source,context)==tree and file_record(package)==original
            and before=={str(folder):snapshot(folder.parent) for folder,_,_ in folders},'Source, original package or evidence changed during export verification')
    output.mkdir(parents=True,exist_ok=False)
    target=output/PACKAGE_NAME
    with package.open('rb') as source_stream,target.open('xb') as target_stream:
        shutil.copyfileobj(source_stream,target_stream,1024*1024)
    require(file_record(target)==original and file_record(package)==original,'Exported unsigned package differs from qualified original')
    require(verify_current_source(source,context)==tree and before=={str(folder):snapshot(folder.parent) for folder,_,_ in folders},
            'Current source or evidence changed during final copy')
    receipt=dict(schema_version=1,product='FolderSail',version='1.0.1.0',identity=identity('Store'),**context,git_tree=tree,
                 generated_at_utc=datetime.now(timezone.utc).isoformat().replace('+00:00','Z'),store_upload_ready=True,
                 package=dict(filename=PACKAGE_NAME,unsigned=True,**original),three_native_lifecycles=evidence,
                 packaged_notices=notices,public_sources=publication,submitted=False,
                 store_license_terms_delivery_required=notices['win2d_original_terms']['store_license_terms_delivery_required'],
                 store_license_terms=notices['win2d_original_terms']['store_terms'],
                 limitations=['Win2D 1.3.2 identifies a build revision unavailable from the public repository; separately attributed MIT notice is not claimed as that build source.',
                              'The original Win2D EULA is retained from independently matched archived Microsoft captures; its current URL redirects. Deliver the packaged license text in the Store license field before submission.',
                              'Vendor native binaries were not rebuilt reproducibly; exact native inputs and available corresponding sources are recorded.',
                              'Framework packages remain on their disposable runners under the existing cleanup policy.'])
    with (output/'release-ready.json').open('x',encoding='utf-8',newline='\n') as stream:json.dump(receipt,stream,indent=2);stream.write('\n')
    return receipt


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for arg in ('source','prior','store','output'):p.add_argument('--'+arg,required=True,type=Path)
    for arg in ('source-commit','workflow-run-id','workflow-run-attempt'):p.add_argument('--'+arg,required=True)
    args=p.parse_args();context={key:getattr(args,key) for key in ('source_commit','workflow_run_id','workflow_run_attempt')}
    receipt=export(args.source,args.prior,args.store,args.output,context)
    print(json.dumps(dict(store_upload_ready=True,package=receipt['package'])))

if __name__=='__main__':main()
