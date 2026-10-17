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
    'chat/chat.h', 'chat/controls.h', 'chat/windows.h', 'party/game.h', 'party/target.h'))
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
# The rows of text: the content Draw's call at +AA is to the drawer (ret 18, six words), and inside the drawer
# the one row-drawing call, cdecl with 22 words the caller takes back (add esp,58), to the row draw.
drawer = unique('CHAT_ROWS_DRAW_PATTERN')
row_site = unique('CHAT_ROW_SITE_PATTERN') + 17
row_draw = unique('CHAT_ROW_DRAW_PATTERN')
assert callee(full + 0xAA) == drawer
assert drawer <= row_site < drawer + 0x200 and callee(row_site) == row_draw
assert data.find(bytes.fromhex('83C458'), row_site + 5, row_site + 40) >= 0
assert data.find(b'\xC2\x18\x00', drawer, drawer + 0x200) >= 0
# the row draw ends in the glyph loop's draw: a 16-pixel cell (the float 16.0 the glyph draw scales by) and the
# width table; and the client's own encoder (the function the decoder is transcribed from) is where expected
assert data.find(bytes.fromhex('6A7F5152B90F00000083EC3C8BFC55F3A5'), drawer, drawer + 0x200) >= 0
encoder = data.find(bytes.fromhex('8B4C240433C033D28A018A51013D9F000000'))
assert encoder >= 0 and data.find(bytes.fromhex('8B4C240433C033D28A018A51013D9F000000'), encoder + 1) < 0
# The two log windows' routing: the keep check reads the second window's owner (the split log's global of the
# primary/split signature) and the config words B9/BA and BB/BC; the category test's first call is the mode
# table lookup, whose table (in the image) ends with a zero mode word; the category index's 30 jump cases are
# each a constant, zero or none; every config reader names one manager global and one of them calls the value,
# whose first call is the entry (44 bytes each, the value at +8).
chat_signature = unique('CHAT_PATTERN')
split_owner = struct.unpack_from('<I', data, chat_signature + 11)[0]
first_keep = unique('CHAT_FIRST_KEEP_PATTERN')
assert struct.unpack_from('<I', data, first_keep + 1)[0] == split_owner
unique('CHAT_SECOND_KEEP_PATTERN')
lookup = unique('CHAT_MODE_LOOKUP_PATTERN')
test = unique('CHAT_CATEGORY_TEST_PATTERN')
assert callee(test + 9) == lookup
table = struct.unpack_from('<I', data, lookup + 1)[0] - base
assert 0 <= table < len(data) - 2048
entries = 0
while struct.unpack_from('<H', data, table + entries * 4)[0]:
    entries += 1
    assert entries < 512
assert entries > 100, entries
index = unique('CHAT_CATEGORY_INDEX_PATTERN')
jumps = struct.unpack_from('<I', data, index + 19)[0] - base
bits = []
for i in range(30):
    target = struct.unpack_from('<I', data, jumps + i * 4)[0] - base
    code = data[target:target + 6]
    if code[0] == 0xB8 and code[5] == 0xC3:
        bits.append(struct.unpack_from('<i', code, 1)[0])
    elif code[:3] == bytes.fromhex('33C0C3'):
        bits.append(0)
    else:
        assert code[:4] == bytes.fromhex('83C8FFC3'), (i, code.hex())
        bits.append(-1)
assert all(-1 <= bit <= 63 for bit in bits) and bits[0] == 0 and -1 in bits, bits
value = unique('CHAT_CONFIG_VALUE_PATTERN')
entry = unique('CHAT_CONFIG_ENTRY_PATTERN')
assert callee(value + 5) == entry
read_pattern = re.search(r'#define CHAT_CONFIG_READ_PATTERN "([^"]+)"', source)[1]
read_regex = b''.join(b'.' if token == '??' else re.escape(bytes.fromhex(token)) for token in read_pattern.split())
readers = [m.start() for m in re.finditer(read_regex, data, re.S)]
assert readers and len({struct.unpack_from('<I', data, at + 2)[0] for at in readers}) == 1, readers
assert any(callee(at + 15) == value for at in readers)
unique('CHAT_LINES_UPDATE_PATTERN')
unique('CHAT_LINES_GROW_PATTERN')
# the owners' base constructor sets the row height (+54) to 14, the fewest (+50) to 0, the most (+4E) to 8, the lines (+31) to 4
assert data.count(bytes.fromhex('66C7465414006689465066C7464E0800')) == 1
print(f'Log window routing: {entries} mode entries, category bits {bits}, {len(readers)} config readers; line fields pinned.')
print('Native full-log vtable/content, tab strip, tab/selection/cursor/scrollbar and row-drawing CALL graph cross-check passed.')
print('Static verification only: live artwork, pulse/fades, hit-tests, menu actions and GPU resets still need validation.')
