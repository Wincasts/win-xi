#!/usr/bin/env python3
"""Trace where a map's ground can be walked, for the mapoverlay addon.

A map paints the ground that can be walked in smooth colours inside dark lines, on mottled
parchment. From points inside that ground (the seeds), this fills outward to the lines; where a map
paints all its ground one colour (or a few), "colors" fills every enclosed patch painted the colour
of those points instead. Lettering, icons and leader lines drawn over the ground are closed over, and
the edge is grown to take in the dark line round it. The result is a mask, two pixels to a map unit,
written to addons/mapoverlay/data/walkable.lua as runs along each row.

    python3 tools/trace_walkable_maps.py references/XICombinedMaps-2048 [--preview DIR] [--only KEY]

Seeds file (addons/mapoverlay/research/walkable.json), every point in 512-reference map units:
    {"maps": {map_key: {"zone": id, "floor": id, "index": client map table entry, "dat": "ROM/17/47.DAT",
                        "seeds": [[x, y], ...],    fill out from each point to the lines round it
                        "light": n,                the seeds fill only what is at least this light
                                                   (0-255, after the grid is taken out), stopping at
                                                   ink: for streets drawn in lines on parchment
                        "colors": [[x, y] | {"rgb": [r, g, b]}, ...],   every enclosed patch painted
                                                   the colour at a point, or that colour
                        "within": [[x, y], ...] | {"circle": [x, y, radius]},   keep only what lies inside
                        "walls": [[[x, y], [x, y], ...], ...],   lines drawn on the map first, to close
                                                   an opening the fill would run out of (a zone's exit)
                        "drop": [[x, y], ...],     the part of the ground at each point taken away
                                                   (parchment fenced by the grid, near the ground's colour)
                        "add": [polygon, ...], "cut": [polygon, ...],   ground given or taken by hand
                        "paths": [{"points": [[x, y], ...], "width": w}, ...],   a street given by
                                                   hand, w map units wide along its middle
                        "tolerance": how far from a point's colour a fill goes on (80): past the
                                                   map's faint grid, not past its dark lines,
                                        "match": how near a patch's colour must be to count (20),
                        "cell": a patch no wider or taller than this is dropped (17 map units),
                        "join": how wide a line over the ground is closed (3 pixels),
                        "edge": how far the ground is grown over its line (2 pixels),
                        "min_area": parts smaller than this are dropped (200 square pixels),
                        "hole": holes smaller than this are filled (900 square pixels)}}}
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from scan_combined_maps import decode

WORK = 1024           # Pixels across the mask: two to a map unit.
SENTINEL = (255, 0, 255)
INK = (60, 30, 10)


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


def grown(mask, rounds):
    for _ in range(rounds):
        mask = grow(mask)
    return mask


def close(mask, rounds):
    """Fills lines narrower than twice rounds drawn across the ground."""
    return ~grown(~grown(mask, rounds), rounds)


def open_mask(mask, rounds):
    """Drops what is narrower than twice rounds: specks of parchment near the ground's colour."""
    return grown(~grown(~mask, rounds), rounds)


def parts(mask):
    """Each connected part of the mask, as a mask of its own."""
    canvas = Image.fromarray(mask.astype(np.uint8) * 255, 'L')
    remaining = mask.copy()
    while remaining.any():
        y, x = np.unravel_index(np.argmax(remaining), remaining.shape)
        filled = canvas.copy()
        ImageDraw.floodfill(filled, (int(x), int(y)), 128)
        part = np.asarray(filled) == 128
        remaining &= ~part
        yield part


def fill_holes(mask, largest):
    """Holes in the ground no larger than largest (an icon, lettering) filled; larger ones (the
    parchment a loop of corridor goes round) kept."""
    padded = np.pad(mask, 1)
    canvas = Image.fromarray((~padded).astype(np.uint8) * 255, 'L').copy()
    ImageDraw.floodfill(canvas, (0, 0), 0)
    holes = np.asarray(canvas)[1:-1, 1:-1] == 255
    out = mask.copy()
    for hole in parts(holes):
        if hole.sum() <= largest:
            out |= hole
    return out


def smooth(pixels, radius=2, most=12):
    """Pixels whose neighbourhood barely varies: painted ground, not mottled parchment."""
    grey = pixels.astype(float).mean(axis=2)
    def box(values):
        total = np.pad(values, radius + 1, mode='edge').cumsum(0).cumsum(1)
        size = 2 * radius + 1
        sums = total[size:, size:] - total[:-size, size:] - total[size:, :-size] + total[:-size, :-size]
        return sums[:values.shape[0], :values.shape[1]] / (size * size)
    mean = box(grey)
    return np.sqrt(np.maximum(box(grey * grey) - mean * mean, 0)) <= most


