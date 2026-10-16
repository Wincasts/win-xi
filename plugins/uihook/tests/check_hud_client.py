#!/usr/bin/env python3
"""Optional private unpacked client verification; never commit/distribute the dump.
Usage: python3 plugins/uihook/tests/check_hud_client.py /path/to/ffximain.bin /path/to/ffximain.txt
"""
import re
import struct
import sys
from pathlib import Path

text = (Path(__file__).resolve().parents[1] / 'src/modules/party/hud.h').read_text()
data = Path(sys.argv[1]).read_bytes()
base = int(re.search(r'base (0x[0-9A-Fa-f]+)', Path(sys.argv[2]).read_text())[1], 16)


def unique(name):
    pattern = re.search(r'#define ' + name + r' "([^"]+)"', text)[1]
    regex = b''.join(b'.' if token == '??' else re.escape(bytes.fromhex(token)) for token in pattern.split())
    matches = [m.start() for m in re.finditer(regex, data, re.S)]
    assert len(matches) == 1, (name, matches)
    print(f'{name}: unique RVA {matches[0]:08X}')
    return matches[0]


def callee(at, opcode=0xE8):
    assert data[at] == opcode
    target = at + 5 + struct.unpack_from('<i', data, at + 1)[0]
    assert 0 <= target < len(data)
    return target


step = unique('COMPASS_STEP_PATTERN')
compass = unique('COMPASS_DRAW_PATTERN')
clock = unique('CLOCK_DRAW_PATTERN')
compact = unique('CLOCK_SMALL_PATTERN')
radar = unique('CLOCK_RADAR_PATTERN')
visible = unique('RADAR_VISIBLE_PATTERN')
weather = unique('CLOCK_WEATHER_PATTERN')
assert callee(step + 35, 0xE9) == compass
assert callee(compact + 4) == callee(radar + 8) == clock
assert compass <= compact < radar <= compass + 0x900
assert callee(compass + 0x44) == visible
first, second = (struct.unpack_from('<I', data, step + offset)[0] for offset in (2, 31))
assert first == second and first % 4 == 0 and base <= first <= base + len(data) - 4
assert clock <= weather < clock + 0x160
weather_global = struct.unpack_from('<I', data, weather + 2)[0]
assert base <= weather_global <= base + len(data) - 2
text_call = unique('CLOCK_TEXT_PATTERN') + int(re.search(r'#define CLOCK_TEXT_CALL (\d+)', text)[1])
assert clock < text_call < clock + 0x100
routine = callee(text_call)
# cdecl: Clock::Draw pushes the next call's argument straight after, and clears both later (add esp,0x28)
assert data[text_call + 5:text_call + 7] == bytes.fromhex('6A04')
print(f'clock text call at RVA {text_call:08X}, calling {routine:08X}')
sprite = None
for name in ('DAY', 'WEATHER', 'SECOND'):
    call = unique(f'CLOCK_{name}_ICON_PATTERN') + int(re.search(rf'#define CLOCK_{name}_ICON_CALL (\d+)', text)[1])
    assert clock < call < clock + 0x160
    target = callee(call)
    assert sprite in (None, target), (name, hex(target))
    sprite = target
# thiscall, five stack words cleared by the callee: the first ret in the routine is ret 0x14
first_ret = min(i for i in (data.find(b'\xC2\x14\x00', sprite, sprite + 0x200), data.find(b'\xC3', sprite, sprite + 0x200)) if i >= 0)
assert data[first_ret:first_ret + 3] == b'\xC2\x14\x00', hex(first_ret)
print(f'clock icon calls to the sprite routine at RVA {sprite:08X} (ret 0x14)')
banks = []
for name in ('DAY', 'WEATHER'):
    at = unique(f'CLOCK_{name}_BANK_PATTERN')
    assert clock < at < clock + 0x160
    banks.append(callee(at + int(re.search(r'#define CLOCK_BANK_CALL (\d+)', text)[1])))
assert banks[0] == banks[1], [hex(b) for b in banks]
# Bank(n): banks[n] for n below 18, else 0, and nothing else
assert data[banks[0]:banks[0] + 12] == bytes.fromhex('8B442404 85C0 7C0D 83F812 7D'.replace(' ', '')), data[banks[0]:banks[0] + 12].hex()
print(f'clock sprite banks getter at RVA {banks[0]:08X}')
print('Clock/compass call graph, live global, native radar query, text and icon calls and weather source cross-check passed.')
print('Static verification only: live layering, visibility, menu/controller, zoning and reset checks remain required.')
