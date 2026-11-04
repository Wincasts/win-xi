# win-xi

Ashita v4 addons for Final Fantasy XI, made for and tested on the Phoenix server. Most of them draw
with `winxi`, a shared library, so they share one look, which you set once in one settings window.

## Getting an addon

Download it from **[DOWNLOADS.md](DOWNLOADS.md)**, which lists the newest zip of each. Extract the zip
into your Ashita folder (the one that holds `addons`, `plugins` and `config`), merging folders when
asked, then follow `addons/<the addon>/INSTALL.txt`. Each zip carries everything that addon needs.

## Addons

| Addon | What it does | Command |
|---|---|---|
| [winplates](addons/winplates) | The names over players, NPCs and monsters, drawn your way, with health and cast bars | `/winplates` |
| [winparty](addons/winparty) | Party, target and pet frames in the style of XivParty | `/winparty` |
| [winbuff](addons/winbuff) | The statuses you are under, in a window, with the time each has left | `/winbuff` |
| [winchat](addons/winchat) | A replacement chat log and input bar, with an info panel. Experimental | `/winchat` |
| [winventory](addons/winventory) | Your bags in a window, by mouse or controller, with the treasure pool and an equipment monitor | `/winventory` |
| [zone](addons/zone) | Banners for the zone, region and weather, and a location line | `/zone` |
| [vis](addons/vis) | How far the world and the people in it are drawn, with the fog where you want it | `/vis` |
| [trigger](addons/trigger) | Plays a sound when something happens: a tell, an invite, a trade, low HP and more | `/trigger` |
| [parse](addons/parse) | A combat parser: damage, hit rates and DPS. Experimental | `/parse` |
| [sct](addons/sct) | Scrolling text for your statuses, items received and key items | `/sct` |
| [mobcast](addons/mobcast) | What the enemies around you are casting, readying and using, in a small window | `/mobcast` |
| [cooldowns](forks/addons/cooldowns) | Your ability and spell recasts in a winxi window (atom0s's, Thorny's and others' imrecast, with changes) | `/cooldowns` |
| [occlusionfix](addons/occlusionfix) | Stops characters near walls and door frames from blinking out of view | `/occlusionfix` |
| [hidecompass](addons/hidecompass) | Hides the game's compass | `/hidecompass` |
| [wxi](addons/wxi) | The look every winxi addon shares, in one settings window | `/winxi` |

Each addon's folder has a README with all of its commands and settings.

## Plugins

| Plugin | What it is for |
|---|---|
| [namehook](plugins/namehook) | What winplates draws names with. Comes in the winplates zip |
| [uihook](plugins/uihook) | What winbuff, winchat and winparty use to work with the game's own windows. Comes in their zips |
| [blockpool](plugins/blockpool) | Works around a memory leak in Proton's wined3d that runs the game out of memory after a few hours. For playing on Linux or a Steam Deck |

## Installing from this repository

mobcast, cooldowns, hidecompass and blockpool are not released as zips yet, and anything here can be
newer than its release. Copy into your Ashita folder, merging folders:

- `addons/libs/winxi` and `addons/wxi`, which every addon but occlusionfix and hidecompass needs
- `addons/<the addon>` (or `forks/addons/cooldowns`) for each addon you want
- a plugin is built from its folder (`build.sh`, on Linux); its README says how

Then, in game: `/addon load <the addon>`, after `/load namehook` for winplates or `/load uihook` for
winbuff, winchat or winparty.

## For developers

`tests/run.sh` runs the checks: each loads an addon against a stand-in for Ashita. `tools/` builds the
data and art the addons use, and `tools/package_release.py <addon>` makes a release zip from the commit,
after the checks pass.

## License

The addons and library written here (`winxi`, the addons above but cooldowns, the tests and the tools)
are MIT licensed: see [LICENSE](LICENSE). `plugins/namehook` is a fork of a GPL v3 plugin and stays
GPL v3. cooldowns keeps its authors' terms. Final Fantasy XI and its art belong to Square Enix.

Author: win.