def painted(image, pixels, points, tolerance, match, within=None, cell=17, step=6, largest=0.08):
    """Every enclosed patch painted the colour at one of the points: filled from each pixel on a
    lattice that is that colour, unless the fill runs out over the parchment (larger than largest of
    the map), its colour on the whole is not the ground's (parchment ringed by a corridor), or it
    would fit in one square of the map's grid (cell map units across): a square of light parchment
    fenced by the grid's lines. Those are given back apart: a room the grid's lines cut into pieces
    takes them back where they touch it across no more than a grid line."""
    wide = pixels.astype(int)
    colours = [np.array(p['rgb']) if isinstance(p, dict) else wide[y, x]
               for p, (x, y) in ((p, (0, 0) if isinstance(p, dict) else representative(pixels, int(p[0] * WORK / 512), int(p[1] * WORK / 512)))
                                 for p in points)]
    even = smooth(pixels)
    near = np.zeros((WORK, WORK), bool)
    for colour in colours:
        near |= np.abs(wide - colour).sum(axis=2) <= match
    near &= even
    if within:
        near &= polygon_mask(within)
    seen = np.zeros((WORK, WORK), bool)
    ground = np.zeros((WORK, WORK), bool)
    small = []
    for y in range(0, WORK, step):
        for x in range(0, WORK, step):
            if not near[y, x] or seen[y, x]:
                continue
            filled = image.copy()
            ImageDraw.floodfill(filled, (x, y), SENTINEL, thresh=tolerance)
            patch = (np.asarray(filled) == SENTINEL).all(axis=2)
            seen |= patch
            if patch.sum() > largest * WORK * WORK:
                continue
            mean = wide[patch].mean(axis=0)
            if min(np.abs(mean - colour).sum() for colour in colours) > match:
                continue
            ys, xs = np.nonzero(patch)
            if max(xs.max() - xs.min(), ys.max() - ys.min()) <= cell * WORK / 512:
                small.append(patch)
            else:
                ground |= patch
    # A grid line is a pixel or two across; a wall, with the parchment beyond it, more.
    taken = True
    while taken and small:
        near = grown(ground, 2)
        taken = [patch for patch in small if (patch & near).any()]
        small = [patch for patch in small if not (patch & near).any()]
        for patch in taken:
            ground |= patch
    return ground


def light_fill(full, seeds, light, ink=100, largest=0.03):
    """For a map drawn in lines (a city's streets): from each seed, the ground painted lighter than
    the parchment around it, within the dark lines. Read from the whole picture, where a line of
    ink (darker than ink) and one of the faint grid (lighter, and thinner) can be told apart: a
    median over 7 pixels takes the grid's lines out and leaves the ink to stop the fill. A seed whose
    fill runs larger than largest of the map has found its way out onto the parchment, and is
    left out."""
    size = full.size[0]
    grey = full.convert('L')
    raw = np.asarray(grey)
    even = np.asarray(grey.filter(ImageFilter.MedianFilter(7)))
    passable = (raw >= ink) & (even >= light)
    canvas = Image.fromarray(passable.astype(np.uint8) * 255, 'L').copy()
    k, reach = size / 512, int(1.5 * size / 512)
    for x, y in seeds:
        cx, cy = int(x * k), int(y * k)
        window = passable[max(0, cy - reach):cy + reach + 1, max(0, cx - reach):cx + reach + 1]
        ys, xs = np.nonzero(window)
        if len(xs) == 0:
            print(f'  seed {x}, {y} is on nothing light enough', file=sys.stderr)
            continue
        nearest = np.argmin((xs - reach) ** 2 + (ys - reach) ** 2)
        px, py = max(0, cx - reach) + int(xs[nearest]), max(0, cy - reach) + int(ys[nearest])
        if canvas.getpixel((px, py)) != 255:
            continue
        trial = canvas.copy()
        ImageDraw.floodfill(trial, (px, py), 64)
        spread = np.asarray(trial) == 64
        if spread.mean() > largest:
            print(f'  seed {x}, {y} runs out onto the parchment ({spread.mean() * 100:.1f}% of the map)', file=sys.stderr)
            continue
        ImageDraw.floodfill(canvas, (px, py), 128)
    filled = Image.fromarray((np.asarray(canvas) == 128).astype(np.uint8) * 255, 'L')
    return np.asarray(filled.resize((WORK, WORK), Image.Resampling.BOX)) >= 128


def scaled(points):
    return [(x * WORK / 512, y * WORK / 512) for x, y in points]


def polygon_mask(points):
    canvas = Image.new('L', (WORK, WORK), 0)
    if isinstance(points, dict):
        (x, y), r = scaled([points['circle'][:2]])[0], points['circle'][2] * WORK / 512
        ImageDraw.Draw(canvas).ellipse((x - r, y - r, x + r, y + r), fill=255)
    else:
        ImageDraw.Draw(canvas).polygon(scaled(points), fill=255)
    return np.asarray(canvas) == 255


