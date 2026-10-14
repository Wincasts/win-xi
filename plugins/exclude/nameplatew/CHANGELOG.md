
## Nameplate-AshitaV4 export fix

- Added the Ashita v4 `expDestroyPlugin` export required by the current Ashita v4 plugin loader.
- Switched the Ashita export macro back to `__declspec(dllexport)` for explicit plugin entry point exports.
- Updated Ashita export definition files to expose `expCreatePlugin`, `expDestroyPlugin`, and `expGetInterfaceVersion` with stable ordinals.
- Documented the required Ashita v4 exports and the expected fix for `Plugin is missing required exports`.

# Changelog

## nameplatew 0.60 - 2026-10-10

Forked from Nameplate-AshitaV4 0.1.0 as `nameplatew`: the DLL, the `/nameplatew` command and the `config\nameplatew` folder all carry the new name.

- Added `mode hidepcparty` and `mode hidepcpartyself` (`NameMode` 7 and 8): player nameplates are hidden except those of the party.
- Added `IncludeAlliance` and `/nameplatew alliance on|off`: whether the rest of the alliance counts as the party.
- Added a whitelist of player names shown in every mode that hides players, managed with `/nameplatew whitelist add|remove|list|clear` and kept in `config\nameplatew\whitelist.txt`.
- Settings are read from `config\nameplate\defaults.ini` until `config\nameplatew\defaults.ini` exists.
- Added `build.sh`, which builds the DLL on Linux with clang-cl and lld-link, and `tests/`, which checks the name modes and the whitelist under wine.
- Removed the GitHub release workflow.

## AshitaV4 cleanup - 2026-06-14

- Fixed MSVC error C4576 in `src/bytes/bytes.h` by replacing a non-standard compound literal with `std::memcpy`.
- Removed an unused command-parser helper that produced warning C4505.
- Replaced the internal `findsignature.cppm` C++ module with `findsignature.h` to avoid Visual Studio module dependency scanner noise against Windows SDK headers.
- Updated CMake target sources for the normal header-based signature helper.
- Updated GitHub Actions release workflow to configure and build Win32 Release with Visual Studio.

## 0.51 - 2024-06-09

Add support for client version 30240604_1 ("June 10, 2024 (JST) Version Update")

## 2024-03-04

No actual code changes

Source code license changed to GNU GPL, version 3

## 0.50 - 2023-12-03

`DamageFontSizeInPx` and `/nameplate damagefontsize` added

## 0.40 - 2023-01-21

`NameMode` added

Commands for updating settings added

## 0.03 - 2023-01-07

Fixed defect preventing loading from startup scripts

## 0.02 - 2023-01-03

`HideStars` added

## 0.01 - 2022-09-30

Initial release
