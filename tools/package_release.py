#!/usr/bin/env python3
"""Packages one addon for a release: a zip to extract into the Ashita folder, and its checksum.

    tools/package_release.py <addon>          buff, clock, inventory, name, occlusionfix, party, trigger or zone
    tools/package_release.py --all            each of them

Each zip holds the addon, everything it needs and nothing else:

    addons/<addon>/              the addon, with INSTALL.txt
    addons/<addon>/winxi/        for an addon released for people who use no other winxi addon (zone):
                                 its own copy of the parts of winxi it loads and their art, used by it alone
                                 (Ashita looks in the addon's folder before addons/libs), checked by running
                                 the addon's checks against the packaged files with no addons/libs/winxi
    addons/libs/winxi/           the shared library, in every zip but a standalone one (winxi.version says which it is)
    addons/winxisettings/        the shared look's settings window, in every zip but a standalone one
    addons/hideparty/            with party
    plugins/namehook.dll         with name, built here, with its GPL license and where its source is
    plugins/uihook.dll           with buff/party, built here, with its MIT license and where its source is

The files are the commit's (git archive of HEAD), never the working folder's, so the zip is what is on
GitHub at that commit. Anything uncommitted in what goes into a zip stops the packaging. Run the checks
(tests/run.sh) first. Written to dist/: <addon>-v<version>.zip, its .sha256, and .notes.md, the top of
the addon's CHANGELOG.md, for the release. The command that makes the release is printed, not run.
"""
import argparse
import hashlib
import io
import os
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'Wincasts/win-xi'

# What each release brings besides the addon, winxi and winxisettings; standalone leaves out those two
RELEASES = {
    'buff': {'plugin': 'uihook'},
    'clock': {'plugin': 'uihook'},
    'inventory': {},
    'name': {'plugin': 'namehook'},
    'occlusionfix': {'standalone': True},
    'party': {'plugin': 'uihook', 'addons': {'hideparty': 'forks/addons/hideparty'}},
    'trigger': {},
    # Released for people who use no other winxi addon, so it carries its own winxi. Its research notes
    # and the data and flag copies no code loads are left out.
    'zone': {'standalone': True, 'private_winxi': True,
             'leave_out': ['research', 'assets/flags', 'assets/backgrounds/flags/*.webp',
                           'data/king_ranperres_tomb_map_labels.lua', 'data/king_ranperres_tomb_poi.lua',
                           'data/map_subregions.lua'],
             'checks': [('zone', 'tests/zoneinfo_fixture.lua', 'zoneinfo_check.lua'),
                        ('zoneinfo-presentation', 'tests/zoneinfo_fixture.lua', 'zoneinfo_presentation_ui_check.lua'),
                        ('zoneinfo-gdi', 'tests/zoneinfo_fixture.lua', 'zoneinfo_gdi_check.lua'),
                        ('zoneinfo-styles', 'tests/zoneinfo_fixture.lua', 'zoneinfo_styles_check.lua')]},
}
# MIT, as the repository's LICENSE says: each is given a copy of it. The others keep their own terms.
MIT = {'addons/clock', 'addons/libs/winxi', 'addons/winxisettings', 'addons/buff', 'addons/name', 'addons/occlusionfix',
       'addons/trigger', 'addons/zone', 'addons/zone/winxi'}
# The art a winxi module draws, which goes with it into an addon's own copy
WINXI_ART = {'backgrounds': 'assets/backgrounds', 'borders': 'assets/borders', 'bars': 'assets/bars'}
# The terms each plugin is under: namehook is a fork of GPL code, buffhook this repository's own
PLUGIN_LICENSES = {'namehook': 'the GNU GPL v3.0', 'buffhook': 'the MIT License', 'uihook': 'the MIT License'}
# Kept with the addons to make their art and sounds, and of no use in the game
LEFT_OUT = ('*.py', '*.sh')
# Text no release should hold: the author's character's settings folder
PRIVATE = (b'Win_4458',)


