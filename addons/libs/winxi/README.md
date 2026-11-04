# winxi

A shared library that almost every addon in this project uses to draw its windows. It gives them all
one look, which you set once. winxi is not an addon: there is nothing to load. You set the shared look
in one window, wxi's `/winxi` (see [wxi](../../wxi/README.md)).

## Why you need it

- An addon you use needs it: each winxi addon needs this folder to run, and its download includes a
  copy.
- It gives all those addons the same look, which you set once in wxi.
- Every winxi addon's settings window is laid out the same way, so once you know one, you know them
  all.

## Installing

An addon that uses winxi needs this folder installed next to it, at `addons/libs/winxi`. Every addon's
zip includes a copy, so extracting the zip into your Ashita folder puts it there.

Each addon is released on its own, with its own copy of winxi. So installing one addon can put an older
winxi over the newer one another addon came with. Each released addon checks, when it loads, that the
winxi it finds is at least the version it was made with. If not, it says so plainly:

```text
<addon> needs winxi <number> or newer, and addons/libs/winxi is <number>: install the newest release of any winxi addon.
```

The addon then does not load. To fix it, install the newest download of any winxi addon from
[DOWNLOADS.md](../../../DOWNLOADS.md). It brings the newest winxi. Then load the addon again. A newer
winxi works with every older addon.

## The theme

The theme is the shared look:

- the background, border, text and highlight colours;
- padding (the space inside a window's edge), drop shadow, and the font and its size;
- the outline round text written over bars and over the game;
- the styles: window border art and its opacity, window background, frame titles, tab style, bar
  texture, bar bookends (the end pieces of a bar), and custom status icons.

It is saved in `config\addons\winxi\theme.lua`, and every addon uses the same copy.

### Where to set it

You set it in wxi's `/winxi` window, or in the **Winxi Theme** tab of an addon's own settings window.
That is the last tab, in its own colour. A change shows at once in that addon. It reaches every other
winxi addon when you let go of the control.

### An addon's own theme

Every winxi addon has a **Use Shared Theme** checkbox. With it on, the addon follows the shared theme.
With it off, the addon keeps its own colours, padding and shadow. The addon's own theme starts as a
copy of the shared one, so turning the shared theme off changes nothing until you change something.

### Settings windows

Settings windows have their own colours, padding, font and font size, set on wxi's **Settings
Windows** tab. So what you choose for the game's windows does not change the window you choose it in.

### Text outline

Text written over a bar, a picture or the game itself has a dark edge all round it, so you can read it
whatever is behind it. Its thickness is the theme's **Text Outline**, one setting for every addon. Its
colour is the theme's **Outline Color**.

### Tooltips

Tooltips always follow the shared theme's tooltip settings, set in wxi's **Tooltips** tab, whether or
not the addon follows the shared theme. These settings are: whether tooltips show, their delay,
colours, padding, text size and width. Words go on to a new line at the **Max Width**.

## Settings windows

Every addon's settings window is laid out the same way, so if you have set up one addon you know them
all. The tabs come in this order:

1. **Settings**: what the addon does. (Some addons give this tab another name, such as General.)
2. The addon's own tabs.
3. **Visibility** (for an addon with a window on screen): **Fade In And Out**, and the rules for
   hiding it.
4. **Winxi Theme**, last.

Every setting is a row: its name, a sentence under the name saying what it does, and its control on
the right.

### Size

You can always resize a settings window.

- It fits its contents as they change, until you take hold of an edge or a corner. From then on it
  keeps the size you give it. It is never bigger than the screen. Anything that does not fit scrolls.
- Double-click an edge or a corner to fit it to its contents again.
- How a settings window opens is set on wxi's **Settings Windows** tab:
  - **Minimum Width**: Fit To Content, or at least this many pixels wide;
  - **Starting Height**: Fit To Content, or a height in pixels, with the contents scrolling inside;
  - a button (**Use This Window's Size**) that takes both from that window as it is now.

### Sections fold up

Every section of a menu can be folded up. Its title starts with `[-]` while open and `[+]` while
folded. Click the title to change it. Which sections are folded is remembered while the addon is
loaded. The titles are in the **Sub-Category Color** set on wxi's Settings Windows tab.

## Fading while idle

An addon can fade its windows out while you are idle. Each addon has its own fade settings; they are
not shared like the theme.

- Idle means standing still. If **Stay Visible While Moving** is off, moving about does not keep the
  windows showing, so they fade while you move too, unless something else keeps them up.
- Other things that count as not idle each have their own setting:
  - being engaged in battle (**Stay Visible While Engaged**);
  - having a target (**Stay Visible While Targeting**). Changing target brings the windows back too;
  - being below full HP (**Stay Visible While Missing HP**);
  - resting (**Stay Visible While Healing**);
  - a change to the party list: someone joining, leaving or changing area (**Show On Party Changes**).

## Arranging windows

An addon that arranges its windows this way has an **Organize** button in its settings window. While
you organize:

- each window is labelled, and a grid can be shown;
- dropping one window onto another links them. The dropped window is held against the side it was
  dropped towards.
- Links are only between windows of the same addon.

You can keep every addon's settings for each screen resolution, on wxi's **Layouts** tab.

## Controller input

Some addons' windows can be used with a controller (XInput, or DirectInput, by make).

- An addon takes only the buttons it uses, and only while its window needs them. Those buttons do not
  reach the game. The sticks and every other button still reach the game.
- A button that is already held down when the addon takes the controller does not count as a press.
- The window the buttons will act in has a bright line around its edge. Under it are the buttons it
  uses, each with a word for what it does.

Buttons are named as on an Xbox controller. XInput is the default.

- For a DirectInput controller, the addon's settings say which make it is (PlayStation, Switch or
  Stadia). Its buttons are read as the Xbox buttons in the same positions.
- **Automatic** follows the kind of controller the game uses, from its **Enable XInput** setting as
  the launcher writes it. A DirectInput controller is taken to be a PlayStation one. Where that
  setting cannot be read, it uses the kind of controller it hears pressing buttons.
- Buttons are shown as they look on the controller in use: A on an Xbox controller, Cross on a
  PlayStation one, B on a Switch Pro.

## Menu sounds

Menus can make small sounds as you use them: opening, moving, changing tabs, confirming, going back,
and errors.

- They are off until an addon turns them on.
- The sounds that come with winxi are plain tones, not the game's.
- Each sound is a WAV file named after what it is for. `sounds\move.wav` in an addon's own folder is
  used before the one in `libs\winxi\sounds`, so an addon can bring its own.
- Ashita plays one sound at a time, at the volume of the file.

## Game status icons and Pivot

When winxi shows the game's own status icons, it reads them from the game's files. It does this in a
way that works with **Pivot** (an Ashita plugin that lets you replace game files with your own). Pivot
decides which replacement wins, in the order you set it. winxi does not guess or reorder them. If the
file cannot be opened, or an icon cannot be read, that icon falls back to the one Ashita provides.

- Pivot's `redirect_fopens=true` setting must be on for this, as it must for winxi's map and cursor
  pictures.
- If you choose custom status icons, they still win while they are on. Turn custom status icons off to
  use only the game's (or Pivot's) pictures.
