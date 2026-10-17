# Native chat selection and expansion — 0.7, 0.8 and 0.9 implementation

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
- Invalid layout, or another menu active before the full log is made, requests full native
  fallback. A menu open over the live full log (a row's actions, opened by Confirm, or the input
  line) does not (0.9): the log is still drawn under it and keeps its skin, with StateFlags bit 4
  noting the menu, which is the game's own. Nonzero scroll and cursor-only movement do not either:
  the frame skin may remain on every native page/tab.

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
move its rows away from native hit-tests. Expanded spacing remains native. The glyphs are the
game's unless the addon asks for its own text (0.9, below): the native row buffer holds engine
font indices, not plain CP932 text, and those are decoded by the encoder's exact inverse.

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

- Tab strip: the content Draw's first call (full+19), to 032F7B80. The prologue pattern fixes the bytes
  from `mov esi,ecx` to the call (`xor ebp,ebp; mov eax,[esi+54]; mov [esp+14],ebp; push eax; call`), so
  ecx is still the owner and the one stack word is the filter: thiscall(owner, filter), `ret 4`, which
  check_chat_client.py looks for within the function. Redirected so that the whole strip, art and
  labels, can be left undrawn while the addon draws its own tabs (0.8), and so that each tab sprite
  call inside it can be measured. The owner's tab sprites are at +0x80 + channel*8 (plain) and
  +0x84 + channel*8 (chosen), channels 0 to 10: whose tab a sprite call draws, and whether chosen.
- Scrollbar fields: the verified Update pattern writes page rows to +0x0C, the filtered row count
  (`and eax,0FFh`) to +0x10 and count − scroll − page, the rows above the view, to +0x14. Read at Draw
  for the addon's own thumb; never written. The Draw's own `cmp [ecx+10],[ecx+0C]; jle` means no Draw
  (and so nothing measured) when every row fits.

