# Changelog

## 0.11.3

- Timestamps, an option in the Chatbox section (on to begin with) and `/chatbox timestamps [on|off]`:
  the time in front of each line as SimpleLog's Timestamps or Ashita's timestamp addon writes it,
  chatbox adding none of its own. Off, the stamps are hidden in the compact log, Window 2 and the
  expanded log, each line laid out and coloured without its own; the messages keep them (every
  stamped line of a joined message), so turning it on shows them again at once, the game's history
  read at start among them. Kept for each character and applied as settings load.
- `/chatbox bytes` reports one line: the sample is held for the whole report, where before each line
  the report said went through text_in itself and took the sample's place, so the stages came from
  different lines of the report. It says whether the line is an addon's own and whether a timestamp
  stands in front of it, and when none does, that an addon loaded after chatbox never reaches it.
  The README says an alphabetical `scripts/default.txt` loads chatbox before simplelog.

## 0.11.2

- A second icon set for the info panel, Classic (Icons tab, Icon Set): days and weather drawn after the
  game's own, its flat mottled day balls and its soft weather sprites (a pale drop, a teal funnel, a purple
  vortex, a periwinkle sphere, a white glow, a fireball, a tilted slab, a violet bolt), in colours sampled
  from them, with a sun in the same manner for a clear sky. Drawn afresh by tools/generate_classic_icons.py;
  none of the game's pixels are used. The sets are listed in Title Case.
- The info panel's Map Grid stays while the game hides its clock (fishing, events, its HUD hidden): the
  grid is then worked out by the game's own grid function, the one its clock asks, found through the
  clock's call to it, so it is the clock's grid, there or not as the zone has one. Time never depended on
  the clock and stays as ever.
- Lighter each frame: a row's coloured parts are measured once and kept with it, not every frame (the
  game's colours still looked up each time); the expanded log measures only its cursor's row and its tab
  names once in their font; the Linkshell title reads the pearl from the inventory once a second, or as a
  pearl is equipped, not every frame; the expanded status line is made only as it changes; and a mouse
  message chatbox would never take (a move without a drag, a release without a press) is let by before
  the game's state is read. The info panel measures its words once each time its fields are read (four
  times a second), not every frame; where its fields cannot be read it tries again then, not every frame;
  and the Icon Set list reads its folders at most once a second while it is open.
- The attached panel moves under chat: it takes the bottom of the logs' place and every drawn log
  (both, stacked or side by side) is lifted by its height to sit wholly above it. The lowest log owns
  it; Window 2 only while it is the one shown. No room to lift chat: no panel that frame.
- While typing, the panel keeps the bottom: the input is lifted onto it and still pushes the logs up,
  which move only as far as clears the lifted input.
- Anchor (Layout tab): Top or Bottom, for attached panels, Window 2's with them. Bottom (the
  default) is the above; Top is 0.11.1's, flush over the upper log with chat, input and menus
  as the game has them. Attach Under Chat is now Attach To Chat.
- Opening the input no longer flashes the game's own bar under the panel for a frame: while closed,
  the input slot stays armed with an empty replacement (it acts only while the game draws its input),
  so the opening frame shows nothing there and chatbox's bar follows in its place. A failed input
  read still gives the game's bar back.
- Native Menus → Anchor Above Chat: menus anchor over the top of the lifted chat. A custom-position
  panel leaves chat in place and menus still anchor above the panel.
- Window 2 Panel (General, off to start): a second panel under Window 2 while the game shows the
  two log windows side by side, with its own slots, layout and icon placement in a new Window 2
  subtab; text and icon look follow the first. Attached panels share the taller one's height, so
  both logs keep one bottom. Stacked or single-window chat shows the one panel as before.
- Hide Game Clock (General, off to start) and `/chatbox clock [hide|show]`: hides the game's clock
  and its day and weather icons through uihook's clock slot, renewed each frame, panel on or off.
  The game's clock is back the moment it is turned off, chatbox stops, zoning or unload. The grid
  and weather the panel reads keep working. Unload clock and hidecompass, which use the same object.
- Hide Compass (General, off to start) and `/chatbox compass [hide|show]`: the same for the game's
  compass and radar through uihook's compass slot, independent of the clock.
- Replace Cursor (Expanded, on to start): the expanded log mirrored whole. With Replace Tabs,
  Replace Scrollbar and Replace Text on, uihook (0.6) leaves nothing of the game's full log drawn, its
  row light, cursor and marked rows' sprites included, and chatbox draws them from the rows uihook
  measures: the cursor's row lit across the log in the Highlight Color (brighter while held), a
  marked row faintly, the cursor after its text. The game still moves the cursor, follows the mouse,
  scrolls and takes Confirm. Off, or with an older uihook, the game's own, tinted, as before.
- The expanded log lights the row the game highlights: uihook measures the game's row-selection art as
  it is drawn (hidden or not) and flags each row under it, and with Replace Cursor chatbox lights those
  rows in the Highlight Color, following the keyboard, controller and mouse as the game does. Without
  the flag (an older uihook), the cursor's row as before.
