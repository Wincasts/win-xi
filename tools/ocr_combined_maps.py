#!/usr/bin/env python3
"""Decode XICombinedMaps DATs and inventory raster text (not runtime areas).

Requires Pillow, Tesseract, and its English language data. Example:
  python tools/ocr_combined_maps.py references/XICombinedMaps-2048 /tmp/map-ocr \
      --zones 100 101 102 103 104 106 107 108 109 110 190

Omit --zones to scan the whole pack. Identical DATs are OCR'd once. Outputs
rasters plus a JSON manifest with provenance and word/line pixel boxes.
Use --jobs N for concurrency and --resume to reuse hash-matched checkpoints.
OCR boxes locate TEXT, not the landmark its leader line points to.
"""
import argparse
import csv
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import os
import re
import subprocess
from pathlib import Path

from PIL import ImageOps

from scan_combined_maps import decode


def parse_tsv(text):
    """Retain recognized words, grouped by Tesseract's line identifiers."""
    groups = {}
    for row in csv.DictReader(io.StringIO(text), delimiter='\t', quoting=csv.QUOTE_NONE):
        if row['level'] != '5' or not row.get('text', '').strip():
            continue
        word = {
            'text': row['text'].strip(),
            'confidence': float(row['conf']),
            'box': [int(row[k]) for k in ('left', 'top', 'width', 'height')],
        }
        key = tuple(row[k] for k in ('page_num', 'block_num', 'par_num', 'line_num'))
        groups.setdefault(key, []).append(word)
    lines = []
    for words in groups.values():
        left = min(w['box'][0] for w in words)
        top = min(w['box'][1] for w in words)
        right = max(w['box'][0] + w['box'][2] for w in words)
        bottom = max(w['box'][1] + w['box'][3] for w in words)
        lines.append({
            'text': ' '.join(w['text'] for w in words),
            'box': [left, top, right - left, bottom - top],
            'confidence': round(sum(w['confidence'] for w in words) / len(words), 2),
            'words': words,
        })
    return lines


def recognize(image_path, tessdata_dir=None):
    command = ['tesseract', str(image_path), 'stdout', '-l', 'eng', '--psm', '11']
    if tessdata_dir:
        command += ['--tessdata-dir', str(tessdata_dir)]
    # Use the parameter directly: custom tessdata directories may lack configs/tsv.
    command += ['-c', 'tessedit_create_tsv=1']
    env = dict(os.environ, OMP_THREAD_LIMIT='1')
    result = subprocess.run(command, capture_output=True, text=True, check=True, env=env)
    return parse_tsv(result.stdout)


def extract_record(path, pack, output, texture, digest, tessdata_dir, resume):
    relative = path.relative_to(pack).as_posix()
    image_name = relative.replace('/', '_').replace('.DAT', '.png')
    cache = output / 'records' / image_name.replace('.png', '.json')
    if resume and cache.exists():
        record = json.loads(cache.read_text())
        if record.get('sha256') == digest and record.get('texture') == texture:
            record['duplicate_dats'] = []
            return record
    try:
        image = decode(path.read_bytes())
    except (ValueError, OSError) as error:
        return {'dat': relative, 'texture': texture, 'error': str(error)}
    image.save(output / image_name)
    gray_name = image_name.replace('.png', '_gray.png')
    ImageOps.autocontrast(ImageOps.grayscale(image)).save(output / gray_name)
    record = {
        'zone_id': int(texture[2:5]), 'map_index': int(texture[6:8]),
        'texture': texture, 'dat': relative, 'duplicate_dats': [],
        'sha256': digest, 'image': image_name,
        'width': image.width, 'height': image.height,
        'ocr': [
            {'variant': 'original', 'lines': recognize(output / image_name, tessdata_dir)},
            {'variant': 'autocontrast_gray', 'lines': recognize(output / gray_name, tessdata_dir)},
        ],
    }
    temporary = cache.with_suffix('.tmp')
    temporary.write_text(json.dumps(record) + '\n')
    temporary.replace(cache)
    print(f'{texture}: {relative} ({sum(len(p["lines"]) for p in record["ocr"])} OCR lines)', flush=True)
    return record


def scan(pack, output, zones=None, tessdata_dir=None, jobs=1, resume=False):
    output.mkdir(parents=True, exist_ok=True)
    (output / 'records').mkdir(exist_ok=True)
    records, errors, seen, tasks, unmatched = [], [], {}, [], []
    scanned = 0
    for path in sorted(pack.rglob('*.DAT')):
        scanned += 1
        with path.open('rb') as stream:
            prefix = stream.read(65)
        texture = prefix[57:65].decode('ascii', errors='replace')
        match = re.fullmatch(r'm_(\d{3})_(\d{2})', texture)
        if not match:
            unmatched.append({'dat': path.relative_to(pack).as_posix(), 'texture': texture})
            continue
        if zones is not None and int(match[1]) not in zones:
            continue
        relative = path.relative_to(pack).as_posix()
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest in seen:
            seen[digest]['duplicates'].append(relative)
            continue
        task = {'path': path, 'texture': texture, 'digest': digest, 'duplicates': []}
        seen[digest] = task
        tasks.append(task)

    def process(task):
        record = extract_record(task['path'], pack, output, task['texture'], task['digest'], tessdata_dir, resume)
        record['duplicate_dats'] = task['duplicates']
        return record

    # executor.map retains deterministic DAT order even when jobs finish out of order.
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        for record in executor.map(process, tasks):
            (errors if 'error' in record else records).append(record)
    manifest = {
        'source_pack': pack.name, 'scanned_dats': scanned,
        'zones_requested': sorted(zones) if zones is not None else None,
        'method': 'Pillow DXT/indexed BITMAP decode; Tesseract English sparse text (PSM 11)',
        'coordinate_space': 'native raster pixels, origin top-left',
        'warning': 'Unreviewed OCR: includes titles, exits, mobs, quest labels and errors. Text boxes are not area boundaries or world coordinates.',
        'maps': records, 'decode_errors': errors, 'unmatched_dats': unmatched,
    }
    (output / 'ocr_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pack', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--zones', nargs='+', type=int)
    parser.add_argument('--tessdata-dir', type=Path)
    parser.add_argument('--jobs', type=int, default=1, help='Concurrent map workers (each OCR process uses one thread)')
    parser.add_argument('--resume', action='store_true', help='Reuse completed per-map OCR records with matching DAT hashes')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    if not args.pack.is_dir():
        parser.error(f'Map pack does not exist: {args.pack}')
    try:
        manifest = scan(args.pack, args.output, set(args.zones) if args.zones else None, args.tessdata_dir, args.jobs, args.resume)
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'OCR failed: {error}\n{getattr(error, "stderr", "")}\nInstall Tesseract and English traineddata, or use --tessdata-dir.\n')
    print(f'Extracted {len(manifest["maps"])} unique maps; {len(manifest["decode_errors"])} decode errors.')


if __name__ == '__main__':
    main()
