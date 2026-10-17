# Changelog

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
- Needs winxi 18 and uihook 0.5 with chat ABI 12.

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
