#!/usr/bin/env python3
"""Trace city buildings from the map artwork into zoneinfo refinements.

The maps draw a building as a patch of one colour inside a dark outline. Given a point inside each
labelled building (research/building_seeds.json), this fills outward from that point to the
outline, takes the patch's edge as the building's polygon, and writes it to
research/boundary_refinements.json as an exact area: one announced on stepping inside, with no
approach distance. A building the artwork does not fill is given as a polygon by hand.

    python3 tools/trace_zoneinfo_buildings.py references/XICombinedMaps-2048 [--preview DIR] [--only KEY]

Seeds file: {"fills": {map_key: [x, y]},
             "maps": {map_key: [{"name": ..., "box": [x0, y0, x1, y1]} | {"name": ..., "seed": [x, y]}
                              | {"name": ..., "seeds": [[x, y], ...]} | {"name": ..., "polygon": [[x, y], ...]}, ...]}}
A box holds one building and keeps its neighbours out; "fills" gives a point on a building of each
map that uses boxes, for the colour buildings are painted there; "tolerances" {map_key: n} narrows or
widens how near that colour counts on a map (60 unless given).
in 512-reference map coordinates. Optional per building: "id", "enabled", "tolerance" (how far from
the seed's colour the fill goes on), "clip" [x0, y0, x1, y1] (keep the part of the patch inside this
box), "join" (how wide a line between two seeded parts is bridged, in half units).
"""
import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from refine_zoneinfo_boundaries import valid_polygon
from scan_combined_maps import decode

METHOD = 'building_footprint_traced_from_map_fill'
WORK = 1024           # Pixels across the image the tracing is done at: two to a map unit.
SENTINEL = (255, 0, 255)


def slug(name):
    return re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')


def representative(pixels, x, y, radius=3):
    """The pixel near (x, y) whose colour is most typical of its surroundings: not lettering or a line."""
    x0, y0 = max(0, x - radius), max(0, y - radius)
    window = pixels[y0:y + radius + 1, x0:x + radius + 1].astype(int)
    median = np.median(window.reshape(-1, 3), axis=0)
    distance = np.abs(window - median).sum(axis=2)
    dy, dx = np.unravel_index(np.argmin(distance), distance.shape)
    return x0 + dx, y0 + dy


def grow(mask):
    out = mask.copy()
    out[1:, :] |= mask[:-1, :]; out[:-1, :] |= mask[1:, :]
    out[:, 1:] |= mask[:, :-1]; out[:, :-1] |= mask[:, 1:]
    return out


def close(mask, rounds):
    """Fills lettering and leader lines drawn across a building."""
    grown = mask
    for _ in range(rounds):
        grown = grow(grown)
    shrunk = ~grown
    for _ in range(rounds):
        shrunk = grow(shrunk)
    return ~shrunk


def connected(mask, x, y):
    """The part of the mask joined to (x, y)."""
    reached = np.zeros_like(mask)
    reached[y, x] = mask[y, x]
    while True:
        larger = grow(reached) & mask
        if larger.sum() == reached.sum():
            return reached
        reached = larger


def keep_component(mask, x, y):
    """The connected part of the mask nearest (x, y): closing can leave specks beside the building."""
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return mask
    nearest = np.argmin((xs - x) ** 2 + (ys - y) ** 2)
    return connected(mask, int(xs[nearest]), int(ys[nearest]))


def fill_holes(mask):
    padded = np.pad(mask, 1)
    return ~connected(~padded, 0, 0)[1:-1, 1:-1]


