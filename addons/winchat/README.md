# winchat (experimental)

winchat draws the game's chat log and the line you type in again, in the winxi look. The game still
runs the chat: winchat draws over the game's own log, in the same place and at the same size. It can
also show tooltips for items, spells and places named in chat, an auto-translate list on Tab, and an
optional info panel with the time, zone, weather and EXP.

## Why use it

- The chat log matches the look of your other winxi addons, in the font and size you choose.
- Rest the mouse on an item, spell, ability, quest or place named in chat to see what it is.
- Tab opens a list of auto-translate phrases and of your own items and key items, which you can use
  with a keyboard or a controller.
- An optional info panel shows the time, zone, weather, EXP, a weather forecast and ship and airship
  departures.

Up to 0.17 this addon was called chatbox. Load `winchat` instead of `chatbox`, and remove the old
`addons\chatbox` folder. Each character's settings are brought over from `chatbox` the first time
that character logs in. Its Auto-Translate list is read from there until winchat writes its own.
`/chatbox` still works as `/winchat`.

## What you see

- **The log.** A compact log takes the place and **size** of the game's main log. It follows the
  game's chat size setting. It has WinXI's background and border, with **12 px text** and **3 px
  padding** to begin with. New messages appear at the bottom. Long messages wrap onto more rows.
- **The title.** A WinXI title on the top edge names the channel. It follows `/cm` (`/chatmode`) at
  once. A line typed with `/p`, `/l`, `/t` and the like changes it for a moment. Until a mode command
  is seen, it is the last channel you spoke in (Say to begin with). Linkshells show `Linkshell 1:
  Name` or `Linkshell 2: Name`, from the pearl you have equipped. If you loaded winchat in the middle
  of a session and the names are missing, equip your pearls again: the game only sends them when you
  log in and when you equip them. **Window Title** puts your own words there instead. Left empty, it
  shows the channel.
- **The input bar.** What you type goes into a WinXI input bar over the game's own one. While you
  type, the input bar takes the compact log's bottom rows. The log does not move or grow.
- **The expanded log.** Confirming on the log opens the game's own expanded log in a WinXI frame. Its
  channel tabs and scrollbar are drawn in WinXI's look, and its text in the chat's font, each where
  the game's are.
- **Colours.** The coloured text that the game and SimpleLog put in a line is always kept. Text with no
  colour of its own takes the colour of its chat mode. These are the game's own colours as you have
  set them, read through uihook. Without uihook, close copies are used.
- **The game's clock** and its icons stay at the top of the log, and move with it.
- **Scrolling.** The mouse wheel scrolls a compact log that is too full, three rows a notch. A slim
  scrollbar appears on its right: drag the thumb, or click the track to move a page.
- **Moving the log.** In WinXI Skin mode, with **Lock Window** off, you can drag the log anywhere
  (Placement Custom). The input bar and the second window move with it. You cannot resize it with the
  mouse.
- **Combat text, filters and timestamps** are left to the game or SimpleLog. **Timestamps** hides the
  times they write, in every log, and shows them again at once.
