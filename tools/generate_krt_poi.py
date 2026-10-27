#!/usr/bin/env python3
"""Generate a first-pass King Ranperre's Tomb sub-zone/POI table.

This is intentionally data-mining oriented rather than hand-authored. It uses the server's
region polygons (which are derived from the map/navmesh walkable areas) and spawn regions
to create named sector points suitable for an addon fallback. The zone's regions.yaml and
mobs.yaml are read as live loads them: fetched by tools/phoenix and patched by the modules
(phoenix.modules.load_yaml).
"""
from __future__ import annotations

import collections
import math
from pathlib import Path

from phoenix import modules, source

ZONE = 'king_ranperres_tomb'
OUT = Path(__file__).resolve().parents[1] / 'addons/zone/data/king_ranperres_tomb_poi.lua'

DIR_NAMES = {
    'n': 'North', 's': 'South', 'e': 'East', 'w': 'West', 'c': 'Central',
    'ne': 'Northeast', 'nw': 'Northwest', 'se': 'Southeast', 'sw': 'Southwest',
    'region': 'Deep Tomb',
}

EXIT_POIS = [
    dict(id='exit_east_ronfaure_west', name='West entrance to East Ronfaure', x=-130.011, y=-3.772, z=260.750, kind='exit', to_zone=101, to_zone_name='East Ronfaure'),
    dict(id='exit_east_ronfaure_east', name='East entrance to East Ronfaure', x=59.815, y=4.162, z=305.710, kind='exit', to_zone=101, to_zone_name='East Ronfaure'),
    dict(id='exit_jugner_forest', name='Jugner Forest exit', x=250.585, y=3.163, z=340.224, kind='exit', to_zone=104, to_zone_name='Jugner Forest'),
]


def polygon_area_xz(poly):
    area = 0.0
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        area += p[0] * q[2] - q[0] * p[2]
    return abs(area) / 2.0


def centroid(poly):
    # Area-weighted centroid in x/z plane; y is averaged.
    signed = 0.0
    cx = cz = 0.0
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        cross = p[0] * q[2] - q[0] * p[2]
        signed += cross
        cx += (p[0] + q[0]) * cross
        cz += (p[2] + q[2]) * cross
    if abs(signed) < 1e-6:
        return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly), sum(p[2] for p in poly) / len(poly))
    return (cx / (3 * signed), sum(p[1] for p in poly) / len(poly), cz / (3 * signed))


def clean_name(template):
    name = template
    for suffix in ('_KRT', '_war', '_blm'):
        name = name.replace(suffix, '')
    return name.replace('_', ' ')


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    source.add_arguments(parser)
    found = source.from_arguments(parser.parse_args())
    print(f'Server: {found.describe()}')
    regions_doc = modules.load_yaml(found.path, f'zones/{ZONE}/regions')
    mobs_doc = modules.load_yaml(found.path, f'zones/{ZONE}/mobs')

    region_mobs = collections.defaultdict(collections.Counter)
    template_counts = collections.Counter()
    for spawn_id, spawn in mobs_doc['spawns'].items():
        template = spawn.get('template')
        region = spawn.get('region')
        if template:
            template_counts[template] += 1
        if template and region:
            region_mobs[region][clean_name(template)] += 1

    subzones = []
    for rid, data in regions_doc['regions'].items():
        poly = data['poly']
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        zs = [p[2] for p in poly]
        cx, cy, cz = centroid(poly)
        prefix = rid.rsplit('_', 1)[0]
        direction = DIR_NAMES.get(prefix, prefix.upper())
        mobs = region_mobs.get(rid, collections.Counter())
        top_mobs = [dict(name=name, count=count) for name, count in mobs.most_common(4)]
        mob_label = ', '.join(m['name'] for m in top_mobs[:2])
        label = f'{direction} sector {rid.rsplit("_", 1)[-1]}' + (f' - {mob_label}' if mob_label else '')
        subzones.append(dict(
            id=rid,
            name=label,
            direction=direction,
            x=round(cx, 2), y=round(cy, 2), z=round(cz, 2),
            min_x=round(min(xs), 2), max_x=round(max(xs), 2),
            min_y=round(min(ys), 2), max_y=round(max(ys), 2),
            min_z=round(min(zs), 2), max_z=round(max(zs), 2),
            area=round(polygon_area_xz(poly), 1),
            mobs=top_mobs,
        ))

    # Named/rare mob POIs: use the centroid of their declared region when available.
    by_region = {z['id']: z for z in subzones}
    pois = list(EXIT_POIS)
    for spawn_id, spawn in mobs_doc['spawns'].items():
        template = spawn.get('template')
        region = spawn.get('region')
        if not template or template_counts[template] > 3 or region not in by_region:
            continue
        z = by_region[region]
        pois.append(dict(
            id=f'mob_{spawn_id}', kind='named_mob', name=clean_name(template),
            x=z['x'], y=z['y'], z=z['z'], region=region,
        ))

    # Deduplicate named mobs by name+region.
    seen = set(); deduped = []
    for p in pois:
        key = (p.get('kind'), p.get('name'), p.get('region'), p.get('to_zone'))
        if key in seen:
            continue
        seen.add(key); deduped.append(p)

    subzones.sort(key=lambda r: (r['direction'], r['id']))
    deduped.sort(key=lambda p: (p['kind'], p['name']))

    def lua_value(v, indent=0):
        pad = ' ' * indent
        if isinstance(v, str):
            return repr(v).replace('\\', '\\\\')
        if isinstance(v, bool):
            return 'true' if v else 'false'
        if isinstance(v, (int, float)):
            return str(v)
        if isinstance(v, list):
            if not v:
                return '{}'
            return '{\n' + ',\n'.join(pad + '    ' + lua_value(x, indent + 4) for x in v) + '\n' + pad + '}'
        if isinstance(v, dict):
            if not v:
                return '{}'
            parts = []
            for k, val in v.items():
                parts.append(pad + '    ' + str(k) + ' = ' + lua_value(val, indent + 4))
            return '{\n' + ',\n'.join(parts) + '\n' + pad + '}'
        raise TypeError(type(v))

    data = dict(
        zone_id=190,
        zone_name="King Ranperre's Tomb",
        note=f'Generated from {source.NAME} regions.yaml/mobs.yaml (as the modules patch them, {found.commit[:9]}) plus zoneline data; intended as a first-pass sub-zone/POI table.',
        subzones=subzones,
        pois=deduped,
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text('return ' + lua_value(data) + '\n')
    print(f'wrote {OUT} ({len(subzones)} subzones, {len(deduped)} POIs)')


if __name__ == '__main__':
    main()
