#!/usr/bin/env python3
"""Package the current name/namehook working tree for Ashita v4.

Build/test first: plugins/namehook/build.sh && plugins/namehook/tests/run.sh
Then: python tools/package_name.py
Produces a root-layout ZIP, extracted staging folder, and SHA256 sidecar in dist/.
Does not modify the live install or include personal settings.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
IGNORE = shutil.ignore_patterns('.git', '.github', '__pycache__', '*.pyc', 'build')


def git_revision(path):
    return subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package(output, name, sdk):
    if Path(name).name != name or name in ('.', '..'):
        raise ValueError('Package name must be a single directory name')
    output = Path(output).resolve()
    staging = output / name
    archive = output / (name + '.zip')
    if staging.exists() or archive.exists():
        raise FileExistsError(f'Refusing to overwrite an existing package: {staging}')
    plugin = ROOT / 'plugins/namehook/build/namehook.dll'
    binary = plugin.read_bytes()
    pe = struct.unpack_from('<I', binary, 0x3c)[0]
    if (binary[:2] != b'MZ' or binary[pe:pe + 4] != b'PE\0\0'
            or struct.unpack_from('<H', binary, pe + 4)[0] != 0x14c
            or not (struct.unpack_from('<H', binary, pe + 22)[0] & 0x2000)):
        raise ValueError('namehook.dll must be a 32-bit Windows DLL')
    sdk = Path(sdk).resolve()
    if not (sdk / 'Ashita.h').is_file():
        raise FileNotFoundError(f'No matching Ashita SDK in {sdk}')
    output.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / 'addons/name', staging / 'addons/name', ignore=IGNORE)
    shutil.copytree(ROOT / 'addons/libs/winxi', staging / 'addons/libs/winxi', ignore=IGNORE)
    (staging / 'plugins').mkdir()
    shutil.copy2(plugin, staging / 'plugins/namehook.dll')
    # Corresponding GPL plugin source and the SDK used to build it.
    shutil.copytree(ROOT / 'plugins/namehook', staging / 'source/namehook', ignore=IGNORE)
    shutil.copytree(sdk, staging / 'source/ashita-sdk', ignore=IGNORE)
    (staging / 'source/tools').mkdir()
    shutil.copy2(Path(__file__), staging / 'source/tools/package_name.py')
    for tool in ('export_name_icons.py', 'build_name_placeholders.py'):
        shutil.copy2(ROOT / 'tools' / tool, staging / 'source/tools' / tool)
    importer = staging / 'source/addons/mobdb/mobdb'
    importer.mkdir(parents=True)
    for filename in ('import_phoenix.py', 'client_names.json'):
        shutil.copy2(ROOT / 'addons/mobdb/mobdb' / filename, importer / filename)
    info = {
        'package': name,
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'base_commit': git_revision(ROOT),
        'source_snapshot': 'Current working tree, including uncommitted changes; not a commit-only release.',
        'sdk_commit': git_revision(sdk),
        'plugin_sha256': sha256(plugin),
        'plugin_target': 'Windows x86 / Ashita v4',
        'live_game_verified': False,
        'personal_configs_included': False,
    }
    (staging / 'BUILD-INFO.json').write_text(json.dumps(info, indent=2) + '\n')
    (staging / 'INSTALL-AND-TEST.txt').write_text(INSTALL)
    files = sorted(path for path in staging.rglob('*') if path.is_file())
    manifest = ''.join(f'{sha256(path)}  {path.relative_to(staging).as_posix()}\n' for path in files)
    (staging / 'SHA256SUMS.txt').write_text(manifest)
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for path in sorted(staging.rglob('*')):
            if path.is_file():
                zipped.write(path, path.relative_to(staging).as_posix())
    with zipfile.ZipFile(archive) as zipped:
        bad = zipped.testzip()
        if bad:
            raise ValueError(f'ZIP CRC validation failed: {bad}')
        if any(path.startswith('config/') for path in zipped.namelist()):
            raise ValueError('Personal configuration unexpectedly included')
    digest = sha256(archive)
    archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
    print(f'Package: {archive}\nSize: {archive.stat().st_size:,} bytes\nSHA256: {digest}')


INSTALL = """NAME + NAMEHOOK - ASHITA V4 EXPERIMENTAL INSTALL PACKAGE
======================================================

REQUIREMENTS
- Current Ashita v4 beta with standard addon libraries (common, settings,
  imgui, d3d8 and their dependencies). Ashita itself is not included.
- Microsoft Visual C++ 2015-2022 x86 redistributable, from Microsoft, if needed.
  The plugin is 32-bit even on 64-bit Windows.
- The preferred font is Corbel Italic (corbeli.ttf), normally available on
  Windows. Select Default or another installed font if it is unavailable.

