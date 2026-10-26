#!/usr/bin/env python3
"""The plugins' shared blocks against their frozen 1.0 layout, and the addons' Lua copies against the plugins.

    tools/abi_check.py           check: exits 1 and says what broke
    tools/abi_check.py --freeze  write plugins/abi/layout-1.0.json from the plugins as they are (once, for 1.0)

Each plugin's own sources are compiled as its build compiles them (clang-cl, i686, the same includes), with
clang's record-layout dump, so the layouts are the ones the DLL has. From each block (BLOCKS) every struct it
holds is followed: those are its records. The rules of plugins/ABI.md, against the baseline:

  - every field of the baseline is still there, at the same offset, of the same type
  - a block may grow, by fields after its 1.0 end; a record may not grow at all
  - the Lua copy (ffi.cdef in the addon or winxi file that reads the block) has each field it shares with
    the C++ struct at the same offset, and is no larger than it (a record exactly its size)

Away from the toolchain (no clang-cl, or no MSVC headers) the C++ half is skipped and said so.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = Path(os.environ.get('TOOLCHAIN', ROOT / '.toolchain'))
MSVC = Path(os.environ.get('MSVC_PATH', TOOLCHAIN / 'msvc'))
SDK = Path(os.environ.get('ASHITA_SDK_PATH', TOOLCHAIN / 'ashita/plugins/sdk'))
BASELINE = ROOT / 'plugins/abi/layout-1.0.json'

# The sources whose compilation sees every shared struct of each plugin
SOURCES = {
    'namehook': ['plugins/namehook/src/Nameplate.cpp'],
    'uihook': ['plugins/uihook/src/modules/party/partyhook.cpp', 'plugins/uihook/src/modules/buffs/buffhook.cpp'],
    'lens': ['plugins/lens/src/lens.cpp'],
}

# Each block an addon reads: plugin, C++ struct, its magic, and the Lua type and file that copy it
BLOCKS = [
    ('namehook', 'HookShared', 'NAMEHOOK', 'namehook_t', 'addons/libs/winxi/nameplates.lua'),
    ('namehook', 'HookCapabilities', 'NAMEHOOKCAPS', 'namehook_capabilities_t', 'addons/libs/winxi/nameplates.lua'),
    ('namehook', 'HookDraw', None, 'namehook_draw_t', 'addons/libs/winxi/nameplates.lua'),
    ('namehook', 'HookBubbles', 'NAMEBUBBLES', 'chatbubbles_world_t', 'addons/chatbubbles/world.lua'),
    ('namehook', 'HookPopups', 'NAMEHOOKPOPUPS', 'namehook_popups_t', 'addons/libs/winxi/popups.lua'),
    ('namehook', 'HookPopupDraw', None, 'namehook_popup_draw_t', 'addons/libs/winxi/popups.lua'),
    ('namehook', 'HookCamera', 'NAMEHOOKCAMERA', 'namehook_camera_t', 'addons/libs/winxi/camera.lua'),
    ('uihook', 'BuffShared', 'BUFFHOOK-SHARED', 'buffhook_t', 'addons/buff/hook.lua'),
    ('uihook', 'PartyShared', 'PARTYHOOK', 'partyhook_shared_t', 'addons/party/hook.lua'),
    ('uihook', 'ChatShared', 'UIHOOK-CHAT', 'uihook_chat_t', 'addons/libs/winxi/nativechat.lua'),
    ('uihook', 'HudShared', 'UIHOOK-HUD', 'uihook_hud_t', 'addons/libs/winxi/nativehud.lua'),
    ('uihook', 'MenuShared', 'UIHOOK-MENUS', 'uihook_menus_t', 'addons/libs/winxi/nativemenus.lua'),
    ('uihook', 'TextTapShared', 'UIHOOK-TEXT', 'uihook_text_t', 'addons/libs/winxi/nativetext.lua'),
    ('uihook', 'ChatHistoryShared', 'UIHOOK-HISTORY', 'uihook_history_t', 'addons/libs/winxi/nativehistory.lua'),
    ('uihook', 'KeysShared', 'UIHOOK-KEYS', 'uihook_keys_t', 'addons/libs/winxi/gamekeys.lua'),
    ('uihook', 'MirrorShared', 'UIHOOK-MIRROR', 'uihook_mirror_t', 'addons/nativeui/groupmirror.lua'),
    ('lens', 'lens::Shared', 'LENS-WARP', 'lens_warp_t', 'addons/libs/winxi/lens.lua'),
]

# Records whose Lua copy goes by another name than the C++ struct's
RECORD_LUA = {
    'HookName': ('namehook_name_t', 'addons/libs/winxi/nameplates.lua'),
    'HookQuad': ('namehook_quad_t', 'addons/libs/winxi/nameplates.lua'),
    'HookDrawing': ('namehook_drawing_t', 'addons/libs/winxi/nameplates.lua'),
    'HookPopup': ('namehook_popup_t', 'addons/libs/winxi/popups.lua'),
    'HookPopupDrawing': ('namehook_popup_drawing_t', 'addons/libs/winxi/popups.lua'),
    'BuffQuad': ('buffhook_quad_t', 'addons/buff/hook.lua'),
    'TextTapEvent': ('uihook_text_event_t', 'addons/libs/winxi/nativetext.lua'),
    'MirrorRun': ('uihook_mirror_run_t', 'addons/nativeui/groupmirror.lua'),
    'MirrorQuad': ('uihook_mirror_quad_t', 'addons/nativeui/groupmirror.lua'),
    'MirrorWindow': ('uihook_mirror_window_t', 'addons/nativeui/groupmirror.lua'),
    'MirrorFrameData': ('uihook_mirror_frame_t', 'addons/nativeui/groupmirror.lua'),
}

# The Lua files in the order their cdefs are loaded: later ones use types the earlier define
LUA_ORDER = ['addons/libs/winxi/nameplates.lua', 'addons/libs/winxi/popups.lua', 'addons/chatbubbles/world.lua',
             'addons/libs/winxi/lens.lua', 'addons/libs/winxi/camera.lua', 'addons/libs/winxi/nativechat.lua', 'addons/libs/winxi/nativehud.lua',
             'addons/libs/winxi/nativemenus.lua', 'addons/libs/winxi/nativetext.lua', 'addons/libs/winxi/nativehistory.lua',
             'addons/libs/winxi/gamekeys.lua', 'addons/buff/hook.lua', 'addons/party/hook.lua', 'addons/nativeui/groupmirror.lua']

FIELD = re.compile(r'^\s*(\d+)(?::\d+-\d+)? \|   (\S.*?) ([A-Za-z_]\w*)$')
RECORD = re.compile(r'^\s*0 \| (?:struct|class) (\S+)$')
SIZE = re.compile(r'\[sizeof=(\d+),')


def toolchain_ready():
    return shutil.which('clang-cl') is not None and (MSVC / 'crt/include').is_dir() and SDK.is_dir()


def dump(plugin):
    """Every complete record the plugin's sources see: name -> {size, fields: [[name, offset, type]]}."""
    records = {}
    for source in SOURCES[plugin]:
        command = ['clang-cl', '--target=i686-pc-windows-msvc', '/nologo', '/std:c++latest', '/EHa', '/Zs',
                   '/DWIN32_LEAN_AND_MEAN', '/DNDEBUG', '/D_CRT_SECURE_NO_WARNINGS', '/DUIHOOK_DIAGNOSTICS=0',
                   '/imsvc', str(MSVC / 'crt/include'), '/imsvc', str(MSVC / 'sdk/include/ucrt'),
                   '/imsvc', str(MSVC / 'sdk/include/um'), '/imsvc', str(MSVC / 'sdk/include/shared'),
                   '/imsvc', str(SDK), '-Xclang', '-fdump-record-layouts-complete', str(ROOT / source)]
        run = subprocess.run(command, capture_output=True, text=True)
        if run.returncode != 0:
            raise SystemExit(f'{source} did not compile:\n{run.stderr[-2000:]}')
        current = None
        for line in run.stdout.splitlines():
            m = RECORD.match(line)
            if m:
                current = {'size': None, 'fields': []}
                name = m.group(1)
                if name not in records:
                    records[name] = current
                else:
                    current = {'size': None, 'fields': []}  # seen already; this copy is read and dropped
                continue
            if current is None:
                continue
            m = SIZE.search(line)
            if m:
                current['size'] = int(m.group(1))
                current = None
                continue
            m = FIELD.match(line)
            if m:
                current['fields'].append([m.group(3), int(m.group(1)), m.group(2).replace('struct ', '')])
    return records


