# uihook — experimental 0.2

One Ashita v4 plugin for native UI replacement, with independent **buff**, **party/alliance**,
**target**, **clock** and **compass** capabilities. Replaces loading `buffhook` and `partyhook`; the addons remain separate.
Loading uihook without addon submissions leaves native drawing unchanged.

## Build and install

```sh
plugins/uihook/build.sh
```

Uses the same clang-cl/lld-link, x86 Windows SDK/MSVC and Ashita SDK toolchain as the previous plugins
(default `.toolchain`; overrides: `TOOLCHAIN`, `ASHITA_SDK_PATH`, `MSVC_PATH`). Output:
`plugins/uihook/build/uihook.dll`.

Unload addons and old hooks **before replacing DLLs**:

```text
/addon unload buff
/addon unload party
/addon unload clock
/unload buffhook
/unload partyhook
/unload uihook
```

Copy the built DLL to your Ashita `plugins/` directory, deploy the updated buff/party addons, and
replace old hook load commands in your startup script with:

```text
/load uihook
/addon load buff
/addon load party
```

Buff uses its existing anchored-bar setting. Party replacement stays default-off:

```text
/addon unload hideparty
/pt native on
/pt native target on
/pt native status
```

Party and target opt-ins are independent. **Do not run hideparty with either native Party mode.**
Organize still uses ordinary ImGui windows. Native party positioning remains gated off, as in
partyhook's testing build. Existing styling, positions and saved settings are unchanged.

Updated addons prefer uihook, but can still use their legacy plugins when uihook is absent.
Do not load old and new plugins together. Uihook refuses initialization if either legacy DLL is
present. Rebuilt legacy plugins also reject loading while uihook is present; older binaries do not
have this guard, so remove their startup commands. To revert, unload the addons and uihook first,
then load the legacy plugins and reload the addons.

## Clock and compass

The [clock addon](../../addons/clock/README.md) writes the clock on one line in place of the game's
text, keeps the game's icons and hides the compass through the compass slot. Deploy winxi 5 and
`/addon load clock` after loading uihook. **Unload hidecompass first**: it hides the shared native
object and prevents both clock and compass render boundaries from running. Enable the native clock
in the client. Radar can remain independently on or off. No compass addon/UI is included yet.

`hud.h` discovers the shared native compass object via hidecompass's update-step signature, verifies
its tail jump to `Compass::Draw`, then cross-checks BOTH clock CALLs (radar-on/off branches) against
`Clock::Draw`. Clock detours steal six whole non-relative instruction bytes and preserve `this` plus
two signed stack coordinates (`ret 8`). A separate signature verifies the native radar-visibility
query before compass replacement can be advertised. Optional native weather discovery is bounded to
the clock function and its in-module global; failure leaves weather unavailable, not clock disabled.
No fixed addresses or persistent native visibility/opacity writes are used.