- Each addon keeps the icons it has read. After you change Pivot's replacements, reload the addons you
  use so they read their icons again.

## Custom icons

A status's icon can be the game's own, or one from a set of custom icons. You choose under **Custom
Icons**: on wxi's **Icons** tab, or under Styles in an addon's own Winxi Theme tab. Choose **None** for
the game's own icons, or choose a set.

- A set is a folder in `libs\winxi\statusicons`. It holds a `<status number>.png` for each status it
  has an icon for: `1.png` for Poison, `33.png` for Haste, and so on.
- A status the set has no file for keeps the game's icon.
- **FFXIV** (the `ffxiv` folder) is the set that comes with winxi.

To add a set:

1. Make a folder next to `ffxiv`. Its name must not have a dot in it.
2. Put the icons in it. Keep every icon in a set the same size.
3. Open the list again. The set is found then; no reload is needed.

The icons are drawn whole, keeping their shape, so square pictures stay square. A folder can also have
a `set.lua` file, to give the set a name in the list, or to say that each icon uses only part of its
picture's width. ffxiv's icons do this: they are 48 by 64 in the middle of a 64 by 64 square:

```lua
return { name = 'FFXIV', left = 8 / 64, right = 56 / 64 };
```

The winplates addon draws statuses from one big picture. For it, a set is put onto one sheet, a few
icons each frame, the first time it is needed. ffxiv's comes ready made, as `sheet.png`.

## Game data

winxi carries game information that the game itself does not give, such as each area's monsters,
items, spells, abilities and quests. It is made from the Phoenix server's data. It also has an
auto-translate dictionary, made from the game you have installed. You choose which server's data is
used on wxi's **Server Data** tab.
