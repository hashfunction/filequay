"""Original demo files and strict capture cleanup; never write app receipt history."""
# Copyright 2026 Trieflow LLC. MIT.
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import uuid

MARKER = '.foldersail-capture-owner'
SOURCE = 'Inbox/Garden workshop brief.md'
COPIED = 'Working drafts/Garden workshop brief.md'
MOVED = 'Ready to share/Garden workshop brief.md'
CSV = 'Receipts/Workshop receipts.csv'
DIRECTORIES = ['Inbox', 'Working drafts', 'Ready to share', 'Receipts']
COLUMNS = ['Id', 'StartedAtUtc', 'CompletedAtUtc', 'Operation', 'Result', 'ItemCount',
           'TotalBytes', 'SourcePaths', 'DestinationPaths', 'FailureCode']
ORIGINALS = {
    SOURCE: '# Garden workshop\n\nA Saturday morning for growing something together.\n\n'
            'Bring a notebook, choose three herbs, and sketch a small sunny corner.\n'
            'Deliverables: a planting plan, a shared shopping list, and a care calendar.\n',
    'Inbox/Workshop agenda.txt': 'Garden workshop\n09:30 Welcome and ideas\n10:00 Plan the beds\n11:00 Plant together\n12:00 Tea and next steps\n',
    'Inbox/Materials budget.csv': 'Item,Quantity,Estimate\nHerb seedlings,12,48\nCompost bags,4,32\nPlant labels,24,12\n',
    'Inbox/Reference notes.md': '# Small garden ideas\n\nKeep paths clear. Group thirsty plants together. Leave room to grow.\n',
    'Working drafts/Working notes.txt': 'Use this folder while preparing the workshop handout.\n',
    'Ready to share/Sharing checklist.txt': 'Read once more, check the dates, and send the finished brief.\n',
    CSV: 'Project,Status\nGarden workshop,Planning\n',
}


def require(value, message):
    if not value:
        raise ValueError(message)


def no_links(path):
    for part in (path, *path.parents):
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        require(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400,
                'Linked capture path preserved')


def digest(path):
    path = Path(path); no_links(path); before = path.lstat()
    require(stat.S_ISREG(before.st_mode) and before.st_size <= 1048576, 'Invalid bounded capture file')
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(descriptor, 'rb') as stream:
        opened = os.fstat(stream.fileno())
        require((before.st_dev, before.st_ino) == (opened.st_dev, opened.st_ino), 'Capture file identity changed')
        data = stream.read(1048577); after = os.fstat(stream.fileno())
    no_links(path); final = path.lstat()
    signature = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns)
    require(len(data) <= 1048576 and signature(before) == signature(opened) == signature(after) == signature(final),
            'Capture file changed while reading')
    return dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())


def snapshot(root):
    no_links(root); require(root.is_dir(), 'Capture root missing')
    files = {}; folders = []; pending = [root]; count = 0
    while pending:
        for path in pending.pop().iterdir():
            count += 1; require(count <= 40, 'Capture tree exceeds bound'); no_links(path)
            relative = path.relative_to(root).as_posix()
            if path.is_dir():
                require(relative in DIRECTORIES, 'Unexpected demo directory preserved')
                folders.append(relative); pending.append(path)
            else:
                files[relative] = digest(path)
    require(sorted(folders) == sorted(DIRECTORIES), 'Demo directory set changed')
    return files


def create(root):
    root = Path(root).absolute(); no_links(root)
    require(not os.path.lexists(root), 'Existing demo preserved')
    require(root.parent.is_dir(), 'Demo parent missing')
    root.mkdir(); token = uuid.uuid4().hex
    with (root / MARKER).open('x', encoding='ascii') as stream:
        stream.write(token)
    for name in DIRECTORIES:
        (root / name).mkdir()
    for name, content in ORIGINALS.items():
        with (root / name).open('xb') as stream:
            stream.write(content.replace('\n', '\r\n').encode('utf-8'))
    originals = {name: digest(root / name) for name in ORIGINALS}
    return dict(schema_version=1, root=str(root), token=token, originals=originals,
                payload=originals[SOURCE], previous_csv=originals[CSV], export=None)


def observe(state):
    root = Path(state['root']); no_links(root)
    require(digest(root / MARKER)['bytes'] == 32 and (root / MARKER).read_text(encoding='ascii') == state['token'],
            'Demo ownership marker changed')
    files = snapshot(root)
    allowed = {MARKER, *state['originals'], COPIED, MOVED}
    if state['export']:
        allowed.add(state['export']['recovery'])
    require(set(files) <= allowed, 'Unexpected demo output preserved')
    for name, original in state['originals'].items():
        expected = state['export']['csv'] if name == CSV and state['export'] else original
        require(files.get(name) == expected, 'Original demo file changed: ' + name)
    for name in (COPIED, MOVED):
        if name in files:
            require(files[name] == state['payload'], 'Copied/moved file differs from original')
    if state['export']:
        require(files.get(state['export']['recovery']) == state['previous_csv'], 'Original CSV recovery changed')
    return files


def verify(state, phase):
    require(phase in ('Initial', 'Copied', 'Moved', 'Exported'), 'Unknown capture phase')
    files = observe(state)
    require((COPIED in files) == (phase == 'Copied') and (MOVED in files) == (phase in ('Moved', 'Exported')),
            'Actual Copy/Move presence differs')
    require(bool(state['export']) == (phase == 'Exported'), 'Actual export phase differs')
    return dict(phase=phase, files=files)


