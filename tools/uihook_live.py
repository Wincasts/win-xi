#!/usr/bin/env python3
# Reads uihook's blocks from the running game (Proton, the phoenix-loader.exe process), read only, through
# /proc/<pid>/mem: the menu mirror (ABI 5) and the watch (uihook 1.23+: every window drawn each frame).
#
#   python3 tools/uihook_live.py            what is asked, drawn and published now
#   python3 tools/uihook_live.py follow DIR a line each time that changes, to DIR/follow.log, and every
#                                           published window in full to DIR/detail.log
import struct, re, subprocess, sys

def game_pid():
    out = subprocess.run(['pgrep', '-f', 'phoenix-loader.exe'], capture_output=True, text=True).stdout.split()
    return int(out[0])

pid = game_pid()
mem = open(f'/proc/{pid}/mem', 'rb', buffering=0)  # unbuffered: a buffered read serves stale bytes after a seek

def read(a, n):
    mem.seek(a); return mem.read(n)

def find_block(magic=b'UIHOOK-MIRROR\0', version=5, size=84632):
    lines = open(f'/proc/{pid}/maps').read().splitlines()
    regions = []
    for i, l in enumerate(lines):
        if 'uihook.dll' in l:
            for l2 in lines[i:i + 12]:
                a, b = (int(x, 16) for x in l2.split()[0].split('-'))
                if 'r' in l2.split()[1]: regions.append((a, b))
    for a, b in regions:
        try: data = read(a, b - a)
        except Exception: continue
        for m in re.finditer(re.escape(magic), data):
            ver, sz = struct.unpack_from('<II', data, m.start() + 16)
            if ver == version and sz == size: return a + m.start()

