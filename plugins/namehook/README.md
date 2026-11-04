# namehook

An Ashita v4 plugin that gives addons a hold on the names the game draws over characters' heads: what each one is, where it is, and whether it is drawn.

It is a fork of nameplatew, which is a fork of Nameplate-AshitaV4, a community fork of [`Shirk/Nameplate`](https://github.com/Shirk/Nameplate). It still does what Nameplate does (names and damage numbers at a size you choose, not stretched or blurred on a wide screen, with or without the Job Mastery stars), and keeps nameplatew's whitelist. Loaded with nothing asked of it, it leaves names and damage numbers as the game draws them: every name shown, the stars as they are, the game's own sizes. The changes from nameplatew 0.60 were made in October 2026 and are listed in `CHANGELOG.md`. The license is unchanged: GNU GPL v3.0, in `LICENSE.md`.

Load it with `/load namehook`, in place of `/load nameplatew` or `/load nameplate`. The three patch the same client code, so only one can be loaded. If `nameplate`, `nameplatew`, or the older `nameplatehook` is running, loading is refused before anything is patched, with a chat and log message that names the conflict and the `/unload` command you need. When a rendering signature is missing, the message also says it may be a competing patch or a client version that is not supported, rather than treating every missing signature as a conflict.

The [winplates](../../addons/winplates/README.md) addon draws its names with namehook, and its zip carries the plugin. Load it before winplates: `/load namehook`, then `/addon load winplates`.

- [Categories](#categories)
- [Commands](#commands)
- [How it works](#how-it-works)
- [Building](#building)
- [Credits](#credits)
- [Stability](#stability)
- [Pre-releases and release candidates](#pre-releases-and-release-candidates)

## Categories

Every name is in exactly one category. A category's names are shown or hidden together.

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

Whether a name is shown is decided in this order. The first rule that applies wins:

1. The game's own `/names` off hides every name.
2. An addon's override for that one entity shows or hides it.
3. A player on the whitelist is shown. The whitelist is for other players only: it does not show your own name, or a monster's.
4. With `target on`, your target is shown, unless it is yourself: your own name goes by its category alone.
5. Otherwise it is shown unless its category is hidden.

A name that is shown may still not be drawn by the game: an addon that draws names itself, as winplates does, claims them.

## Commands

`/nh` is short for `/namehook`.

| Command | What it does |
|---|---|
| `/namehook show <category>...` | Shows the names of one category or more. `all` is every category. |
| `/namehook hide <category>...` | Hides them. |
| `/namehook toggle <category>...` | Shows those that are hidden and hides those that are shown. |
| `/namehook target on` / `off` | Always shows your target's name, whatever its category. Your own name is the exception: if it is hidden, it stays hidden while you have yourself targeted. Off by default. |
| `/namehook popups` | Says the damage popups of last frame: what each says, whose it is, its colour, size and place, and whether the client drew it. |
| `/namehook popups watch on` / `off` | Says each new damage popup as it first appears. Off when the plugin is loaded, and not saved. |
| `/namehook perf` | Says what drawing for addons (names, bubbles, popups, layers) has cost over the last 240 frames: the time a frame on average and at worst, and how many drawings, quads, draw calls and captures of the device's state a frame; then last frame's names listed, those with no room in the list, and the drawings refused since loading. (1.48) |
| `/namehook status` | Says which categories are shown and hidden, how many names were listed last frame, from how many places the client draws names, how many names it drew more than once, and how many of those it moved up to where they were drawn highest. |
| `/namehook othercalls on` / `off` | Whether every place the client draws a name from is taken, or only the one that draws all the names. On by default. Turn it off if something that is not a name over a head goes missing. |
| `/namehook keepstates on` / `off` | Whether the device's state is captured once for a run of names an addon has drawn, or before each one. On by default. Turn it off if what the client draws after the names looks wrong. |
| `/namehook whitelist add <name>...` | Always shows these players' names. `wl` is short for `whitelist`. Names match whatever their case. The list is saved as it changes, to `config\namehook\whitelist.txt`, one name to a line. |
| `/namehook whitelist remove <name>...` | Takes them off the whitelist. |
| `/namehook whitelist list` / `clear` | Says the names on the whitelist, or takes them all off. |
| `/namehook fontsize <number>` | The height of the names, 1 to 256 pixels. 0, or `game`, is the game's own size, stretched as the game stretches it on a wide screen: the default. |
| `/namehook damagefontsize <number>` | The height of the damage numbers, the same way. 0, or `game`, is the game's own size: the default. |
| `/namehook hidestars` / `showstars` | Hides or shows the Job Mastery stars. |
| `/namehook save` | Saves the settings to `config\namehook\defaults.ini`: the sizes, the stars, the hidden categories and the target setting. |
| `/namehook load` | Loads them again. |
| `/namehook help` | Lists the commands. |

For example, to see only your party's names among players: `/nh hide players alliance`.

Settings changed by a command last until the plugin is unloaded, unless you save them. The settings and the whitelist are read from `config\namehook` alone. What the plugin kept under its old name, nameplatehook, and nameplatew's files, were read until 1.28. `/namehook save` writes `defaults.ini` where it is wanted, and `whitelist add` writes the list.

The [winplates](../../addons/winplates/README.md) addon is a settings window for the categories. It keeps them for each character.

## How it works

The client decides, for each character, whether its name is drawn at all, and then calls two functions of its own to draw the name's two lines: the name, and the Job Mastery stars. This plugin stands in the way of those two calls, where the name is sorted, listed, and drawn or not. Everything is put back as it was when the plugin is unloaded.

## Building

`./build.sh` builds `build/namehook.dll` on Linux with clang-cl and lld-link, as a 32-bit Windows plugin. It says at the top what it needs.

On Windows, `CMakeLists.txt` builds it with Visual Studio 2022 and CMake 3.28 or newer, as Win32 and not x64:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 -DASHITA_SDK_PATH="C:\Games\Ashita\plugins\sdk"
cmake --build build --config Release
```

The runtime and help, CMake and Windows resource versions come from `src/Version.h`.

Copy `namehook.dll` to `<Ashita>\plugins`.

## Credits

Nameplate is by BunnyBox Productions (Shirk / Velyn), 2022 to 2024. Nameplate-AshitaV4 is its community fork for Ashita v4. This fork is not affiliated with or endorsed by either.

## Stability

The blocks this plugin shares with addons are frozen at their 1.0 layout until 2.0: an addon made for 1.0 keeps working with every newer 1.x namehook.

## Pre-releases and release candidates

namehook is released inside winplates' package. A pre-release of winplates (`winplates-v<version>-pre1`) is a
pre-release of the namehook it carries, built from the same commit. What a round covers, and what to
send, is in [winplates' README](../../addons/winplates/README.md#pre-releases-and-release-candidates).
