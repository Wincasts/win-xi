# win-xi

Ashita v4 addons for Final Fantasy XI, made for and tested on the Phoenix server. Most of them draw
with `winxi`, a shared library that gives every addon the same look, set once in one settings window.

## Addons

| Addon | What it does | Command |
|---|---|---|
| [buff](addons/buff) | The statuses you are under, in a window, with FFXIV's icons and the time each has left | `/buff` |
| [chatbox](addons/chatbox) | Experimental WinXI chat log the game still drives: the game log's place and size (both log windows, routed as the game routes them), a native-backed input bar, native selection, and the expanded log in WinXI tabs, scrollbar and font; needs `uihook` | `/chatbox` |
| [hidecompass](addons/hidecompass) | Hides the game's compass | `/hidecompass` |
| [mark](addons/mark) | Pick a notorious monster and see its placeholders, their respawns, where it spawns on the map, its window and its drops | `/mark` |
| [name](addons/name) | Shows and hides the names over characters' heads by what they are, and draws them in winxi's style; needs the `namehook` plugin | `/name` |
| [parse](addons/parse) | Experimental packet-based damage, observed hit rates and manual encounter DPS, with capture/replay diagnostics | `/parse` |
| [puppet](addons/puppet) | The next enfeebles and weapon skill an automaton will use | `/puppet` |
| [trigger](addons/trigger) | Plays a sound when something happens: a tell, an invite, a trade, an item dropping, low HP and the like | `/trigger` |
| [winxisettings](addons/winxisettings) | The look shared by every winxi addon, in one settings window | `/winxi` |
| [zone](addons/zone) | Zone, region and weather banners, and a location line | `/zone` |

Each addon's folder has a README with all of its commands and settings.

## Installing

**buff**, **inventory**, **name**, **party** and **trigger** are released one at a time, on the
[Releases](https://github.com/Wincasts/win-xi/releases) page. Each zip has everything the addon needs:
the `winxi` library, `winxisettings`, and with name the `namehook` plugin. New buff/party packages include
`uihook` for native UI replacement; party also includes `hideparty` for the ordinary overlay mode.
Extract it into your Ashita folder (the one holding `addons`, `plugins` and `config`), merging
folders, and follow `addons/<the addon>/INSTALL.txt`. If an addon says it needs a newer winxi,
install the newest release of any of them.

A release is made with `tools/package_release.py <addon>`, from the commit, after `tests/run.sh`.

The others, or anything newer than its release, can be copied from here. Every addon above needs the
`winxi` library. Copy into your Ashita folder, merging folders:

- `addons/libs/winxi`
- `addons/<the addon>` for each one you want
- `addons/winxisettings`, to change the shared look
- for `name`, also `plugins/namehook.dll` (see [plugins/namehook](plugins/namehook))
- for `buff`, `clock`, `chatbox` or native `party` replacement, also `plugins/uihook.dll` (build/install:
  [plugins/uihook](plugins/uihook))

Then, in game: `/addon load <the addon>`. For `name`, `/load namehook` first; for `buff` or native
`party`, `/load uihook` first. Uihook replaces `buffhook` and `partyhook`; unload those before loading
it and remove their startup commands. Party native rendering remains opt-in; unload `hideparty`
before enabling it. The experimental [clock addon](addons/clock/README.md) uses uihook 0.2 to
write the game's clock on one line in place of its text, keeping its day and weather icons, and can
hide the compass; unload `hidecompass` first. Clock requires winxi 5.
[Chatbox](addons/chatbox/README.md) includes a native-backed WinXI input bar and requires
winxi 19 and uihook 0.5 with chat ABI 13;
load uihook first and unload other chat replacements/visibility writers.
See the uihook README for migration and testing steps.

## What else is here

- `addons/` also holds addons built on other people's work (simplelog, targetlines, inventory, party),
  and `forks/addons` copies of other people's addons with changes of ours (cbind, hideparty,
  imrecast, mobdb, tcrossbar). Both are under their authors' terms, not the license below.
- `archive/` holds retired addons and their checks, including [treas](archive/addons/treas).
- `plugins/exclude` is retired work, kept to look back on.
- `tests/` runs addons against a stand-in for Ashita: `tests/run.sh`.
- `tools/` builds data and art the addons use.
- `deploy.sh` copies addons between this folder and a live install, for development.

## License

The addons and library written here (those listed above, `winxi`, the tests and the tools) are MIT
licensed: see [LICENSE](LICENSE). `plugins/namehook` is a fork of a GPL v3 plugin and stays GPL v3.
Folders with a LICENSE of their own, and the other people's addons and forks listed above, keep their own terms.
Final Fantasy XI and its art belong to Square Enix.

Author: win.