- Rows of text (0.9): the content Draw's last call, at +AA (032F80CA), is to the log drawer
  033222E0, shared with the compact logs (thiscall(renderer; x, y, newest row, page rows, y offset,
  marker sprite), `ret 18`); its prologue (`sub esp,0C; mov eax,[global]; mov [esp],ecx; push ebx;
  push ebp; mov cl,[eax+8]; push esi; test cl,cl; push edi; je`) is matched with the global
  wildcarded. The drawer steps back through the history ring (the global at 03738158: `[+14]` the
  newest row's index, `[+16]` the oldest's, 100 rows of 2 KB from +20, 032E92E0 stepping to the
  previous row and giving its text at row+3C) and for each visible row calls 033220F0 once, at
  03322457: cdecl, with the row's text pointer, its 60-byte header copied by value (`mov ecx,0F;
  sub esp,3C; mov edi,esp; push ebp; rep movsd`), x+4, y, alpha 7F, the cursor flag, an out pointer
  and 0: 22 words, taken back by `add esp,58` within the 40 bytes after the call. That site is the
  sixth redirected CALL. The row draw is also called from 032F6BC5 and 032F719A (the full log's own
  copy and action paths), which are left alone. Row header: +00 the message's chat mode (the colour
  032E9C70 gives it), +10 word count, +12 cursor state (1 the cursor's row, which then draws the
  game's mark after its text through 033222A0), +15 flags (0x40 draws the owner's +E0 sprite under
  the row, before the rows, in the drawer: never blocked).
- Row words: the encoder 032E8507 writes, per byte of the message, a glyph (a single byte less 20;
  a two-byte SJIS character through the piecewise JIS-row/column formula at 032DC940) or a negative
  word: `7F xx` as −xx (which 03322140 draws nothing for), `1E xx` as FF00−xx (the palette colour,
  03321FD0) and `1F xx` as FE00−xx (the chat mode's colour, 032E9C70). The glyph draw 032DBF40 →
  032DBBD0 submits each glyph as one DrawPrimitiveUP of a 16-pixel cell (the float at 034EA1AC) at
  x−0.5, y−0.5 in screen space with no transform, so the rows are measured as the tabs are, per
  row-draw call. Glyphs 2115–2143 are the game's pictographs (the table at 037E1934, `[glyph*4 −
  8454]`), EF 1F to EF 4D; glyph 5F is what 81 3F (the blank between an enemy's name's words)
  encodes to. The client's own glyph-to-bytes routine 032DCB50 (called from 032F85F7 for copying a
  row) is off by one at its ED3F band and maps some glyphs elsewhere, so glyphs.h inverts the
  transcribed encoder instead: each glyph the lowest SJIS code that encodes to it. The fixture
  round-trips every two-byte code.

All five control sites/callees and parent-function boundaries must validate before any CALL is patched;
the row site is validated on its own and only taken with them.
Absent/ambiguous signatures disable optional control tinting, not the native content/frame path.
These patterns and relationships were verified against the same private client dump. Native
sprite colour unity is 128. RGB follows the captured theme; alpha multiplies the original native
fade/pulse alpha. Native tab labels/art remain coupled; this is tinting, not custom text or
WinXI Tab Style texture substitution. Navigation/hit-tests/menu actions remain entirely native.

## Measured controls (0.8)

Within a skinned full log, each tab sprite call and the scrollbar Draw are measured from the
screen-space (XYZRHW) vertices they submit, as the clock's draws are, and published normalized to the
viewport they were drawn in (D3D8's half pixel added), with the tab's channel and chosen state and
the scrollbar's rows. The addon asks, with its expanded capture, for the strip and/or the scrollbar
to be left undrawn (GPU submissions blocked for that call alone) and draws its own at the published
places the frame after, so the game's hit-tests, Square selection and wheel are what they were. No
geometry is derived from sprite fields; nothing native is written. A frame in which the game draws
no strip or no scrollbar publishes none, and the addon then leaves the game's drawn.

## Measured text (0.9)

Within a skinned full log, each row-draw call is measured from the screen-space vertices its glyphs
submit (and the cursor's mark, on the cursor's row), its header read from the by-value copy and its
words read (guarded) from the ring, decoded and published with its bounds, mode and flags: TextFrame,
TextCount, Rows[128] and Text[64 KB], newest first, as the drawer draws them; TextSerial moves only
when the published rows differ from the last. A row that drew no glyph is placed where the game
would have drawn them, a 16-pixel cell at its x, y, when the viewport is known. Asked (ReplaceControls
bit 4, only with the row site), each row-draw call's GPU submissions are blocked, glyphs and the
cursor's mark alike; the 0x40 marker sprites, the row highlight, the cursor and all hit-tests are
the game's. The compact logs' rows pass through the same site untouched.

## The two log windows (0.5)

Each log window owns a history ring (the globals at 03738158, 0373815C and 03738160: the first
window's, the second's and the full log's; a window owner's +18 points to its ring), and the text-in
function 032E7C00 (the one Ashita hooks for text_in) hands every message to both compact rings through
032E8CE0, which wraps it to the window's width (owner +32) and keeps a row only where the window's keep
check 032E9980 (thiscall(ring; the 60-byte header by value, the window's filter), ret 40) says so:
filter 0, the first window's, at 032E9B40, filter 8, the second's, at 032E9B80, and the full log's tab
filters 1 to 10 in 032E99F0 (which lists the same modes per channel as chatbox's channels.lua). The
first window keeps everything while the second is hidden (the second's owner, the global [037E1940],
the split log's of the primary/split signature, byte +4D zero), keeps a mode word with bit 15 set
(header byte 1's top bit), and otherwise asks 032E9BB0(mode's low byte, default 1, B9, BA); the
second drops bit-15 words and asks 032E9BB0(mode, default 0, BB, BC). 032E9BB0: the mode's entry in
the table at 0352E888 (032E9CD0: entries of a mode word, a category byte and one more, the first with
that word, ended by a zero word; 196 of them), the category's bit from the jump table of 032EA120
(categories 54 to 71: a constant, zero, or none, which takes the default), and that bit of the two
config words, read through 03353850 (the config manager at [038226CC]; 03355330 the value of the
entry 033554D0 gives, the array at the manager's +4, 44 bytes an entry, the value at +8; -1 without
a manager or array), 03353A10 testing bit n of the pair. windows.h recognises each of these by a
unique pattern (the config reader's is matched twice, the twin reading another value; both must
name one manager global, and one must call the value), reads the table, the cases and the config
words, and makes the same decision for every mode, publishing a bit per mode per window, made again
only when the words or the flag change. Nothing is called and nothing written; the keep check is
not hooked. The compact logs' rows are pre-wrapped lines in each ring, so the addon keeps its own
history and routes it with the published bits rather than reading the rings.

## Each window's lines (0.5)

The compact log owner's Update (03322800 on) holds the window's height in pixels at +34, which its grow
03322560 (called from the ring insert for each row of a message) raises by the row height +54 up to the
most lines +4E (config), and which the Update lowers by the frame's time while nothing holds it, down to
the fewest lines +50 (config); +31 is then the ceiling of the height over the row height, the lines
shown, +30 one more, the page rows the drawer gets, and the window's rectangle (032D8F70 at the Update's
end) is set from +31, its top (lines − 8) × 16 from a baseline. The base constructor 03321ED0 (both
owners', 03321850 the first's and 03321B80 the second's) sets +54 to 14, +4E to 8, +50 to 0 and +31 to
4. SampleLines reads +31, +4E and +50 from each owner (the slots of the primary/split signature), with
+34 and +54 for sense, every frame; nothing is written.

## The game's colours (0.5)

The row draw colours a row's words by its message's chat mode through 032E9C70(mode): the mode's entry in
the table at 0352E888 (032E9CD0), its category byte, then 032E9D00(category): the category colour table at
0352E6E8 (8-byte entries, a category byte and its colour at +4, ended by a zero category; 51 of them;
032E9D40 writes a category's colour, which is where the user's configuration lands), 80808080 for a mode
or category without an entry. A `1F xx` word takes 032E9C70(xx), a `1E xx` word 03321FD0(xx): slots 0 to
16 from the palette of 17 colours at 034F53C8, others as categories. Components are of 80 as one:
80808080 is white, FF5020FF (category 51, Ashita's timestamp) purple, 80FF3C3C (category 63, melee
damage by another) red. colors.h recognises the three lookups by unique patterns and reads the three
tables every frame, publishing each mode's category, each category's colour and the palette with a
serial that moves only when they change; nothing is called or written.

## ABI 13 safety boundary

- 71684-byte shared layout, **version 13** required on both sides.
- SupportedMask bit 3: native full-log state/geometry. Bit 4: verified content hook. Bit 5: control art.
  Bit 6: the tab strip and scrollbar measured and hideable (the same all-or-none group of sites).
  Bit 7: the rows of text decoded, measured and hideable (the row site, verified on its own, taken only with bit 6).
  Bit 8: the two log windows' routing read and the second window's bounds published (recognition only, no site taken).
  Bit 9: each window's lines read from its owner (recognition only).
  Bit 10: the game's colour tables read (recognition only).
- ControlStyleFrame and four RGBA colours are published by Lua. The plugin checks finite [0,1]
  values and a current-frame stamp, then snapshots them only with a successful expanded capture.
  ReplaceControls (1 tabs, 2 scrollbar, 4 text) is snapshotted with it, and only with the hooks each needs.
  Missing/invalid styles never suppress or recolour native message text.
- Primary capture mode 1: compact contents; mode 2: expanded frame only, requires bit 4.
- Compact captures never cover full-log windows, and expanded captures never cover compact
  windows. Empty expanded submissions cannot hide native content. Secondary/input captures
  are not replayed during expansion.
- Missing content hooks leave expanded native drawing intact; compact replacement is independent.
- Stale submissions, capture failure and release restore full native drawing; a menu over the live full log leaves its skin.

## Validation

Offline C++/Wine fixtures cover discovery ambiguity, vtable mismatches, native focus,
scroll/filter state, boundary isolation, native-content unblocking and release. Control fixtures
also check call/callee ambiguity, all-or-none patching, unload restoration, exact argument/float-bit
forwarding, native colour units/fades, selected-tab reads, scoped GPU bypass and scrollbar copy
isolation. `tests/check_chat_client.py` verifies the private client CALL graph. Lua fixtures
check ABI/capability gating, exact full-log bounds, no custom expanded text/selection/input,
mouse pass-through, missing geometry, menu handoff and compact restoration.

The content signature/vtable +10, all five control CALL sites/callees and the row site (the drawer at +AA,
its row-draw callee, the stack cleanup and the encoder's prologue) were also checked against the private client dump.
Still check live: Square/select/expand, hover each row, keyboard and controller navigation,
Confirm/message-action menus on multiple channels and older pages, Cancel, typing, split chat,
UI hiding, resolution/UI scaling, zoning, device recovery and addon/plugin unload/reload.
