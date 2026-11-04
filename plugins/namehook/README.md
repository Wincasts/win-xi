# namehook

An Ashita v4 plugin for the names the game shows over characters' heads. It lets you show or hide
names by group (your party, other players, monsters, NPCs and so on), and set the size of names and
damage numbers. It also lets addons, such as winplates, know each name and where it is, and draw names
in their own way.

## Why you need it

- An addon you use needs it: [winplates](../../addons/winplates/README.md) draws its names with
  namehook, and its download includes the plugin.
- On its own, it lets you show or hide whole groups of names, and keep a list of players whose names
  always show.
- It can set the size of names and damage numbers so they are not stretched or blurred on a wide
  screen, and can hide the Job Mastery stars.

When you load it and change nothing, names and damage numbers look exactly as the game draws them:
every name shown, the stars as they are, and the game's own sizes.

## Where it comes from

namehook is a fork (a changed copy) of nameplatew. nameplatew is a fork of Nameplate-AshitaV4, a
community fork of [`Shirk/Nameplate`](https://github.com/Shirk/Nameplate).

- It still does what Nameplate does: names and damage numbers at a size you choose, not stretched or
  blurred on a wide screen, with or without the Job Mastery stars.
- It keeps nameplatew's whitelist.
- The changes from nameplatew 0.60 were made in October 2026, and are listed in `CHANGELOG.md`.
- The license is unchanged: GNU GPL v3.0, in `LICENSE.md`.

## Loading it

Load it with `/load namehook`, in place of `/load nameplatew` or `/load nameplate`.

- The three plugins change the same part of the game, so only one can be loaded.
- If `nameplate`, `nameplatew` or the older `nameplatehook` is running, namehook refuses to load,
  before it changes anything. A chat and log message names the plugin in the way and the `/unload`
  command you need.
- If a part of the game namehook needs for drawing is not found, the message says it may be another
  plugin's change, or a game version that is not supported. It does not assume every missing part is
  caused by another plugin.

For winplates, load namehook first: `/load namehook`, then `/addon load winplates`.

- [Categories](#categories)
- [Commands](#commands)
- [How it works](#how-it-works)
- [Building](#building)
- [Credits](#credits)
- [Compatibility with addons](#compatibility-with-addons)
- [Pre-releases and release candidates](#pre-releases-and-release-candidates)

## Categories

Every name is in exactly one category. A category's names are shown or hidden together.

| Category | Command word | Whose names |
|---|---|---|
| Self | `self` | Your own |
| Party | `party` | The others in your party, including trusts |
| Alliance | `alliance` | The other parties of your alliance |
| Player | `players` | Every other player |
| My pet | `mypet` | Your own pet |
| Pet | `pets` | Anyone else's pet, trust or adventuring fellow |
| NPC | `npcs` | Anything that cannot be fought |
| Monster | `monsters` | Anything that can be fought, including charmed players |

Whether a name shows is decided in this order. The first rule that applies wins:

1. The game's own `/names` off hides every name.
2. An addon can show or hide one particular character's name.
3. A player on the whitelist is shown. The whitelist is for other players only: it does not show your
   own name, or a monster's.
4. With `target on`, your target's name is shown, unless the target is yourself. Your own name follows
   its category only.
5. Otherwise the name is shown unless its category is hidden.

A name that is shown may still not be drawn by the game: an addon that draws names itself, as
winplates does, takes them over.

## Commands

`/nh` is short for `/namehook`.

### Showing and hiding names

| Command | What it does |
|---|---|
| `/namehook show <category>...` | Shows the names of one or more categories. `all` means every category. |
| `/namehook hide <category>...` | Hides them. |
| `/namehook toggle <category>...` | Shows those that are hidden, and hides those that are shown. |
| `/namehook target on` / `off` | Always shows your target's name, whatever its category. The exception is your own name: if it is hidden, it stays hidden while you target yourself. Off by default. |

For example, to see only your own party's names among players: `/nh hide players alliance`.

### Whitelist

| Command | What it does |
|---|---|
| `/namehook whitelist add <name>...` | Always shows these players' names. `wl` is short for `whitelist`. Capital letters do not matter. The list is saved as it changes, to `config\namehook\whitelist.txt`, one name per line. |
| `/namehook whitelist remove <name>...` | Takes them off the whitelist. |
| `/namehook whitelist list` / `clear` | Lists the names on the whitelist, or takes them all off. |

### Sizes and stars

| Command | What it does |
|---|---|
| `/namehook fontsize <number>` | The height of the names, 1 to 256 pixels. `0` or `game` is the game's own size, stretched as the game stretches it on a wide screen. This is the default. |
| `/namehook damagefontsize <number>` | The height of the damage numbers, the same way. `0` or `game` is the game's own size, the default. |
| `/namehook hidestars` / `showstars` | Hides or shows the Job Mastery stars. |

### Saving

| Command | What it does |
|---|---|
| `/namehook save` | Saves the settings to `config\namehook\defaults.ini`: the sizes, the stars, the hidden categories and the target setting. |
| `/namehook load` | Loads them again. |
| `/namehook help` | Lists the commands. |

Settings changed by a command last until the plugin is unloaded, unless you save them.

- The settings and the whitelist are read only from `config\namehook`.
- Until 1.28, namehook also read the files it kept under its old name (nameplatehook) and nameplatew's
  files. It no longer does.
- `/namehook save` writes `defaults.ini` in the right place, and `whitelist add` writes the list.

The [winplates](../../addons/winplates/README.md) addon gives you a settings window for the
categories, and keeps them for each character.

### Troubleshooting

| Command | What it does |
|---|---|
| `/namehook popups` | Describes the damage numbers (popups) of the last frame: what each says, whose it is, its colour, size and place, and whether the game drew it. |
| `/namehook popups watch on` / `off` | Describes each new damage number as it first appears. Off when the plugin loads, and not saved. |
| `/namehook perf` | Says how much time drawing for addons (names, speech bubbles, damage numbers, layers) took over the last 240 frames: the average and the worst time per frame, and how many drawings, shapes, draw calls and saves of the graphics settings per frame. Then it lists last frame's names, the names there was no room for in the list, and the drawings refused since loading. (1.48) |
| `/namehook status` | Says which categories are shown and hidden, how many names were listed last frame, from how many places the game draws names, how many names it drew more than once, and how many of those it moved up to where they were drawn highest. |
| `/namehook othercalls on` / `off` | Whether namehook handles every place the game draws a name from, or only the main one that draws all the names. On by default. Turn it off if something that is not a name over a head goes missing. |
| `/namehook keepstates on` / `off` | Whether the graphics settings are saved once for a run of names an addon has drawn, or before each name. On by default. Turn it off if what the game draws after the names looks wrong. |

## How it works

For each character, the game first decides whether its name is drawn at all. It then draws the name's
two lines: the name, and the Job Mastery stars. namehook steps in at those two steps. There, it sorts
and lists the name, and lets it be drawn or not. When the plugin is unloaded, everything is put back
as it was.

## Building

`./build.sh` builds `build/namehook.dll` on Linux with clang-cl and lld-link, as a 32-bit Windows
plugin. The top of the script says what it needs.

On Windows, `CMakeLists.txt` builds it with Visual Studio 2022 and CMake 3.28 or newer, as Win32 (not
x64):

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 -DASHITA_SDK_PATH="C:\Games\Ashita\plugins\sdk"
cmake --build build --config Release
```

The version numbers shown in game, in help, and in the CMake and Windows resource files come from
`src/Version.h`.

Copy `namehook.dll` to `<Ashita>\plugins`.

## Credits

Nameplate is by BunnyBox Productions (Shirk / Velyn), 2022 to 2024. Nameplate-AshitaV4 is its community
fork for Ashita v4. This fork is not affiliated with or endorsed by either.

## Compatibility with addons

The data this plugin shares with addons keeps its 1.0 layout until 2.0. So an addon made for namehook
1.0 keeps working with every newer 1.x version.

## Pre-releases and release candidates

namehook is released inside the winplates download. A pre-release of winplates
(`winplates-v<version>-pre1`) is also a pre-release of the namehook it carries, built from the same
code. What a test round covers, and what to send, is in
[winplates' README](../../addons/winplates/README.md#testing-pre-releases).
