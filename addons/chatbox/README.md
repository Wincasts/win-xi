# Chatbox — experimental 0.12

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
  **Window Title** in the Chatbox section puts your own words there instead; left empty, the channel.
- Native and SimpleLog inline colours are always kept; uncoloured text takes its native chat-mode
  colour. The colours are the game's own, as configured, read through uihook; without that, close
  approximations.
- The last 256 messages seen are kept **in memory only**. With two log windows, each also retains
  its own last 256 routed messages, so busy traffic in one cannot erase the other's older messages.
  These share one chronological store (at most 768 messages, with overlapping messages stored once).
  Routing changes apply to the retained messages; already evicted messages cannot be recovered.
  No chat is written to disk. As it starts
  (and after a reset or a new character), chatbox reads the game's own history once through uihook,
  the first log window's last 100 lines, and puts them before its own, so a reload or a late load
  does not begin empty; lines it already has are left out. The game keeps a message as the lines it
  wrapped it into; with timestamps on, a line without one is joined back to the message before it, so
  each message is whole again (with timestamps off, each of the game's lines stays a message).
  `/chatbox status` says how many were read. The expanded log is the game's own.
- While typing, the input bar takes the compact log's bottom rows without moving or enlarging its total footprint. The game's clock and its icons follow the top
  of the log.
- With **Log Window 2** on in the game's settings, a second box stands where the game puts its second
  window, over the first (its own game width and height in Follow Game) or beside it (the game's width and
  gap, the first's bottom), titled Window 2 (or **Window 2 Title**). Each box shows the messages the
  game's Log Window settings route to its window, read from the game, and scrolls on its own; the
  focus light follows the game's focus between them.
- Each box has as many rows as the game's window shows at the moment: the game grows its window a
  row for each message and shrinks it to its fewest lines while none come, and the box follows,
  tall enough for those rows at Font Size. A window at 0 lines shows nothing, the other still drawn.
- The mouse wheel scrolls an overflowing compact log three visual rows a notch, and a slim scrollbar
  appears on its right: drag the thumb or click the track to page.
- In WinXI Skin, with **Lock Window** off, the log can be dragged wherever you want (Position Custom); the
  input bar and the second window go with it. No mouse resizing. Combat formatting, filters and timestamps are left to the game or
  SimpleLog; **Timestamps** hides the stamps they write, in every log, and shows them again at once.
- Resting the mouse on something named in the compact log or Window 2 shows what it is in a Winxi tooltip
  (**Chat Tooltips**). Items, key items and auto-translate phrases are known by the codes the game sends with
  the line, so they are found exactly; spells, abilities, weapon skills, quests and places written as plain
  text are found by their names. Names are matched by text, so an ordinary word that is also the name of an
  item or a place may show one. In the expanded log they work on the rows the addon draws (Replace Expanded
  Log), by name, as the game keeps no tokens in its history.

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
    by its height, so chat sits wholly above it. While typing the panel stays put: input occupies
    the bottom of the first log's footprint, with fewer chat rows above it. The
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
  made by `tools/generate_classic_icons.py`) are bundled, each with a picture for every weather, the skies the
  game draws no icon for among them (a sun for a clear sky, a pair of clouds, a bank of fog), and `gems`
  supplies missing custom pictures. Hidden/Native placement does not auto-insert an icon;
  native HUD visibility is never changed by chatbox.
- Hover a **day icon** to see the Vana'diel weekday and its element, or a **weather icon** or the
  `{weather}` words to see the weather name, element and single/double strength (or no elemental
  weather for clear skies, clouds and fog) and then the **zone's forecast**: today and the four days
  after it, each with what the zone may roll and the odds, as the Phoenix server rolls it. The server
  keeps a table of 2160 Vana'diel days for each zone, three weathers a day; every 3 to 30 Earth minutes
  it rolls again, the rare weather 15% of the time, the common 35%, the normal the rest (from 2:00 to
  7:00, outside cities, a roll that gives a clear sky is fog instead, which the tooltip leaves unsaid);
  a zone with one entry or none never changes. The tables are `winxi/infopanel/zone_weather.lua`, built from the server's
  `sql/zone_weather.sql` and zone types by `tools/build_zone_weather.py`.
- Hover the `{time}`, `{day}`, `{date}` or `{moon}` words for the **Vana'diel calendar**: the month,
  its thirty days in weeks of eight under the Icon Set's day pictures (or the days' names), today
  marked, the days gone dimmed and the neighbouring months' days that fill out the first and last
  weeks fainter still, the moon's phase and fullness, and when the next day begins in Earth minutes.
