#!/usr/bin/env python3
"""Export Mark's selected XICombinedMaps rasters at native resolution (Pillow required).

Unlike Zoneinfo's editor previews, these images are never resized. Source DAT hashes
and existing catalog filenames ensure the artwork retains the same map alignment.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from scan_combined_maps import decode

ROOT = Path(__file__).resolve().parents[1]


def export_maps(pack, catalog, source_manifest, output):
    wanted = set(re.findall(r"image\s*=\s*['\"]([^'\"]+)['\"]", catalog.read_text()))
    if not wanted:
        raise ValueError('No map images in Mark catalog')
    if any(Path(name).name != name or '/' in name or '\\' in name or not name.endswith('.jpg') for name in wanted):
        raise ValueError('Map images must be plain .jpg filenames')
    sources = {}
    for record in json.loads(source_manifest.read_text())['maps']:
        name = Path(record['image']).name
        if name in wanted:
            if name in sources:
                raise ValueError(f'Duplicate source image: {name}')
            sources[name] = record
    missing = wanted - sources.keys()
    if missing:
        raise ValueError('No source mapping for: ' + ', '.join(sorted(missing)))

    output.mkdir(parents=True, exist_ok=True)
    exported, sizes = [], Counter()
    for name in sorted(wanted):
        record = sources[name]
        dat = Path(record['dat'])
        if dat.is_absolute() or '..' in dat.parts:
            raise ValueError(f'Invalid DAT path: {dat}')
        data = (pack / dat).read_bytes()
        if hashlib.sha256(data).hexdigest() != record['sha256']:
            raise ValueError(f'Source DAT hash mismatch: {dat}')
        with decode(data) as image:
            if image.width != image.height:
                raise ValueError(f'Non-square map: {dat}')
            # Preserve the complete native raster, without crop, rotation or resampling.
            image.convert('RGB').save(output / name, quality=95, subsampling=0, optimize=True)
            size = list(image.size)
        sizes[tuple(size)] += 1
        exported.append(dict(image=name, dat=dat.as_posix(), sha256=record['sha256'],
                             zone_id=record['zone_id'], floor_id=record['floor_id'], size=size))
    manifest = dict(source_pack=pack.name, reference_size=512, resized=False,
                    encoding='JPEG quality 95, no chroma subsampling',
                    summary=dict(maps=len(exported), sizes={f'{w}x{h}': count for (w, h), count in sorted(sizes.items())}),
                    maps=exported)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pack', nargs='?', type=Path, default=ROOT / 'references/XICombinedMaps-2048')
    parser.add_argument('--catalog', type=Path, default=ROOT / 'addons/mark/data/maps.lua')
    parser.add_argument('--source-manifest', type=Path, default=ROOT / 'addons/zoneinfo/assets/maps/all/manifest.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'addons/mark/assets/maps')
    args = parser.parse_args()
    result = export_maps(args.pack, args.catalog, args.source_manifest, args.output)
    print(json.dumps(result['summary'], indent=2))


if __name__ == '__main__':
    main()
