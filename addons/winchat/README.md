# winchat (experimental)

Up to 0.17 this addon was called chatbox. Load `winchat` in place of `chatbox` and remove the old
`addons\chatbox` folder: each character's settings are brought over from `chatbox` the first time it
logs in, and its Auto-Translate list is read from there until winchat writes its own. `/chatbox` still
works as `/winchat`.

A **WinXI-styled chat log that the game still drives**. The compact log takes the place and
**size** of the game's main log (it follows the game's chat size setting), in WinXI's background and border art,
with **12px text** and **3px padding** to begin with. New messages appear at the bottom; long ones
wrap and count as rows. A WinXI title on the top edge names the channel. Typing goes into a WinXI
input bar over the game's own editor. Confirming on the log opens the game's own expanded log
in a WinXI frame, with its channel tabs and scrollbar drawn in WinXI's look and its text in the chat's font,
each where the game's are.

- The title follows `/cm` (`/chatmode`) at once, with a passing override for a line typed with
  `/p`, `/l`, `/t` and the like. Until a mode command is seen, it is the last channel spoken in (Say
  to begin with). Linkshells show `Linkshell 1: Name` or `Linkshell 2: Name`, from the equipped
  pearl. If you loaded winchat mid-session and names are missing, re-equip your pearls, because the game
  sends their slots on login and equip.
  **Window Title** in the winchat section puts your own words there instead; left empty, the channel.
- Native and SimpleLog inline colours are always kept; text with no colour of its own takes its native chat-mode
  colour. The colours are the game's own, as you have set them, read through uihook; without uihook, close
  approximations.