- Hover the `{zone}` words for the **ships' and airships' timetable**, as the Phoenix server runs them:
  the next four to leave, soonest first, of the lines ticked in the **Timetable** tab (the airships
  between Jeuno and San d'Oria, Bastok, Windurst and Kazham, the ferry between Selbina and Mhaura,
  the Aht Urhgan ferries, the Manaclipper and the Carpenters' Landing barge, each place one leaves
  from and goes to a line of its own, all on to begin with, with All and None buttons). Each row has
  how long until its door opens (**Boarding**, or `now` while it is open) and shuts (**Leaves**), the
  Vana'diel time it leaves (**At**) and how long the crossing takes (**Trip Time**), in Earth
  minutes:seconds. The rows that board in the zone you are in are marked in the theme's tooltip border
  colour; aboard a ship or airship, a line on top says where you are bound and how long until you are
  put ashore. The server runs every ship on a cycle from its zone's
  `data/zones/<name>/zone.yaml` (`src/map/transports/ship_handler.cpp`): the seconds into the cycle
  are the raw game time less the run's offset, modulo its length, the door open through the docked
  phase and the riders put ashore at the run's disembark second. The runs are
  `winxi/infopanel/transports.lua`, built by `tools/build_transports.py`; the Aht Urhgan ferries run
  only where the server has `ENABLE_TOAU` on, as the live branch does. Both automatically placed icons and `{dayicon}` / `{weathericon}` tokens support
  this, including panel-only mode when the logs are empty. Tooltips use the shared Winxi tooltip
  enable switch, delay and styling, but not its width: each is as wide as its longest line, so the
  forecast's days and the timetable's rows never wrap. Icons and words remain click-through; hovering
  does not consume game input.
- Background, border art and shadow follow the shared/local Winxi theme, captured together with
  the owning log. The panel normally shares that log's draw list. When both logs collapse, a
  panel-sized capture keeps it visible without an empty chat frame or full-size invisible hit area.
  Attached, it lifts the drawn logs (and their scroll regions) by its height; it never changes
  the game's own log rectangles.
- Visibility follows **compact chat**, not the native clock: action/combat menus hiding the game's
  clock no longer stop the panel. When both compact logs are empty, at zero native lines, or
  hidden by Smart Visibility, the enabled panel stays visible. Menu anchors use its actual bounds,
  with no space reserved for the collapsed logs. It still hides during expanded history, zoning,
  chatbox off, or when valid native layout/capture is unavailable. Custom positioning does not override these rules.
- Time, zone and EXP data do not require native clock rendering. Weather uses login/weather packets,
  then fresh native data or a direct read of the game's weather state. Its icon stays available while
  fishing, in events, or when the native clock is hidden—even when Chatbox loads mid-session.
  Temporary read failures retain the last known weather; zone departure and character resets clear it.
  Clear skies are a valid value, never a guessed fallback. `{grid}` likewise falls back to the game's
  own grid function while the clock is hidden; zones without a grid still omit it.

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

The game's own menus are left where the game puts them: chatbox no longer moves the action menus above
the info panel (Anchor Above Info Panel, removed in 0.15.0).

## Commands

