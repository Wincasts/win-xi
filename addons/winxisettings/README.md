# winxisettings

One window for the look shared by every addon that draws with `winxi` (`addons/libs/winxi`). The
window is drawn with winxi itself. It opens when the addon loads.

- `/winxi` or `/wxi` opens or closes the window

There are five tabs, in this order:

- **Game Windows**: the windows on the game screen. Here you set their background, border, text and
  highlight colours, padding, drop shadow, font and font size. You also set the text outline (the dark
  edge round text written over a bar or the game, in every addon) and its colour. And the styles:
  window border and background, border opacity, frame titles (style, colour, all caps, font, size,
  position and shadow), bar texture and bar bookends.
- **Icons**: under HQ Icons, Custom Icons. Choose None for the game's own status icons, or a set of
  custom ones. Each set is a folder in `libs\winxi\statusicons` (FFXIV to start; add a folder of your
  own and it is listed). In an addon's own Winxi Theme tab, this stays under Styles.
- **Tooltips**: every tooltip drawn with `winxi.tooltip`, in every addon. Show Tooltips, the delay
  before one shows, their background, border and text colours, padding, max width and font size, and a
  sample to hover over. These are always the shared theme's, even in an addon that keeps a theme of
  its own.
- **Settings Windows**: every addon's settings windows. These are kept apart from the game screen's
  windows, so what you set there does not change the window you set it in. Here you set their
  background, border, text and highlight colours, the Sub-Category Color of the sections' [-]/[+]
  titles (orange to start), the Winxi Theme tab's colour, padding, font and font size.

- **Layouts**: every addon's settings, kept for each screen resolution (`winxi.layouts`). It shows the
  resolution now, Switch With Resolution (on to start), Save Layout for it, and the saved layouts, each
  with Use and Remove.

Each appearance tab has a reset button for its own values. Every change goes to the shared theme
(`config\addons\winxi\theme.lua`), so it reaches every addon that follows it. An addon that keeps a
theme of its own (Use Shared Theme off, in its Winxi Theme tab) is not changed.

## Layouts

A layout is a copy of every addon's `settings.lua` for every character
(`config\addons\<addon>\<name>_<server>\settings.lua`) and the shared Winxi Theme. It is kept in
`config\addons\winxi\layouts\<width>x<height>\`. An addon's other files are the same at every
resolution: tCrossBar's bindings, simplelog's filters.

Each addon writes its settings back as it closes or as a character logs out. So a layout is put in
place only while no character is logged in. **Use** at the title screen or character select puts it in
place at once. With a character logged in, it is used the next time the game starts.

With **Switch With Resolution** on, starting the game at a different resolution than last time does
two things. It keeps every addon's settings as the layout for the old resolution. Then it uses the
layout kept for the new resolution, if there is one. If there is none, the settings stay as they were,
so you can move them for it. For this to work, winxisettings has to be loaded as the game starts: put
`/addon load winxisettings` in `scripts\default.txt`.

To try another resolution: Save Layout for this one, close the game, change the resolution and start
again. When you go back to it later, what was saved comes back. The new resolution's layout is kept as
you leave it.
