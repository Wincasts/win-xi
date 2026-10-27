# MobDB
MobDB is an addon that displays monster information onscreen, in the same vein as ibar.  For most users, you should not need to do anything besides loading the addon.<br><br>

## /mobdb config ##
You can type this command to edit the appearance of mobdb and change the tokens, either for a specific character or for all characters.  The 'Edit Tokens' button will allow you to change the display strings.

## /md reset ##
This will return the bar to the top left of the screen if it's dragged offscreen or lost due to resolution changes.

## To-Do ##
1. Data parser already handles drop lists and spell lists, among other information.  A later version will include the ability to display a detailed window with far more information about the monster.  This would be larger onscreen, so it will be entirely optional and driven by a command to toggle it on/off.
2. Manual revisions for Dynamis-D and Odyssey to increase usefulness for retail players.
3. Add editor window so mobs can be edited in realtime, and quick note command to save notes on any target.

## Generating Data For Your Custom Server ##
This process is only intended for advanced users, and will allow you to generate data files that exactly match your LSB or wings based private server.  To do this, follow these directions:
1. Change line 2 of import_lsb.lua, import_wings.lua, or import_custom.lua to reflect your current FFXI install path.
2. Load the addon to generate initial configurations if you haven't.  Reload to update path if you changed it.
3. Copy the following files into Ashita/config/addons/mobdb/input/ from your LSB server source:
- mob_droplist.sql
- mob_family_system.sql
- mob_groups.sql
- mob_pools.sql
- mob_resistances.sql (only for LSB-based servers, wings based won't have this)
- mob_spawn_points.sql
- mob_spell_lists.sql
4. Type the command "/mobdb import wings" or "/mobdb import lsb" or "/mobdb import custom" ingame.  This may take several minutes depending on your system.
5. Copy the files generated from Ashita/config/addons/mobdb/output/ to Ashita/addons/mobdb/data.

## This Fork's Data ##
This fork reads each area's monsters from winxi's mobs set (`winxi.mobs`, in `addons/libs/winxi/data/mobs`), which `tools/build_winxi_data.py` makes from the server with `import_phoenix.py`; it has no `data` folder of its own. The importers below still write files in MobDB's format, which the data pack for MobDB as its author releases it is made of.

## Generating Data For A YAML-Based Server (Phoenix) ##
Newer LandSandBoat forks keep mobs in `data/zones/<zone>/mobs.yaml` and `data/ecosystems.yaml` rather than the mob SQL files, so the importers above cannot read them.  `import_phoenix.py` reads the server checkout directly and runs outside the game.  It needs Python 3 and PyYAML.
1. Run `python import_phoenix.py --server <path to server checkout> --out <Ashita/config/addons/mobdb/output>`.
2. Empty Ashita/addons/mobdb/data, then copy the generated files into it.  Emptying it first matters: zones the server has no mobs for would otherwise keep their old files.

It applies the module YAML overlays listed in the server's `modules/init.txt` and reads `settings/main.lua` over `settings/default/main.lua`.  If the live server's settings are not in your checkout, pass them with `--set`, for example `--set RESTRICT_CONTENT=1 --set ENABLE_SOA=0`.  See `--help` for the other options.

`client_names.json` maps server mob names to the names the client displays.  It was built from the stock data files; rebuild it with `--build-names <folder of stock data files>` only if you have newer stock data.

It also holds each entity's name by index, read from the client's name DATs with the server's DAT overlay on top: `--build-dat-names <FINAL FANTASY XI folder> --dat-overlay <polplugins/DATs/EraDATs>`.  Those are the names the client really shows, so a spawn whose name the server gives differently (Phoenix's Floating Eyes in Ranguemont Pass are Bat Eyes to the server) is still found.  A zone's index names are used only if most of its spawns already known by name have that same name at their index; where the client's DATs are newer than the server's layout (the Adoulin areas) they are shuffled, and that zone is named by name alone.
