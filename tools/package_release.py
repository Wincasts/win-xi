#!/usr/bin/env python3
"""Packages one addon for a release: a zip to extract into the Ashita folder, and its checksum.

    tools/package_release.py <addon>          an addon, plugin or data named in RELEASES (chatbox, lens, mobdb, zone...)
    tools/package_release.py --all            each of them

Each zip holds the addon, everything it needs and nothing else:

    addons/<addon>/              the addon, with INSTALL.txt
    addons/<addon>/winxi/        for an addon released for people who use no other winxi addon (zone):
                                 its own copy of the parts of winxi it loads and their art, used by it alone
                                 (Ashita looks in the addon's folder before addons/libs), checked by running
                                 the addon's checks against the packaged files with no addons/libs/winxi
    addons/libs/winxi/           the shared library, in every zip but a standalone one (winxi.version says which it is)
    addons/winxisettings/        the shared look's settings window, in every zip but a standalone one
    plugins/namehook.dll         with name, built here, with its GPL license and where its source is
    plugins/uihook.dll           with buff/chatbox/party, built here, with its MIT license and where its source is

A plugin released alone (lens) is plugins/<plugin>.dll with its license, source and INSTALL.txt beside it.
Data released alone (mobdb) is the folder the addon reads it from, for the addon as its author releases it.

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

from build_tooltips import references as tooltip_references

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'Wincasts/win-xi'

# What each release brings besides the addon, winxi and winxisettings; standalone leaves out those two
RELEASES = {
    'buff': {'plugin': 'uihook'},
    'chatbox': {'plugin': 'uihook'},
    'lens': {'kind': 'plugin'},
    # Phoenix's monsters for ThornyFFXI's MobDB as it is: the data folder alone, versioned by the date it was made
    # the data is winxi's mobs set, the same files mobdb reads as data/<zone>.lua
    'mobdb': {'kind': 'data', 'source': 'forks/addons/mobdb/mobdb', 'from': 'addons/libs/winxi/data/phoenix/mobs', 'data': 'data',
              'changelog': 'forks/addons/mobdb/DATA_CHANGELOG.md',
              'title': 'mobdb data for Phoenix'},
    'parse': {},
    'sct': {},
    # Released for people who use no other winxi addon: its own winxi, for the zones' kinds and the rules
    'vis': {'standalone': True, 'private_winxi': True,
            'checks': [('vis', 'addons/vis/vis.lua', 'vis_check.lua'), ('vis', 'addons/vis/vis.lua', 'vis_game_check.lua')]},
    'inventory': {},
    'name': {'plugin': 'namehook'},
    'occlusionfix': {'standalone': True},
    'party': {'plugin': 'uihook'},
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
MIT = {'addons/libs/winxi', 'addons/winxisettings', 'addons/buff', 'addons/name', 'addons/occlusionfix',
       'addons/trigger', 'addons/zone', 'addons/zone/winxi', 'addons/vis/winxi', 'addons/chatbox', 'addons/parse', 'addons/sct', 'addons/vis'}
# The art a winxi module draws, which goes with it into an addon's own copy
WINXI_ART = {'backgrounds': 'assets/backgrounds', 'borders': 'assets/borders', 'bars': 'assets/bars'}
# The terms each plugin is under: namehook is a fork of GPL code, the others this repository's own
PLUGIN_LICENSES = {'namehook': 'the GNU GPL v3.0', 'uihook': 'the MIT License', 'lens': 'the MIT License'}
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


def plugin_version(plugin):
    match = re.search(r'GetVersion\(\) const override \{ return ([\d.]+); \}', (ROOT / 'plugins' / plugin / 'src' / f'{plugin}.cpp').read_text())
    if not match:
        raise ValueError(f'No GetVersion in plugins/{plugin}/src/{plugin}.cpp')
    return match.group(1)


def released(addon):
    """The versions released before, from the repository's tags: <addon>-v<version>."""
    return [tag[len(addon) + 2:] for tag in git('tag', '-l', f'{addon}-v*').split() if '-test' not in tag]


