# Changelog

## 1.2

- The mouse on a menu the menus addon draws somewhere else, or larger: the game reads each mouse message in
  its own message loop, from the MSG, before Translate and DispatchMessage (0x31c16c0, given the MSG by
  value; its window procedure gives mouse messages to Windows). That call is taken, and a message whose place
  is on a menu drawn elsewhere is given to the game at the same place on its own, so pointing, clicking and
  hit-tests work the menu where it is drawn. Ashita, imgui and addons see the message as it was.
- Mirror ABI 5: `MouseFrame`, `MouseCount` and `Mouse[16][8]` after `Requests`, written by the addon (each
  menu's place as drawn, then the game's own, normalized); `Supported` bit 2 where the handler was found.
  84632 bytes. `/uihook mirror` says whether it was, how many menus are said now and how many messages were
  moved. Needs winxi 41.
- Links user32 (the client area's size).

## 1.1

- Mirror ABI 4: an addon may ask for 128 windows (was 64), `Hide` four words of 32 bits. menus has
  80. Needs winxi 40.

## 1.01

- `/uihook mirror labels` writes the contents' art too (item icons, and letters the game draws one quad
  each in a window's contents, as the top bar's help line), with a phase column: 1 content, 3 element.
- `/uihook mirror labels 5` writes them five seconds on (at most 60), once the chat line the command was
  typed in has closed: typing it changes what the menus show.

## 1.0

- Mirror ABI 3: an addon may ask for 64 windows (was 32), `Hide` two words of 32 bits. With every
  menu of the menus addon on (40) the requests past the 32nd were dropped, and the bit for the 32nd,
  which winxi's LuaJIT wrote as a negative number, left every window watched rather than hidden:
  nothing was replaced. Needs winxi 37.

## 0.99

- `/uihook mirror labels`: every element of the last frame mirrored is cut from its texture as the game
  drew it and written to `logs\uihook-labels\NNN.bmp`, with `labels.txt` naming each one's window, its
  texture's size and format, its place in it (uv and texels) and a hash of its pixels. It is the dump
  the table of the picture labels' words is built from. DXT1–5, A8R8G8B8, X8R8G8B8, R5G6B5, X1R5G5B5,
  A1R5G5B5, A4R4G4B4 and A8 are read; any other format, or a texture that cannot be locked, gets a line
  saying why. Each run goes in a folder of its own (`01`, `02`, …), each texture is also written whole
  once (`sheet-XXXXXXXX.bmp`), and a run with no elements writes nothing.

## 0.98

- The mirror publishes a window's own elements: Window::Render draws, before the contents, each sprite
  of the window's list of elements (a menu's labels where its words are pictures, as the main and
  command menus have them, its buttons and icons) through the one call chat calls the row-selection
  art, in 0x80808080, 0x30808080 greyed, or tinted (0x80805020, 0x40402810) where the element's index is
  the window's cursor's (+3A against +4C, focused +63). Each is now a quad (phase 3, Element, which was
  Selection) with its texture and corners, and the window's Selection is the tinted one's place, the
  element the cursor is on, rather than all of them. The kind-0 elements are the frame's nine-slice
  panels (33F4AB0), still the frame. tests/mirror.cpp: elements as quads, the tinted one the
  selection, apart from the frame. ABI unchanged.

## 0.97

- Mirror ABI 2: an addon names up to 32 windows (`Requests[32]`, a bit of Hide each), 16 are published
  a frame, with up to 512 runs, 512 quads and 32 KB of text; 82564 bytes. ABI 1 bridges are refused.

## 0.96