```text
/chatbox          the settings
/chatbox on       Enable chatbox
/chatbox off      Disable chatbox: the game's logs come back at once
/chatbox clear    forget the messages this addon keeps
/chatbox timestamps   toggle the Timestamps option (on or off to set it)
/chatbox translate    toggle Auto-Translate, chatbox's own phrase list on Tab (on or off to set it)
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

`/chatbox` opens Settings, Info Panel and Tooltips tabs. There is no Winxi Theme tab; Settings are kept for each character. The
Chatbox and Look sections apply in both modes; the Layout and Activity sections are the WinXI Skin's and
are shown only in it (their settings are kept, and ignored, in Follow Game). The look is WinXI's in both:
the mode is how the boxes behave and where they stand.

**Chatbox**

- **Enable** (on to begin with): enables chatbox's log and input bar. Off, the native log and input
  return and all other controls in Settings, Info Panel and Tooltips are greyed out. Saved settings
  are kept. `/chatbox on` and `/chatbox off` control this switch.
- **Replace Native Chat** (on to begin with): on selects **Follow Game**; off selects **WinXI Skin**.
  This changes layout behavior, not whether chatbox is enabled. Existing mode settings are preserved.
- **Auto-Translate** (on to begin with): Tab while typing opens chatbox's own list of auto-translate
  phrases, from the installed client's dictionary, for the word at the caret (with no word, the 42
  categories), drawn above the input bar. Tab, Shift+Tab, Up and Down move, Page Up and Page Down move a
  page, Enter puts the phrase in (on a category, opens it), Escape closes (in a category, back to the
  categories). Typing goes on narrowing the list. The phrase goes into your line as its real token, so
  others see it in their own language when you send. Off, Tab is the game's, whose own menu takes the
  input bar back for as long as it is open. `/chatbox translate on` and `off` do the same.
  Native window size does not necessarily mean the same number of lines.
  - *On — Follow Game*: the log, the input bar and the expanded log where the game puts its own, at its sizes.
    Each log follows its game window's size and its lines, as the game grows its window a row for each
    message and shrinks it to its fewest while none come (at 0 lines nothing is drawn); the second window
    stands where the game shows it, with the game's width and gap. The input bar uses the game's
    height (or enough for the chosen font), centred text, and the log's width, but occupies the bottom
    of the compact footprint rather than moving it when typing;
    the expanded log opens where the game puts it, at its full height.
  - *Off — WinXI Skin*: Width and rows of the addon's own, the activity controls, and the expanded log's place
    and height, from the Layout and Activity sections.
- **Timestamps** (on to begin with): the time in front of each line as SimpleLog's Timestamps or
  Ashita's timestamp addon writes it; chatbox adds none of its own. Off, those are hidden in the
  compact log, Window 2 and the expanded log; the messages keep them, so turning it on shows them
  again at once. Enable timestamps in either SimpleLog or the timestamp addon to supply them;
  avoid enabling both providers at once to prevent duplicate stamps. `/chatbox timestamps on`
  and `off` do the same. There is no history-clear button; `/chatbox clear` remains available.
- **Tooltips tab — Chat Tooltips** (on to begin with): resting the mouse on an item, key item, auto-translate phrase,
  spell, ability, weapon skill, quest or place in the compact log, Window 2 or (with Replace Expanded Log)
  the expanded log's rows shows a tooltip of it, the gap between two rows counted as the row above. While
  it is on, one switch for each kind, all on to begin with: **Items**, **Spells And Abilities**, **Weapon
  Skills**, **Quests**, **Places** and **Auto-Translate**; and **Tooltip Notes** (on to begin with), the
  dimmed lines: what the catalogs cannot vouch for (presence is not availability, modifiers in server
  units) and a phrase's category and kind; off, only the name and the facts. The shared Winxi tooltip settings (whether
  tooltips show, their delay and their look) apply. Nothing shows while the mouse is over the settings or
  another imgui window, while the log or its scrollbar is dragged, or in the expanded log while the game
  draws its own rows.
- **Font**: the log's and input bar's font, the theme's (to begin with) or any `.ttf` in
  `C:\Windows\Fonts`. Japanese and other non-Latin text need a font with those glyphs.
- **Font Size**: 8 to 24 pixels (12 to begin with); the boxes grow with it, and the expanded log's text
  is this size too (with Replace Expanded Log). In Follow Game, **Automatic** (0) takes the size the
  game's rows give: the first window's row pitch (its height less the top and bottom padding, over the
  lines it shows) less the row gap, read where the reading is sound and kept until another is, 12 until
  the first; so the rows stand where the game's do.
- Under them, how to select and expand the log, and the bridge's status.

**Layout** (WinXI Skin)

- **Lock Window** (on to begin with): off, the log can be taken hold of with the left button anywhere on
  it but its scrollbar and dragged wherever you want; let go, the place is kept for the character and
  Position becomes Custom. The wheel and the scrollbar still work. On, it stays where it is, the mouse
  going through it to the game.
- **Position**: **At the Game's Chat** (to begin with), where the game puts its own log, or **Custom**,
  wherever it was dragged to or the **Place** typed under it (the log's bottom-left in pixels from the
  screen's top-left, kept on the screen). Choosing Custom takes the place the log stands at. The input
  bar uses the bottom of that footprint while typing, a stacked or side-by-side
  second window keeps its place beside the first, the info panel attaches as before, and Expand In
  Place opens the expanded log there. The game's clock, which uihook keeps at its distance from the
  log, goes with it; Hide Game Clock in the Info Panel tab takes it away. The game's own log must still
  be drawn (its place known) for the box to be drawn at all, wherever the box stands.
- **Width**: 240 to 1200 pixels (640 to begin with). Also the expanded view's width, capped at its native
  bounds; its tabs, scrollbar and text clipping follow that width. The game still controls history row
  wrapping, selection and hit-tests: narrowing the view clips long native rows rather than rewrapping them.
- **Window 1 Rows / Window 2 Rows**: independently choose 1–50 rows for either compact log.
  **0 (Automatic)**, the default, uses ten rows. A custom count sets only that window's height,
  preserving its width. With Auto Resize enabled, this is its maximum row count. Expanded history is
  unaffected.
- **Expand In Place** (on to begin with): the expanded log opens where the chat log stands, its
  bottom-left on the first log's; the info panel is hidden while the log is expanded, so with Anchor
  Bottom the log takes the panel's place as well. Its rows, hovering, Confirm and scrolling move with it, as
  the game lays them out there. Off, where the game puts it.
- **Expanded Height** (75% to begin with, 25 to 100): how far up the screen the expanded log reaches,
  its top that share of the screen's height up from the bottom and never above the game's own window;
  the tabs stand on its top and the scrollbar keeps within it. The game's rows above it are cut off.
  100% is the game's own.

**Activity** (WinXI Skin)

Window 1 and Window 2 have independent settings, all **off by default**. Each switch shows its own
controls only while it is on.

- **Auto Resize**: grows the compact log to fit recent wrapped messages routed to that window,
  up to its rows, then shrinks as messages age out. With it on:
  - **Animate Resize**: smooth growth and shrinkage, anchored at the bottom edge. Stacked windows
    follow the animated edge; rows are revealed/clipped at the top. Once settled, the box fits its exact
    row count and padding. With it on, **Resize Duration**: 0.05–2 seconds, **0.2** by default, for each
    size transition; new content arriving during a transition retargets it from its current height.
  - **Minimum Rows**: 0–50, **0** by default, capped at the log's rows. Rows left while idle; zero
    hides the log entirely.
- **Fade When Idle**: fades the log away after no messages reach it for Idle Time. A new routed
  message fades it back in over 0.2 seconds. Alone, for a fixed-size log, or with Auto Resize. With it
  on, **Fade Duration**: 0.1–10 seconds, **1** by default, for fading out.
- **Idle Time**, with either on: 1–300 seconds, **15** by default. How long a message counts as recent:
  Auto Resize keeps rows for it, and Fade When Idle starts fading after it. Activity in the other
  window does not reset this timer.

Typing restores both available compact logs to full size and opacity immediately, bypassing resize
animation. Selecting a log, scrolling back in it, or dragging its scrollbar keeps that log visible. The
fade idle delay restarts after interaction. Expanded history is unaffected. Messages stay in history
when hidden; opening or scrolling the log still lets you read them. Imported history does not count as
new activity. Native log capture remains active while hidden, so the game's original log does not show
through. When both logs disappear, the info panel stays visible on its own. Collapsed logs reserve zero
layout height; the panel-only capture uses the visible panel's actual bounds.
One-row logs and small panels also bypass ImGui's normal minimum window height, so their actual
window geometry matches the requested size.

**Look** (both modes)

- **Window Title** and **Window 2 Title**: your own words on each box's top edge; left empty, the
  channel and Window 2.
- **Left Padding**, **Right Padding**, **Top Padding** and **Bottom Padding**: 0 to 40 pixels each
  (3 to begin with), for the log and the input bar. Long lines wrap between the left and right
  padding. Independently sized logs fit exactly their row count plus top and bottom padding, with
  two pixels between rows and no extra title headroom. The input bar is Font Size plus both vertical
  paddings tall, its text and caret always centred in the whole bar, and has a plain `> ` prompt.
  Settings still at the first default of 4 on every side become 3 once; paddings set by hand are kept.
- **Replace Expanded Log** (on to begin with): the expanded log's channel tabs drawn as WinXI buttons,
  each whole and in the game's order, the chosen one lit as the game chooses it; its scrollbar drawn
  as the compact log's, where the game's is; its rows of text in the chat's Font at Font Size, each
  row centred where the game draws its own and in the game's colours; and, with uihook 0.6, its
  cursor, the light on the cursor's row and the game's marked rows, so that nothing of the game's is
  drawn in it. The rows stand at the chat's own pitch, not the game's, so the mouse over the rows is kept
  from the game, whose hover and clicks would land on other rows; the game's tabs and scrollbar are still
  its own to click and drag, a menu of the game's open over the log keeps its mouse, the wheel goes
  through and scrolls, and Square, the arrows and Confirm choose rows. Off, the game's own are drawn in
  the WinXI frame, tinted to the theme, and the mouse is the game's.
The chat log and input text box inherit WinXI theme colours. Per-window colour overrides and their
settings sections have been removed; saved overrides are discarded. Source inline colours are preserved.

Settings from before these: Follow Native Settings on (or, before it, either of Match Game Log Size and
Match Game Input Size) becomes Follow Game, off WinXI Skin; the four Replace switches of the expanded
log become Replace Expanded Log, on where all were. Old Own Color and Override Colours settings
are dropped.

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

**Anchoring.** The log follows the native primary chat base (or, in WinXI Skin with Position Custom,
stands at its own place). While typing, its total footprint stays fixed: input occupies the bottom
of that space, reducing the number of visible chat rows rather than lifting the whole log. Closing
input restores those rows. Native input/log lifting does not move this footprint; the optional info
panel and second window also stay put. Log and input bar always share width and left edge. Uihook moves the native clock
text, day icon and weather icons by the difference between the replacement's top-left and the
native log's, keeping the game's clock-to-log spacing, with the native clock and the `clock` addon
alike (its rectangles are reported where they moved to). The compass stays put. Releasing the log,
or expanding it, restores ordinary clock placement.

**Input.** Open chat as ever: Enter, `/`, Space or your shortcut. Cursor keys, Home/End, editing,
history, Enter and Escape are the **same native editor's**, as are the chat mode, commands and
sending; the bar draws its text and blinking caret and scrolls to keep the caret in view.
Auto-translate phrases already in the line use the game's display buffer, otherwise the raw-byte caret.
With Auto-Translate on, Tab while the game's input is open is chatbox's, so the game's own auto-translate
menu, which would take the input bar back, never opens; while chatbox's list is open, Up, Down, Page Up,
Page Down, Enter and Escape are its own too. They are blocked in Ashita's `key` event (which sees a key
before the game's input handler) and DirectInput's `key_data`, each until it is let go. The game reads the
Enter that sends the line from DirectInput's polled keyboard state, though, not from a key message, so
blocking those alone sent the half-typed line: chatbox also clears the list's keys from that state
(`key_state`, written through `data_modified_raw`) while the list is open and while a key it acted on is
still down. No other key's state is touched; `/chatbox status` counts the times it cleared one. The chosen phrase's six-byte token replaces the word (or goes
in at the caret from a category) on the next frame, through Ashita's `SetInputText`, or each buffer's
setter where that is not kept, read back to be sure; text typed since the choice is never overwritten,
and a line past the setters' 120 bytes is refused rather than cut. `/chatbox status` says what was
written. Nothing is sent, no outgoing message is blocked and no key is pressed for the game: the next
Enter sends the line as ever, the token in it.

Off, the game's own auto-translate menu takes the input bar back from the skin while it is open. Uihook draws the
captured bar at the `menu inline` boundary in place of the game's background, text and caret when it is
safe to replace it. Input is its own slot: closing input, a decode, API or capture failure or a missing
signature releases it, and the game's editor shows. Clicking in the skinned bar does not place the caret
or select. IME menus stay the game's and want live testing.

**Expanded log.** Use the game's Square/window selection on the log, then Confirm: a faint light
over the box and the game's hand cursor at its newest line show the selection. The addon binds no
button and writes no expanded flag. Expanded mode is a **WinXI frame around the game's own
browser**, at its full-log rectangle: uihook replaces the decoration and lets the game draw its
rows, selection and cursor where its mouse hit-tests are. Browsing, tabs, wheel, Confirm (with its
message-action menus) and Cancel are all native; no tell is made up, and every tab uses the game's
own filter. The **tabs, scrollbar and text** are the addon's: uihook measures the game's tab strip,
scrollbar and rows of text as the game draws them and, with Replace Expanded Log on,
leaves them undrawn, and the addon draws its own in exactly those places the frame after. The game draws each tab not chosen only its first 30 units wide, the next over the rest; the
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
its place. Nothing is moved, so Square, the wheel and the mouse on the tabs and the scrollbar still work on
the game's own controls. With Replace Expanded Log off, or without a fresh place from uihook (the first frame, or a
build without the hooks), the game's own are drawn: the selected tab and row highlight in the
Highlight Color, other tabs the Title colour, the cursor and scrollbar the **Border / Art Tint**,
native fade and pulse kept. The row highlight and cursor are the game's, tinted so, unless Replace
Expanded Log mirrors the whole log: then uihook leaves the full log wholly undrawn (with uihook 0.6) and the
addon lights the row the game highlights (uihook measures the game's highlight as it is drawn and
flags the rows under it; the cursor's row with an older uihook) from the left of its text to the scrollbar, a row's pitch tall, in the
Highlight Color (brighter while held down), lights a row the game marks faintly, and draws the cursor
after the cursor row's text; which row that is, is the game's, read as it draws.
The **text** is the addon's with Replace Expanded Log on: uihook decodes each of the game's rows as the
game draws it (its glyph words back to the bytes the game was given, colour codes and all) and
measures the row, and the addon lays the rows out as the compact log does: the chat's **Font** at
**Font Size**, Font Size + 2 apart, the newest ending at the **Bottom Padding** and older ones up from
it, from the log's left edge in by **Left Padding**, in its message's chat-mode colour with the game's
inline colours kept and auto-translate brackets as shapes, clipped
to the log's box; the game's cursor is drawn after the cursor row's text, where the game puts its
mark. Which rows there are and their wrapping, the cursor, Confirm and its menus and the wheel are
still the game's, followed by the rows' order (when the row the game has chosen is past what fits,
the view moves up to keep it in sight). The game's own rows stand 16 of its units apart, which do not line
up with these, so while the rows are the addon's the mouse over the rows is kept from the game: its hover
and clicks would land on other rows than the ones shown. Every mouse message but the wheels is kept there
(moves, and every button's presses and double-clicks), and the release of a press kept is kept wherever
it is let go, while a press the game had (the camera turned across the log, its scrollbar dragged) keeps
its drag and its release wherever they land. The game's tabs and scrollbar (a few pixels round it) are
still its own, and so is the mouse while a menu of the game's (a row's action menu, or the input line) is
open over the log. The wheel goes through and scrolls as ever; Square, the arrows and Confirm choose
rows; Chat Tooltips work on these rows. With Replace Expanded Log off the game draws its own rows and
has its mouse. With a Font Size larger than the game's own row pitch, fewer rows fit than the game
pages: only as many as fit are shown, from the newest of the page up, and the rows at the top of a page
are reached by walking the cursor up with the arrows (the view follows it); the text is never shrunk to
the game's rows. A font wider than the game's can
run past the right edge, where it is clipped. Off, or without a fresh set of rows from uihook, the game's own bitmap font is drawn.
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
luajit tests/chatbox_retention_check.lua
luajit tests/chatbox_scrollbar_check.lua
luajit tests/chatbox_ui_check.lua
luajit tests/infopanel_source_check.lua
luajit tests/winxi_frame_check.lua
luajit tests/nativemenus_check.lua
luajit tests/nativehistory_check.lua
luajit tests/chatbox_input_check.lua
luajit tests/chatbox_translate_check.lua
luajit tests/chatbox_layout_check.lua
luajit tests/harness.lua party addons/party/party.lua tests/winxi_capture_check.lua
luajit tests/winxi_version_check.lua
plugins/uihook/tests/run.sh
```

These are offline checks, not proof of live rendering. Still to check in game: primary and split
logs, wrapping, Enter, slash and mode shortcuts, history, editing and caret scrolling,
the Auto-Translate list (Tab never reaching the game, Enter's phrase kept and not sent) and IME, non-Latin glyphs, input fallback, expanded history, selection and focus
changes, confirm and cancel, menu hiding, shared widths, input lift and close, clock anchoring,
zoning, UI hide, theme and font changes, device recovery and unloading and reloading the addon and
plugin. `/chatbox off` returns to the game's chat at once.