INSTALL / UPDATE
1. Close the game and Ashita before replacing the plugin DLL.
2. Back up addons/name, addons/libs/winxi, plugins/namehook.dll,
   config/addons/name and config/namehook if already present.
3. Extract this ZIP into your Ashita root (the folder containing addons,
   plugins and config). MERGE folders and replace packaged files. Do not
   delete existing libraries or configs. There is no enclosing ZIP folder.
   Confirm these paths:
       addons/name/name.lua
       addons/name/zone_names.lua
       addons/name/assets/player-icons.png
       addons/name/letter_badges.lua
       addons/libs/winxi/shell.lua
       plugins/namehook.dll
4. Disable startup entries for nameplate, nameplatew, nameplatehook or any
   competing nameplate plugin. Do not load them together with namehook.
5. Start the game, then enter:
       /load namehook
       /addon load name
6. Open settings with /name. Optional startup entries use the same load order.

NEW FEATURES / TESTING
- Bundled player-icon atlas with startup load recovery.
- Nameplates -> Mob Nameplates: Show Level / Range, Show Aggro Icons,
  Mob Letters, and editable Mob Format.
- One Mob Format applies to ordinary, targeted and checked monsters. Legacy
  Target Format and Checked Format overrides are ignored.
- Mob Letters is OFF by default. Enable it to test the square badge with a
  transparent uppercase letter cutout, using your chosen font and Bold style.
  The fill follows the nameplate colour. The badge scales and fades with it.
- Enabling letters adds a suffix automatically unless the format contains
  [letter]. To position/tint the badge explicitly, try:
       [aggro] Lv [level]. [name] [letter:yellow]
- Badges fall back to plain letters if texture preparation is unavailable;
  a diagnostic is printed, and preparation retries once per second.
- Letter assignments use the game's own list of each area's names, read
  from the client's files as the area is entered and sorted by entity
  index. Users need the same game files (on Phoenix, the launcher's
  EraDATs) for matching assignments. A-Z wraps after 26 slots; missing/renamed slots
  remain unlabelled. This is experimental, not a universal mob identifier.
- Check font selection, Bold, badge padding/alignment, player icons, target
  and checked mobs, zone changes, respawns, distance fading, crowded areas,
  alt-tab, walls/character occlusion and resolution/render-scale changes.
- Existing character settings take precedence. No personal configs are
  included or overwritten. To try fresh defaults, back up and temporarily
  rename config/addons/name while Ashita is closed.
- Preferred defaults: Corbel Italic, bold, sizes 28/10, outline 1, player icons
  93%, check size 75%. Own name, other players and other pets are hidden;
  party/alliance, your pet, NPCs and monsters are shown; target is enabled.
- This remains an ImGui test build: Experimental/Appearance tabs and text
  control verbs are hidden/disabled. GDI is forced off for the public build.

ROLLBACK
Close the game/Ashita and restore the backed-up addon, winxi, DLL and configs.
When changing plugins in a running game, unload name before namehook; never
load competing nameplate plugins simultaneously.

CONTENTS / INTEGRITY / SOURCE
- addons/name: addon Lua source, assets, level data.
- addons/libs/winxi: required shared library snapshot and resources.
- plugins/namehook.dll: Windows x86 plugin.
- source/namehook: corresponding GPLv3 source, build scripts, tests, license.
- source/ashita-sdk: matching SDK headers and licenses.
- source/tools and source/addons/mobdb: asset/roster exporter source and name
  dictionary. Regenerating rosters requires PyYAML and your own Phoenix YAML
  checkout (--server); exporting player icons requires your own game DAT.
- BUILD-INFO.json: base revision and working-tree snapshot metadata.
- SHA256SUMS.txt: hashes for all packaged files except the manifest itself.
- The ZIP SHA256 is also supplied as a separate .zip.sha256 file.

To rebuild the plugin, see source/namehook/README.md and build.sh. Set
ASHITA_SDK_PATH to source/ashita-sdk, and supply your own compiler and Microsoft
CRT/Windows SDK. Those proprietary build toolchains are not included.
Plugin license: GNU GPLv3 (source/namehook/LICENSE.md). The retained gdifonts
library is MIT licensed (addons/name/gdifonts/LICENSE).

This is a current WORKING-TREE snapshot, not just the recorded base commit.
Build/test results do not replace live-client safety or appearance testing.
The badge appearance and behavior still need in-game verification.
"""


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--name', default='name-namehook-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S') + '-badges')
    parser.add_argument('--sdk', type=Path, default=Path(os.environ.get('ASHITA_SDK_PATH', ROOT / '.toolchain/ashita/plugins/sdk')))
    args = parser.parse_args()
    package(args.output, args.name, args.sdk)
