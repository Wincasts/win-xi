# win-xi

Ashita v4 addons for Final Fantasy XI, made for and tested on the Phoenix server. Most of them draw
with `winxi`, a shared library. It gives every addon the same look, which you set once in one
settings window.

## Addons

| Addon | What it does | Command |
|---|---|---|
| [buff](addons/buff) | Shows the statuses you are under in a window, with FFXIV's icons and the time each has left | `/buff` |
| [chatbox](addons/chatbox) | Experimental WinXI chat log that the game still drives. It sets the game log's place and size (both log windows, routed as the game routes them). It has a native-backed input bar with its own auto-translate picker on Tab, native selection, the expanded log in WinXI tabs, scrollbar and font, and an info panel that shows the Vana'diel calendar, the zone's weather forecast and the ships' and airships' timetable under the mouse. Needs `uihook` | `/chatbox` |
| [vis](addons/vis) | Draw distance for the world and for entities, with the fog at its own scale. Objects don't pop in or lose detail, and distant terrain is drawn. Saved per character, with presets for cities, the outdoors and dungeons, and a zone's own values over them. Replaces drawdistance (it was called drawscale before 2.1) | `/vis` |
| [expbar](addons/expbar) | A basic experience bar with session XP gained and an optional XP/hour rate | `/expbar` |
| [hidecompass](addons/hidecompass) | Hides the game's compass | `/hidecompass` |
| [mark](addons/mark) | Pick a notorious monster and see its placeholders, their respawns, where it spawns on the map, its window and its drops | `/mark` |
| [mobcast](addons/mobcast) | Shows what the enemies around you are casting, readying and using, in a small window, worded as the chat log says it | `/mobcast` |
| [nativeui](addons/nativeui) | Gives the game's own menus a uihook skin (the winxi look), and moves the menus the game stacks over the chat log (the command menu, shops, yes-or-no, item descriptions) to where you want them. Needs `uihook` | `/nativeui` |
| [name](addons/name) | Shows and hides the names over characters' heads by what they are, and draws them in winxi's style. Needs the `namehook` plugin | `/name` |
| [occlusionfix](addons/occlusionfix) | Stops characters near walls, door frames and counters blinking out of view. Needs nothing else | `/occlusionfix` |
| [parse](addons/parse) | Experimental packet-based damage, observed hit rates and manual encounter DPS, with capture/replay diagnostics | `/parse` |
| [puppet](addons/puppet) | The next enfeebles and weapon skill an automaton will use | `/puppet` |
| [tempo](addons/tempo) | Bars that show when your next auto attack comes and when your next resting tick lands, about how much it restores, and when HP and MP will be full. A basic take on cadence | `/tempo` |
| [trigger](addons/trigger) | Plays a sound when something happens: a tell, an invite, a trade, an item dropping, low HP and the like | `/trigger` |
| [winxisettings](addons/winxisettings) | The look shared by every winxi addon, in one settings window | `/winxi` |
| [zone](addons/zone) | Zone, region and weather banners, and a location line | `/zone` |

Each addon's folder has a README with all of its commands and settings.

## Installing

**buff**, **chatbox**, **inventory**, **name**, **occlusionfix**, **parse**, **party**, **sct**, **trigger**,
**vis** and **zone**, the **lens** plugin and **mobdb**'s Phoenix data are released one at a time, on the
[Releases](https://github.com/Wincasts/win-xi/releases) page. The newest of each is listed on one page,
[DOWNLOADS.md](DOWNLOADS.md). Each zip has everything the addon needs:
the `winxi` library and `winxisettings`; with name, the `namehook` plugin; and with buff, chatbox and
party, the `uihook` plugin. vis and zone carry their own copy of the parts of winxi they use, so they
need nothing else. occlusionfix needs nothing at all. Extract the zip into your Ashita folder (the one
that holds `addons`, `plugins` and `config`). Merge folders when asked. Then follow
`addons/<the addon>/INSTALL.txt`. If an addon says it needs a newer winxi, install the newest release
of any of them.

A release is made with `tools/package_release.py <addon>`, from the commit, after `tests/run.sh`.

The other addons, or anything newer than its release, can be copied from here. Every addon above
except occlusionfix needs the `winxi` library. Copy these into your Ashita folder, merging folders:

- `addons/libs/winxi`
- `addons/<the addon>` for each one you want
- `addons/winxisettings`, to change the shared look
- for `name`, also `plugins/namehook.dll` (see [plugins/namehook](plugins/namehook))
- for `buff`, `chatbox` or native `party` replacement, also `plugins/uihook.dll` (build/install:
  [plugins/uihook](plugins/uihook))
- `plugins/lens.dll`: shows the world through a Panini or cylindrical projection for wide screens, adds
  anti-aliasing for the world, sets the field of view and the true proportions the world is drawn with,
  and sets the camera's distance in battle (experimental, see [plugins/lens](plugins/lens))

Then, in game: `/addon load <the addon>`. For `name`, run `/load namehook` first. For `buff` or native
`party`, run `/load uihook` first. Uihook replaces the retired `buffhook` and `partyhook` plugins:
unload those before loading it, and remove their startup commands. Native rendering for party is
still opt-in; unload `hideparty` before turning it on.
[Chatbox](addons/chatbox/README.md) includes a native-backed WinXI input bar. It needs winxi 22 and
uihook 0.5 with chat ABI 13 (0.6 for native action-menu anchoring above the panel, for the expanded log
drawn wholly by chatbox and opened in place, and for the game's history read at start).
Its optional Info Panel belongs to chatbox and does not hide with the native clock.
Unload `clock` before `/chatbox panel on`, or you get two.
Load uihook first, and unload other chat replacements and visibility writers.
See the uihook README for migration and testing steps.

## What else is here

- `addons/` also holds addons built on other people's work (simplelog, targetlines, inventory, party),
  and `forks/addons` holds copies of other people's addons with changes made here (cbind, hideparty,
  cooldowns (formerly imrecast), mobdb, tcrossbar). Both are under their authors' terms, not the license below.
- `archive/` holds retired addons and their checks, including [treas](archive/addons/treas).
- `plugins/exclude` is retired work, kept to look back on.
- `tests/` runs the addons against a stand-in for Ashita: `tests/run.sh`.
- `tools/` builds the data and art the addons use.
- `deploy.sh` copies addons and built plugins between this folder and a live install,
  for development. `./deploy.sh push name` includes changed WinXI and namehook before
  the addon, even when only a dependency changed. Build it first with
  `bash plugins/namehook/build.sh`. `./deploy.sh -a push` includes built namehook
  even on a fresh install. Both keep the terminal safeguards and per-target backups.
  Reload namehook in game after deploying its DLL.

## License

The addons and library written here (those listed above, `winxi`, the tests and the tools) are MIT
licensed: see [LICENSE](LICENSE). `plugins/namehook` is a fork of a GPL v3 plugin and stays GPL v3.
Folders with a LICENSE of their own, and the other people's addons and forks listed above, keep their own terms.
Final Fantasy XI and its art belong to Square Enix.

Author: win.