- The last 256 messages seen are kept **in memory only**. With two log windows, each also keeps
  its own last 256 routed messages, so busy traffic in one cannot erase the other's older messages.
  These share one chronological store (at most 768 messages; a message in more than one list is stored once).
  Routing changes apply to the kept messages; messages already dropped cannot be brought back.
  No chat is written to disk. As it starts
  (and after a reset or a new character), winchat reads the game's own history once through uihook,
  the first log window's last 100 lines, and puts them before its own, so a reload or a late load
  does not begin empty; lines it already has are left out. The game keeps a message as the lines it
  wrapped it into. With timestamps on, a line without one is joined back to the message before it, so
  each message is whole again (with timestamps off, each of the game's lines stays a message).
  `/winchat status` says how many were read. The expanded log is the game's own.
- While you type, the input bar takes the compact log's bottom rows. The log's total footprint does not move or grow. The game's clock and its icons follow the top
  of the log.
- With **Log Window 2** on in the game's settings, a second box stands where the game puts its second
  window: over the first (with its own game width and height in Follow Game) or beside it (the game's width and
  gap, and the first's bottom). It is titled Window 2 (or **Window 2 Title**). Each box shows the messages the
  game's Log Window settings route to its window, read from the game, and scrolls on its own. The
  focus light follows the game's focus between them.
- Each box has as many rows as the game's window shows at the moment. The game grows its window a
  row for each message, and shrinks it to its fewest lines while none come; the box follows,
  tall enough for those rows at Font Size. A window at 0 lines shows nothing, and the other is still drawn.
- The mouse wheel scrolls an overflowing compact log three visual rows a notch, and a slim scrollbar
  appears on its right: drag the thumb, or click the track to page.
- In WinXI Skin, with **Lock Window** off, you can drag the log wherever you want (Position Custom); the
  input bar and the second window go with it. There is no resizing with the mouse. Combat formatting, filters and timestamps are left to the game or
  SimpleLog; **Timestamps** hides the stamps they write, in every log, and shows them again at once.
- Rest the mouse on something named in the compact log or Window 2, and a Winxi tooltip says what it is
  (**Chat Tooltips**). Items, key items and auto-translate phrases are known by the codes the game sends with
  the line, so they are found exactly. Spells, abilities, weapon skills, quests and places written as plain
  text are found by their names. Names are matched by text, so an ordinary word that is also the name of an
  item or a place may show one. In the expanded log they work on the rows the addon draws (Replace Expanded
  Log), by name, because the game keeps no tokens in its history.

## Install

```text
addons/winchat/          this directory
addons/libs/winxi/       WinXI 24 or newer (including infopanel code and bundled icons)
addons/wxi/    shared theme settings (optional)
plugins/uihook.dll       0.5 or newer; 0.8 or newer reads each chat line after every addon, so the addon load order does not matter
```

How to install and update uihook is in [its README](../../plugins/uihook/README.md). Turn
replacement off or unload the addon before you replace its files, and unload uihook before you replace
its DLL. Update the DLL and `addons/libs/winxi` together with winchat. Do not run FancyChat,
hidechatbg or other addons that write the native chat's visibility alongside it.

```text
/load uihook
/addon load winchat
```

With uihook 0.8 or newer loaded after `addons` (as `/load addons` then `/load uihook`), the addon
load order does not matter. winchat reads each chat line through uihook as it stands after every
addon, so SimpleLog's timestamps and a filter's blocks reach it whether SimpleLog is loaded before or
after it (`/winchat status` says "Lines: read through uihook after every addon"). Where uihook is
loaded before `addons`, its copy is the game's original, and winchat keeps its own copy of a line an
earlier addon changed instead. Without that uihook, load chat formatting and filtering addons,
SimpleLog among them, **before** winchat. It then reads `text_in`'s modified text and mode and ignores
blocked messages, but cannot see changes made by handlers that run after its own. An alphabetical
`scripts/default.txt` loads winchat before simplelog, so move simplelog's line above winchat's, or
every game start puts them back (SimpleLog's timestamps then reach the game's log but not winchat's;
`/winchat bytes` says so). winchat never blocks or rewrites a message, so the game's history keeps
everything and is there if replacement stops. SimpleLog's multi-hit and critical tags, aggregation,
actor filters, timestamps and job profiles come through that way; there is no second combat
formatter or filter.

## Optional Info Panel

The **Info Panel** tab in `/winchat` has General, Layout, Data, Window 2, Text and Icons subtabs. Turn the panel on
there or with `/winchat panel on`. It is **off by default**, so an update does not add a second copy
of a clock panel you already have.

- Three separate **Left/Middle/Right** slots, each with a format, a field picker, Left/Center/Right
  alignment, and a relative-width weight. A `|` character typed in the format becomes a Winxi Fine/Beveled/Ornament
  divider; the two slot boundaries can be styled or hidden too.
- Fields: `{time}`, `{zone}`, `{grid}`, `{day}`, `{date}`, `{moon}`, `{weather}`, `{dayicon}`,
  `{weathericon}`, `{level}`, `{exp}`, `{tnl}`, `{rate}`. For example, Left: `{time} | {zone}`,
  Middle: `{day} | {date}`, Right: `{tnl} | {rate}`. An empty field takes the divider before it away.
- Width 0 follows the winchat that owns the panel. Height 0 matches the prepared input-bar height, or grows to fit
  the panel font/icons and padding. The font and its size can follow chat or be set on their own. Text and icons are
  vertically centred; at a fixed size, overflow is clipped inside its own slot.
- Attach To Chat (with offsets), or use a custom position and size, which leaves chat where the game
  puts it. Attached, **Anchor** (Layout tab) chooses where:
  - **Bottom** (default): the panel takes the bottom of the logs' place, and every drawn log is lifted
    by its height, so chat sits wholly above it. While you type the panel stays put: input takes
    the bottom of the first log's footprint, with fewer chat rows above it. The
    lowest visible log owns it: the primary, under a stacked Window 2 or beside a side-by-side one.
  - **Top**: flush over the upper log, its channel title drawn last at their shared seam; chat and
    the input stay where the game puts them. The upper visible log owns it: a stacked Window 2, or
    the primary beside a side-by-side one.
  If only Window 2 is visible, it owns the panel either way.
- **Window 2 Panel** (General, off by default) adds a second panel on Window 2 (over or under it, by Anchor) while the game
  shows the two log windows side by side. Its slots, layout and icon placement are set in the
  **Window 2** subtab; the font, text colour and icon set follow the first panel. Attached panels
  share the taller one's height, so both logs keep one bottom. Stacked logs keep one panel.
- Day and weather icons can go before or after any slot, each with its own offset, or be put in as data
  tokens for an exact order. Icon sets are under `addons/libs/winxi/infopanel/icons`: `gems` (the days cut
  as gemstones) and `classic` (drawn after the game's own: its mottled day balls and soft weather sprites)
  are bundled. Each has a picture for every weather, including the skies the
  game draws no icon for (a sun for a clear sky, a pair of clouds, a bank of fog), and `gems`
  supplies any custom picture that is missing. Hidden/Native placement does not add an icon on its own;
  winchat never changes the native HUD's visibility.
- Hover a **day icon** to see the Vana'diel weekday and its element. Hover a **weather icon** or the
  `{weather}` words to see the weather name, element and single/double strength (or no elemental
  weather for clear skies, clouds and fog), and then the **zone's forecast**: today and the four days
  after it, each with what the zone may roll and the odds, as the Phoenix server rolls it.
- Hover the `{time}`, `{day}`, `{date}` or `{moon}` words for the **Vana'diel calendar**: the month,
  its thirty days in weeks of eight under the Icon Set's day pictures (or the days' names), with today
  marked, the days gone dimmed, and the neighbouring months' days that fill out the first and last
  weeks fainter still; the moon's phase and fullness; and when the next day begins, in Earth minutes.
- Hover the `{zone}` words for the **ships' and airships' timetable**, as the Phoenix server runs them:
  the next four to leave, soonest first, from the lines ticked in the **Timetable** tab (the airships
  between Jeuno and San d'Oria, Bastok, Windurst and Kazham, the ferry between Selbina and Mhaura,
  the Aht Urhgan ferries, the Manaclipper and the Carpenters' Landing barge; each place one leaves
  from and goes to is a line of its own, all on to begin with, with All and None buttons). Each row has
  how long until its door opens (**Boarding**, or `now` while it is open) and shuts (**Leaves**), the
  Vana'diel time it leaves (**At**) and how long the crossing takes (**Trip Time**), in Earth
  minutes:seconds. The rows that board in the zone you are in are marked in the theme's tooltip border
  colour. Aboard a ship or airship, a line on top says where you are bound and how long until you are
  put ashore. The Aht Urhgan ferries run
  only where the server has `ENABLE_TOAU` on, as the live branch does. Both the automatically placed icons and the `{dayicon}` / `{weathericon}` tokens support
  this, including panel-only mode when the logs are empty. Tooltips use the shared Winxi tooltip
  switch, delay and styling, but not its width: each is as wide as its longest line, so the
  forecast's days and the timetable's rows never wrap. Icons and words stay click-through; hovering
  does not take game input.
- Background, border art and shadow follow the shared or local Winxi theme. When both logs collapse,
  the panel stays visible without an empty chat frame. Attached, it lifts the drawn logs (and their
  scroll regions) by its height; it never changes the game's own log rectangles.
- Visibility follows **compact chat**, not the native clock: action and combat menus that hide the game's
  clock no longer stop the panel. When both compact logs are empty, at zero native lines, or
  hidden by Smart Visibility, the panel (if on) stays visible. It still hides during expanded history, zoning,
  winchat off, or when no valid native layout or capture is available. Custom positioning does not override these rules.
- Time, zone and EXP data do not need the native clock to be drawn. The weather icon stays available while
  fishing, in events, or when the native clock is hidden, even when winchat loads mid-session.
  A passing read failure keeps the last known weather; leaving a zone and character resets clear it.
  Clear skies are a real value, never a guessed fallback. `{grid}` likewise falls back to the game's
  own grid function while the clock is hidden; zones without a grid still omit it.

**Switching from clock:** install this winchat and the full updated Winxi library, including the
shared panel icons. `/addon unload clock`, `/addon reload winchat`, then `/winchat panel on`.
winchat does not need the clock addon or its folder; existing clock settings are left as they are
and are not imported. Use `/winchat panel off` before you go back to clock.

**Hide Game Clock** (Info Panel → General, off by default; `/winchat clock [hide|show]`) hides the
game's clock, its time and its day and weather icons while winchat runs, with the panel on or off.
The game still runs its clock, so `{grid}` and the weather stay readable for the panel. Turning it
off, winchat off, zoning or unloading gives the game's clock back at once. Needs uihook with clock
support; unload the clock addon and hidecompass, which use the same object. `/winchat status`
reports it as Game Clock.

**Hide Compass** (Info Panel → General, off by default; `/winchat compass [hide|show]`) does the same
for the game's compass and its radar, through uihook's compass slot. The clock is not affected
either way, and each can be hidden alone. It is given back on the same terms as the clock.

The game's own menus are left where the game puts them: winchat no longer moves the action menus above
the info panel (Anchor Above Info Panel, removed in 0.15.0).

## Commands

```text
/winchat          the settings
/winchat on       Enable winchat
/winchat off      Disable winchat: the game's logs come back at once
/winchat clear    forget the messages this addon keeps
/winchat timestamps   toggle the Timestamps option (on or off to set it)
/winchat translate    toggle Auto-Translate, winchat's own phrase, item and key item list on Tab (on or off to set it)
/winchat status   bridge status, the last box drawn, kept-message and decode-error counts
/winchat modes    the last ten lines kept and their chat modes (to find a channel's)
/winchat bytes    the last incoming line: original, modified, expanded and UTF-8 bytes (hex, first 256 of each)
/winchat panel on     enable the optional info panel (off by default)
/winchat panel off    hide the info panel without affecting chat
/winchat panel reset  reset the panel's EXP-per-hour tracker
/winchat clock        toggle hiding the game's clock (hide or show to set it)
/winchat compass      toggle hiding the game's compass (hide or show to set it)
/uihook chat      native recognition, focus/expansion flags, cursor, page, scroll and filter
/winxi            the shared WinXI look, with wxi installed
```

## Settings

`/winchat` opens the Settings, Info Panel and Tooltips tabs. Every setting is a described row: its name, a sentence under it
saying what it does, and its control at the right (winxi 65). There is no Winxi Theme tab. Settings are kept for each character. The
winchat and Look sections apply in both modes. The Layout and Activity sections belong to the WinXI Skin and
show only in it (their settings are kept, and ignored, in Follow Game). The look is WinXI's in both:
the mode is how the boxes behave and where they stand.

**winchat**

- **Enable** (on to begin with): turns on winchat's log and input bar. Off, the native log and input
  come back, and all the other controls in Settings, Info Panel and Tooltips are greyed out. Saved settings
  are kept. `/winchat on` and `/winchat off` control this switch.
- **Replace Native Chat** (on to begin with): on chooses **Follow Game**; off chooses **WinXI Skin**.
  This changes the layout behaviour, not whether winchat is on. Existing mode settings are kept.
  Native window size does not necessarily mean the same number of lines.
  - *On, Follow Game*: the log, the input bar and the expanded log where the game puts its own, at its sizes.
    Each log follows its game window's size and its lines, as the game grows its window a row for each
    message and shrinks it to its fewest while none come (at 0 lines nothing is drawn); the second window
    stands where the game shows it, with the game's width and gap. The input bar uses the game's
    height (or enough for the chosen font), centred text, and the log's width, but takes the bottom
    of the compact footprint rather than moving it when you type;
    the expanded log opens where the game puts it, at its full height.
  - *Off, WinXI Skin*: the addon's own Width and rows, the activity controls, and the expanded log's place
    and height, from the Layout and Activity sections.
- **Auto-Translate** (on to begin with): Tab while typing opens winchat's own list of auto-translate
  phrases, from the installed client's dictionary, and of your character's own items (in any bag) and key
  items, as the game's own lists are, for the word at the caret (with no word, the 42 categories and Items
  and Key Items), drawn above the input bar. An item or key item says so at the right of its row. Your
  bags are read each time the list opens, and what you have held stays in the list for good, kept for
  each character in `config/addons/winchat/<name>_<id>/autotranslate.lua`. An item or key item someone
  writes in chat (a yell selling it, a tell) is in your list too until you close the game, for every
  character you log into until then. Tab, Shift+Tab, Up and Down move; Page Up and Page Down move a
  page; Enter puts the phrase, item or key item in (on a category, opens it); Escape closes (in a category, goes back to the
  categories). With a controller, while the list is open: the d-pad up and down a row, left and right a
  page, A puts the choice in (on a category, opens it), B goes back or closes; the whole controller is kept
  from the game while the list is open, and given back when it closes. Once you have used a controller,
  a legend above the list shows those buttons, each drawn as it looks on your controller (winxi's legend).
  - **Controller Type** (Automatic to begin with): the kind of controller that works the list. Automatic
    follows the game's own setting, as the Phoenix launcher sets it (XInput or DirectInput; a DirectInput
    controller is taken for a PlayStation one). Otherwise XInput is an Xbox controller, or one set up to act
    as one; for any other choose its DirectInput make (PlayStation, Switch Pro, Stadia). With the wrong kind
    no button reaches the list; the settings and `/winchat status` say so once a button is pressed.
  - **Navigation Sounds** (on to begin with): the winxi menu sounds as the list opens, the highlight moves
    a row (keys, Tab or the d-pad), a page turns, a choice goes in or a category opens, and the list goes
    back or closes; a choice too long for the line plays the error sound. The sounds are winxi's
    (`addons/libs/winxi/sounds`); a wav of the same name in `addons/winchat/sounds` is played in its place. Typing goes on narrowing the list. The phrase goes into your line as its real token, so
  others see it in their own language when you send. Off, Tab is the game's, whose own menu takes the
  input bar back for as long as it is open. `/winchat translate on` and `off` do the same.
- **Timestamps** (on to begin with): the time in front of each line as SimpleLog's Timestamps or
  Ashita's timestamp addon writes it; winchat adds none of its own. Off, those are hidden in the
  compact log, Window 2 and the expanded log; the messages keep them, so turning it on shows them
  again at once. Turn on timestamps in either SimpleLog or the timestamp addon to supply them;
  do not turn on both, or the stamps double. `/winchat timestamps on`
  and `off` do the same. There is no button to clear the history; `/winchat clear` is still there.
- **Chat Tooltips** (Tooltips tab, on to begin with): rest the mouse on an item, key item, auto-translate phrase,
  spell, ability, weapon skill, quest or place in the compact log, Window 2 or (with Replace Expanded Log)
  the expanded log's rows, and a tooltip shows it; the gap between two rows counts as the row above. Under
  it, greyed while it is off, one switch for each kind, all on to begin with: **Items**, **Spells And Abilities**, **Weapon
  Skills**, **Quests**, **Places** and **Auto-Translate**; and **Tooltip Notes** (on to begin with), the
  dimmed lines: what the catalogs cannot vouch for (presence is not availability, modifiers in server
  units) and a phrase's category and kind; off, only the name and the facts. The shared Winxi tooltip settings (whether
  tooltips show, their delay and their look) apply. Nothing shows while the mouse is over the settings or
  another imgui window, while the log or its scrollbar is being dragged, or in the expanded log while the game
  draws its own rows.