def notes(addon, version, changelog):
    """The changelog's sections since the last release: the first section alone for a first release."""
    if not changelog.is_file():
        raise FileNotFoundError(f'{changelog} is needed for the release notes')
    sections = re.split(r'^## ', changelog.read_text(), flags=re.M)[1:]
    top = sections[0] if sections else ''
    if not top.startswith(version + ' ') and not top.startswith(version + '\n'):
        raise ValueError(f"{changelog}'s first section is not {version}: add it before releasing")
    before = set(released(addon)) - {version}
    taken = [top]
    for section in sections[1:]:
        if not before or section.split()[0] in before:
            break
        taken.append(section)
    return ''.join('## ' + section.strip() + '\n\n' for section in taken).rstrip() + '\n'


def winxi_dependencies(text):
    modules = set(re.findall(r"require\(['\"]winxi\.([\w.]+)['\"]\)", text))
    # and those loaded where they may be missing: pcall(require, 'winxi.debuff_durations')
    modules.update(re.findall(r"pcall\(\s*require\s*,\s*['\"]winxi\.([\w.]+)['\"]\s*\)", text))
    # tips.Get loads its catalogue by namespace at runtime, not a literal require.
    modules.update('data.tooltips.' + key.split('.')[0] for key in tooltip_references(text))
    return modules


def winxi_modules(tree, addon):
    """The winxi modules the addon loads, and those they load, as paths under libs/winxi: version.lua too."""
    winxi = tree / 'addons/libs/winxi'
    wanted = set()
    for source in (tree / 'addons' / addon).rglob('*.lua'):
        wanted |= winxi_dependencies(source.read_text(encoding='utf-8', errors='replace'))
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
        queue += list(winxi_dependencies(path.read_text(encoding='utf-8')))
    return sorted(found), [found[name] for name in sorted(found)]


def data_sets(text):
    """The sets of winxi's data a file reads by name: gamedata.Read('items', ...), gamedata.Lookup('zonekinds')
    and catalog.New('statuses'), however winxi.gamedata or winxi.catalog is reached."""
    sets = set(re.findall(r"\b(?:Read|Lookup)\(\s*['\"](\w+)['\"]", text))
    sets.update(re.findall(r"catalog['\"]?\)?\.New\(\s*['\"](\w+)['\"]", text))
    return sets


def winxi_data(tree, addon, paths):
    """What of libs/winxi/data an addon's own winxi carries, as paths under libs/winxi: each set it or the
    winxi modules it loads read, from every server's folder that has it (and data's own, for the sets that
    are no server's), with the list of servers and each server's manifest."""
    winxi = tree / 'addons/libs/winxi'
    data = winxi / 'data'
    wanted = set()
    for source in [*(tree / 'addons' / addon).rglob('*.lua'), *(winxi / path for path in paths)]:
        wanted |= data_sets(source.read_text(encoding='utf-8', errors='replace'))
    servers = sorted(path.parent for path in data.glob('*/manifest.lua'))
    found = [data / 'datasets.lua'] + [server / 'manifest.lua' for server in servers]
    for name in sorted(wanted):
        folders = [folder / name for folder in [*servers, data] if (folder / name).is_dir()]
        if not folders:
            raise FileNotFoundError(f'{addon} reads the {name} set of winxi\'s data, which no server\'s folder has')
        found += folders
    return sorted(wanted), [path.relative_to(winxi) for path in found]