def trace(image, spec, full=None):
    """The mask of walkable ground on one map, WORK pixels square; full is the whole picture, for
    "light"."""
    image = image.copy()
    pen = ImageDraw.Draw(image)
    for wall in spec.get('walls', []):
        pen.line(scaled(wall), fill=INK, width=3)
    if full is not None and spec.get('walls'):
        full = full.copy()
        pen, k = ImageDraw.Draw(full), full.size[0] / 512
        for wall in spec['walls']:
            pen.line([(x * k, y * k) for x, y in wall], fill=INK, width=max(3, int(1.5 * k)))
    pixels = np.asarray(image)
    tolerance = spec.get('tolerance', 80)
    ground = np.zeros((WORK, WORK), bool)
    if spec.get('light'):
        ground |= light_fill(full, spec.get('seeds', []), spec['light'])
    for seed in ([] if spec.get('light') else spec.get('seeds', [])):
        x, y = representative(pixels, int(seed[0] * WORK / 512), int(seed[1] * WORK / 512))
        filled = image.copy()
        ImageDraw.floodfill(filled, (int(x), int(y)), SENTINEL, thresh=tolerance)
        ground |= (np.asarray(filled) == SENTINEL).all(axis=2)
    if spec.get('colors'):
        ground |= painted(image, pixels, spec['colors'], tolerance, spec.get('match', 20), spec.get('within'), spec.get('cell', 17))
    if spec.get('within'):
        ground &= polygon_mask(spec['within'])
    for point in spec.get('drop', []):
        x, y = int(point[0] * WORK / 512), int(point[1] * WORK / 512)
        if ground[y, x]:
            canvas = Image.fromarray(ground.astype(np.uint8) * 255, 'L').copy()
            ImageDraw.floodfill(canvas, (x, y), 128)
            ground &= np.asarray(canvas) != 128
    ground = close(np.pad(ground, 8), spec.get('join', 3))[8:-8, 8:-8]
    least = spec.get('min_area', 200)
    kept = np.zeros_like(ground)
    for part in parts(ground):
        if part.sum() >= least:
            kept |= part
    ground = fill_holes(kept, spec.get('hole', 900))
    ground = grown(ground, spec.get('edge', 2))
    for points in spec.get('add', []):
        ground |= polygon_mask(points)
    for path in spec.get('paths', []):
        canvas = Image.new('L', (WORK, WORK), 0)
        width = int(round(path['width'] * WORK / 512))
        ImageDraw.Draw(canvas).line(scaled(path['points']), fill=255, width=width, joint='curve')
        ground |= np.asarray(canvas) == 255
    for points in spec.get('cut', []):
        ground &= ~polygon_mask(points)
    return ground


def runs(row):
    """A row as the lengths of its runs, out of the ground first: '' for a row with none."""
    if not row.any():
        return ''
    changes = np.flatnonzero(np.diff(np.concatenate(([False], row, [False])).astype(np.int8)))
    edges = [0] + changes.tolist()
    if edges[-1] < len(row):
        edges.append(len(row))
    lengths = [b - a for a, b in zip(edges, edges[1:])]
    while lengths and lengths[-1] == 0:
        lengths.pop()
    return ','.join(str(n) for n in lengths)


def lua_map(key, spec, mask):
    rows = [f'[{y}]=\'{runs(mask[y])}\'' for y in range(WORK) if mask[y].any()]
    return (f'    [\'{key}\'] = {{ zone = {spec["zone"]}, floor = {spec["floor"]}, index = {spec["index"]}, '
            f'dat = \'{spec["dat"]}\',\n      rows = {{ {", ".join(rows)} }} }},\n')


def preview(image, mask):
    """The map as the overlay shows it: the ground, the rest faint, on a dark ground of its own."""
    shown = Image.new('RGB', image.size, (30, 34, 40))
    faint = Image.blend(shown, image, 0.18)
    alpha = Image.fromarray(mask.astype(np.uint8) * 255, 'L')
    return Image.composite(image, faint, alpha)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('pack', type=Path)
    parser.add_argument('--seeds', type=Path, default=Path('addons/mapoverlay/research/walkable.json'))
    parser.add_argument('--out', type=Path, default=Path('addons/mapoverlay/data/walkable.lua'))
    parser.add_argument('--preview', type=Path, help='Write each map as the overlay would show it')
    parser.add_argument('--only', help='Trace this map key alone, for a preview; nothing is written')
    args = parser.parse_args()

    maps = json.loads(args.seeds.read_text())['maps']
    chunks = []
    for key in sorted(maps):
        spec = maps[key]
        if args.only and key != args.only:
            continue
        full = decode((args.pack / spec['dat']).read_bytes()).convert('RGB')
        image = full.resize((WORK, WORK), Image.Resampling.LANCZOS)
        mask = trace(image, spec, full)
        share = mask.mean() * 100
        print(f'{key}: {share:.1f}% walkable', file=sys.stderr)
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            preview(image, mask).save(args.preview / f'{key}.png')
        chunks.append(lua_map(key, spec, mask))
    if args.only:
        return
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text('-- Generated by tools/trace_walkable_maps.py from research/walkable.json: do not edit.\n'
                        '-- Each map\'s walkable ground, ' + str(WORK) + ' pixels square, two to a map unit: for each row\n'
                        '-- with any, the lengths of its runs, out of the ground first.\n'
                        f'return {{\n  width = {WORK},\n  maps = {{\n' + ''.join(chunks) + '  },\n};\n')


if __name__ == '__main__':
    main()