def outline(mask):
    """The outer edge of a single filled shape, as corner points in pixel units, in order."""
    padded = np.pad(mask, 1)
    following = {}
    def edges(where, start, end):
        ys, xs = np.nonzero(where)
        for x, y in zip(xs.tolist(), ys.tolist()):
            following.setdefault((x + start[0], y + start[1]), []).append((x + end[0], y + end[1]))
    # Each edge between a filled pixel and an empty one, walked with the shape on the right.
    edges(padded[1:, :] & ~padded[:-1, :], (0, 1), (1, 1))        # Empty above: east.
    edges(padded[:, :-1] & ~padded[:, 1:], (1, 0), (1, 1))        # Empty to the right: south.
    edges(padded[:-1, :] & ~padded[1:, :], (1, 1), (0, 1))        # Empty below: west.
    edges(padded[:, 1:] & ~padded[:, :-1], (1, 1), (1, 0))        # Empty to the left: north.
    start = min(following, key=lambda p: (p[1], p[0]))
    points, here, heading = [], start, (1, 0)
    for _ in range(len(following) * 2 + 4):
        points.append((here[0] - 1, here[1] - 1))
        choices = following[here]
        # Where two parts of the shape touch at a corner, keep to the right: stay with this part.
        def turn(target):
            dx, dy = target[0] - here[0], target[1] - here[1]
            return {1: 0, 0: 1, -1: 2}[heading[0] * dy - heading[1] * dx] if (dx, dy) != (-heading[0], -heading[1]) else 3
        target = min(choices, key=turn)
        heading, here = (target[0] - here[0], target[1] - here[1]), target
        if here == start:
            break
    return points


def simplify(points, tolerance):
    """Douglas-Peucker on a closed ring."""
    def reduce(segment):
        if len(segment) < 3:
            return segment
        (ax, ay), (bx, by) = segment[0], segment[-1]
        dx, dy = bx - ax, by - ay
        length = (dx * dx + dy * dy) ** .5 or 1
        distances = [abs(dy * (px - ax) - dx * (py - ay)) / length for px, py in segment[1:-1]]
        worst = max(range(len(distances)), key=distances.__getitem__)
        if distances[worst] <= tolerance:
            return [segment[0], segment[-1]]
        return reduce(segment[:worst + 2])[:-1] + reduce(segment[worst + 1:])
    far = max(range(len(points)), key=lambda i: (points[i][0] - points[0][0]) ** 2 + (points[i][1] - points[0][1]) ** 2)
    ring = reduce(points[:far + 1])[:-1] + reduce(points[far:] + [points[0]])[:-1]
    return ring


def trace(image, seeds, tolerance=70, clip=None, reach=45, join=3):
    """The polygon, in 512-reference units, of the patch of artwork around the seeds, and a note if
    it looks wrong. Each seed is filled outward to the dark lines around it; a building the artwork
    divides with a line takes a seed in each part, and the parts are joined across the line.
    clip (x0, y0, x1, y1) keeps what lies inside a box, where a patch has no line on one side."""
    scale = WORK / 512
    xs = [p[0] for p in seeds]; ys = [p[1] for p in seeds]
    box = clip or (min(xs) - reach, min(ys) - reach, max(xs) + reach, max(ys) + reach)
    x0, y0 = max(0, int(box[0] * scale) - 8), max(0, int(box[1] * scale) - 8)
    x1, y1 = min(WORK, int(box[2] * scale) + 9), min(WORK, int(box[3] * scale) + 9)
    window = image.crop((x0, y0, x1, y1))
    pixels = np.asarray(window)
    local = np.zeros(pixels.shape[:2], bool)
    first = None
    for seed in seeds:
        x, y = representative(pixels, int(round(seed[0] * scale)) - x0, int(round(seed[1] * scale)) - y0)
        first = first or (x, y)
        filled = window.copy()
        ImageDraw.floodfill(filled, (x, y), SENTINEL, thresh=tolerance)
        local |= (np.asarray(filled) == SENTINEL).all(axis=2)
    local = close(np.pad(local, 8), join)[8:-8, 8:-8]
    if clip:
        inside = np.zeros_like(local)
        inside[max(0, int(round(clip[1] * scale)) - y0):int(round(clip[3] * scale)) - y0 + 1,
               max(0, int(round(clip[0] * scale)) - x0):int(round(clip[2] * scale)) - x0 + 1] = True
        local &= inside
    local = np.pad(local, 2)  # An empty edge, so the outline closes where the window cut the patch.
    x0, y0 = x0 - 2, y0 - 2
    local = fill_holes(keep_component(local, first[0] + 2, first[1] + 2))
    note = None
    ys, xs = np.nonzero(local)
    if len(xs) == 0 or local.sum() < 8 * scale * scale:
        return None, 'almost nothing filled: move the seed'
    if not clip and (xs.min() <= 2 or ys.min() <= 2 or xs.max() >= local.shape[1] - 3 or ys.max() >= local.shape[0] - 3):
        note = 'fill runs on past a building: give a clip box'
    ring = outline(local)
    polygon = None
    for epsilon in (1.2, 1.8, 2.6, 4.0):
        candidate = [[round(float(px + x0) / scale, 1), round(float(py + y0) / scale, 1)] for px, py in simplify(ring, epsilon)]
        candidate = [p for i, p in enumerate(candidate) if p != candidate[i - 1]]
        if 3 <= len(candidate) <= 40 and valid_polygon(candidate):
            polygon = candidate
            break
    if polygon is None:
        note = 'could not make a simple polygon: give one by hand'
    return polygon, note