- The game's own history before chatbox's: as it starts (and after a reset or a new character)
  chatbox reads the game's first log window's history once through uihook (winxi.nativehistory, the
  last 100 lines, each decoded to the bytes the game was given with its colour codes and whole mode
  word) and puts those lines before its own messages, within its 256; the newest it already has are
  left out, and NPC replays as text_in leaves them out. The game keeps a message as the lines it
  wrapped it into, with the same header on each (seen live: flags and +38 alike on a message's first
  line and the rest); with timestamps on (most lines starting with one), a line with none is joined to
  the one before it in the same mode, so each message is whole again. `/chatbox status` says how many.
- The expanded log's tabs as WinXI buttons, each whole: the game draws a tab not chosen only its
  first 30 units wide; these are side by side from where its strip starts, all as wide as the longest
  name needs (narrowed only to fit the log), in a game window's button colour, the Highlight Color for
  the tab the game has chosen. Choosing a tab (Square, the arrows) is still the game's; its mouse
  clicks on tabs stay at its own places, so there is no mouse light.
- The tabs' order and names from the client's own table (032F8700, pairs of a filter and its tab's
  art): Window, Window 2 (only with the game's second log window setting on), Say, Tell, Party,
  Linkshell 1, Linkshell 2, Assist (E), Assist (J), Unity, Shout. Each tab is named by its art through
  that pairing; chatbox had read the art as a filter, and had Assist (J) before Assist (E). The
  buttons say Win 1, Win 2, Say, Tell, Party, LS 1, LS 2, A (J), A (E), Unity and Shout, in the
  chat's font at 85% of Font Size.
- The expanded log's scrollbar as the compact log's: the thin thumb alone, no track, inside the log's
  right edge rather than as wide as the game's bar, brighter while the mouse is on it or on the
  game's bar (which the game still drags and pages).
- The expanded log's window as the compact log's: its padding, Font Size and the theme's shadow (it
  had none of the padding and no shadow).
- Expanded Height (Expanded, 75% to start, 25 to 100): the expanded log reaches that share of the way
  up the screen and no higher (nor above the game's own window), the tabs standing on its top and the
  scrollbar within it; the game's rows above it are cut off. The game's rows, cursor and hit-tests
  are otherwise its own. 100% is the game's window.
- The expanded log's tab buttons a little bigger: four pixels taller (upward, their foot on the log's
  frame) and ten pixels either side of the longest name.
- Expand In Place (Expanded, on to start): the game's expanded log opens where the chat log stands,
  its bottom-left on the first log's, asked of uihook from the compact log so the game lays it out
  there from its first frame; its rows, hover, Confirm and scrolling move with it. The info panel is
  hidden while the log is expanded, so with Anchor Bottom the log takes the panel's place too.
- The expanded log's text laid out as the compact log's: from the log's left by Left Padding, at Font
  Size, Font Size + 2 apart, the newest ending at the Bottom Padding, in the log's Default Text colour
  when it has one. It no longer stands on the game's own rows (16 of its units apart, fixed in its
  drawer's code): which rows there are, which the game highlights and where its cursor is are still
  the game's, by their order, and when its chosen row is past what fits the view moves to keep it in
  sight. The game's mouse hover and clicks stay at its own rows' places.

## 0.11.1

- Panel attaches flush to chat again, without the extra half-font-height gap. Parent border/title
  draw after the attachment so the channel label remains legible at their shared seam.
- Native Menus → Anchor above panel (General, default on). Uihook 0.6 moves the registered native
  command/magic/ability/item family through its own layout target before Window::Update, retaining
  native frame/row/cursor geometry rather than translating only rendering. Menu ABI 1; chat ABI 13
  is unchanged. Unknown clients/menus and oversized lists remain native. An event's choices (an NPC's
  Yes/No) move with them, so they no longer cover the panel.
- Native positions restored on opt-out, expired/failed capture, expanded history, zoning, unload;
  live owner/header checks and field/call signatures gate writes. `/uihook menus` diagnostics.
- Needs **Winxi 22**; older DLLs still render the panel but cannot anchor menus. Live input/artwork
  validation is still required. Never overwrite a loaded DLL.

## 0.11.0

- Optional Info Panel tab with General/Layout/Data/Text/Icons controls, three weighted/aligned data
  slots, zone/time/EXP/weather fields, inline/movable icons, styled pipes and Winxi frame/shadow.
- Panel uses the upper compact chat window's existing capture, never the native clock slot. Works
  while action menus hide the clock; log geometry, scrolling and published rectangles are unchanged.
- Upper stacked log owns one panel; horizontal logs keep primary, and split-only chat is supported.
  Expanded chat, zero-line logs, zoning and chatbox off do not leave floating panel draws behind.
- `/chatbox panel [on|off|reset]`; opt-in per character. Clock settings/addon are not required or
  auto-imported. Native menus are not moved. The game's clock/compass are left untouched.
- Shared data/layout/icon modules live in Winxi; needs **winxi 21**. No new plugin ABI/DLL required.

## 0.10.0

