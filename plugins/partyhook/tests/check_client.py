#!/usr/bin/env python3
"""Optional check against a private, unpacked codedump (never commit the client's binary).
Usage: python3 plugins/partyhook/tests/check_client.py /path/to/ffximain.bin /path/to/ffximain.txt
"""
import re
import struct
import sys
from pathlib import Path

source = Path(__file__).resolve().parents[1] / 'src/game.h'
data = Path(sys.argv[1]).read_bytes()
metadata = Path(sys.argv[2]).read_text()
base = int(re.search(r'base (0x[0-9A-Fa-f]+)', metadata)[1], 16)
text = source.read_text() + (source.parent / 'target.h').read_text() + (source.parent / 'placement.h').read_text()

def matches(name):
    pattern = re.search(r'#define ' + name + r' "([^"]+)"', text)[1]
    regex = b''.join(b'.' if part == '??' else re.escape(bytes.fromhex(part)) for part in pattern.split())
    return [m.start() for m in re.finditer(regex, data, re.S)]

renderers = matches('WINDOW_PATTERN')
parties = matches('PARTY_PATTERN')
assert len(renderers) == len(parties) == 1, (renderers, parties)
main = struct.unpack_from('<I', data, parties[0] + 0x19)[0]
registries = []
for match in re.finditer(b'menu    partywin', data):
    at = match.start()
    if data[at+44:at+60] != b'menu    raid1   ' or data[at+88:at+104] != b'menu    raid2   ':
        continue
    addresses = [struct.unpack_from('<I', data, at+j*44+32)[0] for j in range(3)]
    if addresses[0] == main and len(set(addresses)) == 3 and all(base <= a <= base+len(data)-4 and a%4 == 0 for a in addresses):
        registries.append((at, addresses))
assert len(registries) == 1, registries
print(f'Unique native window renderer RVA: {renderers[0]:08X}')
print(f'Cross-checked partywin / raid1 / raid2 registry RVA: {registries[0][0]:08X}')
print('HUD global RVAs: ' + ', '.join(f'{a-base:08X}' for a in registries[0][1]))
target = struct.unpack_from('<I', data, parties[0] + 0x23)[0]
target_entries = [m.start() for m in re.finditer(b'menu    targetwi', data)
                  if data[m.start()+16:m.start()+32] == bytes(16)
                  and struct.unpack_from('<I', data, m.start()+32)[0] == target]
assert len(target_entries) == 1 and base <= target <= base+len(data)-4
sprite = matches('SPRITE_PATTERN')
assert len(sprite) == 1
for name, offset in [('MAIN_ARROW_PATTERN', 32), ('SUB_ARROW_PATTERN', 25)]:
    sites = matches(name)
    assert len(sites) == 1
    call = sites[0] + offset
    assert data[call] == 0xe8 and call+5+struct.unpack_from('<i', data, call+1)[0] == sprite[0]
    print(f'{name} call RVA: {call:08X}; original sprite callee RVA: {sprite[0]:08X}')
print(f'Cross-checked targetwi registry RVA: {target_entries[0]:08X}; global RVA: {target-base:08X}')
rect = matches('RECT_PATTERN')
assert len(rect)==1
manager=struct.unpack_from('<I',data,rect[0]+32)[0]
assert base<=manager<=base+len(data)-0x84
print(f'Native rectangle scaling source RVA: {rect[0]:08X}; menu manager RVA: {manager-base:08X}')
print('Static discovery passed; default positioning/scaling still requires live validation.')