- The menu mirror (mirror ABI 1, `UIHOOK-MIRROR`): a window of the game's, named by an addon, keeps
  working as it is (its input, cursor and hit-tests the game's) while what it draws is measured and, if
  the addon asks, left undrawn, so the addon draws its own from what the game would have. Window::Render's
  call to a window's contents (`mov edx,[ecx]; call [edx+10]`, five bytes, `MIRROR_CONTENT_PATTERN`) is a
  call to ours making the same call, so each draw is known to be the frame's, the contents' or a
  control's (the cursor, row highlight and scrollbar, from the chat controls' call sites). In the
  contents, each text call is a run (its bytes to the line's end, colour, the place it was asked for and
  the place measured from its glyphs), and every other draw a quad of the game's art with its texture,
  held by a reference until the next frame is published, and its corners in it. Published whole as each
  frame is presented, in viewport-normalized places: up to eight windows, 256 runs, 256 quads and 16 KB
  of text, what does not fit counted as dropped. A request holds four frames, and each texture is held
  for two frames published, as an addon may draw the last frame's after the next is published. The census's three text
  routes are now taken with Window::Render as uihook loads, all four sites or none, each passing on to
  the game's own while nothing is mirrored and the census is off. `/uihook mirror` says what is asked and
  what the last frame published. tests/mirror.cpp: phases, runs (nested calls part of the outer), quads
  and their textures held once and given back, the watched and nested windows, staleness, no viewport,
  overflow, release, world-space draws; tests/nativemirror_check.lua the bridge; check_census_client.py
  the content call unique and in Window::Render.

## 0.95

- The menu census, the first step toward mirroring the game's menus: the real menu stays open and keeps
  its input, and an addon draws its own from what the real one would have drawn. `/uihook census on`
  takes over the game's three text routines, each passing straight on to the game's own (the bitmap
  font's `(x, y, text, colour, sx, sy, centred)`, its scaled sibling and the rendered font's thiscall),
  and keeps, for every window Window::Render draws, its name (+46), its content draw (vtable +10 of its
  owner at +0C), its layout target (+8C), whether it showed a cursor or focus, its text calls on each
  route, its draw calls and up to 24 distinct texts with their places and colours. `/uihook census dump`
  writes it to `logs\uihook-census.txt` with the windows grouped by the content draw they share; `off`
  gives the routines back, `clear` forgets what was seen. Nothing is written to the game. Off until
  asked, and released with the plugin. tests/check_census_client.py: the three routines unique, the
  plain text wrapper calling the bitmap route.
- The census reads each window's name from its header (+4, then +46), as the chat module does, not
  from the window itself; and the bitmap and scaled routes' x and y as the shorts they are, the upper
  halves of their stack words being whatever the caller left.

## 0.94

- Built against lens 0.6's `warp.h`, whose cylindrical mapping finds its edge once a call instead of
  in every step, so moving the target arrows under the cylindrical warp costs a few microseconds
  instead of about fifty. The arrows go where they did.

## 0.93

- The game's own target and subtarget arrows follow the lens plugin's warp. lens draws the world bent
  and the menu layer flat over it, and the game puts each arrow's tip where the flat projection puts
  the target, so near the sides of the screen it pointed beside it. The two arrow calls uihook already
  stands in (`DrawTargetArrow`) now move the tip, in pixels of the menu layer (the menu manager's
  size at `+0x80`), to where the warp shows that point (`WarpArrow`, `target.h`, through lens's own
  `ScreenOf`), before handing it to the game's sprite draw. The warp is read from the block lens.dll
  exports as `LensWarp` (`lens/src/shared.h`); without lens, with its warp off or not live, or with no
  menu size, the arrow is drawn where the game put it. tests/party.cpp: moved out toward the edge to
  ScreenOf's own point, the middle column kept, and left alone for a stale warp, no lens, strength 0
  and no menu size.

## 0.92

