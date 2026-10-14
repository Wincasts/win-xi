#!/usr/bin/env python3
"""Find a zone by texture name and decode its DXT/indexed map DATs (Pillow required).
Usage: python tools/scan_combined_maps.py MAP_PACK ZONE_ID OUTPUT_DIR
Writes a manifest recording DAT path, SHA256, texture name and raster size.
"""
import argparse
import hashlib
import io
import json
import re
import struct
from pathlib import Path
from PIL import Image


def decode(data):
    header_at = 0x41
    size, width, height, planes, bits, compression, image_size, rx, ry, used, important, kind = struct.unpack_from('<IiiHHIIIIIII', data, header_at)
    fourcc = {0x44585431: b'DXT1', 0x44585433: b'DXT3', 0x44585435: b'DXT5'}.get(kind)
    if size != 40 or planes != 1 or not (0 < width <= 8192 and 0 < height <= 8192):
        raise ValueError('Unsupported map image header')
    if kind == 10 and bits == 8:
        # Indexed BITMAP: a 44-byte header, 256 BGRA palette entries, then
        # bottom-up byte indices. No DXT-specific extra eight bytes here.
        palette_at = header_at + 44
        pixels_at = palette_at + 1024
        length = width * height
        if len(data) < pixels_at + length:
            raise ValueError('Truncated indexed bitmap payload')
        palette = data[palette_at:pixels_at]
        rgb = [channel for i in range(256) for channel in
               (palette[i * 4 + 2], palette[i * 4 + 1], palette[i * 4])]
        image = Image.frombytes('P', (width, height), data[pixels_at:pixels_at + length])
        image.putpalette(rgb)
        return image.transpose(Image.Transpose.FLIP_TOP_BOTTOM).convert('RGB')
    if not fourcc:
        raise ValueError('Unsupported map image header')
    # FFXI stores DXT tags reversed relative to DDS FourCC; payload follows
    # the 44-byte image header and 8 additional bytes (see boussole texture.lua).
    payload_at = header_at + 44 + 8
    length = ((width + 3) // 4) * ((height + 3) // 4) * (8 if fourcc == b'DXT1' else 16)
    if len(data) < payload_at + length:
        raise ValueError('Truncated DXT payload')
    dds = b'DDS ' + struct.pack('<7I', 124, 0x81007, height, width, length, 0, 0)
    dds += bytes(44) + struct.pack('<II4s5I', 32, 4, fourcc, 0, 0, 0, 0, 0)
    dds += struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    image = Image.open(io.BytesIO(dds + data[payload_at:payload_at + length]))
    image.load()
    return image.convert('RGB')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('pack', type=Path)
    p.add_argument('zone', type=int)
    p.add_argument('output', type=Path)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    scanned = 0
    for path in sorted(args.pack.rglob('*.DAT')):
        scanned += 1
        with path.open('rb') as f:
            prefix = f.read(65)
        name = prefix[57:65].decode('ascii', errors='replace')
        if not re.fullmatch(rf'm_{args.zone:03d}_\d\d', name):
            continue
        data = path.read_bytes()
        image = decode(data)
        rel = path.relative_to(args.pack).as_posix()
        output = rel.replace('/', '_').replace('.DAT', '.png')
        image.save(args.output / output)
        records.append(dict(dat=rel, texture=name, sha256=hashlib.sha256(data).hexdigest(), image=output, width=image.width, height=image.height))
    (args.output / 'manifest.json').write_text(json.dumps(dict(zone_id=args.zone, scanned=scanned, maps=records), indent=2) + '\n')
    print(f'Scanned {scanned} DATs; extracted {len(records)} maps to {args.output}')


if __name__ == '__main__':
    main()
