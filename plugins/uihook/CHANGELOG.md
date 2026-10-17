# Changelog

## 0.4

- Chat ABI 10 (70208 bytes): the game's expanded-log rows of text decoded and measured as it draws
  them and, where the addon asks (ReplaceControls bit 4, copied with a successful expanded capture
  and only with the row site), left undrawn, the addon drawing its own text in their places. Each
  row's screen bounds, normalized to the viewport (a row that drew nothing placed where the game
  would have drawn it), its text as the game was given it (CP932 with its 1E/1F colour codes, the
  7F controls left out), its message's chat mode and its flags (cursor, pressed, marked, cut,
  placed) are published newest first (TextFrame, TextCount, TextSerial, Rows[128], Text[64 KB]);
  the serial moves only when the rows change. SupportedMask bit 7.
- A sixth verified CALL site, the one row-drawing call inside the log drawer the content Draw calls
  at +AA (cdecl, 22 words: the row's text, its 60-byte header by value, x, y, alpha, the cursor
  flag, an out pointer and a zero; the caller's add esp,58 checked), validated on its own and taken
  only with the control group; the drawer and the row draw are not patched, and the compact logs'
  rows pass through it untouched. The rows are decoded from the game's glyph words by the exact
  inverse of the client's encoder (transcribed in glyphs.h; the fixture round-trips every two-byte
  character): a single byte is its glyph and 20, glyph 5F (81 3F, the blank in an enemy's name) a
  space, glyphs 2115–2143 the pictographs EF 1F–EF 4D.
- `/uihook chat` says whether the row site was taken and how many rows were published, at what
  frame and serial, and their bytes.

## 0.3

- Chat ABI 9 (564 bytes): the game's expanded-log tab strip and scrollbar measured as it draws them
  and, where the addon asks (ReplaceControls bits 1 tabs, 2 scrollbar, copied with a successful
  expanded capture), left undrawn, the addon drawing its own in their places. Each tab's screen
  bounds, normalized to the viewport, its channel (from the owner's tab sprites) and whether it was
  drawn chosen are published (TabFrame, TabCount, Tabs[12]); the scrollbar's bounds and its page
  rows, row count and rows above the view (ScrollFrame, ScrollRect, ScrollPage/Count/Top), read
  from the fields FullLog::Update writes, never written. SupportedMask bit 6.
- A fifth verified CALL site, the full log's call to its tab strip (thiscall, the filter on the stack,
  ret 4; the content Draw's own fixed bytes keep ecx the owner), in the same all-or-none group as the
  four control sites; the strip's GPU submissions, art and labels alike, are blocked while the addon
  draws its own, with the game's hit-tests and Square selection untouched. Measurement reads
  screen-space vertices only, as the clock's.
- `/uihook chat` says what is replaced, how many tabs were measured and the scrollbar's rows.
- chat.h's helpers are inline, so the controls test builds without unused-function warnings.

## 0.2

- Chat ABI 8 (232 bytes): capture validated theme colours with the expanded frame. Tint native
  tabs, row-selection highlight, cursor and scrollbar via four verified CALL sites, preserving
  positions/scale/flags, native fade alpha and all native input/selection behavior.
- Selected tabs use the actual native sprite; scrollbar colours are changed in a local draw-only
  copy, never in native state. Control hooks are optional/all-or-none; missing signatures leave
  controls native. Add argument-preservation/Wine fixtures and optional private-client verification.
- Expanded capture mode 2 replaces only the frame; a unique full-log content signature
  cross-checked against its vtable lets native tabs, text, cursor and scrollbar draw unchanged.
- Keep native expanded keyboard/controller/mouse selection and message actions; retain the frame
  skin on older pages and all native filters. Reject stale compact/expanded captures across boundaries.
- Expanded typography and exact geometry remain native. Requires the updated nativechat bridge;
  offline tests/build pass, live GPU/interaction validation remains pending.

- Add verified native clock and compass boundaries, sharing the existing capture/replay renderer.
- Add independent HUD ABI 6 (164 bytes), clock/compass capabilities, native weather readback, the game's clock text's place, its map grid and its icons' places, a move and a scale for its weather icons and a preview of all of them.
- Redirect Clock::Draw's three icon calls, measuring each icon and leaving undrawn those the addon draws its own of.
- Redirect Clock::Draw's one text call, so a clock replacement hides only the game's text and keeps its day and weather icons.
- `/uihook` lists the addons handing it something now, and what; `/uihook hud` reports what the clock replacement is drawn into.
- Preserve stock clock during compass replacement and stock compass during clock replacement.
- Honor native radar availability and clock enable/visibility without persistent state writes.
- Keep buff ABI 4 and party ABI 3 unchanged; party and HUD release-all calls are isolated.
- Add basic clock addon and winxi nativehud bridge. No compass addon/UI yet.
- Add C++/Wine fixtures, Lua bridge/presentation checks and optional private-client call-graph verification.
- Live clock/compass validation remains pending.

## 0.1

- Consolidate buffhook and partyhook into one modular plugin without changing their handoff formats.
