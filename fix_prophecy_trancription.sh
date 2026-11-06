#!/usr/bin/env bash
# Targeted transcription corrections. Requires Python 3; no extra packages.
# Run in the transcript folder: bash fix_prophecy_transcription.sh
# Preview: bash fix_prophecy_transcription.sh --dry-run
# Or supply explicit TXT/VTT filenames after the optional --dry-run flag.
set -euo pipefail
command -v python3 >/dev/null || { echo "Python 3 is required." >&2; exit 1; }
python3 - "$@" <<'PYTHON'
import sys, re, os, shutil, tempfile, difflib
from pathlib import Path
from datetime import datetime

RULES = [('\\bEke(?=\\s+(?:Flyxion|Homo)\\b)', 'Ecce'), ('\\bFlexium\\b', 'Flyxion'), ('\\bthe formalists steps in\\b', 'the formalist steps in'), ('\\b(?:Fleishy|Philaxian)\\b', 'Flyxion'), ('And, flags and argues', 'And Flyxion argues'), ('\\b(?:myriology|mariology)\\b', 'mereology'), ('parts and the holes they form', 'parts and the wholes they form'), ('\\ba fantasia\\b', 'aphantasia'), ('\\ban endophagia\\b', 'anendophasia'), ('reality behind the blaster', 'reality behind the plaster'), ('\\bGeorge Spencer Brown\\b', 'George Spencer-Brown'), ('digital letter experiment', 'digital ledger experiment'), ('I sifted the flower', 'I sifted the flour'), ('something every day\\.', 'something everyday.'), ('\\bpet computer\\b', 'PET computer')]

args = sys.argv[1:]
dry_run = '--dry-run' in args
args = [x for x in args if x != '--dry-run']
paths = [Path(x) for x in (args or [
    'A_Self-Refuting_Prophecy.txt',
    'A_Self-Refuting_Prophecy.vtt',
])]
# Validate every input before changing any file.
for p in paths:
    if p.is_symlink() or not p.is_file():
        raise SystemExit(f'Expected an ordinary file (not a symlink): {p}')
    if p.suffix.lower() not in ('.txt', '.vtt'):
        raise SystemExit(f'Expected a .txt or .vtt file: {p}')

stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
log = [f'Prophecy transcript corrections: {stamp}',
       'Only spelling/terminology corrected; factual/editorial claims unchanged.']
changes = []
for p in paths:
    raw = p.read_bytes()
    original = raw.decode('utf-8-sig')
    lines = original.splitlines(keepends=True)
    corrected = []
    counts = {}
    for line in lines:
        # VTT metadata, cue IDs, and timing lines never pass through replacements.
        if p.suffix.lower() == '.vtt' and (
            '-->' in line or line.strip().isdigit() or
            line.startswith(('WEBVTT', 'NOTE', 'STYLE', 'REGION'))):
            corrected.append(line)
            continue
        for pattern, replacement in RULES:
            line, n = re.subn(pattern, replacement, line)
            if n:
                counts[(pattern, replacement)] = counts.get((pattern, replacement), 0) + n
        corrected.append(line)
    updated = ''.join(corrected)
    if p.suffix.lower() == '.vtt':
        assert [x for x in lines if '-->' in x] == [x for x in corrected if '-->' in x]
        assert len(lines) == len(corrected)
        assert [i for i,x in enumerate(lines) if not x.strip()] == [i for i,x in enumerate(corrected) if not x.strip()]
    total = sum(counts.values())
    print(f'{p}: {total} replacement(s)' + (' [preview]' if dry_run else ''))
    log.append(f'\n{p}: {total} replacement(s)')
    for (pattern, replacement), n in counts.items():
        log.append(f'  {pattern!r} -> {replacement!r}: {n}')
    if updated != original:
        delta = ''.join(difflib.unified_diff(original.splitlines(True), updated.splitlines(True), fromfile=str(p), tofile=str(p)+' (corrected)'))
        log.append(delta)
        if dry_run:
            print(delta)
        payload = updated.encode('utf-8')
        if raw.startswith(b'\xef\xbb\xbf'):
            payload = b'\xef\xbb\xbf' + payload
        changes.append((p, payload))

if dry_run:
    raise SystemExit(0)
# Make all backups before the first edit. Existing backups are never overwritten.
for p, payload in changes:
    backup = p.with_name(p.name + '.bak.' + stamp)
    if backup.exists():
        raise SystemExit(f'Backup already exists: {backup}')
    shutil.copy2(p, backup)
    print(f'Backup: {backup}')
for p, payload in changes:
    fd, name = tempfile.mkstemp(prefix='.'+p.name+'.', dir=p.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(payload)
        shutil.copymode(p, name)
        os.replace(name, p)
    finally:
        if os.path.exists(name):
            os.unlink(name)
if changes:
    logfile = Path('prophecy_corrections.'+stamp+'.log')
    logfile.write_text('\n'.join(log)+'\n', encoding='utf-8')
    print(f'Log: {logfile}')
else:
    print('No changes needed.')
PYTHON