- A capture is no longer refused for a texture whose id is a 32-bit pointer sign-extended to 64
  (`TextureAddress`, partyhook.h): the id's low 32 bits are the address, as `Font()` has always taken
  them, where before the whole id was held to `UINT32_MAX` and any ones in its upper half refused the
  capture. A pointer above 2 GB, as imgui's font texture's can be after a while (the renderer makes the
  texture again as the atlas grows), carries them once it has been read as a signed integer. With the
  font texture refused, every window with text in it was refused: the party, alliance and target windows
  and the chat logs drawn by imgui over the game's own, chatbox's second box not drawn at all (it is
  drawn only after the first's capture), and no reload of uihook or of an addon helping, as the texture
  stays; buff's bar, which reads the texture through `Font()`, kept working. The evening of the 19th
  from about 22:50, with nothing said anywhere: the reason is inferred from what was seen and from the
  checks each capture makes, as no command reported them. Hence the next point.
- What a capture was refused for is said. Each slot keeps its last refusal (`PartyRefusal`, slots.h: no
  window or display, a draw command that cannot be replayed, too many draw commands, imgui's texture not
  ready, a texture id that is no 32-bit pointer, a clip rectangle or a vertex that is not a number, a
  vertex index past the buffer, too many vertices, the capture threw), the frame of it and how many in a
  row; `/uihook` lists the slots refused now with the reason, the run and the age, and the count of
  captures refused since loading. Ashita's log gets a warning the first time a slot is refused and when
  its reason changes (`uihook | party list: capture refused at frame N, ...`), and a line when a capture
  is taken again; a slot released on purpose reports nothing. tests/party: `TextureAddress` for a pointer
  below 2 GB, one above zero- and sign-extended, ones over a low pointer, a 33-bit value, the font mark,
  a null and a low address.
- `/uihook`'s first line no longer begins with a stray `0.8.`, left from 0.8's help text.

## 0.91

- What an addon asks for is good for eight frames, as what it hands over has been since 0.9
  (`CHAT_REQUEST_FRAMES`): the action menus' place above chatbox's panel (`MenuFresh`), the expanded log's
  place (`LogFresh`), and the replacement log's place that the clock follows (`ChatClockOffset`, and
  `winxi.nativechat`'s `ClockAnchor`). With two, a few frames the game presented before the addons ran
  again sent the menus and the clock back to the game's places for a frame, as the windows had been at
  more than 60 frames a second. What the game draws itself is still held to two.

## 0.9

- A submission is good for eight frames, not two: the party, alliance and target windows, the clock and
  compass, the chat logs and input (`PARTY_FRESH_FRAMES`) and the buff bar (`BUFF_DRAW_FRAMES`). Under
  TrueFPS the game can present a few frames before the addons are next run, and with two its own windows
  showed for a frame now and then, along with namehook's names. Stopping a replacement still gives the
  game's back at once; an addon that stops without a word gives it back within eight frames (about 90 ms
  at 90 fps).

## 0.8

- Each line given to the game's chat log, recorded for addons as it stands at uihook's turn (the
  independent text ABI 1, magic `UIHOOK-TEXT`; `winxi.nativetext`): Ashita's own incoming-text event
  (PluginFlags::UseText), the bytes the game was given and the bytes it will keep, both modes, and
  whether the line is injected, blocked, indented, changed or cut; a ring of 64, the line with serial s
  at (s - 1) % 64, written whole before its serial. Loaded after `addons`, uihook sees each line after
  every addon, so an addon reading lines here no longer depends on its place in the load order
  (chatbox before SimpleLog). Nothing is read from the game or written to it, no line changed or blocked.
  tests/texttap: untouched, changed, injected, blocked, same bytes, missing pointers, a cut line, round
  the ring.

## 0.7

- Lighter every frame: each guarded read of the client's memory (every window the game draws has its
  name read, a chat window its owner followed, and the chat's state, lines and routing are sampled each
  frame) asked Windows about that memory, a system call. The regions found readable are now kept for
  the frame, a read inside one made at once, and forgotten as the frame is presented.
- The game's chat colours, a few thousand bytes read and compared, are read every fourth frame once they
  have been read, and vouched for as current between: ColorFrame still moves each frame.

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
