# wxi

One settings window for the look of every addon that draws its windows with the `winxi` library
(`addons/libs/winxi`). You set colours, fonts, borders, tooltips and icons here once, and every
winxi addon uses them. The window opens when the addon loads.

## Why use it

- You set the look of all your winxi addons in one place, instead of in each addon.
- You can keep a different set of addon settings for each screen resolution, and switch between them.
- You can choose which server's game data the winxi addons read.

This addon was called winxisettings before. Load `wxi` in its place, and remove the old
`addons\winxisettings` folder.

## Opening the window

- `/winxi` or `/wxi` opens or closes the window.

## The tabs

There are six tabs, in this order:

| Tab | What you set there |
|---|---|
| **Game Windows** | The windows on the game screen (see below). |
| **Icons** | Which status icons to use. |
| **Tooltips** | Every tooltip, in every addon. |
| **Settings Windows** | Every addon's settings windows. |
| **Layouts** | Addon settings kept for each screen resolution. |
| **Server Data** | Which server's game data every winxi addon reads. |

### Game Windows

The windows on the game screen. Here you set:

- their background, border, text and highlight colours;
- padding (the space inside a window's edge), drop shadow, font and font size;
- the text outline and its colour. The text outline is the dark edge round text written over a bar or
  over the game, in every addon;
- the styles: window border and background, border opacity, frame titles (style, colour, all caps,
  font, size, position and shadow), bar texture and bar bookends (the end pieces of a bar).

### Icons

Under the **Icons** section, **Custom Icons** chooses the status icons. Choose **None** for the
game's own icons, or choose a set of custom icons. Each set is a folder in `libs\winxi\statusicons`.
**FFXIV** is the set you start with. Add a folder of your own and it is listed too. In an addon's own
Winxi Theme tab, this setting is under Styles.

### Tooltips

These settings apply to every tooltip drawn with `winxi.tooltip`, in every addon:

- **Show Tooltips**, and the delay before a tooltip shows;
- background, border and text colours, padding, max width and font size;
- a sample tooltip to hover over.

Tooltips always use the shared theme's values, even in an addon that keeps a theme of its own.

### Settings Windows

Every addon's settings windows. They are kept apart from the windows on the game screen. So what you
change there does not change the window you are changing it in. Here you set:

- background, border, text and highlight colours;
- **Sub-Category Color**: the colour of the section titles that fold open and shut with [-] and [+]
  (orange to start);
- the colour of the Winxi Theme tab;
- padding, font and font size;
- how big a settings window is when it opens (**Minimum Width** and **Starting Height**).

### Layouts

Every addon's settings, kept for each screen resolution. The tab shows:

- the resolution you are using now;
- **Switch With Resolution** (on to start);
- **Save Layout**, to save a layout for this resolution;
- the saved layouts, each with **Use** and **Remove**.

See [How layouts work](#how-layouts-work) below.

### Server Data

Choose which server's data every winxi addon reads: its monsters, spells, statuses and rules. The tab
also shows what the data was made from, and when.

## Resetting and sharing

Each appearance tab has a reset button for its own values.

Every change goes to the shared theme, saved in `config\addons\winxi\theme.lua`. So it reaches every
addon that follows the shared theme. An addon that keeps a theme of its own is not changed. (That is
an addon with **Use Shared Theme** turned off, in its Winxi Theme tab.)

## How layouts work

A layout is a copy of:

- every addon's `settings.lua` for every character
  (`config\addons\<addon>\<name>_<server>\settings.lua`);
- the shared Winxi Theme.

It is kept in `config\addons\winxi\layouts\<width>x<height>\`. An addon's other files are the same at
every resolution, for example tCrossBar's bindings and simplelog's filters.

Each addon saves its settings when it closes or when a character logs out. So a layout can only be put
in place while no character is logged in:

- **Use** at the title screen or character select puts the layout in place at once.
- **Use** with a character logged in puts it in place the next time the game starts.

With **Switch With Resolution** on, starting the game at a different resolution from last time does
two things:

1. It saves every addon's settings as the layout for the old resolution.
2. It uses the layout saved for the new resolution, if there is one. If there is none, your settings
   stay as they were, so you can move your windows to suit the new resolution.

For this to work, wxi must be loaded when the game starts. Put `/addon load wxi` in
`scripts\default.txt`.

To try another resolution:

1. Press **Save Layout** for this resolution.
2. Close the game, change the resolution and start the game again.

When you go back to the first resolution later, the settings you saved come back. The new
resolution's layout is saved as you leave it.
