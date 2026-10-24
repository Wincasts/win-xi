#!/usr/bin/env python3
"""Optional private unpacked client verification; never commit/distribute the dump.
Usage: python3 plugins/uihook/tests/check_window_client.py /path/to/ffximain.bin /path/to/ffximain.txt
The three text routines the window hooks take: each unique, and the wrappers around them calling them; and
Window::Render's call to a window's contents, unique and inside it.
"""
import re
import struct
import sys
from pathlib import Path

text = (Path(__file__).resolve().parents[1] / 'src/modules/window/window.h').read_text()
text += (Path(__file__).resolve().parents[1] / 'src/modules/party/game.h').read_text()
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


bitmap = unique('TEXT_BITMAP_PATTERN')
scaled = unique('TEXT_SCALED_PATTERN')
font = unique('TEXT_FONT_PATTERN')
# the plain wrapper (x, y, text, colour) passes on to the bitmap route with scale 1 and not centred
wrapper = bytes.fromhex('8B 44 24 10 8B 4C 24 0C 8B 54 24 08 6A 00 68 00 00 80 3F 68 00 00 80 3F 50 8B 44 24 14 51 52 50 E8')
at = data.find(wrapper)
assert at >= 0 and data.find(wrapper, at + 1) < 0, 'wrapper'
assert at + len(wrapper) + 4 + struct.unpack_from('<i', data, at + len(wrapper))[0] == bitmap
# the rendered-font route is reached through the two thunks that load the font object
assert len(callers(font)) >= 2, 'font callers'
for name, at in (('bitmap', bitmap), ('scaled', scaled), ('font', font)):
    print(f'{name}: {len(callers(at))} callers at {base + at:08X}')
# the content call: mov edx,[ecx]; call [edx+10] in Window::Render (its prologue may be the detour's jump in a dump
# taken with uihook loaded, so it is found from its later bytes)
site = unique('WINDOW_CONTENT_PATTERN')
at = int(re.search(r'#define WINDOW_CONTENT_AT (\d+)', text)[1])
assert data[site + at:site + at + 5] == bytes.fromhex('8B 11 FF 52 10'), 'content call'
tail = re.search(r'#define WINDOW_PATTERN "([^"]+)"', text)[1].split()[6:]  # past the six bytes a loaded uihook's jump covers
regex = b''.join(b'.' if token == '??' else re.escape(bytes.fromhex(token)) for token in tail)
renders = [m.start() - 6 for m in re.finditer(regex, data, re.S)]
assert len(renders) == 1, ('Window::Render', renders)
render = renders[0]
assert 0 <= site - render < 0x800, ('content call outside Window::Render', render, site)
print(f'content call at {base + site + at:08X}')
print('window hooks client check passed')
