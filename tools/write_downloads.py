#!/usr/bin/env python3
"""Writes DOWNLOADS.md: one page with the newest release of every package, to share as one link.

    python3 tools/write_downloads.py          asks GitHub (gh) for the releases and writes DOWNLOADS.md

For each package in tools/package_release.py's RELEASES, the newest GitHub release whose tag starts with
its name: the version, a direct link to the zip and to its checksum, what the zip carries, and the release
page with its notes. A pre-release or release candidate is marked. Run it after publishing a round, and
commit the page. Shared as https://github.com/Wincasts/win-xi/blob/main/DOWNLOADS.md.
"""
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from package_release import RELEASES, REPOSITORY, ROOT

# One plain line each, for the page
WHAT = {
    'buff': 'The statuses you are under, in a window, with the time each has left.',
    'chatbox': 'A replacement chat log and input bar, with an info panel. Experimental.',
    'inventory': 'Your bags in a window, by mouse or controller, with the treasure pool and an equipment monitor.',
    'name': 'The names over players, NPCs and monsters, drawn your way, with health and cast bars.',
    'occlusionfix': 'Stops characters near walls and door frames from blinking out of view.',
    'parse': 'A combat parser: damage, hit rates and DPS for everyone in the fight.',
    'party': 'Party, target and pet frames in the style of XivParty.',
    'sct': 'Scrolling text for statuses, items received and key items.',
    'trigger': 'Plays a sound when something happens: a tell, an invite, a trade, low HP and more.',
    'vis': 'How far the world and the people in it are drawn, with the fog where you want it.',
    'zone': 'Banners for the zone, region, sub-zone and weather, and a location line.',
    'lens': 'The world through a wide-screen projection, with anti-aliasing and your choice of field of view.',
    'mobdb': "Phoenix's monsters for ThornyFFXI's MobDB addon: the data alone.",
}


def gh(*args):
    return json.loads(subprocess.check_output(['gh', *args, '-R', REPOSITORY]))


def carries(extras):
    if extras.get('kind') == 'plugin':
        return 'The plugin alone'
    if extras.get('kind') == 'data':
        return 'The data alone, for MobDB as you have it'
    if extras.get('private_winxi'):
        return 'Everything it needs, with its own copy of winxi'
    if extras.get('standalone'):
        return 'Everything it needs'
    if extras.get('plugin'):
        return f"winxi, winxisettings and the {extras['plugin']} plugin"
    return 'winxi and winxisettings'


def main():
    releases = gh('release', 'list', '--json', 'tagName,name,isPrerelease,isDraft,publishedAt', '--limit', '200')
    rows = []
    for package, extras in sorted(RELEASES.items()):
        prefix = f'{package}-data-v' if extras.get('kind') == 'data' else f'{package}-v'
        found = [r for r in releases if r['tagName'].startswith(prefix) and not r['isDraft']]
        if not found:
            continue
        newest = max(found, key=lambda r: r['publishedAt'])
        tag = newest['tagName']
        version = tag[len(prefix):]
        assets = gh('release', 'view', tag, '--json', 'assets')['assets']
        zips = [a for a in assets if a['name'].endswith('.zip')]
        sums = [a for a in assets if a['name'].endswith('.sha256')]
        if not zips:
            continue
        stage = re.search(r'-(pre\d+|rc\d+)$', version)
        kind = ''
        if stage:
            kind = ' (pre-release)' if stage.group(1).startswith('pre') else ' (release candidate)'
        elif newest['isPrerelease']:
            kind = ' (pre-release)'
        size = f"{zips[0]['size'] / 1_000_000:.1f} MB" if zips[0]['size'] >= 1_000_000 else f"{zips[0]['size'] / 1000:.0f} KB"
        checksum = f" · [sha256]({sums[0]['url']})" if sums else ''
        rows.append(f"| **{package}** | {version}{kind} | [{zips[0]['name']}]({zips[0]['url']}) ({size}){checksum} "
                    f"| {WHAT.get(package, '')} | {carries(extras)} | [notes](https://github.com/{REPOSITORY}/releases/tag/{tag}) |")
    when = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    text = f'''# Downloads

The newest package of each addon, as one list. Each zip is extracted into your Ashita folder (the one
holding `addons`, `plugins` and `config`), merging folders. Then follow the `INSTALL.txt` inside it.
A pre-release is a testing build; its notes say what to try. The full history is on the
[Releases](https://github.com/{REPOSITORY}/releases) page.

| Package | Version | Download | What it is | The zip carries | |
|---|---|---|---|---|---|
{chr(10).join(rows)}

Every winxi addon comes with its own copy of the `winxi` library. If one says it needs a newer winxi,
install the newest package of any of them. The list was written on {when} by `tools/write_downloads.py`.
'''
    (ROOT / 'DOWNLOADS.md').write_text(text)
    print(f'DOWNLOADS.md: {len(rows)} packages')


if __name__ == '__main__':
    main()
