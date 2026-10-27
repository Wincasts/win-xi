#!/usr/bin/env python3
"""Watch the running game's 32-bit heap for the leaked wined3d light records.

Read only: /proc/<pid>/maps and /proc/<pid>/mem of phoenix-loader.exe. One line a sample:

    01:18:40  arena 459 MB  orphans 1051864  (+0 /min)

arena: the committed part of the wine heap arena the records accumulate in (reserved at
0x4b2a0000 in every session seen so far; --arena to change). orphans: 272-byte heap blocks
holding a wined3d_light_info for light index 2 with glIndex -1 (never given a GL light), the
record that leaked ~800 times a second on 2026-10-26/27 as a black directional light and ~550
a second on 2026-10-27 10:47 as a warm point light; the light's contents vary, the index does not. The rate is per minute
since the previous sample.

    python3 tools/leakwatch.py                # every 60 s until the game exits or Ctrl-C
    python3 tools/leakwatch.py --every 30 --log /tmp/leak.txt
    python3 tools/leakwatch.py --once

Line the samples up against ~/Games/PhoenixXI/logs/<newest>.txt (plugin loads and unloads) and
the game's TEMP/Win chat logs (addon loads, what was happening).
"""
import argparse
import re
import struct
import subprocess
import sys
import time

SIGNATURE = re.compile(rb'\x22\x00\x08\x00..\x75\x80', re.S)


def find_pid():
    out = subprocess.run(['pgrep', '-f', 'phoenix-loader.exe'], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def arena_ranges(pid, lo, hi):
    ranges = []
    with open(f'/proc/{pid}/maps') as maps:
        for line in maps:
            fields = line.split()
            start, end = (int(x, 16) for x in fields[0].split('-'))
            if lo <= start < hi and fields[1].startswith('rw'):
                ranges.append((start, end))
    return ranges


def sample(pid, lo, hi):
    ranges = arena_ranges(pid, lo, hi)
    committed = sum(end - start for start, end in ranges) / 2**20
    orphans = 0
    with open(f'/proc/{pid}/mem', 'rb') as mem:
        for start, end in ranges:
            mem.seek(start)
            data = mem.read(end - start)
            for match in SIGNATURE.finditer(data):
                off = match.start()
                if off + 272 > len(data):
                    continue
                index, gl_index = struct.unpack_from('<Ii', data, off + 8 + 0x68)
                if index == 2 and gl_index == -1:
                    orphans += 1
    return committed, orphans


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--every', type=float, default=60, help='seconds between samples (default 60)')
    parser.add_argument('--once', action='store_true', help='one sample, then exit')
    parser.add_argument('--log', help='append each line to this file as well')
    parser.add_argument('--arena', default='0x4b2a0000-0x67fa0000', help='address range of the arena, hex (default 0x4b2a0000-0x67fa0000)')
    args = parser.parse_args()
    lo, hi = (int(x, 16) for x in args.arena.split('-'))

    previous = None
    while True:
        pid = find_pid()
        if pid is None:
            print(time.strftime('%H:%M:%S'), 'game not running; waiting', flush=True)
            if args.once:
                return 1
            time.sleep(args.every)
            continue
        try:
            committed, orphans = sample(pid, lo, hi)
        except (OSError, PermissionError) as problem:
            print(time.strftime('%H:%M:%S'), 'could not read the game:', problem, flush=True)
            if args.once:
                return 1
            time.sleep(args.every)
            continue
        now = time.time()
        rate = ''
        if previous is not None and now > previous[0]:
            per_minute = (orphans - previous[1]) / ((now - previous[0]) / 60)
            rate = f'  ({per_minute:+.0f} /min)'
        line = f'{time.strftime("%H:%M:%S")}  arena {committed:.0f} MB  orphans {orphans}{rate}'
        print(line, flush=True)
        if args.log:
            with open(args.log, 'a') as log:
                log.write(line + '\n')
        previous = (now, orphans)
        if args.once:
            return 0
        time.sleep(args.every)


if __name__ == '__main__':
    sys.exit(main() or 0)