PUB = 2628
def snapshot(base):
    b = read(base, 84632)
    frame, supported = struct.unpack_from('<II', b, 24)
    request = struct.unpack_from('<I', b, 32)[0]
    hide = struct.unpack_from('<4I', b, 36)
    asked = []
    for i in range(128):
        n = b[52 + i*16: 68 + i*16]
        if n[0]: asked.append((n[8:].rstrip(b' \0').decode('latin1'), (hide[i//32] >> (i % 32)) & 1))
    mframe, mcount = struct.unpack_from('<II', b, 2100)
    serial, dropped = struct.unpack_from('<II', b, 2620)
    pf, wc, rc, qc, tu = struct.unpack_from('<5I', b, PUB)
    W = PUB + 20; R = W + 16*132; Q = R + 512*44; T = Q + 512*48
    out = dict(frame=frame, supported=supported, requestAge=frame - request if request else None, asked=asked,
               mouse=(frame - mframe if mframe else None, mcount), serial=serial, dropped=dropped, published=pf, windows=[])
    for i in range(min(wc, 16)):
        o = W + i*132
        name = b[o:o+16][8:].rstrip(b' \0').decode('latin1')
        flags = struct.unpack_from('<I', b, o+16)[0]
        rect, cur, sel, scr = (struct.unpack_from('<4f', b, o+20+16*k) for k in range(4))
        cf, sf, scf, sp, sc, st = struct.unpack_from('<6I', b, o+84)
        target = struct.unpack_from('<4h', b, o+108)
        fr, nr, fq, nq = struct.unpack_from('<4I', b, o+116)
        runs = []
        for j in range(fr, min(fr+nr, 512)):
            ro = R + j*44
            rr = struct.unpack_from('<4f', b, ro); _, route, col, off, ln, ph = struct.unpack_from('<6I', b, ro+16); x, y = struct.unpack_from('<2h', b, ro+40)
            runs.append((b[T+off:T+off+ln].decode('latin1', 'replace'), route, ph, rr, x, y))
        quads = []
        for j in range(fq, min(fq+nq, 512)):
            qo = Q + j*48
            quads.append((struct.unpack_from('<4f', b, qo), struct.unpack_from('<4f', b, qo+16), *struct.unpack_from('<4I', b, qo+32)))
        out['windows'].append(dict(name=name, flags=flags, rect=rect, cursor=cur if cf else None, selection=sel if sf else None,
            scroll=(scr, sp, sc, st) if scf else None, target=target, runs=runs, quads=quads))
    return out

def show(s, runs=False):
    print(f"frame {s['frame']} supported {s['supported']} request age {s['requestAge']} published {s['published']} dropped {s['dropped']} mouse {s['mouse']}")
    print('asked:', ' '.join(n + ('*' if h else '') for n, h in s['asked']))
    for w in s['windows']:
        r = w['rect']
        phases = {}
        for q in w['quads']: phases[q[5]] = phases.get(q[5], 0) + 1
        print(f"  {w['name']:9} flags {w['flags']:X} rect {r[0]:.3f},{r[1]:.3f}-{r[2]:.3f},{r[3]:.3f} runs {len(w['runs'])} quads {phases} cursor {'y' if w['cursor'] else '-'} target {w['target']}")
        if runs:
            for t in w['runs'][:12]: print('     ', repr(t[0]), 'route', t[1], 'phase', t[2], 'rect', ','.join(f'{v:.3f}' for v in t[3]))

WATCH_SIZE = 32 + 36*64
def find_watch(): return find_block(b'UIHOOK-WATCH\0', 1, WATCH_SIZE)
def watch(base):
    b = read(base, WATCH_SIZE)
    frame, count = struct.unpack_from('<II', b, 24)
    out = []
    for i in range(min(count, 64)):
        o = 32 + i*36
        name = b[o+8:o+16].decode('latin1').rstrip(' \0')
        kind, = struct.unpack_from('<I', b, o+16)
        draws, depth, flags = b[o+20], b[o+21], b[o+22]
        up, other, buf = struct.unpack_from('<3I', b, o+24)
        out.append((name, kind, draws, depth, flags, up, other, buf))
    return frame, out

def follow(out):
    import os, time
    os.makedirs(out, exist_ok=True)
    log = open(os.path.join(out, 'follow.log'), 'a', buffering=1)
    detail = open(os.path.join(out, 'detail.log'), 'a', buffering=1)  # every window in full (runs, quads) each time the set published changes
    lastNames = None
    def stamp(): return time.strftime('%H:%M:%S')
    base, wbase, last = None, None, None
    while True:
        try:
            if not base: base = find_block()
            if not wbase: wbase = find_watch()
            s = snapshot(base)
            drawn = []
            if wbase:
                _, ws = watch(wbase)
                for name, kind, draws, depth, flags, up, other, buf in ws:
                    mark = '' if flags & 4 else ('!' if flags & 1 else '')  # ! asked but not mirrored
                    kinds = ('' if not other else f' other{other}') + ('' if not buf else f' buf{buf}')
                    drawn.append(f'{name}{mark}{kinds}')
        except Exception as e:
            log.write(f'{stamp()} read failed: {e}\n'); time.sleep(5); base = wbase = None; continue
        asked = ' '.join(n + ('*' if h else '') for n, h in s['asked'])
        wins = []
        for w in s['windows']:
            r = w['rect']; ph = {}
            for q in w['quads']: ph[q[5]] = ph.get(q[5], 0) + 1
            placed = r[2] > r[0] and r[3] > r[1]
            wins.append(f"{w['name']}[{'%.2f,%.2f-%.2f,%.2f' % tuple(r) if placed else 'NO PLACE'} f{w['flags']:X} r{len(w['runs'])} q{ph}{' c' if w['cursor'] else ''}]")
        key = (asked, tuple(drawn), tuple(wins))
        if key != last:
            if last is None or asked != last[0]: log.write(f'{stamp()} asked: {asked}\n')
            if last is None or tuple(drawn) != last[1]: log.write(f'{stamp()} drawn: {" ".join(drawn) if wbase else "(no watch block: uihook before 1.22)"}\n')
            log.write(f'{stamp()} published: {" ".join(wins) or "none"}\n')
            last = key
            names = tuple(w['name'] for w in s['windows'])
            if names != lastNames:
                lastNames = names
                detail.write(f'=== {stamp()} frame {s["frame"]}\n')
                for w in s['windows']:
                    detail.write(f"== {w['name']} flags {w['flags']:X} rect {[round(v,4) for v in w['rect']]} cursor {w['cursor'] and [round(v,4) for v in w['cursor']]} sel {w['selection'] and [round(v,4) for v in w['selection']]} scroll {w['scroll'] and ([round(v,4) for v in w['scroll'][0]], w['scroll'][1:])} target {w['target']}\n")
                    for t in w['runs']: detail.write(f"   run {t[0]!r} route {t[1]} ph {t[2]} {[round(v,4) for v in t[3]]} at {t[4]},{t[5]}\n")
                    for q in w['quads']: detail.write(f"   q {[round(v,4) for v in q[0]]} uv {[round(v,4) for v in q[1]]} tex {q[3]:X} col {q[4]:08X} ph {q[5]}\n")
        time.sleep(0.25)

if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == 'follow':
        follow(sys.argv[2])
    else:
        show(snapshot(find_block()), runs=True)
        w = find_watch()
        if w:
            frame, ws = watch(w)
            print(f'drawn in frame {frame}:')
            for name, kind, draws, depth, flags, up, other, buf in ws:
                print(f"  {name:9} kind {kind:X} depth {depth} {'asked' if flags & 1 else '-'}{' hidden' if flags & 2 else ''}{' mirrored' if flags & 4 else ''}; draws {up} measured, {other} not screen space, {buf} buffers")
        else:
            print('no watch block (uihook before 1.23)')
