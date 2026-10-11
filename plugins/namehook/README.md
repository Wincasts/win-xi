# namehook

An Ashita v4 plugin that gives addons a hold on the names the game draws over characters' heads: what each one is, where it is, and whether it is drawn.

It is a fork of nameplatew, which is a fork of Nameplate-AshitaV4, a community fork of [`Shirk/Nameplate`](https://github.com/Shirk/Nameplate). It still does what Nameplate does (names and damage numbers that are not stretched or blurred on a wide screen, at a size you choose, with or without the Job Mastery stars), and keeps nameplatew's whitelist. Changes from nameplatew 0.60 were made in October 2026 and are listed in `CHANGELOG.md`. The license is unchanged: GNU GPL v3.0, in `LICENSE.md`.

It is loaded with `/load namehook`, in place of `/load nameplatew` or `/load nameplate`: the three patch the same client code, and only one can be loaded.

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
4. With `target on`, your target is shown, unless it is yourself: your own name goes by its category alone.
5. Otherwise it is shown unless its category is hidden.

A name that is shown may still not be drawn by the game: an addon that draws names itself [claims](#drawing-names-in-place-of-the-game) them.

## Commands

`/nh` is short for `/namehook`.

| Command | What it does |
|---|---|
| `/namehook show <category>...` | Shows the names of one category or more. `all` is every category. |
| `/namehook hide <category>...` | Hides them. |
| `/namehook toggle <category>...` | Shows those that are hidden and hides those that are shown. |
| `/namehook target on` / `off` | Always shows your target's name, whatever its category. Your own name is the exception: hidden, it stays hidden while you have yourself targeted. Off by default. |
| `/namehook status` | Says which categories are shown and hidden, how many names were listed last frame, and from how many places the client draws names. |
| `/namehook othercalls on` / `off` | Whether every place the client draws a name from is taken, or only the one that draws all the names. On by default; turn it off if something that is no name over a head goes missing. |
| `/namehook whitelist add <name>...` | Always shows these players' names. `wl` is short for `whitelist`. Names are matched without regard to case, and the list is saved as it changes, to `config\namehook\whitelist.txt`, one name to a line. |
| `/namehook whitelist remove <name>...` | Takes them off the whitelist. |
| `/namehook whitelist list` / `clear` | Says the names on the whitelist, or takes them all off. |
| `/namehook fontsize <number>` | The height of the names, 1 to 256 pixels. 22 by default. |
| `/namehook damagefontsize <number>` | The height of the damage numbers. |
| `/namehook hidestars` / `showstars` | Hides or shows the Job Mastery stars. |
| `/namehook save` | Saves the settings to `config\namehook\defaults.ini`: the sizes, the stars, the hidden categories and the target setting. |
| `/namehook load` | Loads them again. |
| `/namehook help` | Lists the commands. |

For example, to see only your party's names among players: `/nh hide players alliance`.

Settings changed by a command last until the plugin is unloaded, unless saved. It was called nameplatehook up to 1.11, and until `defaults.ini` exists the settings and the whitelist it kept under that name, in `config\nameplatehook`, are read. Failing those the settings are read from nameplatew's, in `config\nameplatew`: its `mode` becomes the categories that mode hid, and its whitelist is read until this one's is first changed.

The `name` addon, in `addons/name` of this project, is a settings window for the categories, which keeps them for each character.

## For addons

The plugin keeps one block in its own memory, `HookShared` in `src/Nameplate.h`. An addon finds it in `namehook.dll` by its first 16 bytes, reads the names in it, and writes the settings in it.

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

nameplates.SetHidden(nameplates.Category.Player, true);   -- as /namehook hide players
nameplates.Override(entityIndex, false);                  -- hide one entity's name; nil gives it back to its category
```

The head of that file lists everything it offers.

### The block

| Field | Meaning |
|---|---|
| `Magic` | The 8 bytes `NAMEHOOK` and eight 0s, by which the block is found |
| `Version` | 2 |
| `Size`, `NameSize` | The size in bytes of the block and of one name. An addon that has either otherwise does not read on. |
| `Hooked` | 1 while the client's name drawing is in the plugin's hands; 0 on a client it does not recognise, where names are shown and hidden but none are listed |
| `Hidden` | The categories whose names are hidden, a bit each. Written by addons and by the commands. |
| `Options` | Bit 0: the target's name is always shown, unless it is the local player's own. Written by addons and by the commands. |
| `Claimed`, `ClaimFrame` | The categories an addon draws itself, and the `Frame` that was last said in. Written by addons. |
| `Frame` | Counts the frames drawn |
| `Count` | How many names are listed |
| `Width`, `Height` | The size of the picture the names' places on screen are in: the client's window |
| `Sequence` | Goes up each time the list is made ready: once a frame as a rule, and more if names are drawn in more than one scene |
| `Draw` | The address of the `HookDraw`, for an addon that has the plugin [draw names for it](#having-the-plugin-draw-the-names) |
| `TargetWidth`, `TargetHeight` | The size of the picture the client draws the world on, which is larger than its window when the background resolution is. 0 until a name has been drawn. |
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
| Custom | 0x100 | Drawn by the plugin, from what an addon set out for it |

### Which names are listed

Those the client was about to draw in the last frame: so not one that is too far away or off screen, which the client leaves out itself, and none at all with the game's `/names` off. A name the plugin hides is listed like any other, without the wanted flag, so that an addon can tell a name that is hidden from one that is not there.

The client draws its names during a scene and addons draw as the frame is presented. The list is made ready as that scene ends, or failing that as the frame is presented, so an addon reading it in `d3d_present` has the names of the frame it is drawing over.

Entities are known by index, and an index belongs to another entity after a change of area. `Override` is not cleared by the plugin: an addon that sets it clears it then.

### Drawing names in place of the game

An addon that draws names itself sets `Claimed` to the categories it draws and `ClaimFrame` to the block's `Frame`, every frame (`nameplates.Claim(categories)`). While it does, a name of those categories that is shown is listed with the wanted flag and without the drawn flag, and the client does not draw it or its stars. A name that is hidden stays hidden: the addon draws what is wanted.

A claim that is not made again lapses 30 frames later, and the client draws the names as before. So an addon that stops, or is unloaded, need do nothing.

### Having the plugin draw the names

An addon draws as the frame is presented, on the finished picture, where nothing of the world can hide what it draws: the client has by then put away the depth of the world it drew, which was on a picture of its own. So an addon that wants its names hidden by what is in front of them, as the client's are, does not draw them. It sets each one out and leaves it with the plugin, which draws it in the client's picture at the moment the client would have drawn the name.

What is set out goes in `HookDraw` (`src/Nameplate.h`), at the address in the block's `Draw`:

| Field | Meaning |
|---|---|
| `Frame` | Set by the addon to the block's `Frame` each time it sets names out. What was set out more than 2 frames ago is not drawn. |
| `QuadCount` | How many of `Quads` are in use. Set to 0 by the addon each frame, and raised as it adds them. |
| `QuadsMax` | 16384 |
| `Textures` | Eight Direct3D textures (`IDirect3DTexture8*`), or 0. The plugin holds each while it draws from it. |
| `Entities` | For each of the client's 0x900 entities, by index: `Frame` (as `HookDraw`'s when it was set out, or it is not drawn), `First` and `Count` (its quads, 256 at most), `Alpha` (0 to 1, how solid the whole name is), `Edge` (how thick a dark edge its edged quads are given, in pixels) and `EdgeColor`. A quad's edge is as solid as the quad's own colour is |
| `Quads` | Each a rectangle: its corners `X0`, `Y0`, `X1`, `Y1` in pixels of the client's picture, measured from the point the client puts the name at; the same corners in its texture, `U0`, `V0`, `U1`, `V1`; `Color` as 0xAARRGGBB; `Texture`, which of the eight; and `Flags`, 1 if it is given the edge |

The quads are in pixels of the client's picture, not of its window: an addon that wants a letter 15 pixels high on the screen makes it `15 * TargetWidth / Width` high. `winxi.nameplates` does the bookkeeping (`BeginDrawing`, `SetTexture`, `BeginName`, `Quad`, `EndName`), and `addons/name/custom.lua` sets names out this way, from imgui's font.

The plugin draws a name when all of these hold: its category is claimed, it is wanted, and the addon set it out within the last 2 frames. It is then listed with the custom flag. A claimed name that was not set out is not drawn at all. What is set out in one frame is drawn in the next, where the client then puts the name: the name's place is never a frame behind, only what it looks like.

Each name is drawn twice: once blended into the picture and tested against its depth, and once more to the depth alone where the name is solid, so that what the client draws afterwards, and behind the name, is not drawn over it. Everything of the device's state that this changes is put back before the client goes on.

### How it works

The client decides, for each character, whether its name is drawn at all, and then calls two functions of its own to draw the name's two lines: the name, and the Job Mastery stars. Nameplate patched the first decision. This plugin lets every name through it and stands in the way of the two calls instead, where the client has already worked out the name's place, its colours and what it writes: there the name is sorted, listed, and drawn or not.

The two calls are found beside Nameplate's patch, and taken only if both lead where they are expected to. The client calls the same two functions from other places as well, and those calls are found by going through its code for every call that goes to either: they are taken too, unless `othercalls` is off. On a client where they do not, `Hooked` stays 0, names are shown and hidden at the first decision as nameplatew did it, and `/namehook status` says so. Everything is put back as it was when the plugin is unloaded.

## Building

`./build.sh` builds `build/namehook.dll` on Linux with clang-cl and lld-link, as a 32-bit Windows plugin, and `tests/run.sh` checks the categories, the list, the commands and the files under wine; the drawing itself is not checked there, having no client to draw on. Both say at the top what they need.

On Windows, `CMakeLists.txt` builds it with Visual Studio 2022 and CMake 3.28 or newer, as Win32 and not x64:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 -DASHITA_SDK_PATH="C:\Games\Ashita\plugins\sdk"
cmake --build build --config Release
```

Copy `namehook.dll` to `<Ashita>\plugins`.

## Credits

Nameplate is by BunnyBox Productions (Shirk / Velyn), 2022 to 2024. Nameplate-AshitaV4 is its community fork for Ashita v4. This fork is not affiliated with or endorsed by either.
