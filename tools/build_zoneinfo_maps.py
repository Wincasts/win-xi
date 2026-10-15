#!/usr/bin/env python3
"""Build all-raster editor coverage and explicitly heuristic feature polygons.

Uses reviewed names only. OCR boxes are approximate *localization hints*, never
proof of terrain extent. Unlocalized names and unnamed maps get disabled drafts.
"""
import argparse
import difflib
import hashlib
import json
import math
import re
from pathlib import Path
from PIL import Image
from scan_combined_maps import decode
from refine_zoneinfo_boundaries import apply_refinements, load_refinements


def floor_indices(path):
    return {int(zone): {int(floor): int(index) for floor, index in re.findall(r'\[(\d+)\] = (\d+)', block)}
            for zone, block in re.findall(r'\[(\d+)\] = \{(.*?)\n    \}', path.read_text(), re.S)}


def normalized(text):
    return re.sub(r'[^a-z0-9]', '', text.lower())


def anchor(label, record, ordinal, total):
    if 'map_x' in label and 'map_y' in label:
        return label['map_x'], label['map_y'], 'reviewed_feature_anchor', True
    target = normalized(label['name'])
    words = re.findall(r'[a-z]+', label['name'].lower())
    distinctive = [w for w in words if len(w) >= 5 and w not in {
        'river', 'sands', 'square', 'street', 'spring', 'waterway', 'lighthouse', 'landing', 'entrance'}]
    best = None
    for candidate in record['ocr_candidates']:
        text = normalized(candidate['text'])
        if not text:
            continue
        full = difflib.SequenceMatcher(None, target, text).ratio()
        unique = max((difflib.SequenceMatcher(None, w, text).ratio() for w in distinctive), default=0)
        score = max(full, unique * .94)
        if score >= .72 and (best is None or score > best[0]):
            sightings = candidate['sightings']
            if sightings:
                box = sightings[0]['text_box']
                best = score, (box[0] + box[2] / 2) * 512 / record['width'], (box[1] + box[3] / 2) * 512 / record['height']
    if best:
        return best[1], best[2], 'ocr_label_hint_NOT_feature_extent', True
    columns = max(1, math.ceil(math.sqrt(total)))
    rows = max(1, math.ceil(total / columns))
    return 64 + 384 * ((ordinal % columns) + .5) / columns, 64 + 384 * ((ordinal // columns) + .5) / rows, 'unlocalized_editor_template', False


def guessed_polygon(name, kind, x, y):
    words = set(re.findall(r'[a-z]+', (name + ' ' + kind).lower()))
    if words & {'river', 'creek', 'brook', 'waterway'}:
        rx, ry = 60, 14
    elif words & {'lake', 'marsh', 'swamp'}:
        rx, ry = 40, 30
    elif words & {'street', 'road', 'avenue', 'bridge'}:
        rx, ry = 40, 12
    elif words & {'crag'}:
        rx, ry = 45, 42
    elif words & {'hill', 'ridge', 'mount', 'mountain', 'mountains', 'tor', 'valley'}:
        rx, ry = 42, 34
    elif words & {'sands', 'dunes', 'beach', 'coast'}:
        rx, ry = 38, 28
    elif words & {'pond', 'spring', 'fountain', 'well'}:
        rx, ry = 18, 14
    else:
        rx, ry = 26, 22
    x, y = max(rx + 1, min(511 - rx, x)), max(ry + 1, min(511 - ry, y))
    return [[round(x + rx * dx, 3), round(y + ry * dy, 3)]
            for dx, dy in [(-.65, -1), (.65, -1), (1, -.65), (1, .65), (.65, 1), (-.65, 1), (-1, .65), (-1, -.65)]]


def lua(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (float, int)):
        return str(value)
    if isinstance(value, list):
        return '{' + ', '.join(lua(v) for v in value) + '}'
    return '{' + ', '.join(f'{key} = {lua(v)}' for key, v in value.items()) + '}'


def build(catalog, indices):
    maps = []
    for zone in catalog['zones']:
        for record in zone['maps']:
            key = f"{zone['zone_id']:03d}_{record['texture']}_{record['sha256'][:12]}"
            areas = []
            for i, label in enumerate(record['reviewed_labels']):
                x, y, method, enabled = anchor(label, record, i, len(record['reviewed_labels']))
                areas.append(dict(id=re.sub(r'[^a-z0-9]+', '_', label['name'].lower()).strip('_'),
                                  name=label['name'], enabled=enabled, provenance=method,
                                  polygon=guessed_polygon(label['name'], label['kind'], x, y)))
            if not areas:
                areas.append(dict(id='draft_area', name='Unnamed draft area', enabled=False,
                                  provenance='no_reviewed_names_editor_only', polygon=[[96, 96], [416, 96], [416, 416], [96, 416]]))
            maps.append(dict(key=key, zone_id=zone['zone_id'], name=zone['zone_name'], floor_id=record['map_index'],
                             table_index=indices.get(zone['zone_id'], {}).get(record['map_index']),
                             client_floor_count=len(indices.get(zone['zone_id'], {})),
                             texture=record['texture'], dat=record['dat'], sha256=record['sha256'],
                             image=f'maps/all/{key}.jpg', review_status=record['review_status'], areas=areas))
    return maps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pack', type=Path)
    parser.add_argument('--catalog', type=Path, default=Path('addons/zone/research/map_label_catalog.json'))
    parser.add_argument('--floors', type=Path, default=Path('references/boussole/data/zonesFloors.lua'))
    parser.add_argument('--addon', type=Path, default=Path('addons/zone'))
    parser.add_argument('--refinements', type=Path, default=Path('addons/zone/research/boundary_refinements.json'))
    parser.add_argument('--defaults-only', action='store_true', help='Refresh polygons/manifest without re-encoding existing previews')
    args = parser.parse_args()
    refinements = load_refinements(args.refinements)
    maps = apply_refinements(build(json.loads(args.catalog.read_text()), floor_indices(args.floors)), refinements)
    output = args.addon / 'assets/maps/all'
    output.mkdir(parents=True, exist_ok=True)
    manifest = []
    for record in maps:
        destination = args.addon / 'assets' / record['image']
        if not args.defaults_only:
            data = (args.pack / record['dat']).read_bytes()
            if hashlib.sha256(data).hexdigest() != record['sha256']:
                raise ValueError(f"Source DAT hash mismatch: {record['dat']}")
            image = decode(data)
            image.convert('RGB').resize((512, 512), Image.Resampling.LANCZOS).save(destination, quality=90, optimize=True)
        elif not destination.exists():
            raise ValueError(f'Missing preview; rerun without --defaults-only: {destination}')
        manifest.append({k: record[k] for k in ('key', 'zone_id', 'floor_id', 'dat', 'sha256', 'image')})
    text = '-- Generated by tools/build_zoneinfo_maps.py. UNVERIFIED heuristic boundaries.\n'
    text += '-- Every unique supplied raster is editable. Disabled drafts are not announced.\nreturn {\n'
    text += ''.join('    ' + lua(record) + ',\n' for record in maps) + '};\n'
    (args.addon / 'data/all_maps.lua').write_text(text)
    # Apply after the original POC merge too, so those defaults reflect player examples.
    (args.addon / 'data/boundary_refinements.lua').write_text(
        '-- Generated from research/boundary_refinements.json; raster-specific, unverified geometry.\nreturn {\n'
        + ''.join('    ' + lua(patch) + ',\n' for patch in refinements['areas']) + '};\n')
    summary = dict(maps=len(maps), zones=len({m['zone_id'] for m in maps}),
                   areas=sum(len(m['areas']) for m in maps),
                   located_named_drafts=sum(a['enabled'] for m in maps for a in m['areas']),
                   client_index_matched=sum(m['table_index'] is not None for m in maps))
    (output / 'manifest.json').write_text(json.dumps(dict(summary=summary, note='512-reference previews; bounds and OCR localizations are heuristic, not verified.', maps=manifest), indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
