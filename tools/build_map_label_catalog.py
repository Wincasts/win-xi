#!/usr/bin/env python3
"""Build all-zone research coverage and a reviewed-only Lua table from map OCR.

The OCR manifest is never promoted directly into runtime landmarks. Explicit
per-raster visual reviews supply those names; pending OCR stays in the catalogue.
Zones with no supplied raster are listed separately from reviewed empty maps.
"""
import argparse
import ast
import collections
import json
import re
from pathlib import Path


LUA_STRING = r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')'''


def zone_names(path):
    """Read the generated one-record-per-line Boussole resource table, not arbitrary Lua."""
    result = {}
    pattern = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{\s*id\s*=\s*\d+,\s*en\s*=\s*' + LUA_STRING)
    for line in path.read_text().splitlines():
        match = pattern.match(line)
        if match:
            result[int(match[1])] = ast.literal_eval(match[2])
    if not result:
        raise ValueError(f'No zone names found in {path}')
    return result


def normalize(text):
    return re.sub(r'[^a-z0-9]', '', text.casefold())


def candidate_lines(record, known_names, confidence=55):
    """Filter obvious noise and merge exact text across passes, preserving sightings."""
    grouped = {}
    for variant in record['ocr']:
        for line in variant['lines']:
            text = line['text'].strip()
            if line['confidence'] < confidence or not re.search(r'[A-Za-z]{3}', text):
                continue
            if re.search(r'https?://|www\.|\.com\b|\.co\.jp\b|remapster|mapster', text, re.I):
                continue
            key = normalize(text)
            category = 'zone_title_or_destination' if key in known_names else 'unclassified'
            if category == 'unclassified' and re.search(
                r'\b(river|creek|brook|lake|pond|spring|falls|hill|hillock|ridge|glen|'
                r'dunes|sands|pass|valley|lagoon|isle|island|square|alley|street|'
                r'bridge|chamber|garden|waterway|landing|watchtower)\b|marsh\b', text, re.I
            ):
                category = 'possible_area_label'
            item = grouped.setdefault(key, {
                'text': text, 'confidence': line['confidence'], 'category_hint': category,
                'review_status': 'unreviewed', 'sightings': [],
            })
            if line['confidence'] > item['confidence']:
                item['text'], item['confidence'] = text, line['confidence']
            item['sightings'].append({'variant': variant['variant'], 'text_box': line['box']})
    return list(grouped.values())


def build_catalog(manifest, names, reviews):
    by_dat = {}
    for record in manifest['maps']:
        for dat in [record['dat'], *record['duplicate_dats']]:
            by_dat[dat] = record
    visual = {}
    for review in reviews['maps']:
        if review['dat'] not in by_dat:
            raise ValueError(f'Review DAT not in extracted manifest: {review["dat"]}')
        canonical = by_dat[review['dat']]['dat']
        if canonical in visual:
            raise ValueError(f'Multiple reviews for the same raster: {canonical}')
        visual[canonical] = review

    known = {normalize(name) for name in names.values()}
    grouped = collections.defaultdict(list)
    for record in sorted(manifest['maps'], key=lambda r: (r['zone_id'], r['map_index'], r['dat'])):
        review = visual.get(record['dat'])
        labels = review['labels'] if review else []
        candidates = candidate_lines(record, known)
        confirmed = {normalize(label['name']) for label in labels}
        for candidate in candidates:
            if normalize(candidate['text']) in confirmed:
                candidate['review_status'] = 'text_matches_reviewed_label'
                # This confirms spelling, not the OCR box as a feature location.
        item = {k: record[k] for k in ('dat', 'texture', 'map_index', 'sha256', 'image', 'width', 'height', 'duplicate_dats')}
        item.update({
            'review_status': review['review_status'] if review else 'pending_visual_review',
            'reviewed_labels': labels, 'ocr_candidates': candidates,
        })
        if review and review.get('note'):
            item['review_note'] = review['note']
        grouped[record['zone_id']].append(item)

    errors = collections.defaultdict(list)
    for error in manifest.get('decode_errors', []):
        errors[int(error['texture'][2:5])].append(error)
    zones = []
    for zone in sorted(set(names) | set(grouped) | set(errors)):
        maps = grouped[zone]
        reviewed = sum(m['review_status'] != 'pending_visual_review' for m in maps)
        status = 'no_map_in_pack'
        if maps:
            status = 'extracted_pending_review' if not reviewed else 'selected_rasters_reviewed'
        if errors[zone]:
            status = 'decode_errors'
        unique_labels = sorted({l['name'] for m in maps for l in m['reviewed_labels']})
        zones.append({
            'zone_id': zone, 'zone_name': names.get(zone, f'Zone {zone}'),
            'coverage_status': status, 'unique_rasters': len(maps),
            'reviewed_rasters': reviewed, 'reviewed_names': unique_labels,
            'maps': maps, 'decode_errors': errors[zone],
        })
    summary = {
        'scanned_dats': manifest['scanned_dats'],
        'zone_map_dats': sum(1 + len(m['duplicate_dats']) for m in manifest['maps'])
                         + sum(1 + len(e.get('duplicate_dats', [])) for e in manifest.get('decode_errors', [])),
        'unique_rasters': len(manifest['maps']),
        'duplicate_dats': sum(len(m['duplicate_dats']) for m in manifest['maps']),
        'zones_with_maps': sum(bool(z['maps']) for z in zones), 'known_zones': len(zones),
        'zones_without_maps': sum(not z['maps'] and not z['decode_errors'] for z in zones),
        'decode_errors': len(manifest.get('decode_errors', [])),
        'reviewed_rasters': sum(z['reviewed_rasters'] for z in zones),
        'zones_with_reviewed_names': sum(bool(z['reviewed_names']) for z in zones),
        'reviewed_zone_name_pairs': sum(len(z['reviewed_names']) for z in zones),
        'reviewed_label_entries': sum(len(m['reviewed_labels']) for z in zones for m in z['maps']),
        'ocr_candidates': sum(len(m['ocr_candidates']) for z in zones for m in z['maps']),
    }
    return {
        'source_pack': manifest['source_pack'], 'summary': summary,
        'review_scope': reviews['scope'],
        'warning': 'Research only. Full extraction is not full visual review. OCR text boxes are not feature locations. No world calibration or verified boundaries.',
        'unmatched_dats': manifest.get('unmatched_dats', []), 'zones': zones,
    }


def compact_records(document, key):
    """Keep one complete record per line without megabytes of indentation."""
    header = {k: v for k, v in document.items() if k != key}
    return json.dumps(header, indent=2, ensure_ascii=False)[:-2] + ',\n  "' + key + '": [\n' + ',\n'.join(
        '    ' + json.dumps(record, ensure_ascii=False, separators=(',', ':'))
        for record in document[key]
    ) + '\n  ]\n}\n'


def lua_string(value):
    return json.dumps(value, ensure_ascii=False)


def write_lua(catalog, path):
    lines = [
        '-- Generated by tools/build_map_label_catalog.py from raster OCR + explicit visual reviews.',
        '-- Only reviewed map text appears in landmarks; OCR candidates remain in the research catalogue.',
        '-- Empty landmarks can mean pending review, NOT that the zone has no named places.',
        '-- Optional map_x/map_y are approximate feature anchors in 0..512 image space.',
        '-- Names without anchors still need feature localization; no world coordinates or boundaries.',
        'return {',
        "    source_pack = 'XICombinedMaps-2048',",
        "    coordinate_space = 'map_image_512',",
        '    world_calibrated = false, boundaries_verified = false,',
        '    maps = {',
    ]
    for zone in catalog['zones']:
        for record in zone['maps']:
            lines += [
                '        {',
                f'            zone_id = {zone["zone_id"]}, zone_name = {lua_string(zone["zone_name"])},',
                f'            dat = {lua_string(record["dat"])}, texture = {lua_string(record["texture"])},',
                f'            width = {record["width"]}, height = {record["height"]},',
                f'            review_status = {lua_string(record["review_status"])},',
                '            landmarks = {',
            ]
            for label in record['reviewed_labels']:
                fields = [f'name = {lua_string(label["name"])}', f'kind = {lua_string(label["kind"])}']
                for key in ('map_x', 'map_y'):
                    if key in label:
                        fields.append(f'{key} = {label[key]}')
                lines.append('                { ' + ', '.join(fields) + ' },')
            lines += ['            },', '        },']
    lines += ['    },', '    zones_without_maps = {']
    for zone in catalog['zones']:
        if zone['coverage_status'] == 'no_map_in_pack':
            lines.append(f'        {{ zone_id = {zone["zone_id"]}, zone_name = {lua_string(zone["zone_name"])} }},')
    lines += ['    },', '}']
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n')


def markdown(catalog):
    s = catalog['summary']
    lines = [
        '# All-zone map-label catalogue', '',
        f'{s["scanned_dats"]} DATs scanned; {s["zone_map_dats"]} zone-map DATs; '
        f'{s["unique_rasters"]} unique rasters; {s["duplicate_dats"]} duplicates; '
        f'{s["zones_with_maps"]} mapped zones; {s["decode_errors"]} decode errors.', '',
        f'{s["known_zones"]} zones in the available resource registry; '
        f'{s["zones_without_maps"]} have no map in this pack. This does not mean no map exists in the game.', '',
        f'{s["reviewed_rasters"]} rasters have a selected-label visual review; '
        f'{s["reviewed_zone_name_pairs"]} reviewed zone/name pairs in '
        f'{s["zones_with_reviewed_names"]} zones. Review is not exhaustive.', '',
        '**Research only: no world calibration or verified area boundaries.**', '',
        catalog['review_scope'], '',
        'The candidate text below is UNREVIEWED unless it exactly matches a reviewed name. '
        'Hints are heuristic, not classifications: they can still contain mobs, exits, legends and OCR errors. '
        'Split lines have not been guessed or joined. An empty review list is not proof of absence.', '',
        '| ID | Zone | Rasters | Reviewed rasters | Reviewed names | Coverage |',
        '| --- | --- | ---: | ---: | ---: | --- |',
    ]
    for zone in catalog['zones']:
        lines.append(f'| {zone["zone_id"]} | {zone["zone_name"]} | {zone["unique_rasters"]} | '
                     f'{zone["reviewed_rasters"]} | {len(zone["reviewed_names"])} | {zone["coverage_status"]} |')
    for zone in catalog['zones']:
        if not zone['maps']:
            continue
        lines += ['', f'## {zone["zone_id"]}: {zone["zone_name"]}', '',
                  '**Reviewed names:** ' + ('; '.join(zone['reviewed_names']) or 'None recorded yet.'), '']
        for record in zone['maps']:
            lines += [f'### {record["texture"]} — `{record["dat"]}`', '',
                      f'Review: `{record["review_status"]}`; raster: `{record["image"]}` '
                      f'({record["width"]}×{record["height"]}).', '']
            if record['duplicate_dats']:
                lines += ['Identical DATs: ' + ', '.join(f'`{p}`' for p in record['duplicate_dats']), '']
            if record.get('review_note'):
                lines += [record['review_note'], '']
            lines += ['<details><summary>OCR candidate text (not approved area names)</summary>', '',
                      '| Text | Confidence | Hint | Review |', '| --- | ---: | --- | --- |']
            for candidate in record['ocr_candidates']:
                text = candidate['text'].replace('|', '\\|').replace('<', '&lt;').replace('>', '&gt;')
                lines.append(f'| {text} | {candidate["confidence"]:.1f} | {candidate["category_hint"]} | {candidate["review_status"]} |')
            lines += ['', '</details>', '']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--zone-names', type=Path, default=Path('references/boussole/data/zones.lua'))
    parser.add_argument('--reviews', type=Path, default=Path('addons/zoneinfo/research/map_label_reviews.json'))
    parser.add_argument('--lua-output', type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    catalog = build_catalog(manifest, zone_names(args.zone_names), json.loads(args.reviews.read_text()))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'combined_maps_ocr.json').write_text(compact_records(manifest, 'maps'))
    (args.output / 'map_label_catalog.json').write_text(compact_records(catalog, 'zones'))
    (args.output / 'map_label_catalog.md').write_text(markdown(catalog))
    reviewed_rows = [
        '# Reviewed map-area names', '',
        'Generated from explicit per-raster visual reviews. These are community-map labels, not necessarily official names.',
        'Includes geography and city areas/landmarks. Not exhaustive; no calibrated world positions or boundaries.', '',
        '| ID | Zone | Reviewed names |', '| --- | --- | --- |',
    ]
    for zone in catalog['zones']:
        if zone['reviewed_names']:
            reviewed_rows.append(f'| {zone["zone_id"]} | {zone["zone_name"]} | ' + '; '.join(zone['reviewed_names']) + ' |')
    (args.output / 'map_subregions_reviewed.md').write_text('\n'.join(reviewed_rows) + '\n')
    if args.lua_output:
        write_lua(catalog, args.lua_output)
    print(json.dumps(catalog['summary'], indent=2))


if __name__ == '__main__':
    main()
