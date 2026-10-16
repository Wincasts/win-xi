# clock — experimental 0.1

A minimal Vana'diel clock, drawn through **uihook 0.2** at the client's native clock boundary.
Shows **HH:MM**, weekday, Vana'diel date, moon illumination percentage and weather (when the
native weather source is available). No compass replacement UI is included.

## Install

1. Build `plugins/uihook/build.sh` and copy `plugins/uihook/build/uihook.dll` to Ashita's `plugins/`.
   Unload addons and the plugin before updating a DLL. Do not load buffhook/partyhook alongside uihook.
2. Copy `addons/clock` and the updated `addons/libs/winxi` (version **5** or newer) to Ashita's addons.
   The clock also uses Ashita's supplied `common`, `imgui`, `settings`, and `ffxi.time` libraries.
3. In game:

   ```text
   /addon unload hidecompass
   /load uihook
   /addon load clock
   ```

**Unload hidecompass first.** It hides the shared native compass/clock object, so the client's clock
render boundary no longer runs. Keep the native clock enabled in the game's settings too. Radar can
be disabled independently in the client: the clock hook covers both radar-on and radar-off paths.

## Commands

- `/clock` or `/clock status`: readiness/off status.
- `/clock on`: enable replacement (default).
- `/clock off`: release the clock slot; the stock clock returns.
- `/clock pos <x> <y>`: set position in ImGui display pixels.
- `/clock pos native`: back on the game's clock (the default).
- `/clock help`: command summary.

Settings are saved per character. The display is intentionally basic: fixed font, background, no
mouse interaction or configuration window. By default its bottom-left corner sits on the bottom-left
of the game's own clock, wherever uihook sees the game draw it, and it grows upward from there. It is
drawn when the game draws its clock, so what the game draws afterwards (the chat log) covers it: a
place of your own below the clock can be hidden. Until uihook has seen where the clock is, it sits 105
pixels above the bottom-left of the screen. It doesn't use winxi's full themed-window stack.

## Behavior and limitations

- Replaces only the **clock/day/weather** draw routine. The native compass stays untouched.
- Native visibility/layering is retained: no clock replacement when the client does not call its
  clock drawing routine, including native compass/clock hide states. No always-on floating fallback
  when the plugin, ABI, or time library is unavailable.
- One timestamp supplies all fields, sampled four times per second. Weather is read by C++ from the
  verified native source and handed over as an ID; no game or texture pointers cross Lua.
- Disabling/unloading Clock releases only its slot, not buffs, party, targets or a future compass
  addon. Missing submissions expire after two presented frames as with the other replacement modes.
- Capture/replay is prior-frame geometry. GPU capture/replay failures retain the existing renderer's
  fail-open behavior; this experimental addon does not guarantee a seamless transition on failure.
- Native keyboard/controller behavior is not rewritten. No memory state/opacity/visibility writes
  from hidecompass are used by the replacement.

**Not live-validated yet.** Check menu overlap, native clock/radar toggles, cutscenes, zoning, UI
hide/show, resolution/font changes, reset recovery and addon/plugin reload. The C++ discovery has
been cross-checked against the local private client dump; that is not proof of visible GPU output.

## Checks

```sh
plugins/uihook/tests/run.sh
luajit tests/nativehud_check.lua
luajit tests/clock_check.lua
```

See [uihook](../../plugins/uihook/README.md) for the hook protocol and native discovery details.
MIT, as the rest of this repository.