- The game's second log window mirrored. With Log Window 2 on in the game's settings, a second WinXI
  box stands where the game puts its second window: over the first in the game's vertical layout (the
  first's width, the game's height for it) or beside it in the horizontal (the game's width and gap
  from the first, the first's bottom, lifting with it over the input); as many rows as fit at Font
  Size, or ten with Match Game Log Size off; titled Window 2. Each box shows
  the messages the game's Log Window settings route to its window, as uihook reads the game's own
  routing (the first shows everything while the second is off, as the game does); each scrolls on
  its own with the wheel and its scrollbar; the focus light and cursor go to the window the game's
  focus is on. With one window, as before: the game's second log is hidden under the first.
  `/chatbox status` says what the second window is doing.
- Each box has as many rows as the game's window shows at the moment, with Match Game Log Size on:
  the game grows its window a row for each message and shrinks it to its fewest lines while none
  come, and the box follows, no shorter than the game's window and tall enough for its rows at Font
  Size, so a message to a window at 0 lines brings its box back one row tall, and more grow it. A
  window the game has at 0 lines shows nothing: no box in its place (and nothing of the game's
  either), the other window still drawn, the input bar still working. With a uihook that does not
  say the lines, as many rows as fit the game's window, as before.
- The game's own chat colours, as you have them configured, in place of the approximations: each
  line's body in the colour the game draws its chat mode in (SimpleLog's and other addons' lines too,
  whatever mode they are sent with), and the inline colour codes the colours the game gives them. A
  mode the game has no colour for is white, as the game draws it. Without uihook's reading, the
  approximations as before.
- Two boxes no longer undo each other's layout every frame. The log's caches held one box's wrapping,
  row counts and rows, so with the second window shown each frame laid the history out again, and
  with the windows side by side (two widths) re-measured every message's wrapping: thousands of text
  measurements a frame. They hold both boxes now, and a frame with no new message measures nothing.
- Needs winxi 19 and uihook 0.5 with chat ABI 13.

## 0.9.0

- The expanded log's text in the chat's font. uihook decodes the game's rows of text as it draws
  them (its glyph words back to the bytes it was given, colour codes and all) and measures each
  row; asked, it leaves the game's text undrawn, and the addon draws each row where the game drew
  it: in the chat's **Font**, at **Font Size** or the game's row height if that is less, centred in
  the row, in its message's chat-mode colour with the game's inline colours kept, auto-translate
  brackets as shapes; the game's cursor after the cursor row's text. The rows, their wrapping,
  the cursor, hovering, Confirm and its menus, the wheel and the scrollbar are still the game's.
  **Replace Text** (experimental, on to begin with) in the Expanded section; off, or without a
  fresh set of rows from uihook, the game's own font is drawn as before. Each row is decoded once
  and kept by its bytes.
- The game's other pictographs (EF 29 to EF 4D) show nothing, in place of a stray character.
- Confirm on a player's line opens the game's action menu over the expanded log, which keeps its
  WinXI look under it instead of showing the game's own; `/chatbox status` says a menu is open.
- Needs winxi 16 and uihook 0.4 with chat ABI 10.

## 0.8.0

- The expanded log's tabs and scrollbar in WinXI's look, where the game's are. uihook measures the
  game's tab strip and scrollbar as it draws them and, asked, leaves them undrawn; the addon draws
  each tab in its place, in the game's order with the chosen one last, on top, where they overlap:
  a square-cornered box, as winxi's windows are, the background colour, the Highlight Color over it
  (solid for the chosen one, faint for the rest), the theme's tab style and an edge in the border
  colour, with the channel's name in the chat's font with winxi's dark edge centred in what is left
  uncovered; and a track and thumb in the game's bar as the compact log's. Choosing a tab, by Square or the mouse, and scrolling are still the game's; the
  rows, selection and cursor are drawn by the game as before. **Replace Tabs** and **Replace
  Scrollbar** (on to begin with) in a new **Expanded** section; off, the game's own are drawn,
  tinted, as in 0.7. Without a fresh place from uihook the game's are left drawn.
- Needs winxi 15 and uihook 0.3 with chat ABI 9.

## 0.7.0

- A WinXI-styled chat log the game still drives. The compact log takes the native primary log's
  place and size (Match Game Log Size, on to begin with), as many rows as fit at Font Size, in the
  theme's font or one of `C:\Windows\Fonts`. Rows come from `text_in`, unblocked and unrewritten,
  with native mode colours and SimpleLog's inline colours kept; the last 256 are kept in memory
  only. Titled with the channel from `/cm`, or the one a line is being typed in.
- The input bar skins the game's own editor: typing, history, commands, IME and auto-translate stay
  the game's. Match Game Input Size takes the native input's width, height and place.
- Expanded mode is a WinXI frame around the game's own full log: its tabs, rows, cursor and
  scrollbar are the game's, at their own places, tinted with the theme's or the log's colours.
  Square/window selection, Confirm and Cancel stay native.
- The game's clock and its icons follow the top of the log, at the game's spacing.
- Settings in five sections, each folding away: Chatbox, Size, Text (Font, Font Size), Padding
  (each side, 3 pixels to begin with) and Window Colors (the log's and the input bar's own
  background, border, text and title colours).
- Needs winxi 14 and uihook with chat ABI 8.
