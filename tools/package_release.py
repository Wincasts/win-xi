#!/usr/bin/env python3
"""Packages one addon for a release: a zip to extract into the Ashita folder, and its checksum.

    tools/package_release.py <addon>          buff, inventory, name, party or trigger
    tools/package_release.py --all            each of them

Each zip holds the addon, everything it needs and nothing else:

    addons/<addon>/              the addon, with INSTALL.txt
    addons/libs/winxi/           the shared library, in every zip (winxi.version says which it is)
    addons/winxisettings/        the shared look's settings window, in every zip
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

# What each release brings besides the addon, winxi and winxisettings
RELEASES = {
    'buff': {'plugin': 'uihook'},
    'clock': {'plugin': 'uihook'},
    'inventory': {},
    'name': {'plugin': 'namehook'},
    'party': {'plugin': 'uihook', 'addons': {'hideparty': 'forks/addons/hideparty'}},
    'trigger': {},
}
# MIT, as the repository's LICENSE says: each is given a copy of it. The others keep their own terms.
MIT = {'addons/clock', 'addons/libs/winxi', 'addons/winxisettings', 'addons/buff', 'addons/name', 'addons/trigger'}
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
    lines += [
        '',
        'and for the look every winxi addon shares: /addon load winxisettings, then /winxi.',
        '',
        'Every winxi addon comes with its own copy of addons/libs/winxi. If an addon says it needs a',
        'newer winxi, install the newest release of any winxi addon.',
    ]
    return '\n'.join(lines) + '\n'


def stage(addon, extras, staging, commit):
    paths = ['LICENSE', f'addons/{addon}', 'addons/libs/winxi', 'addons/winxisettings']
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
    bundled = [f'winxi {winxi}', 'winxisettings', *extras.get('addons', {})]
    if extras.get('plugin'):
        bundled.append(f"the {extras['plugin']} plugin")
    (output / f'{name}.notes.md').write_text(
        release_notes + f"\nComes with {', '.join(bundled[:-1])} and {bundled[-1]}."
        + f' Extract into your Ashita folder; see addons/{addon}/INSTALL.txt.\n')

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
