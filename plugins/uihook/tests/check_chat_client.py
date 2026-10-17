#!/usr/bin/env python3
"""Optional verification against a private unpacked client dump. Never distribute the dump.
Usage: python3 plugins/uihook/tests/check_chat_client.py /path/to/ffximain.bin /path/to/ffximain.txt
"""
import re
import struct
import sys
from pathlib import Path

modules = Path(__file__).resolve().parents[1] / 'src/modules'
source = '\n'.join((modules / name).read_text() for name in (
    'chat/chat.h', 'chat/controls.h', 'party/game.h', 'party/target.h'))
data = Path(sys.argv[1]).read_bytes()
base = int(re.search(r'base (0x[0-9A-Fa-f]+)', Path(sys.argv[2]).read_text())[1], 16)


def unique(name):
    pattern = re.search(r'#define ' + name + r' "([^"]+)"', source)[1]
    regex = b''.join(b'.' if token == '??' else re.escape(bytes.fromhex(token)) for token in pattern.split())
    matches = [m.start() for m in re.finditer(regex, data, re.S)]
    assert len(matches) == 1, (name, matches)
    print(f'{name}: unique RVA {matches[0]:08X}')
    return matches[0]


def callee(at):
    assert data[at] == 0xE8
    target = at + 5 + struct.unpack_from('<i', data, at + 1)[0]
    assert 0 <= target < len(data)
    return target


window = unique('WINDOW_PATTERN')
constructor = unique('CHAT_FULL_PATTERN')
full = unique('CHAT_FULL_DRAW_PATTERN')
vtable = struct.unpack_from('<I', data, constructor + 48)[0] - base
assert 0 <= vtable <= len(data) - 0x2C
assert struct.unpack_from('<I', data, vtable + 0x10)[0] - base == full
assert data[full:full + 5] == bytes.fromhex('83EC0C5355')
tabs = callee(full + 19)
site_offsets = (('CHAT_TAB_ART_PATTERN', 24), ('CHAT_SELECTION_ART_PATTERN', 14),
                ('CHAT_CURSOR_ART_PATTERN', 18), ('CHAT_SCROLL_ART_PATTERN', 10))
sites = {name: unique(name) + offset for name, offset in site_offsets}
simple = unique('CHAT_TAB_SPRITE_PATTERN')
sprite = unique('SPRITE_PATTERN')
scroll = unique('CHAT_SCROLL_DRAW_PATTERN')
assert tabs <= sites['CHAT_TAB_ART_PATTERN'] < tabs + 0x200
for name in ('CHAT_SELECTION_ART_PATTERN', 'CHAT_CURSOR_ART_PATTERN', 'CHAT_SCROLL_ART_PATTERN'):
    assert window <= sites[name] < window + 0x800
assert callee(sites['CHAT_TAB_ART_PATTERN']) == simple
assert callee(sites['CHAT_SELECTION_ART_PATTERN']) == callee(sites['CHAT_CURSOR_ART_PATTERN']) == sprite
assert callee(sites['CHAT_SCROLL_ART_PATTERN']) == scroll
# Native callee stack cleanup: five-word simple sprite, eight-word scaled sprite, and the tab strip's one
# word (the filter; its this is ecx, still the owner at the call, as the content Draw pattern fixes the bytes
# between mov esi,ecx and the call).
for entry, cleanup in ((simple, 0x14), (sprite, 0x20), (tabs, 0x04)):
    assert data.find(b'\xC2' + struct.pack('<H', cleanup), entry, entry + 0x400) >= 0, hex(entry)
print('Native full-log vtable/content, tab strip and tab/selection/cursor/scrollbar CALL graph cross-check passed.')
print('Static verification only: live artwork, pulse/fades, hit-tests, menu actions and GPU resets still need validation.')
