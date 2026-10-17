# Native chat selection and expansion — 0.7 implementation

Static evidence from the unpacked Phoenix client captured 2026-10-15:
`addons/codedump/ffximain.bin` in the local test install (image base 031C0000).
Addresses below are **disassembly evidence, never runtime constants**. Discovery uses
unique byte patterns, in-module pointer checks and guarded live reads. Live GPU/interaction
validation remains required.

## Compact chat selection

- `CHAT_INPUT_PATTERN` locates the active native menu pointer. Cross-check the window
  against the primary/split owner children, not just its name.
- `Window::Render` (032D77D0) uses window +62 for cursor enable and +63 for focused-cell
  rendering. Native window selection drives the compact highlight without a Square binding.
- Primary-log event 5 (confirm) handler 03321AA0 opens `menu    fulllog ` via the native
  menu manager. Cancel uses the native close path. Neither action is intercepted.
- `menu    chatctrl` is the typing/channel menu, not the window selector.

## Expanded state and recognition

- `CHAT_STATE_PATTERN` identifies the native menu manager; byte +F1 > 2 is the existing
  expanded-chat predicate used by other addons. No writes or competing expansion state.
- Registry rows 0353282C / 03532858 / 03532884 describe logwindo / logwin2 / fulllog.
  The 44-byte rows' +32 globals must agree with the primary/split pointer signature.
- Full-log constructor 032F7630 identifies vtable 034F3B68. Owner +8 is the live child;
  its header must name `menu    fulllog ` at +46.
- Full-log Open (032F76A0) initializes cursor +1C, scroll +20, filter +54 and page rows +58.
  Unique Open/Update field-access patterns are checked against that class's vtable +28
  Update entry (032F7840). All live reads are guarded and bounded.
- Another active menu/input or invalid layout requests full native fallback. Nonzero scroll
  and cursor-only movement do not: the frame skin may remain on every native page/tab.

## Native content pass-through, not independent selection

The old implementation intercepted Up/Down/Confirm and selected independently wrapped addon
messages. Native row indices cannot safely map to that history: wrapping, deduplication,
filters and messages predating addon load can differ. That custom input path is removed.

Disassembly of `Window::Render` shows native decoration/list drawing before 032D7CEE, then
an owner virtual call through vtable +10 at 032D7D04. Native cursor and scrollbar rendering
follow that call. The full-log content method at 032F8020:

1. Draws the actual channel tabs via 032F7B80.
2. Reads the game's selected filtered history, skips native scroll rows, and draws the
   visible native rows through 033222E0.
3. Leaves the generic window renderer to draw its native cursor and scrollbar afterward.

`CHAT_FULL_DRAW_PATTERN` uniquely matches this content method's prologue and must equal the
verified full-log vtable +10 entry. Only then may the plugin detour its first five bytes:
`sub esp,0Ch; push ebx; push ebp` (whole non-relative instructions).

For a fresh **frame-only** primary submission, uihook replays the WinXI decoration at the
full-log boundary and suppresses native decoration GPU submissions. At content Draw it turns
GPU blocking off, allowing the native tabs, rows, row decorations, cursor and scrollbar to
render normally in the same native frame. Blocking and scope flags are restored on leaving
the outer window render. All navigation, mouse hit-testing and message-action menus remain
native; no row mapping, name parsing, synthesized keys or input-buffer writes are involved.

Expanded geometry is exactly native: compact width/font/padding/input relocation must not
move its rows away from native hit-tests. Expanded glyphs, spacing and colours remain native.
Re-rendering these with WinXI fonts would require a separately verified source-text/glyph and
row-position bridge; the native row buffer contains engine font indices, not plain CP932 text.

## Native control artwork

`controls.h` redirects four uniquely matched CALL sites; shared sprite functions are not detoured:

- Tab art: 032F7C36, within 032F7B80 (itself the first callee of full-log content Draw).
  Calls simple Sprite::Draw at 032DFB60: thiscall with five stack words (x, y, colour, flags, flags).
  The selected sprite is `owner + 0x84 + filter*8`; this follows the actual selected native tab,
  not a guessed tab order. Channel 0..10 is accepted for this optional art read.
- Row-selection art: 032D7AAE, inside Window::Render, calls scaled Sprite::Draw 032DFC80.
  Only native selected-row colours 80805020 / 40402810 are tinted and allowed through frame
  suppression. Other window background/art colours remain suppressed as before.
- Cursor: 032D7E92, same scaled sprite callee and eight stack words. Coordinates, scaling float
  bits and flags remain unchanged; colour follows the captured cursor tint.
- Scrollbar: 032D7EB9 calls Scrollbar::Draw at 033F4660. Draw only reads +00..+27, with colours
  at +18/+1C; a local 40-byte copy changes those words only and is passed to the original Draw.
  The native object, page/count/offset, dimensions, scale and mouse/drag fields are never written.

All four sites/callees and parent-function boundaries must validate before any CALL is patched.
Absent/ambiguous signatures disable optional control tinting, not the native content/frame path.
These patterns and relationships were verified against the same private client dump. Native
sprite colour unity is 128. RGB follows the captured theme; alpha multiplies the original native
fade/pulse alpha. Native tab labels/art remain coupled; this is tinting, not custom text or
WinXI Tab Style texture substitution. Navigation/hit-tests/menu actions remain entirely native.

## ABI 8 safety boundary

- 232-byte shared layout, **version 8** required on both sides.
- SupportedMask bit 3: native full-log state/geometry. Bit 4: verified content hook. Bit 5: control art.
- ControlStyleFrame and four RGBA colours are published by Lua. The plugin checks finite [0,1]
  values and a current-frame stamp, then snapshots them only with a successful expanded capture.
  Missing/invalid styles never suppress or recolour native message text.
- Primary capture mode 1: compact contents; mode 2: expanded frame only, requires bit 4.
- Compact captures never cover full-log windows, and expanded captures never cover compact
  windows. Empty expanded submissions cannot hide native content. Secondary/input captures
  are not replayed during expansion.
- Missing content hooks leave expanded native drawing intact; compact replacement is independent.
- Nested menus/input, stale submissions, capture failure and release restore full native drawing.

## Validation

Offline C++/Wine fixtures cover discovery ambiguity, vtable mismatches, native focus,
scroll/filter state, boundary isolation, native-content unblocking and release. Control fixtures
also check call/callee ambiguity, all-or-none patching, unload restoration, exact argument/float-bit
forwarding, native colour units/fades, selected-tab reads, scoped GPU bypass and scrollbar copy
isolation. `tests/check_chat_client.py` verifies the private client CALL graph. Lua fixtures
check ABI/capability gating, exact full-log bounds, no custom expanded text/selection/input,
mouse pass-through, missing geometry, menu handoff and compact restoration.

The content signature/vtable +10 and all four control CALL sites/callees were also checked against the private client dump.
Still check live: Square/select/expand, hover each row, keyboard and controller navigation,
Confirm/message-action menus on multiple channels and older pages, Cancel, typing, split chat,
UI hiding, resolution/UI scaling, zoning, device recovery and addon/plugin unload/reload.