Clock::Draw makes one text call, `Text(x-50, y+26, "%d:%02d  %s", colour)` (cdecl, four arguments),
then draws the day icon at (x-68, y+26) and, for weather 4 to 19, the weather icon at (x-68, y-42),
twice side by side for double weather. `CLOCK_TEXT_PATTERN` finds that call, unique and within
Clock::Draw's first 0x100 bytes, and it is aimed at uihook's own (still a CALL, so the return address
is the game's). With a fresh clock replacement only the text gives way: the game's text call still
runs with its GPU submissions blocked, which is how its screen bounds are measured, and the icons
draw as ever. Without the call found, the whole of Clock::Draw is replaced, icons and all.

The three icon calls, `Sprite::Draw(this=sprite, x, y, colour, 0, 0)` (thiscall, five stack words,
`ret 0x14`), are found the same way, all three or none, each inside Clock::Draw and each calling the
one sprite routine, and aimed at uihook's own. Each icon is measured on the screen, drawn or not
(`IconRect`). The game's day or weather icons (both weather icons for double weather) are left
undrawn only for those the addon names in `HideIcons`, and only while its clock replacement is drawn
in that call: an addon that stops, fails or is unloaded has the game's back at once.

The dispatcher runs original native logic with GPU submissions suppressed only while a fresh
replacement is being drawn. Nested clock calls temporarily escape compass suppression; with only a
compass replacement, the stock clock still draws, and with only a clock replacement, the stock
compass still draws. Radar-disabled/unsupported-zone checks gate compass replay. Native clock-enable
and shared visibility states gate clock replay. Missing signatures or replay failure leave the
unsupported element native. HUD discovery does not depend on party/window recognition.

### HUD ABI 4

A third, independent block in `uihook.dll`: `UIHOOK-HUD` padded to 16 bytes, **152 bytes** total:

```text
char Magic[16]
u32 Version, Size, SupportedMask, Frame, Submit
u32 DrawnFrame[2], NativeFrame[2], Weather
float ClockRect[4]; u32 ClockRectFrame
char Grid[12]
float IconRect[3][4]; u32 IconFrame[3]
u32 HideIcons            written by the addon
```

`SupportedMask`: bit 0 clock, bit 1 compass. `Submit` is `cdecl int(index, capture)` and may only be
called on the render thread while the matching DLL/ABI is loaded. Index 0 clock, 1 compass;
capture 1 synchronously captures/consumes the current ImGui window, 0 renews intentionally empty,
-1 releases that slot. Index -1 releases both HUD slots **only**, never Party's slots. Party's own
release-all likewise cannot release HUD slots. `NativeFrame` records the last eligible native
boundary; `Weather` is a native ID (0xffff unavailable), sampled at `NativeFrame[0]` and expiring
with that timestamp. `ClockRect` is where the game wrote its clock's text (left, top, right, bottom), taken
from the screen-space draws of its text call, replaced or not (all of Clock::Draw's draws without the
call), and turned into ImGui display pixels by the inverse of replay's mapping; current at
`ClockRectFrame`. A replacement drawn below the clock would be covered by what the game draws after
it, the chat log among them. `Grid` is the map grid the game prints after the time, `(H-9)`, copied
from the clock's object (+0x11, eight characters, then zeros) at `ClockRectFrame`. `IconRect` is
the day icon (0), the weather icon (1) and the second weather icon (2), as `ClockRect`, each current
at its `IconFrame`. `HideIcons` is bit 0 the day icon and bit 1 the weather icons; the bridge writes
it each frame and clears it as the clock slot is released. Geometry limits,
clipping, font validation, texture retention and two-frame
freshness reuse the existing capture/replay implementation. Addons should use the slot-specific
`winxi.nativehud` bridge, which validates ABI, capability, unload/reload and weather, place and grid freshness.

## Architecture

- `src/uihook.cpp`: sole exported plugin entry point, lifecycle dispatch and scoped GPU-filter routing.
- `src/modules/buffs/`: icon/time detours, native origin and selector cursor, textured quad replay.
- `src/modules/party/`: party/alliance/target identification, ImGui capture/clipping/replay,
  scoped stock-HUD suppression and native target-arrow exceptions. `hud.h` adds clock/compass
  discovery and scope helpers, sharing the same renderer/filter rather than installing another.

This is a behavior-preserving consolidation, not a rewrite of both renderers into one abstraction.
Each module retains its own frame clock, D3D state/texture ownership, signature validation and cleanup.
One GPU filter handles party/target and clock/compass scopes; buffs intercepts separate native icon callbacks.
A missing signature disables only the affected capability. No additional global UI suppression is added.

The two existing shared blocks are now located in **uihook.dll**: `BUFFHOOK-SHARED` (buff ABI 4) and
`PARTYHOOK` (party ABI 3, 168 bytes). Marker names and layouts intentionally remain unchanged.
Each addon validates its own block; there is no new combined ABI or hard dependency between addons.
Missing/stale submissions restore native drawing after two presented frames. Fresh empty submissions
mean intentionally hidden replacement. Module-specific native behavior is not generalized away.

Implementation background and inherited limitations:
[buff protocol](../buffhook/README.md#for-the-addon),
[party capture/target arrows](../partyhook/README.md#rendering-implementation).
Future UI modules should own their recognition and native semantics; any additional use of
`Window::Render` must share the existing detour/dispatch rather than patch that boundary twice.

## Checks

```sh
plugins/uihook/build.sh
plugins/uihook/tests/run.sh
luajit tests/nativehud_check.lua
luajit tests/harness.lua clock tests/clock_stand_in.lua tests/clock_check.lua
python3 plugins/uihook/tests/check_hud_client.py /path/to/ffximain.bin /path/to/ffximain.txt
luajit tests/party_hook_performance_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/party_hook_integration_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/party_native_positioning_check.lua
```

The Wine fixtures compile against the migrated modules' headers, checking signatures, detours,
restoration, clipping, arrow forwarding and party ABI. Lua bridge checks run against both legacy
DLL names and uihook. HUD fixtures cover discovery ambiguity/call-target/global rejection,
clock calling convention/trampoline/restoration, radar/clock filter independence, optional weather and
ABI. Lua checks cover slot isolation, reloads, weather expiry, clock presentation and capture timing.
These are offline checks, **not proof of live GPU output**.

In game, `/uihook` (or `/uihook addons`) lists the addons handing uihook something now, and what:
buff's bar, party's party, alliance and target windows, clock's line and its hidden compass, each
marked "(hidden)" where the addon hands over an intentionally empty replacement. A plugin cannot see
which Lua addon calls it, so this is read from the slots, each filled by one addon only, while the
last submission is fresh (two frames). It also says which parts this client was not recognised for.

`/uihook hud` prints what the clock replacement was drawn into: Clock::Draw's calls and
position, the replayed vertices' bounds, the viewport, the render target against the back buffer,
whether a scene was open, a few of the game's render states, and the game's own clock draws (their
count, vertex format and, for drawing from memory, their screen bounds), where its text is, whether its
text call was taken and the grid. It only reads.

Live validation is required for combined buff/party/target use: menu overlap, buff selection/cursor
restoration, target/subtarget arrows, independent toggles, Organize, addon/plugin unload/reload,
cutscenes, zoning, UI hide/show, resolution/font changes and device recovery. Existing partyhook
validation gaps carry over; uihook itself has not yet been live-tested. Clock/compass additionally
need native clock/radar toggle checks, radar-disabled zones and hidecompass removal validation.

MIT; see `LICENSE.md`.
