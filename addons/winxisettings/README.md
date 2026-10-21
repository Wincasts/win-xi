# winxisettings

The look shared by every addon that draws with `winxi` (`addons/libs/winxi`), in one window of its own,
drawn with winxi itself. It opens as it is loaded.

- `/winxi` or `/wxi` opens or closes the window

Five tabs, in this order:

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

- **Layouts**: every addon's settings kept for each screen resolution (`winxi.layouts`). It shows the
  resolution now, Switch With Resolution (on to start), Save Layout for it, and the saved layouts, each
  with Use and Remove.

Each appearance tab has a reset button for its own values. Every change is to the shared theme
(`config\addons\winxi\theme.lua`), and so reaches every addon that follows it; an addon that keeps a
theme of its own (Use Shared Theme off, in its Winxi Theme tab) is not changed.

## Layouts

A layout is a copy of every addon's `settings.lua` for every character
(`config\addons\<addon>\<name>_<server>\settings.lua`) and the shared Winxi Theme, kept in
`config\addons\winxi\layouts\<width>x<height>\`. Other files of an addon are the same at every resolution:
tCrossBar's bindings, simplelog's filters.

Each addon writes its settings back as it closes or a character logs out, so a layout is put in place
only while no character is logged in. **Use** at the title screen or character select puts it in place at
once; with a character logged in it is used the next time the game starts.

With **Switch With Resolution** on, starting the game at another resolution than last time keeps every
addon's settings as the layout for the old resolution, then uses the one kept for the new resolution,
if there is one (if not, the settings stay as they were, to be moved for it). For this winxisettings has to
be loaded as the game starts: put `/addon load winxisettings` in `scripts\default.txt`.

To try another resolution: Save Layout for this one, close the game, change the resolution and start
again. Going back to it later brings back what was saved, and the new resolution's is kept as you leave it.
