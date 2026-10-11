# nameplatew

A fork of [Nameplate-AshitaV4](#nameplate-ashitav4), below, for Ashita v4. It does everything that plugin does, and adds:

- `/nameplatew mode hidepcparty` hides player nameplates except those of your party, your own, and charmed players. NPC and monster nameplates are all shown.
- `/nameplatew mode hidepcpartyself` is the same, with your own nameplate hidden as well.
- `/nameplatew alliance on|off` counts the other parties of your alliance as your party in those two modes. Off by default.
- `/nameplatew whitelist add <name>...`, `remove <name>...`, `list` and `clear` manage a list of players whose nameplates are shown in every mode that hides players (`hidepc`, `hidepcself`, `hidepcparty`, `hidepcpartyself`). `wl` is short for `whitelist`. Names are matched without regard to case, and the list is saved as it changes, to `config\nameplatew\whitelist.txt`, one name to a line.

- `/nameplatew custom on|off` is **experimental**. With it on, and an addon asking, the names the client is about to draw are handed to that addon to draw in its own way, and the client does not draw them. Off by default; with no such addon loaded it changes nothing. See [Handing names to an addon](#handing-names-to-an-addon), below.

It is loaded with `/load nameplatew` in place of `/load nameplate`: the two patch the same client code and cannot be loaded together. Its settings are kept in `config\nameplatew\defaults.ini`; until that file exists they are read from Nameplate's `config\nameplate\defaults.ini`.

`./build.sh` builds `build/nameplatew.dll` on Linux with clang-cl and lld-link, and `tests/run.sh` checks the name modes and the whitelist under wine; both say at the top what they need.

## Handing names to an addon

Experimental. The plugin keeps a list in its own memory, `CustomNames` in `src/Nameplate.cpp`:

| Field | Meaning |
|---|---|
| `Magic` | The 16 bytes `NAMEPLATEW-LIST` and a 0, by which an addon finds the list in `nameplatew.dll` |
| `Version` | 1 |
| `Hooked` | 1 while the client's name drawing is in the plugin's hands; 0 on a client it does not recognise |
| `Enabled` | The `custom` setting |
| `Consumer` | Set by the addon while it is drawing names, cleared when it stops |
| `Count` | Names added since the addon last set this to 0 |
| `Names` | Up to 256 of them: the entity's index, the point in the world where the client puts the name (above the head), the client's scale for it, and the model's colour |

While `Enabled` and `Consumer` are both set, each name the client is about to draw is added to the list and not drawn, and nor are its Job Mastery stars. Only names that would have been drawn are listed: the mode and the whitelist have had their say, and so has the client, which leaves out what is too far away or off screen. The addon reads the list once a frame and sets `Count` to 0.

If the list fills, no addon is emptying it, and the client draws names again until one does. So an addon that stops without clearing `Consumer` costs a few frames without names, and no more.

The client's two calls that draw a name are found beside the `mode` patch, and taken only if both lead where they are expected to. On a client where they do not, `Hooked` stays 0, `custom on` says so, and everything else works as before.

`addons/nameplates` in this project is a basic addon that draws the names this way.

Changes from Nameplate-AshitaV4 0.1.0 were made in October 2026 and are listed in `CHANGELOG.md`. The license is unchanged: GNU GPL v3.0.

---

# Nameplate-AshitaV4

Community-maintained Ashita v4 fork of [`Shirk/Nameplate`](https://github.com/Shirk/Nameplate), an FFXI plugin that corrects stretched or blurry nameplate rendering on widescreen and ultrawide displays.

This fork focuses on keeping Nameplate usable for modern Ashita v4 users while preserving the original project’s purpose, license, and attribution.

## What It Does

Final Fantasy XI’s native nameplate rendering can appear stretched or blurry when the game is played at widescreen or ultrawide resolutions. Nameplate corrects the nameplate aspect ratio so names remain clearer and more consistent across different window sizes.

This is especially useful for players using displays such as:

- 16:9
- 21:9 ultrawide
- 32:9 super ultrawide
- Other non-4:3 aspect ratios

The widescreen and ultrawide correction is automatic once the plugin is loaded. There is no separate “ultrawide mode” command.

## Project Status

This repository is a community-maintained Ashita v4 fork of the original Nameplate project.

Original project:

```text
https://github.com/Shirk/Nameplate
```

Original author / maintainer:

```text
Shirk / Velyn
```

This fork is not affiliated with or endorsed by the original author unless otherwise stated.

## Supported Runtime

Primary supported target:

```text
Ashita v4
```

This fork is intended to build and run as a 32-bit Ashita v4 plugin.

> Final Fantasy XI and Ashita v4 are 32-bit. Build this plugin as Win32/x86, not x64.

## Runtime Compatibility Note

Ashita v4 plugins must expose the required unmangled plugin entry points. This fork exports:

```text
expCreatePlugin
expDestroyPlugin
expGetInterfaceVersion
```

If Ashita reports `Plugin is missing required exports`, the DLL was built from an older or incorrect source state, or the linker did not include the Ashita exports definition file. Rebuild the DLL from the current source and replace the installed copy in `<AshitaRoot>\plugins`.

## Installation

### Manual Install

Copy the compiled plugin DLL:

```text
nameplatew.dll
```

to your Ashita plugins folder:

```text
<AshitaRoot>\plugins\nameplatew.dll
```

Example:

```text
C:\Games\PC\FFXI\Ashita\plugins\nameplatew.dll
```

Do not copy these build artifacts:

```text
nameplatew.lib
nameplatew.exp
```

Only `nameplatew.dll` is needed at runtime.

### First-Time Test

Launch Final Fantasy XI through Ashita, then run:

```text
/load nameplatew
/nameplatew help
```

Do not add Nameplate to your startup script until it has been manually tested and confirmed working in-game.

## Ashita v4 Usage

Load the plugin:

```text
/load nameplatew
```

Show command help:

```text
/nameplatew help
```

Save current settings:

```text
/nameplatew save
```

Reload saved settings:

```text
/nameplatew load
```

## Commands

| Command | Description |
|---|---|
| `/nameplatew help` | Shows in-game command help. |
| `/nameplatew load` | Loads configuration from `config\nameplatew\defaults.ini`. |
| `/nameplatew save` | Saves current configuration to `config\nameplatew\defaults.ini`. |
| `/nameplatew fontsize <number>` | Sets the nameplate font size in pixels. |
| `/nameplatew damagefontsize <number>` | Sets the damage font size in pixels. |
| `/nameplatew dmgfontsize <number>` | Alias for `/nameplatew damagefontsize`. |
| `/nameplatew hidestars` | Hides Job Mastery stars. |
| `/nameplatew showstars` | Shows Job Mastery stars. |
| `/nameplatew mode all` | Shows all nameplates. |
| `/nameplatew mode none` | Hides all nameplates. |
| `/nameplatew mode hideself` | Hides your own nameplate. |
| `/nameplatew mode hidepc` | Hides player nameplates, except when charmed. |
| `/nameplatew mode hidepcself` | Hides player nameplates, except when charmed, and also always hides your own nameplate. |
| `/nameplatew mode hidenpc` | Hides non-player nameplates. |
| `/nameplatew mode hidenpcself` | Hides non-player nameplates and also always hides your own nameplate. |
| `/nameplatew mode hidepcparty` | Hides player nameplates, except your party's, your own, and when charmed. |
| `/nameplatew mode hidepcpartyself` | Hides player nameplates, except your party's and when charmed, and also always hides your own nameplate. |
| `/nameplatew alliance on` / `off` | Counts the other parties of your alliance as your party in the `hidepcparty` modes. |
| `/nameplatew custom on` / `off` | Experimental. Hands the names that would be drawn to an addon that asks for them, in place of drawing them. |
| `/nameplatew whitelist add <name>...` | Always shows these players' nameplates in the modes that hide players. Saved at once. |
| `/nameplatew whitelist remove <name>...` | Takes these players off the whitelist. |
| `/nameplatew whitelist list` | Shows the names on the whitelist. |
| `/nameplatew whitelist clear` | Takes every name off the whitelist. |

## Recommended Starting Settings

For widescreen and ultrawide users, a good starting point is:

```text
/nameplatew fontsize 22
/nameplatew damagefontsize 22
/nameplatew mode all
/nameplatew save
```

If names look too large, try:

```text
/nameplatew fontsize 20
/nameplatew damagefontsize 20
/nameplatew save
```

If names look too small, try:

```text
/nameplatew fontsize 24
/nameplatew damagefontsize 24
/nameplatew save
```

## Configuration File

Ashita v4 configuration path:

```text
<AshitaRoot>\config\nameplatew\defaults.ini
```

Example:

```text
C:\Games\PC\FFXI\Ashita\config\nameplatew\defaults.ini
```

Example configuration:

```ini
[Settings]
FontSizeInPx=22
DamageFontSizeInPx=22
HideStars=0
IncludeAlliance=0
NameMode=0
```

### NameMode Values

| Value | Mode |
|---:|---|
| `0` | Show all nameplates |
| `1` | Hide all nameplates |
| `2` | Hide your own nameplate |
| `3` | Hide player nameplates, except when charmed |
| `4` | Hide player nameplates, except when charmed, and always hide your own nameplate |
| `5` | Hide non-player nameplates |
| `6` | Hide non-player nameplates and always hide your own nameplate |
| `7` | Hide player nameplates, except your party's, your own, and when charmed |
| `8` | Hide player nameplates, except your party's and when charmed, and always hide your own nameplate |

The configuration file is not automatically saved after in-game changes. Run this after changing settings:

```text
/nameplatew save
```

## Building from Source

### Requirements

- Windows
- Visual Studio 2022 or Visual Studio 2022 Build Tools
- CMake
- Ashita v4 plugin SDK containing `Ashita.h`

### Important Build Notes

Build as Win32/x86:

```text
-A Win32
```

Do not build as x64.

The CMake variable `ASHITA_SDK_PATH` must point to the folder containing `Ashita.h`.

Example:

```text
C:\Games\PC\FFXI\Ashita\plugins\sdk
```

### PowerShell Build Example

```powershell
$AshitaSdk="C:\Games\PC\FFXI\Ashita\plugins\sdk"; Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue; cmake -S . -B build -G "Visual Studio 17 2022" -A Win32 -DASHITA_SDK_PATH="$AshitaSdk"; if ($LASTEXITCODE -eq 0) { cmake --build build --config Release }
```

The compiled DLL should be created at:

```text
build\Release\nameplatew.dll
```

### Install Built DLL

```powershell
Copy-Item ".\build\Release\nameplatew.dll" "C:\Games\PC\FFXI\Ashita\plugins\nameplatew.dll" -Force
```

Adjust the destination path to match your Ashita installation.

## Ashita Manager Integration Notes

Nameplate should be treated as an Ashita v4 plugin.

Install target:

```text
<AshitaRoot>\plugins\nameplatew.dll
```

Recommended Ashita Manager behavior:

1. Download or build `nameplatew.dll`.
2. Confirm Ashita/FFXI is not currently running.
3. Back up any existing `plugins\nameplatew.dll`.
4. Copy the new DLL into the Ashita `plugins` folder.
5. Let the user manually test with `/load nameplatew`.
6. Only add Nameplate to startup if the user chooses to enable it.

Suggested component metadata:

```text
Name: Nameplate
Type: Plugin
Support Level: Community-maintained Ashita v4 fork
Install Target: plugins\nameplatew.dll
Original Project: https://github.com/Shirk/Nameplate
License: GNU GPL v3.0
```

## Repository Scope

This fork is maintained primarily for Ashita v4 users. Some original Windower-related code or historical references may remain in the source tree for attribution, compatibility history, or future reference, but Ashita v4 is the primary supported target for this repository.

## Credits

Original Nameplate project by Shirk / Velyn:

```text
https://github.com/Shirk/Nameplate
```

Community Ashita v4 maintenance:

```text
Rager825 and contributors
```

Special thanks to the FFXI modding community for preserving, modernizing, and documenting tools that make the game more enjoyable on modern systems.

## License

Nameplate is licensed under the GNU General Public License v3.0.

See:

```text
LICENSE.md
```

for the full license text.

Because this project is GPL-3.0, any distributed modified builds must preserve the license and provide corresponding source code.

## Disclaimer

This software is provided as-is, without warranty of any kind.

Use at your own risk. Final Fantasy XI, Ashita, Windower, and related names belong to their respective owners. This project is a community-maintained plugin fork and is not affiliated with Square Enix, Ashita, Windower, or the original upstream maintainer unless otherwise stated.
