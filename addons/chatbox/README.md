# Chatbox — experimental 0.10

A **WinXI-styled chat log the game still drives**. The compact log takes the native primary log's
place and **size** (it follows the game's chat size setting), in WinXI's background and border art,
with **12px text** and **3px padding** to begin with. New messages appear at the bottom; long ones
wrap and count as rows. A WinXI title on the top edge names the channel. Typing goes into a WinXI
input bar over the game's own editor, and confirming on the log opens the game's own expanded log
in a WinXI frame, its channel tabs and scrollbar drawn in WinXI's look and its text in the chat's font,
each where the game's are.

- The title follows `/cm` (`/chatmode`) at once, with a passing override for a line typed with
  `/p`, `/l`, `/t` and the like. Until a mode command is seen it is the last channel spoken in (Say
  to begin with). Linkshells show `Linkshell 1: Name` or `Linkshell 2: Name`, from the equipped
  pearl; loaded mid-session, re-equip your pearls if names are missing, as the game sends their
  slots on login and equip.
- Native and SimpleLog inline colours are always kept; uncoloured text takes its native chat-mode
  colour.
- The last 256 messages seen are kept **in memory only**. No chat is written to disk. Compact history
  begins when the addon loads; the expanded log is the game's own, from before it loaded too.
- The log lifts above the input bar while typing, and the game's clock and its icons follow the top
  of the log.
- With **Log Window 2** on in the game's settings, a second box stands where the game puts its second
  window, over the first (the same width, the game's height for it) or beside it (the game's width and
  gap, the first's bottom), titled Window 2. Each box shows the messages the
  game's Log Window settings route to its window, read from the game, and scrolls on its own; the
  focus light follows the game's focus between them.
- The mouse wheel scrolls an overflowing compact log three visual rows a notch, and a slim scrollbar
  appears on its right: drag the thumb or click the track to page.
- No dragging or mouse resizing. Combat formatting, filters and timestamps are left to the game or
  SimpleLog.

## Install

```text
addons/chatbox/          this directory
addons/libs/winxi/       WinXI 17 or newer
addons/winxisettings/    shared theme settings (optional)
plugins/uihook.dll       0.5 or newer, chat ABI 11 (native content, the tab strip, scrollbar and rows of text measured, the two log windows' routing)
```

Build uihook with `plugins/uihook/build.sh`; the output is `plugins/uihook/build/uihook.dll`. Turn
replacement off or unload the addon before replacing its files, and unload uihook before replacing
its DLL; update the DLL and `addons/libs/winxi` together with chatbox. Do not run FancyChat,
hidechatbg or other native-chat visibility writers alongside it.

```text
/load uihook
/addon load chatbox
```

Load chat formatting and filtering addons, SimpleLog among them, **before** chatbox. It reads
`text_in`'s modified text and mode and ignores blocked messages, but cannot see changes made by
handlers that run after its own. It never blocks or rewrites a message, so the game's history keeps
everything and is there if replacement stops. SimpleLog's multi-hit and critical tags, aggregation,
actor filters, timestamps and job profiles come through that way; there is no second combat
formatter or filter.

## Commands

```text
/chatbox          the settings
/chatbox on       Replace Native Chat on
/chatbox off      Replace Native Chat off: the game's logs come back at once
/chatbox clear    forget the messages this addon keeps
/chatbox status   bridge status, the last box drawn, kept-message and decode-error counts
/chatbox modes    the last ten lines kept and their chat modes (to find a channel's)
/chatbox bytes    the last incoming line: original, modified, expanded and UTF-8 bytes (hex, first 256 of each)
/uihook chat      native recognition, focus/expansion flags, cursor, page, scroll and filter
/winxi            the shared WinXI look, with winxisettings installed
```

## Settings

`/chatbox` opens the settings: six sections, each folding away, and a Winxi Theme tab. Settings
are kept for each character.

**Chatbox**

- **Replace Native Chat**: the WinXI log and input bar in place of the game's (on to begin with).
- **Chat History**: **Clear** forgets the messages kept for the compact log; the game's own history
  stays.
- Under them, how to select and expand the log, and the bridge's status.

**Size**

- **Match Game Log Size** (on to begin with): the box takes the width and height of the game's own
  log, read by uihook after the game lays it out, and fits as many whole rows as that height holds
  at Font Size, at the bottom. Resize the game's log in its settings and the box follows the next
  frame. Off, the box is **Width** wide and ten rows tall.
- **Width**: 240 to 1200 pixels (640 to begin with), with both Match options off.
- **Match Game Input Size** (off to begin with): both boxes take the native input's width and left
  edge, and the input bar its height and place, its text centred. A Font Size too large for that
  height grows the bar upward from the native bar's foot. The last native width ratio is kept while
  input is closed, following the primary log's UI scale. Off, both boxes use Width (or the game
  log's, with Match Game Log Size), and the input sits on the native chat base. When input first
  opens it can take a frame to find the bounds; missing or stale input geometry falls back to
  compact sizing, keeping the native width when known, and `/chatbox status` says so.

**Text**

- **Font**: the log's and input bar's font, the theme's (to begin with) or any `.ttf` in
  `C:\Windows\Fonts`. Japanese and other non-Latin text need a font with those glyphs.
- **Font Size**: 8 to 24 pixels (12 to begin with); both boxes grow with it. The expanded log's text
  is this size too, with Replace Text, though no taller than the game's rows.

**Padding**

- **Left Padding**, **Right Padding**, **Top Padding** and **Bottom Padding**: 0 to 40 pixels each
  (3 to begin with), for the log and the input bar. Long lines wrap between the left and right
  padding. The log fits as many whole rows as go between the top padding (below half a row kept for
  the title) and the bottom padding, two pixels apart and centred, any spare part of a row shared
  above and below. The input bar is Font Size plus both vertical paddings tall, its text and caret
  always centred in the whole bar, and has a plain `> ` prompt. Settings still at the first default
  of 4 on every side become 3 once; paddings set by hand are kept.

**Expanded**

- **Replace Tabs** (on to begin with): the expanded log's channel tabs drawn in WinXI's tab style and
  the chat's font, each where the game draws its own, so Square and the mouse still choose among
  them. Off, the game's own tabs are drawn, tinted.
- **Replace Scrollbar** (on to begin with): the expanded log's scrollbar drawn as the compact log's,
  a faint track and a thumb, where the game's is; scrolling is still the game's. Off, the game's own
  is drawn, tinted.
- **Replace Text** (experimental, on to begin with): the expanded log's rows of text drawn in the
  chat's Font, at Font Size or the game's row height if that is less, each row where the game draws
  its own and in the game's colours, so the cursor, hovering, Confirm and scrolling are still the
  game's. Off, the game's own font.

**Window Colors**

**Chat Log Window** and **Input Text Box** each have an **Own Color** box and colour picker for:

- **Background**, with its opacity, over the chosen WinXI background style.
- **Border / Art Tint**, with its opacity: a plain border's colour or the border art's tint (the
  art keeps its shading). Its alpha replaces Border Opacity for that window.
- **Default Text**: the log's base text colour (inline colours, source timestamps among them, still
  win), or the input's text, prompt and caret.
- **Title**, on the log only.

Unchecked colours follow the shared or local WinXI theme. **Follow WinXI Theme** turns a window's
boxes off and keeps the colours chosen. None of these change the theme or other addons.

## Native behaviour and limitations

**Compact log.** `winxi.nativechat` captures the complete themed window, after its border and title,
and uihook replays it at the native primary log's render boundary. The game's second log window, where
it shows one, is replaced the same way by the second box, with the messages the game routes to it
(uihook reads the game's own routing; nothing is guessed from the channels); with one window, or
without that reading, the split log is hidden while the first box shows. The game decides when the log is drawn: the replacement never forces a closed log open,
ignores UI hide, or draws over browsing and action menus. Zoning suspends it. Turning it off,
unloading, a failed capture or stale submissions bring the game's drawing back; a missing or stale
primary rectangle, or too little room above the native anchor, leaves the game's log showing rather
than floating the box elsewhere, while the input bar carries on. A character or settings swap
clears the kept messages. Windows stay click-through except for the wheel over an overflowing log
and its scrollbar, and the box is kept within the screen's width.

**Anchoring.** The log follows the native primary chat base, and sits above the input bar while
typing: the game's own upward movement is kept, with only a no-overlap clamp, never the input's
height again. Log and input bar always share width and left edge. Uihook moves the native clock
text, day icon and weather icons by the difference between the replacement's top-left and the
native log's, keeping the game's clock-to-log spacing, with the native clock and the `clock` addon
alike (its rectangles are reported where they moved to). The compass stays put. Releasing the log,
or expanding it, restores ordinary clock placement.

**Input.** Open chat as ever: Enter, `/`, Space or your shortcut. Cursor keys, Home/End, editing,
history, Enter and Escape are the **same native editor's**, as are the chat mode, commands and
sending; the bar draws its text and blinking caret and scrolls to keep the caret in view.
Auto-translate previews use the game's display buffer, otherwise the raw-byte caret. No keystrokes
are intercepted or made up, no second draft is kept, and no `+69`/`+6A` flag, chat timer or
input-buffer write is used. Uihook draws the captured bar at the `menu inline` boundary in place of
the game's background, text and caret. Input is its own slot: closing input, a decode, API or
capture failure or a missing signature releases only it, and the game's editor shows. Clicking in
the bar does not place the caret or select. Completion and IME menus stay the game's and want live
testing.

**Expanded log.** Use the game's Square/window selection on the log, then Confirm: a faint light
over the box and the game's hand cursor at its newest line show the selection. The addon binds no
button and writes no expanded flag. Expanded mode is a **WinXI frame around the game's own
browser**, at its full-log rectangle: uihook replaces the decoration and lets the game draw its
rows, selection and cursor where its mouse hit-tests are. Browsing, tabs, wheel, Confirm (with its
message-action menus) and Cancel are all native; no tell is made up, and every tab uses the game's
own filter. The **tabs, scrollbar and text** are the addon's: uihook measures the game's tab strip,
scrollbar and rows of text as the game draws them and, with Replace Tabs, Replace Scrollbar and
Replace Text on, leaves them undrawn, and the addon draws its own in exactly those places the frame
after. The game's tabs
overlap at their edges and are stacked; the addon draws them in the game's order, each over the ones
before it, and the chosen one last, on top of all. Each is a square-cornered box, as winxi's windows
are: the log's **Background** colour, then WinXI's **Highlight Color** over it, solid for the chosen
tab and faint for the rest, the theme's **Tab Style** over both, and an edge in the **Border / Art
Tint**, so the joins show where one lies over another. The tab's name, in the chat's **Font** and **Font
Size** and the log's **Title** colour with winxi's dark edge, is centred in the part of the tab left
uncovered and cut to what fits there: with the whole strip drawn the tabs are named by where they
stand, left to right, Window, Say, Tell, Party, Linkshell 1, Linkshell 2, Assist (J), Assist (E),
Unity and Shout; with fewer, by the channel each was drawn for where that is known. No line under the row, the frame's border being there. The
scrollbar is a faint track and a white thumb, as wide as the
game's bar, the thumb where the game's page is among its rows. A tab that cannot be named is named for
its place. Nothing is moved, so Square, the mouse and the wheel still work on the
game's own controls. With either off, or without a fresh place from uihook (the first frame, or a
build without the hooks), the game's own are drawn: the selected tab and row highlight in the
Highlight Color, other tabs the Title colour, the cursor and scrollbar the **Border / Art Tint**,
native fade and pulse kept. The row highlight and cursor are always the game's, tinted so.
The **text** is the addon's with Replace Text on: uihook decodes each of the game's rows as the
game draws it (its glyph words back to the bytes the game was given, colour codes and all) and
measures the row, and the addon draws the row's text where the game drew it, in the chat's **Font**
at **Font Size** or the game's row height if that is less, centred in the row, in its message's
chat-mode colour with the game's inline colours kept and auto-translate brackets as shapes, clipped
to the log's box; the game's cursor is drawn after the cursor row's text, where the game puts its
mark. The rows themselves, their wrapping and spacing, the cursor, hovering, Confirm and its menus
and the wheel are still the game's. A font wider than the game's can run past the right edge, where
it is clipped. Off, or without a fresh set of rows from uihook, the game's own bitmap font is drawn.
Padding, Width and Default Text apply to the compact log and input only, and there is no WinXI
title over the tabs. Missing control signatures leave the art untinted and the game's tabs,
scrollbar and text drawn; missing content signatures, geometry or a failed capture leave the
game's whole view showing.
Compact and expanded captures are never replayed at each other's boundary. A row's action menu
(Confirm on a player's line) and the input line open over the log, which keeps its WinXI look under
them; the menu itself is the game's. Expanding releases compact scrollbar drags and resets the
wheel. Other addons' Under Expanded Chat hiding works as before.

**Colours.** The palettes are **standard-palette approximations**, not live reads: custom DAT
colours and your own channel colours are not imported. Text without inline codes takes its mode's
second-palette colour (white for unlisted slots); unknown modes take the WinXI theme's. Both
palette banks survive wrapping and paragraph breaks, and a reset returns to the mode's colour.
Named NPC dialogue gets `[NPC]` after the speaker, only `NPC` in yellow, never doubled. Combat lines
are not compacted, grouped, filtered or timestamped; settings left from those removed options are
dropped on load.

**Text.** Auto-translate is expanded and CP932 converted to UTF-8. FFXI `1E`/`1F` colour escapes
are parsed first, kept as byte ranges and never drawn; slot 1 resets to the line's colour. NPC bell
separators and CRLF become paragraph breaks; `7F` prompt, end and timing controls are consumed;
truncated escapes are dropped. Auto-translate brackets are drawn as shapes, and elemental
`EF 1F`–`EF 26` symbols as `[fire]`, `[ice]` and so on. The game's other pictographs (`EF 29`–`EF 4D`),
blinking and timed reveal are not reproduced. No FancyChat code is used; palette observations are credited in `palette.lua`.
Native chat recognition lives in uihook, not in this addon.

## Checks

```sh
luajit tests/chatbox_log_check.lua
luajit tests/chatbox_encoding_check.lua
luajit tests/chatbox_inline_check.lua
luajit tests/chatbox_appearance_check.lua
luajit tests/chatbox_scrollbar_check.lua
luajit tests/chatbox_ui_check.lua
luajit tests/chatbox_input_check.lua
luajit tests/chatbox_layout_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/winxi_capture_check.lua
luajit tests/winxi_version_check.lua
plugins/uihook/tests/run.sh
```

These are offline checks, not proof of live rendering. Still to check in game: primary and split
logs, wrapping, Enter, slash and mode shortcuts, history, editing and caret scrolling,
auto-translate and IME, non-Latin glyphs, input fallback, expanded history, selection and focus
changes, confirm and cancel, menu hiding, shared widths, input lift and close, clock anchoring,
zoning, UI hide, theme and font changes, device recovery and unloading and reloading the addon and
plugin. `/chatbox off` returns to the game's chat at once.
