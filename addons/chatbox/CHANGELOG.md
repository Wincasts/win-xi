# Changelog

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
