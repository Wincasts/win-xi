# win-xi

Ashita v4 addons for Final Fantasy XI, made for and tested on the Phoenix server. Most of them are
built on `winxi`, a shared library. So they all have the same look, and you set that look once, in one
settings window (wxi).

## Getting an addon

1. Download it from **[DOWNLOADS.md](DOWNLOADS.md)**, which lists the newest zip of each addon.
2. Extract the zip into your Ashita folder (the one that holds `addons`, `plugins` and `config`).
   Merge the folders when asked.
3. Follow `addons/<the addon>/INSTALL.txt`.

Each zip has everything that addon needs.

## Addons

| Addon | What it does | Command |
|---|---|---|
| [winplates](addons/winplates) | Replaces the game's names over players, NPCs and monsters with fully configurable ones | `/winplates` |
| [winparty](addons/winparty) | Party, alliance, target and pet frames in the shared winxi style, following the compact layout of the Windower addon XivParty | `/winparty` |
| [winbuff](addons/winbuff) | Replaces the game's row of status icons with a bar of FFXIV-style icons, each showing the time remaining on that buff or debuff | `/winbuff` |
| [winchat](addons/winchat) | Redraws the game's chat log and input line in the winxi style, with chat tooltips and an optional information panel. Experimental | `/winchat` |
| [winventory](addons/winventory) | Displays all of your bags in a single window, with full mouse and controller support | `/winventory` |
| [zone](addons/zone) | Displays location banners for the zone, region, weather and named areas as you travel | `/zone` |
| [vis](addons/vis) | Extends how far the game draws terrain, buildings and characters, with independent control over the fog | `/vis` |
| [trigger](addons/trigger) | Plays an audio alert when something notable happens, such as a tell, a party invite, low HP or a wanted item dropping | `/trigger` |
| [parse](addons/parse) | A combat parser reporting damage, DPS and hit rates for you, your party and your alliance. Experimental | `/parse` |
| [sct](addons/sct) | Scrolling text for buffs and enfeebles gained or lost, and for items you receive | `/sct` |
| [mobcast](addons/mobcast) | Shows the actions of nearby enemies in a compact on-screen window | `/mobcast` |
| [cooldowns](forks/addons/cooldowns) | Displays your ability and spell recast times, and a puppetmaster's automaton cooldowns, in a winxi window | `/cooldowns` |
| [occlusionfix](addons/occlusionfix) | Prevents players, NPCs and monsters from disappearing when they stand near walls, door frames, counters and other scenery | `/occlusionfix` |
| [hidecompass](addons/hidecompass) | Hides the game's compass as soon as it is loaded | `/hidecompass` |
| [wxi](addons/wxi) | A single settings window for the look shared by every winxi addon | `/winxi` |

Each addon's folder has a README with all of its commands and settings.

## Plugins

| Plugin | What it is for |
|---|---|
| [namehook](plugins/namehook) | Lets winplates draw the names. Comes in the winplates zip |
| [uihook](plugins/uihook) | Lets winbuff, winchat and winparty work with the game's own windows. Comes in their zips |
| [blockpool](plugins/blockpool) | For playing on Linux or a Steam Deck. Works around a memory leak in Proton's wined3d, which makes the game run out of memory after a few hours |

## Installing from this repository

Every addon and plugin above has a release on [DOWNLOADS.md](DOWNLOADS.md), which is the easier way.
What is here can be newer than its release. To use it, copy these into your Ashita folder, merging folders:

- `addons/libs/winxi` and `addons/wxi`, which every addon but occlusionfix and hidecompass needs
- `addons/<the addon>` (or `forks/addons/cooldowns`) for each addon you want
- a plugin is built from its folder (`build.sh`, on Linux); its README says how

Then, in game, type `/addon load <the addon>`. For winplates, first type `/load namehook`. For winbuff,
winchat or winparty, first type `/load uihook`.

## License

`winxi`, the uihook and blockpool plugins, and the addons above except winparty, winventory and
cooldowns are MIT licensed: see [LICENSE](LICENSE). winparty and winventory are built on other
people's work and keep their terms. cooldowns is Ashita's imrecast with changes, and `plugins/namehook`
a fork of a GPL v3 plugin: both stay GPL v3. Final Fantasy XI and its art belong to Square Enix.

Author: win.