def open_mask(mask, rounds):
    """Drops what is thinner than a wall and a floor together: leader lines, icons' edges."""
    shrunk = ~mask
    for _ in range(rounds):
        shrunk = grow(shrunk)
    grown = ~shrunk
    for _ in range(rounds):
        grown = grow(grown)
    return grown


def trace_box(image, box, fill, tolerance=60, join=4):
    """The polygon of the building inside box (x0, y0, x1, y1). The maps paint buildings one colour
    (fill) and streets another, so the building is what is painted that colour inside the box: joined
    across the lines drawn through it, its largest piece taken, and grown out to its wall. The box
    only has to hold the building and keep its neighbours out."""
    scale = WORK / 512
    x0, y0, x1, y1 = (int(round(v * scale)) for v in box)
    pixels = np.asarray(image.crop((x0, y0, x1, y1))).astype(int)
    painted = np.abs(pixels - np.asarray(fill, int)).sum(axis=2) <= tolerance
    # Joined across the lines drawn through it; then anything thinner than a room goes (the map's
    # grid lines and the edges of icons can be near the same colour).
    local = open_mask(close(np.pad(painted, 10), join), 4)
    x0, y0 = x0 - 10, y0 - 10
    if not local.any():
        return None, 'nothing painted as a building in the box'
    best, remaining = None, local.copy()
    while remaining.any():
        ys, xs = np.nonzero(remaining)
        piece = connected(remaining, int(xs[0]), int(ys[0]))
        if best is None or piece.sum() > best.sum():
            best = piece
        remaining &= ~piece
    local = grow(grow(fill_holes(best)))  # Out over the wall line, so the doorway itself is inside.
    note = None
    ys, xs = np.nonzero(local)
    if local.sum() < 10 * scale * scale:
        note = 'very little painted as a building in the box'
    ring = outline(local)
    for epsilon in (1.2, 1.8, 2.6, 4.0):
        candidate = [[round(float(px + x0) / scale, 1), round(float(py + y0) / scale, 1)] for px, py in simplify(ring, epsilon)]
        candidate = [p for i, p in enumerate(candidate) if p != candidate[i - 1]]
        if 3 <= len(candidate) <= 40 and valid_polygon(candidate):
            return candidate, note
    return None, 'could not make a simple polygon: give one by hand'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('pack', type=Path)
    parser.add_argument('--seeds', type=Path, default=Path('addons/zoneinfo/research/building_seeds.json'))
    parser.add_argument('--refinements', type=Path, default=Path('addons/zoneinfo/research/boundary_refinements.json'))
    parser.add_argument('--manifest', type=Path, default=Path('addons/zoneinfo/assets/maps/all/manifest.json'))
    parser.add_argument('--preview', type=Path, help='Write each map with its traced buildings drawn on it')
    parser.add_argument('--only', help='Trace this map key alone (others keep what they had)')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    source = json.loads(args.seeds.read_text())
    seeds, floors = source['maps'], {}
    document = json.loads(args.refinements.read_text())
    dats = {m['key']: m['dat'] for m in json.loads(args.manifest.read_text())['maps']}
    patches = {(p['map_key'], p['area_id']): p for p in document['areas']}
    order = [(p['map_key'], p['area_id']) for p in document['areas']]
    problems = 0
    for key, buildings in seeds.items():
        if args.only and key != args.only:
            continue
        # Buildings dropped from the seeds file go from the refinements too.
        wanted = {b.get('id') or slug(b['name']) for b in buildings}
        for stale in [k for k in order if k[0] == key and patches[k]['method'] == METHOD and k[1] not in wanted]:
            order.remove(stale); del patches[stale]
        image = decode((args.pack / dats[key]).read_bytes()).convert('RGB').resize((WORK, WORK), Image.Resampling.LANCZOS)
        # The colour buildings are painted on this map: sampled at "fills" [x, y], a point on one.
        point = source.get('fills', {}).get(key)
        if point:
            sample = np.asarray(image)
            fx, fy = representative(sample, int(point[0] * WORK / 512), int(point[1] * WORK / 512))
            floors[key] = sample[fy, fx].tolist()
        drawn = []
        for building in buildings:
            area_id = building.get('id') or slug(building['name'])
            note = None
            if 'polygon' in building:
                polygon = [[float(x), float(y)] for x, y in building['polygon']]
                if not valid_polygon(polygon):
                    polygon, note = None, 'hand polygon is not a simple polygon inside the map'
            elif 'box' in building:
                polygon, note = trace_box(image, building['box'], floors[key], building.get('tolerance', source.get('tolerances', {}).get(key, 60)),
                                          building.get('join', 4))
            else:
                polygon, note = trace(image, building.get('seeds') or [building['seed']], building.get('tolerance', 70),
                                      building.get('clip'), join=building.get('join', 3))
            if note:
                problems += 1
                print(f'{key} | {building["name"]}: {note}', file=sys.stderr)
            if polygon is None:
                continue
            drawn.append((building['name'], polygon, note))
            existing = patches.get((key, area_id))
            patch = dict(map_key=key, area_id=area_id, name=building['name'], enabled=building.get('enabled', True),
                         polygon=polygon, method=METHOD, exact=True)
            # A building the label review already listed is reshaped; any other is added.
            if existing is None or existing.get('add'):
                patch['add'] = True
            if (key, area_id) not in patches:
                order.append((key, area_id))
            patches[(key, area_id)] = patch
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            canvas = image.copy()
            pen = ImageDraw.Draw(canvas)
            for number, (name, polygon, note) in enumerate(drawn, 1):
                points = [(x * WORK / 512, y * WORK / 512) for x, y in polygon]
                pen.line(points + [points[0]], fill=(255, 0, 0) if note else (0, 90, 255), width=2)
                cx, cy = sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)
                pen.text((cx, cy), str(number), fill=(255, 255, 255), anchor='mm', stroke_width=2, stroke_fill=(0, 0, 0))
            canvas.save(args.preview / f'{key}.png')
            print(key, '|', '; '.join(f'{n}={name}' for n, (name, _, _) in enumerate(drawn, 1)))
    if not args.dry_run:
        document['areas'] = [patches[k] for k in order]
        args.refinements.write_text(json.dumps(document, indent=1) + '\n')
    print(f'{sum(p["method"] == METHOD for p in patches.values())} buildings in the refinements; {problems} to look at')


if __name__ == '__main__':
    main()
