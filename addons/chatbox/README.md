# Chatbox — experimental 0.11

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
  colour. The colours are the game's own, as configured, read through uihook; without that, close
  approximations.
- The last 256 messages seen are kept **in memory only**. No chat is written to disk. As it starts
  (and after a reset or a new character), chatbox reads the game's own history once through uihook,
  the first log window's last 100 lines, and puts them before its own, so a reload or a late load
  does not begin empty; lines it already has are left out. The game keeps a message as the lines it
  wrapped it into; with timestamps on, a line without one is joined back to the message before it, so
  each message is whole again (with timestamps off, each of the game's lines stays a message).
  `/chatbox status` says how many were read. The expanded log is the game's own.
- The log lifts above the input bar while typing, and the game's clock and its icons follow the top
  of the log.
- With **Log Window 2** on in the game's settings, a second box stands where the game puts its second
  window, over the first (the same width, the game's height for it) or beside it (the game's width and
  gap, the first's bottom), titled Window 2. Each box shows the messages the
  game's Log Window settings route to its window, read from the game, and scrolls on its own; the
  focus light follows the game's focus between them.
- Each box has as many rows as the game's window shows at the moment: the game grows its window a
  row for each message and shrinks it to its fewest lines while none come, and the box follows,
  tall enough for those rows at Font Size. A window at 0 lines shows nothing, the other still drawn.
- The mouse wheel scrolls an overflowing compact log three visual rows a notch, and a slim scrollbar
  appears on its right: drag the thumb or click the track to page.
- No dragging or mouse resizing. Combat formatting, filters and timestamps are left to the game or
  SimpleLog; **Timestamps** hides the stamps they write, in every log, and shows them again at once.

## Install

```text
addons/chatbox/          this directory
addons/libs/winxi/       WinXI 24 or newer (including infopanel code and bundled icons)
addons/winxisettings/    shared theme settings (optional)
plugins/uihook.dll       0.5 or newer, chat ABI 13 (native content, the tab strip, scrollbar and rows of text measured, the two log windows' routing and lines, the game's colours); 0.8 or newer reads each chat line after every addon, so the addon load order does not matter
```

Build uihook with `plugins/uihook/build.sh`; the output is `plugins/uihook/build/uihook.dll`. Turn
replacement off or unload the addon before replacing its files, and unload uihook before replacing
its DLL; update the DLL and `addons/libs/winxi` together with chatbox. Do not run FancyChat,
hidechatbg or other native-chat visibility writers alongside it.

```text
/load uihook
/addon load chatbox
```

With uihook 0.8 or newer loaded after `addons` (as `/load addons` then `/load uihook`), the addon
load order does not matter: chatbox reads each chat line through uihook as it stands after every
addon, so SimpleLog's timestamps and a filter's blocks reach it whether SimpleLog is loaded before or
after it (`/chatbox status` says "Lines: read through uihook after every addon"). Where uihook is
loaded before `addons`, its copy is the game's original, and chatbox keeps its own copy of a line an
earlier addon changed instead. Without that uihook, load chat formatting and filtering addons,
SimpleLog among them, **before** chatbox: it then reads `text_in`'s modified text and mode and ignores
blocked messages, but cannot see changes made by handlers that run after its own; an alphabetical
`scripts/default.txt` loads chatbox before simplelog, so move simplelog's line above chatbox's, or
every game start puts them back (SimpleLog's timestamps then reach the game's log but not chatbox's;
`/chatbox bytes` says so). It never blocks or rewrites a message, so the game's history keeps
everything and is there if replacement stops. SimpleLog's multi-hit and critical tags, aggregation,
actor filters, timestamps and job profiles come through that way; there is no second combat
formatter or filter.

## Optional Info Panel

The **Info Panel** tab in `/chatbox` has General, Layout, Data, Window 2, Text and Icons subtabs. Enable it
there or with `/chatbox panel on`. It is **off by default**, so updating does not add a duplicate
of an existing clock panel.

- Three independent **Left/Middle/Right** slots, each with a format, field picker, Left/Center/Right
  alignment, and relative-width weight. Literal `|` characters become Winxi Fine/Beveled/Ornament
  dividers; the two slot boundaries can be styled or hidden too.
- Fields: `{time}`, `{zone}`, `{grid}`, `{day}`, `{date}`, `{moon}`, `{weather}`, `{dayicon}`,
  `{weathericon}`, `{level}`, `{exp}`, `{tnl}`, `{rate}`. For example, Left: `{time} | {zone}`,
  Middle: `{day} | {date}`, Right: `{tnl} | {rate}`. Empty fields take their preceding divider away.
- Width 0 follows the owning chatbox; Height 0 matches the prepared input-bar height or grows to fit
  the panel font/icons and padding. Font/size can follow chat or be overridden. Text/icons are
  vertically centred; fixed-size overflow is clipped inside its own slot.
- Attach To Chat (with offsets), or use a custom position and size, which leaves chat where the game
  puts it. Attached, **Anchor** (Layout tab) chooses where:
  - **Bottom** (default): the panel takes the bottom of the logs' place and every drawn log is lifted
    by its height, so chat sits wholly above it. While typing the panel stays at the bottom (the
    input's own bottom): the input is lifted to sit on it, and the logs above the input as ever. The
    lowest visible log owns it: the primary, under a stacked or beside a side-by-side Window 2.
  - **Top**: flush over the upper log, its channel title drawn last at their shared seam; chat and
    the input stay where the game puts them. The upper visible log owns it: a stacked Window 2, or
    the primary beside a side-by-side one.
  If only Window 2 is visible, it owns the panel either way.
- **Window 2 Panel** (General, off by default) adds a second panel on Window 2 (by Anchor, over or under it) while the game
  shows the two log windows side by side. Its slots, layout and icon placement are set in the
  **Window 2** subtab; font, text colour and icon set follow the first panel. Attached panels
  share the taller one's height so both logs keep one bottom. Stacked logs keep one panel.
- Day/weather icons can be placed before/after any slot, offset independently, or inserted as data
  tokens for exact order. Icon sets are under `addons/libs/winxi/infopanel/icons`: `gems` (the days cut
  as gemstones) and `classic` (drawn after the game's own: its mottled day balls and soft weather sprites,
  made by `tools/generate_classic_icons.py`) are bundled, and `gems` supplies missing custom pictures. Hidden/Native placement does not auto-insert an icon;
  native HUD visibility is never changed by chatbox.
- Background, border art and shadow follow the shared/local Winxi theme, captured together with
  the owning log. The panel is an attachment on that log's draw list, **not a separate floating
  ImGui window**. Attached, it lifts the drawn logs (and their scroll regions) by its height; it
  never changes their size or the game's own log rectangles.
- Visibility follows **compact chat**, not the native clock: action/combat menus hiding the game's
  clock no longer stop the panel. It hides during expanded history, zoning, chatbox off, or when
  neither compact log is visible. Custom positioning does not override these rules.
- Time, zone and EXP data do not require native clock rendering. Weather uses login/weather packets,
  with a fresh native read as fallback. `{grid}` is optional native-clock data: omitted when that
  source is stale/hidden rather than freezing an old position. Weather may be unknown after loading
  mid-session until a native sample or weather/login packet arrives; it is never guessed as clear.

**Switching from clock:** install this chatbox and the full updated Winxi library, including the
shared panel icons. `/addon unload clock`, `/addon reload chatbox`, then `/chatbox panel on`.
The clock addon/folder is not required by chatbox; existing clock settings remain untouched and
are not automatically imported. Use `/chatbox panel off` before returning to clock.

**Hide Game Clock** (Info Panel → General, off by default; `/chatbox clock [hide|show]`) hides the
game's clock, its time and its day and weather icons, while chatbox runs, with the panel on or off.
Each frame chatbox renews an empty replacement in uihook's clock slot and names both icons hidden,
so the game still runs its clock: `{grid}` and the weather stay readable for the panel. Turning it
off, chatbox off, zoning or unloading gives the game's clock back at once. Needs uihook with clock
support; unload the clock addon and hidecompass, which use the same object. `/chatbox status`
reports it as Game Clock.

**Hide Compass** (Info Panel → General, off by default; `/chatbox compass [hide|show]`) does the same
for the game's compass and its radar, through uihook's compass slot; the clock is not affected
either way, and each can be hidden alone. It is given back on the same terms as the clock.

**Native Menus → Anchor Above Chat** (General, on by default) moves the registered command,
magic, ability, inventory/item-use and related control menus, and an event's choices (an NPC's Yes/No),
above the top of the lifted chat when anchored to the bottom, and above the panel itself when anchored
to the top or given a custom position, with a 2px clearance.
Requires **uihook 0.6** (independent menu ABI 1); `/uihook menus` reports recognition and relocation
counts. Older/unrecognised DLLs leave menus untouched and the panel still works. The plugin sets
native layout targets before the game's own Window update, so its frame/rows/cursor/hit geometry
share coordinates—no render-only offset or mouse remapping. Positional opening animations may
snap to the new anchor. Unrelated menus remain native; a list too tall to fit above that anchor is
left in its original position. This is experimental and needs live mouse/controller validation.

Disabling menu anchoring, the panel or chatbox, expanding history, losing fresh host captures,
zoning or unloading restores owned native positions. A newer game-written target is never
blindly overwritten. **Unload uihook before replacing its DLL**, or close the game; do not overwrite
a loaded plugin. Deploy `plugins/uihook/build/uihook.dll` to Ashita's `plugins/uihook.dll`, plus
the updated chatbox and Winxi 22 directories. The existing chat ABI remains 13.

## Commands

```text
/chatbox          the settings
/chatbox on       Replace Native Chat on
/chatbox off      Replace Native Chat off: the game's logs come back at once
/chatbox clear    forget the messages this addon keeps
/chatbox timestamps   toggle the Timestamps option (on or off to set it)
/chatbox status   bridge status, the last box drawn, kept-message and decode-error counts
/chatbox modes    the last ten lines kept and their chat modes (to find a channel's)
/chatbox bytes    the last incoming line: original, modified, expanded and UTF-8 bytes (hex, first 256 of each)
/chatbox panel on     enable the optional info panel (off by default)
/chatbox panel off    hide the info panel without affecting chat
/chatbox panel reset  reset the panel's EXP-per-hour tracker
/chatbox clock        toggle hiding the game's clock (hide or show to set it)
/chatbox compass      toggle hiding the game's compass (hide or show to set it)
/uihook chat      native recognition, focus/expansion flags, cursor, page, scroll and filter
/winxi            the shared WinXI look, with winxisettings installed
```

## Settings

`/chatbox` opens Settings (six collapsible sections), Info Panel, and Winxi Theme tabs.
Settings are kept for each character.

**Chatbox**

- **Replace Native Chat**: the WinXI log and input bar in place of the game's (on to begin with).
- **Timestamps** (on to begin with): the time in front of each line as SimpleLog's Timestamps or
  Ashita's timestamp addon writes it; chatbox adds none of its own. Off, those are hidden in the
  compact log, Window 2 and the expanded log; the messages keep them, so turning it on shows them
  again at once. `/chatbox timestamps on` and `off` do the same.
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
  is this size too, with Replace Text, laid out as the compact log's.

**Padding**

- **Left Padding**, **Right Padding**, **Top Padding** and **Bottom Padding**: 0 to 40 pixels each
  (3 to begin with), for the log and the input bar. Long lines wrap between the left and right
  padding. The log fits as many whole rows as go between the top padding (below half a row kept for
  the title) and the bottom padding, two pixels apart and centred, any spare part of a row shared
  above and below. The input bar is Font Size plus both vertical paddings tall, its text and caret
  always centred in the whole bar, and has a plain `> ` prompt. Settings still at the first default
  of 4 on every side become 3 once; paddings set by hand are kept.

**Expanded**

- **Replace Tabs** (on to begin with): the expanded log's channel tabs drawn as WinXI buttons, each
  whole and in the game's order, the chosen one lit as the game chooses it (Square, the arrows). The
  game's mouse clicks on its tabs stay at its own places. Off, the game's own tabs are drawn, tinted.
- **Replace Scrollbar** (on to begin with): the expanded log's scrollbar drawn as the compact log's,
  a thin thumb and no track inside the log's right edge, over the game's bar's height and where its
  page is; scrolling, and dragging the game's bar, are still the game's. Off, the game's own
  is drawn, tinted.
- **Replace Text** (experimental, on to begin with): the expanded log's rows of text drawn in the
  chat's Font at Font Size, each row centred where the game draws
  its own and in the game's colours, so the cursor, hovering, Confirm and scrolling are still the
  game's. Off, the game's own font.
- The expanded log's window is the compact log's: the same padding, Font Size, shadow and **Window
  Colors**, its foot where the newest row's text and Bottom Padding end, and its rows from Left
  Padding in the chat's Font at Font Size.
- **Expanded Height** (75% to begin with, 25 to 100): how far up the screen the expanded log reaches,
  its top that share of the screen's height up from the bottom and never above the game's own window;
  the tabs stand on its top and the scrollbar keeps within it. The game's rows above it are cut off.
  100% is the game's own.
- **Expand In Place** (on to begin with): the expanded log opens where the chat log stands, its
  bottom-left on the first log's; the info panel is hidden while the log is expanded, so with Anchor
  Bottom the log takes the panel's place as well. Its rows, hovering, Confirm and scrolling move with it, as the game lays them
  out there. Off, where the game puts it.
- **Replace Cursor** (on to begin with): with the three above on, the expanded log mirrored whole:
  the game draws nothing of it, and chatbox draws its cursor, the light on the cursor's row and the
  game's marked rows as well. The game still moves the cursor, follows the mouse and takes Confirm.
  Off, the game's own, tinted.

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
after. The game draws each tab not chosen only its first 30 units wide, the next over the rest; the
addon draws every tab whole, as **WinXI buttons** side by side from where the game's strip starts, all
as wide as the longest name needs (narrowed only to fit the log): rounded, over the log's
**Background** colour, in a game window's button colour (the **Border / Art Tint**, faint), the
**Highlight Color** for the tab the game has chosen, its short name (Win 1, Win 2, Say, Tell, Party,
LS 1, LS 2, A (J), A (E), Unity, Shout) in the chat's **Font** at 85% of **Font Size** and the log's
**Title** colour with winxi's dark edge, centred and cut only where the log is too
narrow. Which tabs there are and their order are the game's, as its strip is drawn: Window, Window 2
(only with the game's second log window setting on), Say, Tell, Party, Linkshell 1, Linkshell 2,
Assist (E), Assist (J), Unity and Shout, each named by the art the game draws it with, through the
client's own pairing of art and filter. The game's mouse clicks on its tabs stay at its own places,
so the buttons have no mouse light. The
scrollbar is the compact log's: a thin white thumb, no track, inside the log's right edge, as tall as the
game's bar and where the game's page is among its rows, brighter while the mouse is on it or on the
game's bar, which the game still drags. A tab that cannot be named is named for
its place. Nothing is moved, so Square, the mouse and the wheel still work on the
game's own controls. With either off, or without a fresh place from uihook (the first frame, or a
build without the hooks), the game's own are drawn: the selected tab and row highlight in the
Highlight Color, other tabs the Title colour, the cursor and scrollbar the **Border / Art Tint**,
native fade and pulse kept. The row highlight and cursor are the game's, tinted so, unless Replace
Cursor mirrors the whole log: then uihook leaves the full log wholly undrawn (with uihook 0.6) and the
addon lights the row the game highlights (uihook measures the game's highlight as it is drawn and
flags the rows under it; the cursor's row with an older uihook) from the left of its text to the scrollbar, a row's pitch tall, in the
Highlight Color (brighter while held down), lights a row the game marks faintly, and draws the cursor
after the cursor row's text; which row that is, is the game's, read as it draws.
The **text** is the addon's with Replace Text on: uihook decodes each of the game's rows as the
game draws it (its glyph words back to the bytes the game was given, colour codes and all) and
measures the row, and the addon lays the rows out as the compact log does: the chat's **Font** at
**Font Size**, Font Size + 2 apart, the newest ending at the **Bottom Padding** and older ones up from
it, from the log's left edge in by **Left Padding**, in the log's Default Text colour when it
has its own, otherwise its message's chat-mode colour with the game's inline colours kept and auto-translate brackets as shapes, clipped
to the log's box; the game's cursor is drawn after the cursor row's text, where the game puts its
mark. Which rows there are and their wrapping, the cursor, Confirm and its menus and the wheel are
still the game's, followed by the rows' order (when the row the game has chosen is past what fits,
the view moves up to keep it in sight); the game's mouse hover and clicks stay at its own rows'
places, 16 of its units apart, which no longer line up with these. A font wider than the game's can run past the right edge, where
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
luajit tests/infopanel_source_check.lua
luajit tests/winxi_frame_check.lua
luajit tests/nativemenus_check.lua
luajit tests/nativehistory_check.lua
luajit tests/clock_panel_check.lua
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