- **Font**: the log's and input bar's font, the theme's (to begin with) or any `.ttf` in
  `C:\Windows\Fonts`. Japanese and other non-Latin text need a font with those glyphs.
- **Font Size**: 8 to 24 pixels (12 to begin with); the boxes grow with it, and the expanded log's text
  is this size too (with Replace Expanded Log). In Follow Game, **Automatic** (0) takes the size the
  game's rows give, so the rows stand where the game's do (12 until it is first read).
- The bridge's status is at the foot of the tab.

**Layout** (WinXI Skin)

- **Lock Window** (on to begin with): off, you can take hold of the log with the left button anywhere on
  it but its scrollbar and drag it wherever you want; when you let go, the place is kept for the character and
  Placement becomes Custom. The wheel and the scrollbar still work. On, it stays where it is, and the mouse
  goes through it to the game.
- **Placement**: **At the Game's Chat** (to begin with), where the game puts its own log, or **Custom**,
  wherever it was dragged to or the **Position** typed under it (the log's bottom-left in pixels from the
  screen's top-left, kept on the screen). Choosing Custom takes the place the log stands at. The input
  bar uses the bottom of that footprint while you type, a stacked or side-by-side
  second window keeps its place beside the first, the info panel attaches as before, and Expand In
  Place opens the expanded log there. The game's clock, which uihook keeps at its distance from the
  log, goes with it; Hide Game Clock in the Info Panel tab takes it away. The game's own log must still
  be drawn (its place known) for the box to be drawn at all, wherever the box stands.
- **Width**: 240 to 1200 pixels (640 to begin with). Also the expanded view's width, capped at its native
  bounds; its tabs, scrollbar and text clipping follow that width. The game still controls how history rows
  wrap, selection and hit-tests: narrowing the view clips long native rows rather than wrapping them again.
- **Window 1 Rows / Window 2 Rows**: choose 1–50 rows for either compact log, each on its own.
  **0 (Automatic)**, the default, uses ten rows. A custom count sets only that window's height;
  its width stays. With Auto Resize on, this is its most rows. Expanded history is
  not affected.
- **Expand In Place** (on to begin with): the expanded log opens where the chat log stands, its
  bottom-left on the first log's. The info panel is hidden while the log is expanded, so with Anchor
  Bottom the log takes the panel's place as well. Its rows, hovering, Confirm and scrolling move with it, as
  the game lays them out there. Off, where the game puts it.
- **Expanded Height** (75% to begin with, 25 to 100): how far up the screen the expanded log reaches.
  Its top is that share of the screen's height up from the bottom, and never above the game's own window;
  the tabs stand on its top and the scrollbar keeps within it. The game's rows above it are cut off.
  100% is the game's own.

**Activity** (WinXI Skin)

Window 1 and Window 2 have their own settings, all **off by default**, each window a sub-section. Each
switch's own rows are under it, greyed while it is off.

- **Auto Resize**: grows the compact log to fit the recent wrapped messages routed to that window,
  up to its rows, then shrinks as messages age out. With it on:
  - **Animate Resize**: smooth growth and shrinking, anchored at the bottom edge. Stacked windows
    follow the animated edge; rows are revealed or clipped at the top. Once settled, the box fits its exact
    row count and padding. With it on, **Resize Duration**: 0.05–2 seconds, **0.2** by default, for each
    change of size; new content arriving during a change retargets it from its current height.
  - **Minimum Rows**: 0–50, **0** by default, capped at the log's rows. The rows left while idle; zero
    hides the log entirely.
- **Fade When Idle**: fades the log away after no messages reach it for Idle Time. A new routed
  message fades it back in over 0.2 seconds. Use it alone, for a fixed-size log, or with Auto Resize. With it
  on, **Fade Duration**: 0.1–10 seconds, **1** by default, for fading out.
- **Idle Time**, with either on: 1–300 seconds, **15** by default. How long a message counts as recent:
  Auto Resize keeps rows for it, and Fade When Idle starts fading after it. Activity in the other
  window does not reset this timer.

Typing brings both available compact logs back to full size and opacity at once, skipping the resize
animation. Choosing a log, scrolling back in it, or dragging its scrollbar keeps that log visible. The
fade's idle delay restarts after you interact with it. Expanded history is not affected. Messages stay in history
when hidden; opening or scrolling the log still lets you read them. Imported history does not count as
new activity. Native log capture stays active while hidden, so the game's original log does not show
through. When both logs disappear, the info panel stays visible on its own.

**Look** (both modes)

- **Window Title** and **Window 2 Title**: your own words on each box's top edge; left empty, the
  channel and Window 2.
- **Left Padding**, **Right Padding**, **Top Padding** and **Bottom Padding**: 0 to 40 pixels each
  (3 to begin with), for the log and the input bar. Long lines wrap between the left and right
  padding. Logs sized on their own fit exactly their row count plus the top and bottom padding, with
  two pixels between rows and no extra room for a title. The input bar is Font Size plus both vertical
  paddings tall, its text and caret always centred in the whole bar, and it has a plain `> ` prompt.
  Settings still at the first default of 4 on every side become 3 once; paddings set by hand are kept.
- **Replace Expanded Log** (on to begin with): the expanded log's channel tabs are drawn as WinXI buttons,
  each whole and in the game's order, the chosen one lit as the game chooses it; its scrollbar is drawn
  like the compact log's, where the game's is; its rows of text are in the chat's Font at Font Size, each
  row centred where the game draws its own and in the game's colours; and, with uihook 0.6, its
  cursor, the light on the cursor's row and the game's marked rows, so that nothing of the game's is
  drawn in it. The rows stand at the chat's own pitch, not the game's, so the mouse over the rows is kept
  from the game, whose hover and clicks would land on other rows. The game's tabs and scrollbar are still
  its own to click and drag, a menu of the game's open over the log keeps its mouse, the wheel goes
  through and scrolls, and Square, the arrows and Confirm choose rows. Off, the game's own are drawn in
  the WinXI frame, tinted to the theme, and the mouse is the game's.
The chat log and input text box take WinXI theme colours. Per-window colour overrides and their
settings sections have been removed; saved overrides are discarded. The source's inline colours are kept.

Settings from before these: Follow Native Settings on (or, before it, either of Match Game Log Size and
Match Game Input Size) becomes Follow Game, and off becomes WinXI Skin; the four Replace switches of the expanded
log become Replace Expanded Log, on where all were on. The old Own Color and Override Colours settings
are dropped.

## Limitations

- The game decides when the log is drawn: winchat never forces a closed log open, never ignores UI
  hide, and never draws over browsing and action menus. Zoning suspends it.
- If the game's log is not where winchat can find it, or there is too little room above it, the game's
  log shows instead, while the input bar carries on. Turning winchat off, unloading or a failed capture
  also brings the game's drawing back.
- A character or settings swap clears the kept messages.
- The windows are click-through, except for the wheel over an overflowing log and its scrollbar.
- The game's clock moves with the log, keeping its distance from it; the compass stays put.
- Clicking in the skinned input bar does not place the caret or select. IME menus stay the game's and
  want live testing.
- With Auto-Translate off, the game's own auto-translate menu takes the input bar back from the skin while it is open.
- The expanded log is opened with the game's Square/window selection on the log, then Confirm. The addon
  binds no button. Browsing, tabs, wheel, Confirm (with its message-action menus) and Cancel are the game's.
- With a Font Size larger than the game's own row pitch, fewer rows fit in the expanded log than the game
  pages: the rows at the top of a page are reached by walking the cursor up with the arrows. A font wider
  than the game's can run past the right edge, where it is clipped.
- Padding, Width and Default Text apply to the compact log and input only, and there is no WinXI
  title over the expanded log's tabs.
- The palettes are standard-palette approximations, not live reads: custom DAT colours and your own
  channel colours are not imported. Unknown modes take the WinXI theme's colour.
- Named NPC dialogue gets `[NPC]` after the speaker, only `NPC` in yellow.
- Combat lines are not compacted, grouped, filtered or timestamped by winchat.
- Elemental symbols are drawn as `[fire]`, `[ice]` and so on. The game's other pictographs,
  blinking and timed reveal are not reproduced.