def element(type_text):
    """The struct an array or field type is of, without struct/const and the array's bounds."""
    base = re.sub(r'\[\d+\]', '', type_text).replace('const ', '').strip()
    return base


def layouts():
    """The blocks and every struct each holds, as the plugins have them now."""
    out = {}
    for plugin in SOURCES:
        records = dump(plugin)
        roots = [b[1] for b in BLOCKS if b[0] == plugin]
        seen, todo = set(), list(roots)
        while todo:
            name = todo.pop()
            if name in seen:
                continue
            seen.add(name)
            if name not in records:
                raise SystemExit(f'{plugin}: {name} was not found in its compiled sources')
            rec = records[name]
            out[name] = {'plugin': plugin, 'kind': 'block' if name in roots else 'record',
                         'size': rec['size'], 'fields': rec['fields']}
            for _, _, type_text in rec['fields']:
                base = element(type_text)
                if base in records and base not in seen:
                    todo.append(base)
    return out


def compare(baseline, current):
    problems = []
    for name, old in baseline.items():
        new = current.get(name)
        if new is None:
            problems.append(f'{name}: gone')
            continue
        fields = {f[0]: f for f in new['fields']}
        for fname, offset, type_text in old['fields']:
            f = fields.get(fname)
            if f is None:
                problems.append(f'{name}.{fname}: gone (it was at {offset})')
            elif f[1] != offset or f[2] != type_text:
                problems.append(f'{name}.{fname}: was {type_text} at {offset}, is {f[2]} at {f[1]}')
        if new['size'] < old['size']:
            problems.append(f'{name}: shrank from {old["size"]} to {new["size"]} bytes')
        if old['kind'] == 'record' and new['size'] != old['size']:
            problems.append(f'{name}: a record, {old["size"]} bytes at 1.0, is {new["size"]}: add a parallel list to its block instead')
        old_names = {f[0] for f in old['fields']}
        for fname, offset, type_text in new['fields']:
            if fname not in old_names and offset < old['size']:
                problems.append(f'{name}.{fname}: new, at {offset}, inside the 1.0 layout (blocks grow only after {old["size"]})')
    return problems


