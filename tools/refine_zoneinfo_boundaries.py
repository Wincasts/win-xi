#!/usr/bin/env python3
"""Apply versioned, raster-specific boundary exemplars/refinements to generated defaults.

No live files are modified. Refinement JSON is an explicit authoring input;
source hash/map keys prevent inheritance across past/alternate/floor artwork.
"""
import json
import math
from pathlib import Path


def valid_polygon(polygon):
    if not isinstance(polygon, list) or not 3 <= len(polygon) <= 64:
        return False
    if any(not isinstance(p, list) or len(p) != 2 or any(type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 512 for v in p) for p in polygon):
        return False
    def cross(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    def on(a, b, p):
        return abs(cross(a, b, p)) < 1e-6 and min(a[0], b[0]) <= p[0] <= max(a[0], b[0]) and min(a[1], b[1]) <= p[1] <= max(a[1], b[1])
    area = 0
    for i, a in enumerate(polygon):
        b = polygon[(i + 1) % len(polygon)]
        if abs(a[0] - b[0]) + abs(a[1] - b[1]) < .01:
            return False
        area += a[0] * b[1] - b[0] * a[1]
        for j in range(i + 1, len(polygon)):
            if j == i + 1 or (i == 0 and j == len(polygon) - 1):
                continue
            c, d = polygon[j], polygon[(j + 1) % len(polygon)]
            if (cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0) or on(a, b, c) or on(a, b, d) or on(c, d, a) or on(c, d, b):
                return False
    return abs(area) >= 1


def apply_refinements(maps, source):
    lookup = {m['key']: m for m in maps}
    for patch in source['areas']:
        if patch['map_key'] not in lookup:
            raise ValueError(f"Unknown refinement raster: {patch['map_key']}")
        record = lookup[patch['map_key']]
        area = next((a for a in record['areas'] if a['id'] == patch['area_id']), None)
        if area is None and patch.get('add') is True:
            # A feature the label review did not list: named and drawn here, on this raster only.
            if not isinstance(patch.get('name'), str) or not patch['name'].strip():
                raise ValueError(f"Added refinement area needs a name: {patch['area_id']}")
            area = {'id': patch['area_id'], 'name': patch['name']}
            record['areas'].append(area)
        if area is None:
            raise ValueError(f"Unknown refinement area: {patch['area_id']}")
        polygon = patch['polygon']
        if not valid_polygon(polygon):
            raise ValueError('Invalid refinement polygon')
        if type(patch['enabled']) is not bool:
            raise ValueError('Refinement must specify a boolean detection flag')
        area['polygon'] = polygon
        if 'name' in patch:
            area['name'] = patch['name']
        area['enabled'] = patch['enabled']
        area['provenance'] = patch['method']
        if patch.get('exact') is True:
            area['exact'] = True  # A building: entered by stepping inside, with no approach distance.
        else:
            area.pop('exact', None)
    return maps


def load_refinements(path=Path('addons/zone/research/boundary_refinements.json')):
    return json.loads(path.read_text())