def timestamp(value):
    match = re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(?:Z|\+00:00)', value or '')
    require(match is not None, 'Receipt timestamp is not UTC round-trip text')
    return match[1], (match[2] or '').ljust(7, '0')


def register_export(state, receipts, recovery):
    root = Path(state['root']); recovery = Path(recovery).absolute()
    require(recovery.parent == (root / CSV).parent and
            re.fullmatch(re.escape(Path(CSV).name) + r'\.[0-9a-f]{32}\.filequay-original', recovery.name),
            'Foreign CSV recovery preserved')
    require(digest(recovery) == state['previous_csv'], 'CSV recovery original bytes differ')
    require(isinstance(receipts, list) and len(receipts) == 2, 'Expected two actual app receipts')
    seen = set(); operations = set()
    for row in receipts:
        identifier = str(uuid.UUID(row['id'])); op = row['fileOperationType']
        require(identifier == row['id'].lower() and identifier not in seen and op in (3, 4) and op not in operations and
                row['returnResult'] == 1 and row['failureCode'] is None, 'Actual receipt identity/result differs')
        seen.add(identifier); operations.add(op)
        source, destination = (SOURCE, COPIED) if op == 3 else (COPIED, MOVED)
        require(row['sourcePaths'] == [str(root / source)] and row['destinationPaths'] == [str(root / destination)],
                'Actual receipt paths differ')
        require(timestamp(row['startedAtUtc']) <= timestamp(row['completedAtUtc']) and
                all(type(row[k]) is int and row[k] >= 0 for k in ('itemCount', 'totalBytes')), 'Receipt metadata differs')
    facts = digest(root / CSV)
    parsed = list(csv.reader(io.StringIO((root / CSV).read_text(encoding='utf-8-sig'), newline=''), strict=True))
    require(len(parsed) == 3 and parsed[0] == COLUMNS and all(len(row) == 10 for row in parsed), 'CSV columns/count differ')
    seen_csv = set()
    for values in parsed[1:]:
        matches = [row for row in receipts if row['id'] == values[0]]
        require(len(matches) == 1 and values[0] not in seen_csv, 'CSV receipt identity differs')
        seen_csv.add(values[0]); row = matches[0]
        expected = [row['id'], row['startedAtUtc'], row['completedAtUtc'], 'Copy' if row['fileOperationType'] == 3 else 'Move',
                    'Success', str(row['itemCount']), str(row['totalBytes']), row['sourcePaths'][0], row['destinationPaths'][0], '']
        require(all(timestamp(values[i]) == timestamp(expected[i]) if i in (1, 2) else values[i] == expected[i]
                    for i in range(10)), 'CSV values differ from actual receipts')
    state['export'] = dict(csv=facts, recovery=recovery.relative_to(root).as_posix(), rows=2)
    verify(state, 'Exported')
    return state['export']


def seal(state, stopped):
    require(stopped, 'Owned processes must be stopped before sealing')
    return dict(files=observe(state))


def cleanup(state, sealed, stopped):
    require(stopped, 'Owned processes must be stopped before cleanup')
    require(observe(state) == sealed['files'], 'Demo changed after seal; preserved')
    root = Path(state['root'])
    for relative in sealed['files']:
        if relative == MARKER:
            continue
        (root / relative).unlink()
    for relative in DIRECTORIES:
        (root / relative).rmdir()
    (root / MARKER).unlink()
    root.rmdir()
    return dict(removed=not os.path.lexists(root))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['create', 'verify', 'register-export', 'seal', 'cleanup'])
    parser.add_argument('--state', required=True, type=Path); parser.add_argument('--root', type=Path)
    parser.add_argument('--phase'); parser.add_argument('--receipts', type=Path); parser.add_argument('--recovery')
    parser.add_argument('--stopped', action='store_true'); args = parser.parse_args()
    no_links(args.state)
    if args.mode == 'create':
        require(os.name == 'nt' and args.root == Path(r'C:\FolderSail Demo'), 'Only the exact isolated marketing demo path is allowed')
        require(not os.path.lexists(args.state), 'Existing capture state preserved')
        state = create(args.root)
        with args.state.open('x', encoding='utf-8') as stream:
            json.dump(state, stream, indent=2)
        result = state
    else:
        original_state = digest(args.state); state = json.loads(args.state.read_text(encoding='utf-8-sig'))
        seal_path = args.state.with_suffix('.seal.json')
        if args.mode == 'verify':
            result = verify(state, args.phase)
        elif args.mode == 'register-export':
            digest(args.receipts)
            result = register_export(state, json.loads(args.receipts.read_text(encoding='utf-8-sig')), args.recovery)
            # State belongs exclusively to this capture; verify original state bytes
            # again before updating its known, independently checked export metadata.
            require(digest(args.state) == original_state, 'Capture state changed during output verification')
            args.state.write_text(json.dumps(state, indent=2), encoding='utf-8')
        elif args.mode == 'seal':
            result = seal(state, args.stopped)
            with seal_path.open('x', encoding='utf-8') as stream:
                json.dump(result, stream, indent=2)
        else:
            digest(seal_path)
            result = cleanup(state, json.loads(seal_path.read_text()), args.stopped)
    print(json.dumps(result))


if __name__ == '__main__':
    main()
