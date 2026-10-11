# nameplatehook

An Ashita v4 plugin that gives addons a hold on the names the game draws over characters' heads: what each one is, where it is, and whether it is drawn.

It is a fork of nameplatew, which is a fork of Nameplate-AshitaV4, a community fork of [`Shirk/Nameplate`](https://github.com/Shirk/Nameplate). It still does what Nameplate does (names and damage numbers that are not stretched or blurred on a wide screen, at a size you choose, with or without the Job Mastery stars), and keeps nameplatew's whitelist. Changes from nameplatew 0.60 were made in October 2026 and are listed in `CHANGELOG.md`. The license is unchanged: GNU GPL v3.0, in `LICENSE.md`.

It is loaded with `/load nameplatehook`, in place of `/load nameplatew` or `/load nameplate`: the three patch the same client code, and only one can be loaded.

- [Categories](#categories)
- [Commands](#commands)
- [For addons](#for-addons)
- [Building](#building)

## Categories

Every name is in exactly one category, and a category's names are shown or hidden together.

| Category | Command word | Whose names |
|---|---|---|
| Self | `self` | Your own |
| Party | `party` | The others of your party, trusts among them |
| Alliance | `alliance` | The other parties of your alliance |
| Player | `players` | Every other player |
| My pet | `mypet` | Your own pet |
| Pet | `pets` | Anyone else's pet, trust or adventuring fellow |
| NPC | `npcs` | What cannot be fought |
| Monster | `monsters` | What can be fought, charmed players among them |

Whether a name is shown is decided in this order, the first that applies:

1. The game's own `/names` off hides every name.
2. An addon's override for that one entity shows or hides it.
3. A player on the whitelist is shown. The whitelist is of other players only: it does not show your own name, or a monster's.
4. With `target on`, your target is shown.
5. Otherwise it is shown unless its category is hidden.

A name that is shown may still not be drawn by the game: an addon that draws names itself [claims](#drawing-names-in-place-of-the-game) them.

## Commands

`/nph` is short for `/nameplatehook`.

| Command | What it does |
|---|---|
| `/nameplatehook show <category>...` | Shows the names of one category or more. `all` is every category. |
| `/nameplatehook hide <category>...` | Hides them. |
| `/nameplatehook toggle <category>...` | Shows those that are hidden and hides those that are shown. |
| `/nameplatehook target on` / `off` | Always shows your target's name, whatever its category. Off by default. |
| `/nameplatehook status` | Says which categories are shown and hidden, and how many names were listed last frame. |
| `/nameplatehook whitelist add <name>...` | Always shows these players' names. `wl` is short for `whitelist`. Names are matched without regard to case, and the list is saved as it changes, to `config\nameplatehook\whitelist.txt`, one name to a line. |
| `/nameplatehook whitelist remove <name>...` | Takes them off the whitelist. |
| `/nameplatehook whitelist list` / `clear` | Says the names on the whitelist, or takes them all off. |
| `/nameplatehook fontsize <number>` | The height of the names, 1 to 256 pixels. 22 by default. |
| `/nameplatehook damagefontsize <number>` | The height of the damage numbers. |
| `/nameplatehook hidestars` / `showstars` | Hides or shows the Job Mastery stars. |
| `/nameplatehook save` | Saves the settings to `config\nameplatehook\defaults.ini`: the sizes, the stars, the hidden categories and the target setting. |
| `/nameplatehook load` | Loads them again. |
| `/nameplatehook help` | Lists the commands. |

For example, to see only your party's names among players: `/nph hide players alliance`.

Settings changed by a command last until the plugin is unloaded, unless saved. Until `defaults.ini` exists the settings are read from nameplatew's, in `config\nameplatew`: its `mode` becomes the categories that mode hid, and its whitelist is read until this one's is first changed.

The `nametoggle` addon, in `addons/nametoggle` of this project, is a settings window for the categories, which keeps them for each character.

## For addons

The plugin keeps one block in its own memory, `HookShared` in `src/Nameplate.h`. An addon finds it in `nameplatehook.dll` by its first 16 bytes, reads the names in it, and writes the settings in it.

In this project that is done by `addons/libs/winxi/nameplates.lua`, which needs nothing else of winxi:

```lua
local nameplates = require('winxi.nameplates');

ashita.events.register('d3d_present', 'example_present', function ()
    for _, name in nameplates.Each() do
        local x, y = nameplates.Screen(name);
        if (x ~= nil and nameplates.Has(name, nameplates.Flag.Wanted)) then
            -- nameplates.Name(name) is at x, y on screen
        end
    end
end);

nameplates.SetHidden(nameplates.Category.Player, true);   -- as /nameplatehook hide players
nameplates.Override(entityIndex, false);                  -- hide one entity's name; nil gives it back to its category
```

The head of that file lists everything it offers.

### The block

| Field | Meaning |
|---|---|
| `Magic` | The 13 bytes `NAMEPLATEHOOK` and three 0s, by which the block is found |
| `Version` | 1 |
| `Size`, `NameSize` | The size in bytes of the block and of one name. An addon that has either otherwise does not read on. |
| `Hooked` | 1 while the client's name drawing is in the plugin's hands; 0 on a client it does not recognise, where names are shown and hidden but none are listed |
| `Hidden` | The categories whose names are hidden, a bit each. Written by addons and by the commands. |
| `Options` | Bit 0: the target's name is always shown. Written by addons and by the commands. |
| `Claimed`, `ClaimFrame` | The categories an addon draws itself, and the `Frame` that was last said in. Written by addons. |
| `Frame` | Counts the frames drawn |
| `Count` | How many names are listed |
| `Width`, `Height` | The size of the picture the names' places on screen are in: the client's window |
| `Sequence` | Goes up each time the list is made ready, which is more than once a frame |
| `Override` | A byte for each of the client's 0x900 entities, by index: 0 by its category, 1 shown, 2 hidden. Written by addons. |
| `Names` | Up to 256 names |

The categories' bits are, from bit 0: self, party, alliance, player, my pet, pet, NPC, monster.

### A name

| Field | Meaning |
|---|---|
| `EntityIndex`, `ServerId` | Whose name it is |
| `Category` | Its one category, as a bit |
| `Flags` | See below |
| `X`, `Y`, `Z` | Where the client puts the name, in the world: the point above the head |
| `Scale` | 1 near to, falling to 0 as the name nears the distance it is no longer drawn at |
| `ScreenX`, `ScreenY`, `Depth` | The same point on screen, in pixels from the top left of a picture `Width` by `Height`, and how far in front of the camera it is. Only with the on-screen flag. |
| `NameColor` | The client's colour for the name, as 0xAARRGGBB with 0x80 for full |
| `IconColor` | Its colour for the linkshell pearl, as 0xAABBGGRR with 0x80 for full |
| `Name` | The entity's name |
| `Text` | The name as the client writes it: its icons first, each a single byte of 0x8E or more in the client's font, then a space if there were any, then the name |

| Flag | Bit | Meaning |
|---|---|---|
| Wanted | 0x01 | Shown, by the order under [Categories](#categories) |
| Drawn | 0x02 | Drawn by the client: wanted, and not claimed |
| Stars | 0x04 | The client was about to draw the Job Mastery stars over it. Never with `hidestars`. |
| Target | 0x08 | It is your target |
| Charmed | 0x10 | A player who can be fought |
| Whitelisted | 0x20 | A player on the whitelist |
| On screen | 0x40 | In front of the camera |
| Overridden | 0x80 | Shown or hidden by `Override` |

### Which names are listed

Those the client was about to draw in the last frame: so not one that is too far away or off screen, which the client leaves out itself, and none at all with the game's `/names` off. A name the plugin hides is listed like any other, without the wanted flag, so that an addon can tell a name that is hidden from one that is not there.

The client draws its names during the scene and addons draw as the frame is presented. The list is made ready as the scene ends and again as the frame is presented, so an addon reading it in `d3d_present` has the names of the frame it is drawing over.

Entities are known by index, and an index belongs to another entity after a change of area. `Override` is not cleared by the plugin: an addon that sets it clears it then.

### Drawing names in place of the game

An addon that draws names itself sets `Claimed` to the categories it draws and `ClaimFrame` to the block's `Frame`, every frame (`nameplates.Claim(categories)`). While it does, a name of those categories that is shown is listed with the wanted flag and without the drawn flag, and the client does not draw it or its stars. A name that is hidden stays hidden: the addon draws what is wanted.

A claim that is not made again lapses 30 frames later, and the client draws the names as before. So an addon that stops, or is unloaded, need do nothing.

### How it works

The client decides, for each character, whether its name is drawn at all, and then calls two functions of its own to draw the name's two lines: the name, and the Job Mastery stars. Nameplate patched the first decision. This plugin lets every name through it and stands in the way of the two calls instead, where the client has already worked out the name's place, its colours and what it writes: there the name is sorted, listed, and drawn or not.

The two calls are found beside Nameplate's patch, and taken only if both lead where they are expected to. On a client where they do not, `Hooked` stays 0, names are shown and hidden at the first decision as nameplatew did it, and `/nameplatehook status` says so. Everything is put back as it was when the plugin is unloaded.

## Building

`./build.sh` builds `build/nameplatehook.dll` on Linux with clang-cl and lld-link, as a 32-bit Windows plugin, and `tests/run.sh` checks the categories, the list, the commands and the files under wine. Both say at the top what they need.

On Windows, `CMakeLists.txt` builds it with Visual Studio 2022 and CMake 3.28 or newer, as Win32 and not x64:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 -DASHITA_SDK_PATH="C:\Games\Ashita\plugins\sdk"
cmake --build build --config Release
```

Copy `nameplatehook.dll` to `<Ashita>\plugins`.

## Credits

Nameplate is by BunnyBox Productions (Shirk / Velyn), 2022 to 2024. Nameplate-AshitaV4 is its community fork for Ashita v4. This fork is not affiliated with or endorsed by either.