def git(*args, binary=False):
    out = subprocess.check_output(['git', '-C', str(ROOT), *args])
    return out if binary else out.decode().strip()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def addon_version(source):
    match = re.search(r"^addon\.version\s*=\s*'([^']+)'", source.read_text(), re.M)
    if not match:
        raise ValueError(f'No addon.version in {source}')
    return match.group(1)


def notes(addon, version):
    changelog = ROOT / 'addons' / addon / 'CHANGELOG.md'
    if not changelog.is_file():
        raise FileNotFoundError(f'{changelog} is needed for the release notes')
    sections = re.split(r'^## ', changelog.read_text(), flags=re.M)
    top = sections[1] if len(sections) > 1 else ''
    if not top.startswith(version + ' ') and not top.startswith(version + '\n'):
        raise ValueError(f"{changelog}'s first section is not {version}: add it before releasing")
    return '## ' + top.strip() + '\n'


def winxi_modules(tree, addon):
    """The winxi modules the addon loads, and those they load, as paths under libs/winxi: version.lua too."""
    winxi = tree / 'addons/libs/winxi'
    wanted = set()
    for source in (tree / 'addons' / addon).rglob('*.lua'):
        wanted |= set(re.findall(r"require\(['\"]winxi\.([\w.]+)['\"]\)", source.read_text(encoding='utf-8', errors='replace')))
    found, queue = {}, ['version', *wanted]
    while queue:
        name = queue.pop()
        if name in found:
            continue
        path = winxi / (name.replace('.', '/') + '.lua')
        if not path.is_file():
            path = winxi / name.replace('.', '/') / 'init.lua'
        if not path.is_file():
            raise FileNotFoundError(f'{addon} loads winxi.{name}, which libs/winxi does not have')
        found[name] = path.relative_to(winxi)
        queue += re.findall(r"require\(['\"]winxi\.([\w.]+)['\"]\)", path.read_text(encoding='utf-8'))
    return sorted(found), [found[name] for name in sorted(found)]