- **Tooltips.** Rest the mouse on something named in the compact log or Window 2, and a Winxi tooltip
  says what it is (**Chat Tooltips**). See [Tooltips](#tooltips).

### A second log window

With **Log Window 2** on in the game's settings, a second box stands where the game puts its second
window:

- over the first, with its own game width and height (in Follow Game mode), or
- beside it, with the game's width and gap, and the first window's bottom.

It is titled Window 2, or the words in **Window 2 Title**. Each box shows the messages the game's Log
Window settings send to that window, read from the game. Each scrolls on its own. The light that shows
which window has focus follows the game's focus.

### How many rows

Each box has as many rows as the game's window shows at the moment. The game grows its window by a row
for each message, and shrinks it to its fewest lines while none come. The box does the same, tall
enough for those rows at **Font Size**. A window at 0 lines shows nothing, and the other one is still
drawn.

### Messages kept

- The last 256 messages are kept **in memory only**. No chat is written to disk.
- With two log windows, each window also keeps its own last 256 messages. So a busy window cannot push
  out the other's older messages. They share one store, in time order: at most 768 messages, and a
  message in more than one list is kept once.
- Changes to which window gets which messages apply to the kept messages. Messages already dropped
  cannot be brought back.
- When winchat starts (and after a reset or a change of character), it reads the game's own history
  once through uihook: the first log window's last 100 lines. It puts them before its own, so a reload
  or a late load does not start empty. Lines it already has are left out.
- The game keeps a long message as the separate lines it wrapped it into. With timestamps on, a line
  with no timestamp is joined back to the one before it, so each message is whole again. With
  timestamps off, each of the game's lines stays a message of its own.
- `/winchat status` says how many lines were read. The expanded log is the game's own.

## Install

You need:

| What | Version | Notes |
|---|---|---|
| `addons/winchat/` | | This folder |
| `addons/libs/winxi/` | WinXI 72 or newer | Including the info panel code and its icons. With an older WinXI, winchat says so and does not load |
| `addons/wxi/` | | Optional: the shared theme settings |
| `plugins/uihook.dll` | 0.5 or newer | 0.8 or newer reads each chat line after every other addon, so the order addons load in does not matter |

How to install and update uihook is in [its README](../../plugins/uihook/README.md).

- Before you replace winchat's files, turn replacement off or unload the addon.
- Before you replace uihook's DLL, unload uihook.
- Update the DLL and `addons/libs/winxi` together with winchat.
- **Do not run FancyChat, hidechatbg or other addons that show or hide the game's chat alongside
  winchat.**

```text
/load uihook
/addon load winchat
```

### Load order and other chat addons

**With uihook 0.8 or newer, loaded after `addons`** (for example `/load addons`, then `/load uihook`),
the load order does not matter. winchat reads each chat line through uihook after every other addon
has changed it. So SimpleLog's timestamps, and lines another filter addon blocks, reach winchat
whether SimpleLog loads before or after it. `/winchat status` then says "Lines: read through uihook
after every addon".

**If uihook is loaded before `addons`**, its copy of a line is the game's original. winchat then
keeps its own copy of any line that an earlier addon changed.

**Without that uihook**, load chat formatting and filter addons, SimpleLog among them, **before**
winchat. winchat then reads the text and chat mode as those addons changed them, and skips the
messages they block. It cannot see changes made by addons that run after it.

- An alphabetical `scripts/default.txt` loads winchat before simplelog. Move simplelog's line above
  winchat's, or every game start puts them back in that order. (SimpleLog's timestamps then reach the
  game's log but not winchat's.)

winchat never blocks or changes a message. So the game's history keeps everything, and is there if
winchat stops. SimpleLog's multi-hit and critical tags, grouping, filters by who acts, timestamps and
job profiles all come through. winchat has no combat formatter or filter of its own.

## Commands

| Command | What it does |
|---|---|
| `/winchat` | Opens the settings |
| `/winchat on` | Turns winchat on (**Enable**) |
| `/winchat off` | Turns winchat off. The game's logs come back at once |
| `/winchat clear` | Forgets the messages this addon keeps |
| `/winchat timestamps` | Switches the **Timestamps** option (add `on` or `off` to set it) |
| `/winchat translate` | Switches **Auto-Translate**, winchat's own phrase, item and key item list on Tab (add `on` or `off` to set it) |
| `/winchat panel` | Switches the info panel on or off |
| `/winchat panel on` | Turns on the optional info panel (off to begin with) |
| `/winchat panel off` | Hides the info panel. Chat is not changed |
| `/winchat panel reset` | Resets the panel's EXP-per-hour count |
| `/winchat clock` | Switches hiding the game's clock (add `hide` or `show` to set it) |
| `/winchat compass` | Switches hiding the game's compass (add `hide` or `show` to set it) |
| `/winxi` | The shared WinXI look, if wxi is installed |

For finding problems:

| Command | What it does |
|---|---|
| `/winchat status` | How winchat is connected to the game, the last box drawn, and counts of kept messages and of lines it could not read |
| `/uihook chat` | What uihook sees of the game's chat: recognition, focus and expanded flags, cursor, page, scroll and filter |

## Settings

`/winchat` opens three tabs: **Settings**, **Info Panel** and **Tooltips**. Settings are kept for each
character. Each setting is a row: its name, a sentence under it that says what it does, and its
control on the right. There is no Winxi Theme tab.

The **Settings** tab has four sections. **winchat** and **Look** work in both modes. **Layout** and
**Activity** belong to the WinXI Skin mode and only show there. (Their settings are kept, and
ignored, in Follow Game mode.) Both modes use WinXI's look. The mode only decides how the boxes behave
and where they stand.

### winchat section

