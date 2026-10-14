#!/usr/bin/env python3
"""Prepare three preview rasters for zoneinfo's experimental debug overlay.

python3 tools/prepare_zoneinfo_poc_maps.py references/XICombinedMaps-2048
Images are resized for display, never used to derive world coordinates.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image
from scan_combined_maps import decode

MAPS = {100: 'ROM/17/24.DAT', 103: 'ROM/17/27.DAT', 107: 'ROM/17/31.DAT'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pack', type=Path)
    parser.add_argument('--output', type=Path, default=Path('addons/zoneinfo/assets/maps'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    for zone, dat in MAPS.items():
        data = (args.pack / dat).read_bytes()
        image = decode(data)
        image.resize((1024, 1024), Image.Resampling.LANCZOS).save(args.output / f'{zone}.png')
        records.append({
            'zone_id': zone, 'dat': dat, 'sha256': hashlib.sha256(data).hexdigest(),
            'texture': data[57:65].decode('ascii'), 'source_size': list(image.size),
            'preview_size': [1024, 1024], 'image': f'{zone}.png',
        })
    (args.output / 'manifest.json').write_text(json.dumps({
        'source_pack': args.pack.name, 'map_reference_size': 512,
        'note': 'Debug previews of supplied community-map rasters; not world calibration or area validation.',
        'maps': records,
    }, indent=2) + '\n')
    print(f'Prepared {len(records)} previews in {args.output}')


if __name__ == '__main__':
    main()
