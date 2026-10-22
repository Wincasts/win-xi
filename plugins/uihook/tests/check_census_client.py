#!/usr/bin/env python3
"""Optional private unpacked client verification; never commit/distribute the dump.
Usage: python3 plugins/uihook/tests/check_census_client.py /path/to/ffximain.bin /path/to/ffximain.txt
The census's three text routines: each unique, the wrappers around them calling them, and the bitmap
route drawing its glyphs through Sprite::Draw.
"""
import re
import struct
import sys
from pathlib import Path

text = (Path(__file__).resolve().parents[1] / 'src/modules/mirror/census.h').read_text()
data = Path(sys.argv[1]).read_bytes()
base = int(re.search(r'base (0x[0-9A-Fa-f]+)', Path(sys.argv[2]).read_text())[1], 16)


def unique(name):
    pattern = re.search(r'#define ' + name + r' "([^"]+)"', text)[1]
    regex = b''.join(b'.' if token == '??' else re.escape(bytes.fromhex(token)) for token in pattern.split())
    matches = [m.start() for m in re.finditer(regex, data, re.S)]
    assert len(matches) == 1, (name, matches)
    print(f'{name}: unique RVA {matches[0]:08X}')
    return matches[0]


def callers(target):
    found = []
    for at in range(len(data) - 5):
        if data[at] == 0xE8 and at + 5 + struct.unpack_from('<i', data, at + 1)[0] == target:
            found.append(at)
    return found


bitmap = unique('CENSUS_TEXT_PATTERN')
scaled = unique('CENSUS_SCALED_PATTERN')
font = unique('CENSUS_FONT_PATTERN')
# the plain wrapper (x, y, text, colour) passes on to the bitmap route with scale 1 and not centred
wrapper = bytes.fromhex('8B 44 24 10 8B 4C 24 0C 8B 54 24 08 6A 00 68 00 00 80 3F 68 00 00 80 3F 50 8B 44 24 14 51 52 50 E8')
at = data.find(wrapper)
assert at >= 0 and data.find(wrapper, at + 1) < 0, 'wrapper'
assert at + len(wrapper) + 4 + struct.unpack_from('<i', data, at + len(wrapper))[0] == bitmap
# the rendered-font route is reached through the two thunks that load the font object
assert len(callers(font)) >= 2, 'font callers'
for name, at in (('bitmap', bitmap), ('scaled', scaled), ('font', font)):
    print(f'{name}: {len(callers(at))} callers at {base + at:08X}')
print('census client check passed')
