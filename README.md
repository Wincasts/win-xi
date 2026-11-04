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
| [winplates](addons/winplates) | Draws the names over players, NPCs and monsters in its own style, with health bars, cast bars and status icons if you want them | `/winplates` |
| [winparty](addons/winparty) | Shows your party, target and pet in frames with health bars, laid out like the XivParty addon | `/winparty` |
| [winbuff](addons/winbuff) | Shows the statuses you are under in a bar, with the time each has left, in place of the game's own row of icons | `/winbuff` |
| [winchat](addons/winchat) | Draws the chat log and the line you type in again in the winxi look, with chat tooltips and an optional info panel. Experimental | `/winchat` |
| [winventory](addons/winventory) | Shows your bags in a window that you can use with a mouse or a controller, with the treasure pool and an equipment monitor | `/winventory` |
| [zone](addons/zone) | Shows a banner with the zone, region and weather when you arrive, and names the places in a zone as you walk into them | `/zone` |
| [vis](addons/vis) | Sets how far the world and the characters in it are drawn, and keeps the fog where you want it | `/vis` |
| [trigger](addons/trigger) | Plays a sound when something happens, such as a tell, an invite, a trade or low HP | `/trigger` |
| [parse](addons/parse) | A combat parser that counts damage, hit rates and DPS. Experimental | `/parse` |
| [sct](addons/sct) | Scrolling text for the statuses you gain and lose, the items you receive and the key items you get | `/sct` |
| [mobcast](addons/mobcast) | Shows in a small window what the enemies around you are casting, readying and using | `/mobcast` |
| [cooldowns](forks/addons/cooldowns) | Shows your ability and spell recast times in a winxi window (atom0s's, Thorny's and others' imrecast, with changes) | `/cooldowns` |
| [occlusionfix](addons/occlusionfix) | Stops characters near walls and door frames from blinking out of view | `/occlusionfix` |
| [hidecompass](addons/hidecompass) | Hides the game's compass | `/hidecompass` |
| [wxi](addons/wxi) | One settings window for the look that every winxi addon shares | `/winxi` |

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
