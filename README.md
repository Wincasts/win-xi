# ffxi-addons

Ashita v4 addons for Final Fantasy XI, made for and tested on the Phoenix server. Most of them draw
with `winxi`, a shared library that gives every addon the same look, set once in one settings window.

## Addons

| Addon | What it does | Command |
|---|---|---|
| [buff](addons/buff) | The statuses you are under, in a window, with FFXIV's icons and the time each has left | `/buff` |
| [hidecompass](addons/hidecompass) | Hides the game's compass | `/hidecompass` |
| [mark](addons/mark) | Pick a notorious monster and see its placeholders, their respawns, where it spawns on the map, its window and its drops | `/mark` |
| [name](addons/name) | Shows and hides the names over characters' heads by what they are, and draws them in winxi's style; needs the `namehook` plugin | `/name` |
| [puppet](addons/puppet) | The next enfeebles and weapon skill an automaton will use | `/puppet` |
| [trigger](addons/trigger) | Plays a sound when something happens: a tell, an invite, a trade, an item dropping, low HP and the like | `/trigger` |
| [winxisettings](addons/winxisettings) | The look shared by every winxi addon, in one settings window | `/winxi` |
| [zoneinfo](addons/zoneinfo) | Zone, region and weather banners, and a location line | `/zoneinfo config` |

Each addon's folder has a README with all of its commands and settings.

## Installing

Every addon above needs the `winxi` library. Copy into your Ashita folder (the one holding `addons`,
`plugins` and `config`), merging folders:

- `addons/libs/winxi`
- `addons/<the addon>` for each one you want
- `addons/winxisettings`, to change the shared look
- for `name`, also `plugins/namehook.dll` (see [plugins/namehook](plugins/namehook))

Then, in game: `/addon load <the addon>`. For `name`, `/load namehook` first.

## What else is here

- `addons/` also holds addons built on other people's work (simplelog, targetlines, inventory, party,
  treas), and `forks/addons` copies of other people's addons with changes of ours (cbind, hideparty,
  imrecast, mobdb, tcrossbar). Both are under their authors' terms, not the license below.
- `plugins/exclude` is retired work, kept to look back on.
- `tests/` runs addons against a stand-in for Ashita: `tests/run.sh`.
- `tools/` builds data and art the addons use.
- `deploy.sh` copies addons between this folder and a live install, for development.

## License

The addons and library written here (the eight above, `winxi`, the tests and the tools) are MIT
licensed: see [LICENSE](LICENSE). `plugins/namehook` is a fork of a GPL v3 plugin and stays GPL v3.
Folders with a LICENSE of their own, and the other people's addons and forks listed above, keep their own terms.
Final Fantasy XI and its art belong to Square Enix.

Author: win.