def private_winxi(addon, tree, staging):
    """The addon's own copy of what it needs of winxi, in addons/<addon>/winxi."""
    winxi = tree / 'addons/libs/winxi'
    names, paths = winxi_modules(tree, addon)
    target = staging / 'addons' / addon / 'winxi'
    for path in paths:
        (target / path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(winxi / path, target / path)
    for name, art in WINXI_ART.items():
        if name in names:
            shutil.copytree(winxi / art, target / art, ignore=shutil.ignore_patterns(*LEFT_OUT))
    number = re.search(r'Number = (\d+)', (winxi / 'version.lua').read_text()).group(1)
    (target / 'README.txt').write_text(
        f'The parts of winxi {number} that {addon} uses, and their art: its own copy, used by {addon} alone.\n'
        f'Ashita looks in addons/{addon} before addons/libs, so a winxi installed by another addon is left\n'
        f'to that addon. The look follows the shared theme (config/addons/winxi) where winxisettings has\n'
        f'set one, and winxi\'s own otherwise. winxi is at https://github.com/{REPOSITORY}/tree/main/addons/libs/winxi\n')
    return names


def check_private(addon, extras, staging):
    """Runs the addon's checks against the packaged files alone: no addons/libs/winxi to fall back on."""
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        shutil.copytree(ROOT / 'tests', root / 'tests')
        shutil.copytree(staging / 'addons', root / 'addons')
        if (root / 'addons/libs/winxi').exists():
            raise RuntimeError('addons/libs/winxi got into a release that carries its own')
        for name, target, check in extras['checks']:
            # the addon's folder searched from the start, as Ashita has it, and before addons/libs
            run = subprocess.run(['luajit', 'tests/harness.lua', name, target, f'tests/{check}'], cwd=root,
                                 capture_output=True, text=True, env={**os.environ, 'LUA_PATH': f'addons/{addon}/?.lua;;'})
            if run.returncode != 0:
                raise RuntimeError(f'{check} fails against the packaged {addon}:\n{run.stdout[-2000:]}{run.stderr[-2000:]}')
            print(f'  {check}: passes against the packaged files')


def install_text(addon, version, extras):
    lines = [
        f'{addon} {version}, from https://github.com/{REPOSITORY}',
        '',
        'Extract the zip into your Ashita folder (the one holding addons, plugins and config), merging',
        'folders and replacing files. Your settings, in config, are kept.',
        '',
        'Then, in game:',
    ]
    if extras.get('plugin'):
        lines.append(f"    /load {extras['plugin']}")
    lines.append(f'    /addon load {addon}')
    for other in extras.get('addons', {}):
        lines.append(f'    /addon load {other}          (optional: see its README)')
    if extras.get('private_winxi'):
        lines += [
            '',
            f'{addon} needs nothing else: addons/{addon}/winxi is its own copy of the parts of winxi it uses.',
            f'If you use other winxi addons, the look they share (set with winxisettings and /winxi) is {addon}\'s too.',
        ]
    if extras.get('standalone'):
        return '\n'.join(lines) + '\n'
    lines += [
        '',
        'and for the look every winxi addon shares: /addon load winxisettings, then /winxi.',
        '',
        'Every winxi addon comes with its own copy of addons/libs/winxi. If an addon says it needs a',
        'newer winxi, install the newest release of any winxi addon.',
    ]
    return '\n'.join(lines) + '\n'


def stage(addon, extras, staging, commit):
    paths = ['LICENSE', f'addons/{addon}']
    if not extras.get('standalone'):
        paths += ['addons/libs/winxi', 'addons/winxisettings']
    elif extras.get('private_winxi'):
        paths += ['addons/libs/winxi']
    paths += list(extras.get('addons', {}).values())
    if extras.get('plugin'):
        paths.append(f"plugins/{extras['plugin']}")

    dirty = git('status', '--porcelain', '--', *paths)
    if dirty:
        raise RuntimeError('Uncommitted changes in what would be packaged: commit them first\n' + dirty)

    archive = git('archive', '--format=tar', commit, '--', *paths, binary=True)
    tree = staging.parent / 'tree'
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(tree, filter='data')

    shutil.copytree(tree / 'addons', staging / 'addons', ignore=shutil.ignore_patterns(*LEFT_OUT))
    if extras.get('private_winxi'):
        shutil.rmtree(staging / 'addons/libs')
        private_winxi(addon, tree, staging)
    for pattern in extras.get('leave_out', []):
        matched = list((staging / 'addons' / addon).glob(pattern))
        if not matched:
            raise FileNotFoundError(f'Nothing in addons/{addon} is {pattern}: take it out of leave_out')
        for path in matched:
            shutil.rmtree(path) if path.is_dir() else path.unlink()
    for name, source in extras.get('addons', {}).items():
        if source != f'addons/{name}':
            shutil.copytree(tree / source, staging / 'addons' / name, ignore=shutil.ignore_patterns(*LEFT_OUT))
    for folder in MIT:
        if (staging / folder).is_dir() and not (staging / folder / 'LICENSE').exists():
            shutil.copy2(tree / 'LICENSE', staging / folder / 'LICENSE')

    plugin = extras.get('plugin')
    if plugin:
        built = build_plugin(plugin)
        (staging / 'plugins').mkdir()
        shutil.copy2(built, staging / 'plugins' / f'{plugin}.dll')
        shutil.copy2(tree / 'plugins' / plugin / 'LICENSE.md', staging / 'plugins' / f'{plugin}-LICENSE.md')
        (staging / 'plugins' / f'{plugin}-SOURCE.txt').write_text(
            f'{plugin}.dll is built from the source at\n'
            f'https://github.com/{REPOSITORY}/tree/{commit}/plugins/{plugin}\n'
            f'and is licensed under {PLUGIN_LICENSES[plugin]}: {plugin}-LICENSE.md.\n')


def build_plugin(plugin):
    """Builds the plugin from the working folder, which stage() has found to be the commit's."""
    folder = ROOT / 'plugins' / plugin
    subprocess.run([str(folder / 'build.sh')], check=True, stdout=subprocess.DEVNULL)
    built = folder / 'build' / f'{plugin}.dll'
    binary = built.read_bytes()
    pe = struct.unpack_from('<I', binary, 0x3c)[0]
    if (binary[:2] != b'MZ' or binary[pe:pe + 4] != b'PE\0\0'
            or struct.unpack_from('<H', binary, pe + 4)[0] != 0x14c
            or not (struct.unpack_from('<H', binary, pe + 22)[0] & 0x2000)):
        raise ValueError(f'{built} is not a 32-bit Windows DLL')
    return built


def package(addon, output):
    extras = RELEASES[addon]
    commit = git('rev-parse', 'HEAD')
    version = addon_version(ROOT / 'addons' / addon / f'{addon}.lua')
    name = f'{addon}-v{version}'
    archive = output / f'{name}.zip'
    if archive.exists():
        raise FileExistsError(f'{archive} is already there: remove it, or raise the version')
    release_notes = notes(addon, version)

    with tempfile.TemporaryDirectory() as temporary:
        staging = Path(temporary) / name
        staging.mkdir()
        stage(addon, extras, staging, commit)
        (staging / 'addons' / addon / 'INSTALL.txt').write_text(install_text(addon, version, extras))
        if extras.get('private_winxi'):
            check_private(addon, extras, staging)

        files = sorted(path for path in staging.rglob('*') if path.is_file())
        for path in files:
            data = path.read_bytes()
            for private in PRIVATE:
                if private in data:
                    raise ValueError(f'{path.relative_to(staging)} holds {private.decode()}')
        output.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
            for path in files:
                zipped.write(path, path.relative_to(staging).as_posix())

    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip():
            raise ValueError(f'{archive} did not read back whole')
        names = zipped.namelist()
    if any(not entry.startswith(('addons/', 'plugins/')) for entry in names):
        raise ValueError('Something outside addons/ and plugins/ got in')

    digest = sha256(archive.read_bytes())
    (output / f'{name}.zip.sha256').write_text(f'{digest}  {archive.name}\n')
    winxi = re.search(r'Number = (\d+)', (ROOT / 'addons/libs/winxi/version.lua').read_text()).group(1)
    if extras.get('private_winxi'):
        comes = f'Needs nothing else: it carries its own copy of the parts of winxi {winxi} it uses.'
    elif extras.get('standalone'):
        comes = 'Needs nothing else.'
    else:
        bundled = [f'winxi {winxi}', 'winxisettings', *extras.get('addons', {})]
        if extras.get('plugin'):
            bundled.append(f"the {extras['plugin']} plugin")
        comes = f"Comes with {', '.join(bundled[:-1])} and {bundled[-1]}."
    (output / f'{name}.notes.md').write_text(
        release_notes + f'\n{comes} Extract into your Ashita folder; see addons/{addon}/INSTALL.txt.\n')

    shown = archive.relative_to(ROOT) if archive.is_relative_to(ROOT) else archive
    print(f'{shown}: {len(names)} files, {archive.stat().st_size:,} bytes, sha256 {digest}')
    print(f'  gh release create {name} -R {REPOSITORY} --target {commit} --prerelease '
          f'--title "{addon} {version}" --notes-file dist/{name}.notes.md '
          f'dist/{name}.zip dist/{name}.zip.sha256')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('addon', nargs='?', choices=sorted(RELEASES))
    parser.add_argument('--all', action='store_true', help='every addon that is released')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    if args.all == (args.addon is not None):
        parser.error('name one addon, or give --all')
    for addon in sorted(RELEASES) if args.all else [args.addon]:
        package(addon, args.output.resolve())
