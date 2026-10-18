# Changelog

## 0.6

- Lighter for every window the game draws: a window's own name is read first, so one that is none of the
  chat's costs two guarded reads, not eight; a chat menu's name still has its owner followed afresh.
- Independent menu ABI 1: chat-owned panel bounds published only with successful compact capture.
  Registered native command/magic/ability/inventory/item-use/control menus can anchor above it.
- Verified Window::Render→Update call and target-field copy signatures; live registry ownership,
  header, writable-field and scaled-coordinate checks. Native layout target is changed before its
  own Update; no render-only offset, mouse remapping, selection or input interception.
- Restore owned positions on expired replay/request, expanded chat, opt-out, zoning and unload;
  never restore a freed/replaced owner or overwrite a newer native-written origin. Oversized menus
  and unknown clients/owners stay native. `/uihook menus` reports readiness/apply/restore counts.
- An event's choices (`query`, an NPC's Yes/No under its message) join the moved family; a unique
  in-module registry global, as the others.
- The first log window over a second stacked above it: the game draws the second after the first, so the
  second's replacement covered the half of the first's title above its top edge. While the second is
  replaced (drawn last frame, with a capture), the first's replay is held back and drawn straight after the
  second's. Side by side, or the second drawn first, nothing changes.
- The full log mirrored: ReplaceControls bit 8 (CHAT_REPLACE_ALL, granted only with tabs and text)
  keeps the full log's GPU submissions blocked through its content Draw and Window::Render's cursor,
  scrollbar and row-selection art, so the marked rows' sprites and anything else it draws are left
  undrawn too; every control and row is still measured and published, and all navigation, hover and
  Confirm stay native. SupportedMask bit 11 (2048) advertises it, with the row site. Menus over the
  log are other windows and stay native.
- `/uihook chat history` and `/uihook menus` reach their reports: the command dispatcher read only two
  words and had no `menus` case, so the first gave `/uihook chat`'s report and the second the help.
- The first log window's history read on request: an independent history ABI 1 (magic UIHOOK-HISTORY,
  16 + 36 + 2400 + 65536 bytes). On an addon's request, uihook reads the window's ring (its owner's +18:
  +14 newest, +16 oldest, +1A count, 100 lines of 2 KB from +20) oldest to newest, each line's 60-byte
  header and words, decoded with the expanded log's decoder, and publishes each line's text, whole mode
  word, serial (+0C), flags (+15) and +38 (cleared, with flags masked to 0xB0, on a message's lines after
  its first); read only, once a request. `/uihook chat history` prints the newest 12 with those fields.
  tests/history: order round the ring's end, decoding, the fields, bad indices, a full ring.
- The full log's row highlight measured: each row-selection art call in a skinned full log (drawn or
  not) is measured from its vertices, and a published row whose middle it covers gets Rows flag 32
  (CHAT_ROW_LIT), so the addon lights what the game highlights. No ABI change.
- The expanded chat log placed where the addon asks: menu ABI 1 grows to 108 bytes (LogRequestFrame,
  LogPlace[2] bottom-left in pixels, LogFrame, LogApplied, LogRestored; unreleased, so still 1). The
  full log's Window target is moved before its own Update, as the menus' are, its size kept, kept on
  the screen; a stale request, release and unload give the game's place back. `/uihook menus` says it.
- Chat ABI stays 13; older addons behave as before. Needs live cursor/mouse/artwork validation.

## 0.5

- Chat ABI 13 (71684 bytes): the game's chat colours as configured (ColorFrame, ColorSerial, InlineColors[17],
  CategoryColors[256], ModeCategory[256]), read each frame from the game's mode table, category colour table
  and inline palette, the serial moving only when they change; the game's components are of 80 as one.
  SupportedMask bit 10. Recognition only, nothing written.
  Each table is copied whole, one memory check for each region it lies in, not one for each entry: about 250
  VirtualQuery calls a frame fewer.
- Chat ABI 12: each log window's lines as the game has them now (LinesFrame, Lines[2][3]:
  its lines, its most and its fewest), read each frame from the window's owner, whose fields are pinned
  by its Update and grow signatures and checked for sense. SupportedMask bit 9. The game grows a window
  a row for each message and shrinks it to its fewest lines while none come; its window rect follows.
- Chat ABI 11: the game's two log windows. The second window's bounds (SplitRect,
  SplitRectFrame, read as the primary's are) and the game's routing between the two, read each frame
  (WindowFrame, WindowFlags bit 1 the second window shown, WindowModes[2][8]: per window, a bit for
  each chat mode its Log Window settings keep). SupportedMask bit 8. Nothing is hooked or written for
  it: the client's keep check is recognised (the first window's, which keeps everything while the
  second is hidden, a mode word with bit 15 set, and otherwise its config words B9/BA by the mode's
  category's bit; the second's, which drops bit-15 words and reads BB/BC) with its mode table, its
  category cases (read from the jump table) and the config manager's value reader, and the decision
  is made again for every mode from the same data, again only when the config or the flag changes.
- `/uihook chat` says whether the routing was read, whether the second window is shown, how many
  modes each window keeps and when the second window's bounds were read.

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
- A menu open over the live full log (a row's action menu, the input line) no longer hands the
  expanded view back to the game: the log keeps its skin under the menu, and StateFlags bit 4
  (`State().nested`) notes it. Invalid layout, or another menu before the full log is made, still does.

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