- **Enable** (on to begin with): turns on winchat's log and input bar. Off, the game's own log and
  input bar come back, and every other control in Settings, Info Panel and Tooltips is greyed out.
  Your saved settings are kept. `/winchat on` and `/winchat off` work this switch.
- **Replace Native Chat** (on to begin with): chooses the mode. On is **Follow Game**; off is **WinXI
  Skin**. This changes how the boxes are laid out, not whether winchat is on. Settings for each mode
  are kept. The game's window size does not always mean the same number of lines.
  - **On, Follow Game:** the log, the input bar and the expanded log are where the game puts its own,
    at its sizes. Each log follows its game window's size and lines (see
    [How many rows](#how-many-rows)). At 0 lines nothing is drawn. The second window stands where the
    game shows it, with the game's width and gap. The input bar uses the game's height (or enough for
    your font), centred text, and the log's width. It takes the bottom of the log's space when you
    type, instead of moving the log. The expanded log opens where the game puts it, at full height.
  - **Off, WinXI Skin:** the addon's own width and rows, the activity settings, and the expanded log's
    place and height, from the Layout and Activity sections.
- **Auto-Translate** (on to begin with): see [Auto-Translate list](#auto-translate-list).
- **Timestamps** (on to begin with): the time in front of each line, as SimpleLog's Timestamps or
  Ashita's timestamp addon writes it. winchat adds no times of its own.
  - Off, those times are hidden in the compact log, Window 2 and the expanded log. The messages still
    have them, so turning it on shows them again at once.
  - To get times, turn on timestamps in SimpleLog or in the timestamp addon. Do not turn on both, or
    the times appear twice.
  - `/winchat timestamps on` and `off` do the same.
  - There is no button to clear the history. `/winchat clear` still does it.
- **Font**: the font of the log and input bar. The theme's font (to begin with), or any `.ttf` in
  `C:\Windows\Fonts`. Japanese and other non-Latin text need a font that has those characters.
- **Font Size**: 8 to 24 pixels (12 to begin with). The boxes grow with it. With **Replace Expanded
  Log**, the expanded log's text is this size too. In Follow Game mode, **Automatic** (0) takes the
  size that fits the game's rows, so the rows stand where the game's do (12 until it is first read).
- At the foot of the tab is the status of winchat's connection to the game.

### Auto-Translate list

With **Auto-Translate** on, pressing Tab while you type opens winchat's own list above the input bar.
It lists:

- auto-translate phrases, from the dictionary of the game you have installed;
- your character's own items (in any bag) and key items, as the game's own lists have them.

It shows matches for the word at the text cursor. With no word, it shows the 42 categories, and Items
and Key Items. An item or key item says so at the right of its row.

- Your bags are read each time the list opens. What you have held stays in the list for good. It is
  kept for each character in `config/addons/winchat/<name>_<id>/autotranslate.lua`.
- An item or key item that someone writes in chat (a yell selling it, a tell) is also in your list
  until you close the game, for every character you log into until then.
- Typing goes on narrowing the list.
- The phrase goes into your line as a real auto-translate phrase. So others see it in their own
  language when you send it.
- Off, Tab is the game's again. The game's own menu takes the input bar back while it is open.
- `/winchat translate on` and `off` do the same.

**With a keyboard:**

| Key | What it does |
|---|---|
| Tab, Shift+Tab, Up, Down | Move a row |
| Page Up, Page Down | Move a page |
| Enter | Puts in the phrase, item or key item. On a category, opens it |
| Escape | Closes the list. In a category, goes back to the categories |

**With a controller,** while the list is open:

| Button | What it does |
|---|---|
| D-pad up and down | Move a row |
| D-pad left and right | Move a page |
| A | Puts in your choice. On a category, opens it |
| B | Goes back, or closes |

While the list is open, the whole controller is kept from the game. It is given back when the list
closes. Once you have used a controller, a legend above the list shows these buttons, each drawn as it
looks on your controller (winxi's legend).

- **Controller Type** (Automatic to begin with): the kind of controller that works the list.
  - **Automatic** follows the game's own setting, as the Phoenix launcher sets it (XInput or
    DirectInput). A DirectInput controller is taken to be a PlayStation one.
  - Otherwise, choose **XInput (Xbox)** for an Xbox controller, or one set up to act as one. For any other,
    choose its DirectInput make (PlayStation, Switch Pro, Stadia).
  - With the wrong kind, no button reaches the list. The settings and `/winchat status` say so once a
    button is pressed.
- **Navigation Sounds** (on to begin with): the winxi menu sounds when the list opens, when the
  highlight moves a row (keys, Tab or the d-pad), when a page turns, when a choice goes in or a
  category opens, and when the list goes back or closes. A choice too long for the line plays the
  error sound. The sounds are winxi's (`addons/libs/winxi/sounds`). A `.wav` with the same name in
  `addons/winchat/sounds` is played instead.

### Layout section (WinXI Skin)

- **Lock Window** (on to begin with): off, you can hold the left mouse button anywhere on the log
  except its scrollbar, and drag it anywhere. When you let go, the place is kept for the character and
  **Placement** becomes Custom. The wheel and the scrollbar still work. On, the log stays where it is,
  and the mouse goes through it to the game.
- **Placement**: **At the Game's Chat** (to begin with), where the game puts its own log, or
  **Custom**: where you dragged it, or the **Position** typed under it (the log's bottom-left corner,
  in pixels from the screen's top-left, kept on the screen). Choosing Custom keeps the log where it is
  now.
  - The input bar uses the bottom of the log's space while you type.
  - A second window above or beside the first keeps its place next to it.
  - The info panel attaches as before.
  - **Expand In Place** opens the expanded log there.
  - The game's clock, which uihook keeps at its distance from the log, moves with it. **Hide Game
    Clock** in the Info Panel tab removes it.
  - The game's own log must still be drawn (so its place is known) for the box to be drawn at all,
    wherever the box stands.
- **Width**: 240 to 1200 pixels (640 to begin with). This is also the expanded log's width, but no
  wider than the game's own. Its tabs, scrollbar and text follow that width. The game still decides
  how history rows wrap, and handles selection and clicks. So a narrower expanded log cuts off long
  rows instead of wrapping them again.
- **Window 1 Rows / Window 2 Rows**: 1 to 50 rows for each compact log, on its own. **0 (Automatic)**,
  the default, uses ten rows. A row count sets only that window's height; its width stays. With **Auto
  Resize** on, this is the most rows it has. The expanded log is not affected.
- **Expand In Place** (on to begin with): the expanded log opens where the chat log stands, with its
  bottom-left corner on the first log's. The info panel is hidden while the log is expanded, so with
  Anchor Bottom the log takes the panel's place too. Its rows, hovering, Confirm and scrolling move
  with it, as the game lays them out there. Off, it opens where the game puts it.
- **Expanded Height** (75% to begin with, 25 to 100): how far up the screen the expanded log reaches.
  Its top is that share of the screen's height up from the bottom, and never above the game's own
  window. The tabs stand on its top, and the scrollbar stays inside it. The game's rows above it are
  cut off. 100% is the game's own height.

### Activity section (WinXI Skin)

Window 1 and Window 2 each have their own settings, in a sub-section each. All are **off to begin
with**. Each switch's own rows are under it, greyed out while it is off.

| Setting | What it does |
|---|---|
| **Auto Resize** | The compact log grows to fit the recent messages sent to that window, up to its rows. It shrinks again as messages get old |
| **Animate Resize** (with Auto Resize) | Grows and shrinks smoothly, from the bottom edge. A window stacked on it follows the moving edge. Rows appear or are cut off at the top. When it stops, the box fits its rows and padding exactly |
| **Resize Duration** (with Animate Resize) | 0.05 to 2 seconds, **0.2** to begin with, for each change of size. New messages during a change start it again from the current height |
| **Minimum Rows** (with Auto Resize) | 0 to 50, **0** to begin with, but no more than the log's rows. The rows left when nothing is happening. Zero hides the log completely |
| **Fade When Idle** | Fades the log away when no messages reach it for **Idle Time**. A new message fades it back in over 0.2 seconds. Use it on its own, for a log of fixed size, or with Auto Resize |
| **Fade Duration** (with Fade When Idle) | 0.1 to 10 seconds, **1** to begin with, for fading out |
| **Idle Time** (with either on) | 1 to 300 seconds, **15** to begin with. How long a message counts as recent: Auto Resize keeps rows for it, and Fade When Idle starts fading after it. Activity in the other window does not reset this timer |

- Typing brings both compact logs back to full size and full opacity at once, without the animation.
- Choosing a log, scrolling back in it, or dragging its scrollbar keeps that log visible. The idle
  time starts again after you use it.
- The expanded log is not affected.
- Hidden messages stay in the history. Opening or scrolling the log still lets you read them.
- History read in at start-up does not count as new activity.
- winchat still covers the game's log while its own is hidden, so the game's log does not show
  through.
- When both logs disappear, the info panel stays visible on its own.

### Look section (both modes)

- **Window Title** and **Window 2 Title**: your own words on each box's top edge. Left empty, they show
  the channel and Window 2.
- **Left Padding**, **Right Padding**, **Top Padding** and **Bottom Padding**: 0 to 40 pixels each (3
  to begin with), for the log and the input bar.
  - Long lines wrap between the left and right padding.
  - A log sized by the addon fits exactly its rows plus the top and bottom padding, with two pixels
    between rows and no extra room for a title.
  - The input bar is **Font Size** plus both top and bottom paddings tall. Its text and text cursor
    are always centred in the bar, and it has a plain `> ` prompt.
  - Settings still at the first default of 4 on every side become 3, once. Paddings you set yourself
    are kept.
- **Replace Expanded Log** (on to begin with): winchat draws the expanded log itself.
  - The channel tabs are WinXI buttons, each whole and in the game's order. The chosen one is lit as
    the game chooses it.
  - The scrollbar is drawn like the compact log's, where the game's is.
  - The rows of text are in the chat's **Font** at **Font Size**, each row centred where the game draws
    its own, in the game's colours.
  - With uihook 0.6, the cursor, the highlight on the cursor's row and the game's marked rows are
    drawn too, so nothing of the game's is drawn in it.
  - The rows are spaced as the chat's rows, not the game's. So the mouse over the rows is kept from the
    game, whose hover and clicks would land on other rows.
  - You can still click and drag the game's tabs and scrollbar. A game menu open over the log keeps its
    mouse. The wheel goes through and scrolls. Square, the arrows and Confirm choose rows.
  - Off, the game's own expanded log is drawn in the WinXI frame, tinted to the theme, and the mouse is
    the game's.

The chat log and input box use WinXI theme colours. The colours a line comes with are kept. Colour
settings for each window, and their sections, have been removed. Saved colour overrides are dropped.

## Tooltips

**Chat Tooltips** (Tooltips tab, on to begin with): rest the mouse on an item, key item, auto-translate
phrase, spell, ability, weapon skill, quest or place in the compact log, in Window 2, or (with
**Replace Expanded Log**) in the expanded log's rows, and a tooltip shows it. The gap between two rows
counts as the row above.

- Items, key items and auto-translate phrases are found exactly, by the codes the game sends with the
  line.
- Spells, abilities, weapon skills, quests and places written as plain text are found by their names.
  So an ordinary word that is also the name of an item or a place may show a tooltip.
- In the expanded log, tooltips are found by name only, because the game keeps no codes in its
  history.

Under it, greyed out while it is off, is one switch for each kind, all on to begin with: **Items**,
**Spells And Abilities**, **Weapon Skills**, **Quests**, **Places** and **Auto-Translate**.

**Tooltip Notes** (on to begin with) adds the dimmed lines: what the lists cannot promise (that an
item exists does not mean it can be had; bonuses are shown in the server's own units), and a phrase's
category and kind. Off, only the name and the facts are shown.

The shared Winxi tooltip settings apply: whether tooltips show, their delay and their look. Nothing
shows while the mouse is over the settings or another addon window, while the log or its scrollbar is
being dragged, or in the expanded log while the game draws its own rows.

## Info panel

The **Info Panel** tab in `/winchat` has the sub-tabs **General**, **Layout**, **Data**, **Window 2**,
**Text**, **Timetable** and **Icons**. Turn the panel on there, or with `/winchat panel on`. It is
**off to begin with**, so an update does not add a second clock panel if you already have one.

### What the panel shows

- **Three slots**, **Left**, **Middle** and **Right**. Each has a format, a field picker, Left, Center
  or Right alignment, and a width share. A `|` typed in the format becomes a Winxi divider (Fine,
  Beveled or Ornament). The two edges between slots can be styled or hidden too.
- **Fields:** `{time}`, `{zone}`, `{grid}`, `{day}`, `{date}`, `{moon}`, `{weather}`, `{dayicon}`,
  `{weathericon}`, `{level}`, `{exp}`, `{tnl}`, `{rate}`. For example, Left: `{time} | {zone}`,
  Middle: `{day} | {date}`, Right: `{tnl} | {rate}`. An empty field removes the divider before it.
- **Size:** width 0 follows the winchat that owns the panel. Height 0 matches the input bar's height,
  or grows to fit the panel's font, icons and padding. The font and its size can follow the chat, or
  be set on their own. Text and icons are centred top to bottom. At a fixed size, text that does not
  fit is cut off inside its own slot.

### Where the panel goes

Choose **Attach To Chat** (with offsets), or your own position and size, which leaves chat where the
game puts it. When attached, **Anchor** (General → Anchor And Game Clock) chooses where:

- **Bottom** (to begin with): the panel takes the bottom of the logs' space. Every drawn log is raised
  by its height, so chat sits wholly above it. While you type, the panel stays put: the input takes the
  bottom of the first log's space, with fewer chat rows above it. The lowest visible log owns the
  panel: the first log, below a stacked Window 2, or beside a side-by-side one.
- **Top**: right over the upper log, with its channel title drawn last where they meet. Chat and the
  input stay where the game puts them. The upper visible log owns the panel: a stacked Window 2, or the
  first log beside a side-by-side one.

If only Window 2 is visible, it owns the panel either way.

**Window 2 Panel** (Window 2 sub-tab, off to begin with) adds a second panel on Window 2 (over or
under it, by Anchor) while the game shows the two log windows side by side. Its slots, layout and icon
placement are set in the **Window 2** sub-tab. The font, text colour and icon set follow the first
panel. Attached panels share the taller one's height, so both logs keep the same bottom. Stacked logs
keep one panel.

### Day and weather icons

- Day and weather icons can go before or after any slot, each with its own offset. Or put them in as
  fields (`{dayicon}`, `{weathericon}`) for an exact order.
- Icon sets are in `addons/libs/winxi/infopanel/icons`. Two come with it: `gems` (the days cut as
  gemstones) and `classic` (drawn after the game's own mottled day balls and soft weather pictures).
- Each set has a picture for every weather, including skies the game draws no icon for (a sun for a
  clear sky, a pair of clouds, a bank of fog). `gems` fills in any picture a custom set is missing.
- Hidden/Native placement does not add an icon by itself, and does not show or hide the game's own
  icons. (Only **Hide Game Clock** does that.)

### Hover for more

Hovering works on the icons placed automatically and on the `{dayicon}` and `{weathericon}` fields,
also when the panel is shown alone with the logs empty.

- **Day icon:** the Vana'diel weekday and its element.
- **Weather icon or `{weather}`:** the weather's name, element and single or double strength (or no
  elemental weather, for clear skies, clouds and fog). Then the **zone's forecast**: today and the
  next four days, each with what weather the zone may get and the chances, as the Phoenix server rolls
  it.
- **`{time}`, `{day}`, `{date}` or `{moon}`:** the **Vana'diel calendar**.
  - The month: its thirty days in weeks of eight, under the icon set's day pictures (or the days'
    names). Today is marked, past days are dimmed, and days of the next and last months that fill the
    first and last weeks are fainter still.
  - The moon's phase and how full it is.
  - When the next day begins, in Earth minutes.
- **`{zone}`:** the **ships' and airships' timetable**, as the Phoenix server runs them.
  - The next four to leave, soonest first, from the lines ticked in the **Timetable** sub-tab.
  - The lines: the airships between Jeuno and San d'Oria, Bastok, Windurst and Kazham; the ferry
    between Selbina and Mhaura; the Aht Urhgan ferries; the Manaclipper; and the Carpenters' Landing
    barge. Each place a boat leaves from and goes to is a line of its own. All are on to begin with,
    and there are **All** and **None** buttons.
  - Each row has: how long until its door opens (**Boarding**, or `now` while it is open) and shuts
    (**Leaves**), the Vana'diel time it leaves (**At**), and how long the trip takes (**Trip Time**),
    in Earth minutes:seconds.
  - Rows that board in the zone you are in are marked in the theme's tooltip border colour.
  - On board a ship or airship, a line at the top says where you are going and how long until you
    arrive.
  - The Aht Urhgan ferries only run where the server has `ENABLE_TOAU` on, as the live branch does.

Tooltips use the shared Winxi tooltip switch, delay and look, but not its width: each is as wide as
its longest line, so the forecast's days and the timetable's rows never wrap. Icons and words let
clicks through. Hovering does not take input from the game.

### How the panel behaves

- Its background, border and shadow follow the shared or local Winxi theme.
- When both logs shrink away, the panel stays visible, without an empty chat frame. When attached, it
  raises the drawn logs (and the area they scroll in) by its height. It never changes the game's own
  log areas.
- It is shown when the **compact chat** is, not when the game's clock is. Action and combat menus that
  hide the game's clock do not hide the panel. When both compact logs are empty, at zero lines, or
  hidden by Smart Visibility, the panel (if on) stays visible.
- It is still hidden while the expanded log is open, while zoning, while winchat is off, or when the
  game's chat layout cannot be read. A custom position does not change these rules.
- The time, zone and EXP do not need the game's clock to be drawn. The weather icon stays available
  while fishing, in events, or when the game's clock is hidden, even when winchat loads in the middle
  of a session.
- If the weather cannot be read for a moment, the last known weather is kept. Leaving a zone and
  changing character clear it. A clear sky is a real reading, never a guess.
- `{grid}` also uses the game's own grid function while the clock is hidden. Zones without a grid
  still leave it out.

### Switching from the clock addon

Install this winchat and the full updated Winxi library, including the shared panel icons. Then:

```text
/addon unload clock
/addon reload winchat
/winchat panel on
```

winchat does not need the clock addon or its folder. Your clock settings are left as they are, and
are not brought over. Use `/winchat panel off` before you go back to clock.

### Hide the game's clock and compass

**Hide Game Clock** (Info Panel → General, off to begin with; `/winchat clock [hide|show]`) hides the
game's clock, with its time and its day and weather icons, while winchat runs, with the panel on or
off.

- The game still runs its clock, so `{grid}` and the weather can still be read for the panel.
- Turning it off, turning winchat off, zoning or unloading gives the game's clock back at once.
- It needs uihook with clock support.
- Unload the clock addon and hidecompass, which use the same part of the game's display.
- `/winchat status` reports it as Game Clock.

**Hide Compass** (Info Panel → General, off to begin with; `/winchat compass [hide|show]`) does the
same for the game's compass and its radar, through uihook's compass support. The clock is not affected
either way, and each can be hidden alone. The compass comes back in the same cases as the clock.

The game's own menus stay where the game puts them. winchat no longer moves the action menus above
the info panel (Anchor Above Info Panel was removed in 0.15.0).

## Limitations

- **The game decides when the log is drawn.** winchat never forces a closed log open, never ignores
  the game's "hide interface", and never draws over browsing and action menus. Zoning pauses it.
- If winchat cannot find the game's log, or there is too little room above it, the game's log shows
  instead, while the input bar keeps working. Turning winchat off, unloading it, or a failure to read
  the game's log also brings the game's own drawing back.
- A change of character or settings clears the kept messages.
- The windows let clicks through, except for the wheel over a log that is too full, and its
  scrollbar.
- The game's clock moves with the log, keeping its distance from it. The compass stays put.
- Clicking in the input bar does not move the text cursor or select text. The game keeps its own IME
  menus (the input method used to type Japanese and other languages). They still need testing in
  game.
- With Auto-Translate off, the game's own auto-translate menu takes the input bar back from winchat
  while it is open.
- To open the expanded log, select the log with the game's Square (window selection) button, then
  Confirm. winchat binds no button. Browsing, tabs, the wheel, Confirm (with its message menus) and
  Cancel are the game's.
- With a **Font Size** larger than the game's own row spacing, fewer rows fit in the expanded log than
  the game puts on a page. To reach the rows at the top of a page, move the cursor up with the arrows.
  A font wider than the game's can run past the right edge, where it is cut off.
- Padding and Width apply to the compact log and input bar only. There is no WinXI title over the
  expanded log's tabs.
- Without uihook's colours, the colours are close copies of the standard palette, not read from the
  game. Then colours changed in the game's data files (DATs), and your own channel colours, are not used. Unknown chat modes take the
  WinXI theme's colour.
- Named NPC speech gets `[NPC]` after the speaker, with only `NPC` in yellow.
- winchat does not shorten, group, filter or timestamp combat lines.
- Elemental symbols are written as `[fire]`, `[ice]` and so on. The game's other picture characters,
  blinking text and text that appears bit by bit are not copied.

## Settings from older versions

- **Follow Native Settings** on (or, before that, **Match Game Log Size** or **Match Game Input
  Size**) becomes Follow Game. Off becomes WinXI Skin.
- The four Replace switches of the expanded log become **Replace Expanded Log**: on if all four were
  on.
- The old **Own Color** and **Override Colours** settings are dropped.