def private_winxi(addon, tree, staging):
    """The addon's own copy of what it needs of winxi, in addons/<addon>/winxi: its data sets too."""
    winxi = tree / 'addons/libs/winxi'
    names, paths = winxi_modules(tree, addon)
    target = staging / 'addons' / addon / 'winxi'
    for path in paths:
        (target / path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(winxi / path, target / path)
    sets, data = winxi_data(tree, addon, paths)
    for path in data:
        (target / path).parent.mkdir(parents=True, exist_ok=True)
        if (winxi / path).is_dir():
            shutil.copytree(winxi / path, target / path, dirs_exist_ok=True)
        else:
            shutil.copy2(winxi / path, target / path)
    if sets:
        print(f"  {addon}'s own winxi carries the data sets {', '.join(sets)}")
    for name, art in WINXI_ART.items():
        if name in names:
            shutil.copytree(winxi / art, target / art, ignore=shutil.ignore_patterns(*LEFT_OUT))
    number = re.search(r'Number = (\d+)', (winxi / 'version.lua').read_text()).group(1)
    (target / 'README.txt').write_text(
        f'The parts of winxi {number} that {addon} uses, and their art: its own copy, used by {addon} alone.\n'
        f'Ashita looks in addons/{addon} before addons/libs, so a winxi installed by another addon is left\n'
        f'to that addon. The look follows the shared theme (config/addons/winxi) where winxisettings has\n'
        f'set one, and winxi\'s own otherwise. Its data (data/<server>/<set>) is the sets {addon} reads, for each\n'
        f'server there is data for: the server whose data is used is chosen in winxisettings, for every winxi addon.\n'
        f'winxi is at https://github.com/{REPOSITORY}/tree/main/addons/libs/winxi\n')
    return names


def check_private(addon, extras, staging):
    """Runs the addon's checks against the packaged files alone: no addons/libs/winxi to fall back on."""
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        shutil.copytree(ROOT / 'tests', root / 'tests')
        shutil.copytree(staging / 'addons', root / 'addons')
        if (root / 'addons/libs/winxi').exists():
            raise RuntimeError('addons/libs/winxi got into a release that carries its own')
        for name, target, check in extras.get('checks', []):
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


def finish(name, title, archive, release_notes, output, commit):
    """Checks the zip, writes its checksum and notes, and prints the command that makes the release."""
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip():
            raise ValueError(f'{archive} did not read back whole')
        names = zipped.namelist()
    if any(not entry.startswith(('addons/', 'plugins/')) for entry in names):
        raise ValueError('Something outside addons/ and plugins/ got in')
    digest = sha256(archive.read_bytes())
    (output / f'{name}.zip.sha256').write_text(f'{digest}  {archive.name}\n')
    (output / f'{name}.notes.md').write_text(release_notes)
    shown = archive.relative_to(ROOT) if archive.is_relative_to(ROOT) else archive
    print(f'{shown}: {len(names)} files, {archive.stat().st_size:,} bytes, sha256 {digest}')
    print(f'  gh release create {name} -R {REPOSITORY} --target {commit} --prerelease '
          f'--title "{title}" --notes-file dist/{name}.notes.md '
          f'dist/{name}.zip dist/{name}.zip.sha256')


def write_zip(staging, archive, output):
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


def package_plugin(plugin, output):
    """A plugin alone: plugins/<plugin>.dll, its license, where its source is and how to load it."""
    commit = git('rev-parse', 'HEAD')
    folder = f'plugins/{plugin}'
    dirty = git('status', '--porcelain', '--', folder)
    if dirty:
        raise RuntimeError('Uncommitted changes in what would be packaged: commit them first\n' + dirty)
    version = plugin_version(plugin)
    name = f'{plugin}-v{version}'
    archive = output / f'{name}.zip'
    if archive.exists():
        raise FileExistsError(f'{archive} is already there: remove it, or raise the version')
    release_notes = notes(plugin, version, ROOT / folder / 'CHANGELOG.md')
    with tempfile.TemporaryDirectory() as temporary:
        staging = Path(temporary) / name
        (staging / 'plugins').mkdir(parents=True)
        shutil.copy2(build_plugin(plugin), staging / 'plugins' / f'{plugin}.dll')
        (staging / 'plugins' / f'{plugin}-LICENSE.md').write_bytes(git('show', f'{commit}:{folder}/LICENSE.md', binary=True))
        (staging / 'plugins' / f'{plugin}-SOURCE.txt').write_text(
            f'{plugin}.dll is built from the source at\n'
            f'https://github.com/{REPOSITORY}/tree/{commit}/plugins/{plugin}\n'
            f'and is licensed under {PLUGIN_LICENSES[plugin]}: {plugin}-LICENSE.md.\n')
        (staging / 'plugins' / f'{plugin}-INSTALL.txt').write_text(
            f'{plugin} {version}, from https://github.com/{REPOSITORY}\n\n'
            'Extract the zip into your Ashita folder (the one holding addons, plugins and config), merging\n'
            f'folders and replacing files. Your settings, in config/{plugin}, are kept. Unload the plugin\n'
            f'(/unload {plugin}) before replacing it.\n\nThen, in game:\n    /load {plugin}\n    /{plugin} help\n')
        write_zip(staging, archive, output)
    finish(name, f'{plugin} {version}', archive, release_notes + '\nNeeds nothing else. Extract into your Ashita folder; '
           f'see plugins/{plugin}-INSTALL.txt.\n', output, commit)


def package_data(addon, output):
    """An addon's data alone, as the folder it reads it from: for the addon as its author releases it."""
    extras = RELEASES[addon]
    commit = git('rev-parse', 'HEAD')
    # where the data is in the repository: its own folder, or a set of winxi's ('from')
    source = extras.get('from') or f"{extras['source']}/{extras['data']}"
    changelog = ROOT / extras['changelog']
    dirty = git('status', '--porcelain', '--', source, extras['changelog'])
    if dirty:
        raise RuntimeError('Uncommitted changes in what would be packaged: commit them first\n' + dirty)
    sections = re.findall(r'^## (\S+)', changelog.read_text(), flags=re.M)
    if not sections:
        raise ValueError(f'{changelog} has no section to release')
    version = sections[0]
    name = f'{addon}-data-v{version}'
    archive = output / f'{name}.zip'
    if archive.exists():
        raise FileExistsError(f'{archive} is already there: remove it, or add a newer section')
    release_notes = notes(f'{addon}-data', version, changelog)
    archived = git('archive', '--format=tar', commit, '--', source, binary=True)
    with tempfile.TemporaryDirectory() as temporary:
        tree = Path(temporary) / 'tree'
        with tarfile.open(fileobj=io.BytesIO(archived)) as tar:
            tar.extractall(tree, filter='data')
        staging = Path(temporary) / name
        target = staging / 'addons' / addon / extras['data']
        shutil.copytree(tree / source, target, ignore=shutil.ignore_patterns(*LEFT_OUT))
        count = len(list(target.glob('*.lua')))
        (staging / 'addons' / addon / f'{addon}-data-INSTALL.txt').write_text(
            f'{extras["title"]} {version}, from https://github.com/{REPOSITORY}\n\n'
            f'The data alone, {count} zones of it, for {addon} as you have it installed already. Unload {addon}\n'
            f'(/addon unload {addon}), empty addons/{addon}/{extras["data"]}, then extract the zip into your Ashita folder\n'
            f'(the one holding addons, plugins and config). Emptying the folder first matters: a zone with no\n'
            f'monsters on the server would otherwise keep its old file. Then /addon load {addon}.\n\n'
            f'Made with import_phoenix.py, at https://github.com/{REPOSITORY}/tree/{commit}/{extras["source"]}\n'
            f'(through tools/build_winxi_data.py, which writes it as {source})\n')
        write_zip(staging, archive, output)
    finish(name, f'{extras["title"]} {version}', archive, release_notes + f'\nThe data alone ({count} zones), for {addon} '
           f'as you have it. Empty addons/{addon}/{extras["data"]} first, then extract into your Ashita folder; '
           f'see addons/{addon}/{addon}-data-INSTALL.txt.\n', output, commit)


def package(addon, output):
    extras = RELEASES[addon]
    if extras.get('kind') == 'plugin':
        return package_plugin(addon, output)
    if extras.get('kind') == 'data':
        return package_data(addon, output)
    commit = git('rev-parse', 'HEAD')
    version = addon_version(ROOT / 'addons' / addon / f'{addon}.lua')
    name = f'{addon}-v{version}'
    archive = output / f'{name}.zip'
    if archive.exists():
        raise FileExistsError(f'{archive} is already there: remove it, or raise the version')
    release_notes = notes(addon, version, ROOT / 'addons' / addon / 'CHANGELOG.md')

    with tempfile.TemporaryDirectory() as temporary:
        staging = Path(temporary) / name
        staging.mkdir()
        stage(addon, extras, staging, commit)
        (staging / 'addons' / addon / 'INSTALL.txt').write_text(install_text(addon, version, extras))
        if extras.get('private_winxi'):
            check_private(addon, extras, staging)

        write_zip(staging, archive, output)

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
    finish(name, f'{addon} {version}', archive,
           release_notes + f'\n{comes} Extract into your Ashita folder; see addons/{addon}/INSTALL.txt.\n', output, commit)


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