def lua_cdefs(path):
    text = (ROOT / path).read_text(encoding='utf-8')
    return re.findall(r'ffi\.cdef\s*(?:,\s*|\(\s*)?\[\[(.*?)\]\]', text, re.S)


def lua_layouts(current):
    """sizeof and each C++ field's offset as LuaJIT has the Lua copies, or None where Lua lacks the field."""
    wanted = {}
    for plugin, name, _, lua_type, path in BLOCKS:
        wanted[name] = (lua_type, path)
    for name, (lua_type, path) in RECORD_LUA.items():
        wanted[name] = (lua_type, path)
    script = ['local ffi = require("ffi")', 'local out = {}']
    for path in LUA_ORDER:
        for block in lua_cdefs(path):
            script.append('pcall(ffi.cdef, [==[' + block + ']==])')
    for name, (lua_type, _) in wanted.items():
        if name not in current:
            continue
        names = ', '.join('"%s"' % f[0] for f in current[name]['fields'])
        script.append(f'do local ok, size = pcall(ffi.sizeof, "{lua_type}")\n'
                      f'  if ok and size then local parts = {{ "{name}", tostring(size) }}\n'
                      f'    for _, f in ipairs({{ {names} }}) do local okf, at = pcall(ffi.offsetof, "{lua_type}", f)\n'
                      f'      parts[#parts + 1] = f .. "=" .. ((okf and at) and tostring(at) or "-") end\n'
                      f'    print(table.concat(parts, " "))\n'
                      f'  else print("{name} missing") end end')
    with tempfile.NamedTemporaryFile('w', suffix='.lua', delete=False) as f:
        f.write('\n'.join(script))
        temp = f.name
    try:
        run = subprocess.run(['luajit', temp], capture_output=True, text=True)
    finally:
        os.unlink(temp)
    if run.returncode != 0:
        raise SystemExit('luajit failed:\n' + run.stderr)
    found = {}
    for line in run.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == 'missing':
            found[parts[0]] = None
            continue
        found[parts[0]] = {'size': int(parts[1]), 'fields': dict(p.split('=') for p in parts[2:])}
    return wanted, found


def compare_lua(layout):
    problems, notes = [], []
    wanted, found = lua_layouts(layout)
    for name, (lua_type, path) in wanted.items():
        if name not in layout:
            continue
        lua = found.get(name)
        if lua is None:
            problems.append(f'{lua_type} ({path}): not declared, or its cdef did not load')
            continue
        cpp = layout[name]
        shared = 0
        for fname, offset, _ in cpp['fields']:
            at = lua['fields'].get(fname, '-')
            if at == '-':
                continue
            shared += 1
            if int(at) != offset:
                problems.append(f'{lua_type}.{fname} ({path}): at {at} in Lua, {offset} in {name}')
        if lua['size'] > cpp['size']:
            problems.append(f'{lua_type} ({path}): {lua["size"]} bytes in Lua, more than {name}\'s {cpp["size"]}')
        if cpp['kind'] == 'record' and lua['size'] != cpp['size']:
            problems.append(f'{lua_type} ({path}): a record of {lua["size"]} bytes in Lua, {cpp["size"]} in {name}')
        if shared == 0:
            problems.append(f'{lua_type} ({path}): no field in common with {name}')
        missing = len(cpp['fields']) - shared
        if missing:
            notes.append(f'{lua_type}: {missing} of {name}\'s fields not declared in Lua (sizes still checked)')
    return problems, notes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--freeze', action='store_true', help='write the 1.0 baseline from the plugins as they are')
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    if not toolchain_ready():
        print('abi: the plugins\' toolchain is not here; their layouts were not checked')
        return 0
    layout = layouts()
    if args.freeze:
        BASELINE.parent.mkdir(parents=True, exist_ok=True)
        BASELINE.write_text(json.dumps(layout, indent=1, sort_keys=True) + '\n', encoding='utf-8')
        print(f'abi: froze {len(layout)} structs into {BASELINE.relative_to(ROOT)}')
        return 0
    baseline = json.loads(BASELINE.read_text(encoding='utf-8'))
    problems = compare(baseline, layout)
    lua_problems, notes = compare_lua(layout)
    problems += lua_problems
    if args.verbose:
        for note in notes:
            print('abi: ' + note)
    for p in problems:
        print('abi: BROKEN ' + p)
    blocks = sum(1 for v in baseline.values() if v['kind'] == 'block')
    print(f'abi: {blocks} blocks and {len(baseline) - blocks} records against 1.0, and their Lua copies: '
          + ('passed' if not problems else f'{len(problems)} broken'))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
