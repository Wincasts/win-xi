# winxisettings

The look shared by every addon that draws with `winxi` (`addons/libs/winxi`), in one window of its own,
drawn with winxi itself. It opens as it is loaded.

- `/winxi` or `/wxi` opens or closes the window

Four tabs, in this order:

- **Game Windows**: the windows on the game screen. Their background, border, text and highlight
  colours, padding, drop shadow, font and font size, the text outline (the dark edge round text written
  over a bar or the game, in every addon) and its colour, and the styles: window border and background,
  border opacity, frame titles (style, colour, all caps, font, size, position and shadow), bar texture and bar
  bookends.
- **Icons**: under HQ Icons, Custom Icons: None for the game's own status icons, or a set of custom ones,
  each a folder of `libs\winxi\statusicons` (FFXIV to start; add a folder of your own and it is listed).
  In an addon's own Winxi Theme tab this stays under Styles.
- **Tooltips**: every tooltip drawn with `winxi.tooltip`, in every addon. Show Tooltips, the delay
  before one shows, their background, border and text colours, padding, max width and font size, and a
  sample to hover. These are always the shared theme's, even in an addon that keeps a theme of its own.
- **Settings Windows**: every addon's settings windows, kept apart from the game screen's so that what
  is set there does not change the window it is set in. Their background, border, text and highlight
  colours, the Sub-Category Color of the sections' [-]/[+] titles (orange to start), the Winxi Theme tab's colour, padding, font and font size.

Each tab has a reset button for its own values. Every change is to the shared theme
(`config\addons\winxi\theme.lua`), and so reaches every addon that follows it; an addon that keeps a
theme of its own (Use Shared Theme off, in its Winxi Theme tab) is not changed.
