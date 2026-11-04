# winxi

Shared drawing for Ashita addons that render with imgui: one look, set once, used by every addon.

winxi is a library, not an addon: there is nothing to load. Nearly every addon of this project draws
its windows with it, and the look they share is set in one window, wxi's `/winxi` (see
[wxi](../../wxi/README.md)).

## Installing

An addon that uses winxi needs this folder installed alongside it, at `addons/libs/winxi`. Every addon's
zip carries a copy, so extracting the zip into your Ashita folder puts it there.

Each addon is released on its own, with its own copy of winxi, so installing one addon can put an older
winxi over the one another addon came with. Every addon that is released checks, as it loads, that the
winxi it finds is at least the one it was made with, and says so plainly if it is not:

```text
<addon> needs winxi <number> or newer, and addons/libs/winxi is <number>: install the newest release of any winxi addon.
```

The addon then does not load. Install the newest package of any winxi addon from
[DOWNLOADS.md](../../../DOWNLOADS.md), which brings the newest winxi, and load the addon again. A newer
winxi serves every older addon.

## The theme

The theme is the background, border, text and highlight colours, padding, drop shadow, the font and its
size, the outline round text over bars and the game, and the styles: window border art and its opacity,
window background, frame titles, tab style, bar texture, bar bookends and custom status icons. It is
saved in `config\addons\winxi\theme.lua` and kept in step across addons.

It is set in wxi's `/winxi` window, or in the Winxi Theme tab of an addon's own settings window, the last
tab, in its own colour. A change made there shows at once in that addon, and reaches every other addon
using winxi when the control is let go.

Every addon that uses winxi gives you the choice, with its "Use Shared Theme" checkbox: follow the shared
theme, or keep colours, padding and shadow of its own. The addon's own theme starts from the shared
theme's values, so switching the shared theme off changes nothing until something is changed.

Settings windows have colours, padding, a font and a font size of their own, set on wxi's Settings
Windows tab, so what is chosen for the game's windows does not change the window it is chosen in.

Text written over a bar, an image or the game itself has a dark edge all round it, so it can be read
whatever is behind it. Its thickness is the theme's Text Outline, one setting for every addon, and its
colour the theme's Outline Color.

Tooltips follow the shared theme's Tooltip values, set in wxi's Tooltips tab, whether or not the addon
follows the shared theme: whether they show, their delay, colours, padding, text size and width. Words go
on to another line at the Max Width.

## Settings windows

Every addon's settings window is laid out the same way, so that someone who has set one addon up knows
every other: Settings (the addon's behaviour), then the addon's own tabs, then Visibility (for an addon
with a window: Fade In And Out and the rules for hiding), then Winxi Theme last. Every setting is a row:
its name, a sentence under the name saying what it does, and its control at the right.

A settings window can always be resized. It fits its content as it changes, until a grip or an edge is
taken hold of; from then it keeps the size it is given, never bigger than the screen, with anything too
big scrolling. A double-click on a grip or an edge fits it to its content again. How a settings window
opens is set on wxi's Settings Windows tab: Minimum Width (Fit To Content, or at least so many pixels
wide), Starting Height (Fit To Content, or a height in pixels that its content scrolls within), and a
button that takes both from that window as it stands.

### Sections collapse

Every section of a menu can be collapsed: its title starts `[-]` while open and `[+]` while collapsed,
and a click on the title changes which. Which sections are collapsed is kept while the addon is loaded.
The titles are in the Sub-Category Color on wxi's Settings Windows tab.

## Fading while idle

An addon can fade its windows out while you are idle. The fade settings are each addon's own, not
shared like the theme.

Idle is standing still, unless the Moving setting is off: then moving about does not keep the windows
up, and they fade on the move too once nothing else has kept them up. What else counts as not idle is
each a setting: being engaged, having a target (a change of target brings the windows back as well),
being below full HP, resting, and a change to the party list (someone joining, leaving or changing
area).

## Arranging windows

An addon that arranges its windows this way has an Organize button in its settings window. While organizing, windows are
labelled, a grid can be shown, and dropping one window onto another links them: the dropped one is held
against the side it was dropped towards. Links are between the windows of one addon.

Every addon's settings can be kept for each screen resolution, on wxi's Layouts tab.

## Controller input

Some addons' windows can be worked with a controller (XInput, or DirectInput by make). Only the buttons
an addon uses are taken, and only while its window has reason to take them: they are kept from the game,
and the sticks and every other button still reach it. A button already down when the addon takes the
controller is not counted as a press. The window the buttons will act in has a bright line drawn around
its edge, and under it the buttons it uses, each with a word for what it does.

Buttons are named as an Xbox controller's are. XInput is the default. For a DirectInput controller,
the addon's settings say which make it is (PlayStation, Switch or Stadia), and its buttons are read as
the Xbox buttons in the same positions. Automatic follows the kind the game reads, its Enable XInput
setting as the launcher writes it, a DirectInput controller taken for a PlayStation one; where that
cannot be read, the kind heard pressing buttons. Buttons are shown as they look on the kind in use: A on
an Xbox controller, Cross on a PlayStation one, B on a Switch Pro.

## Menu sounds

Menus can make small sounds as they are worked (opening, moving, changing tabs, confirming, going back
and errors). They are off until an addon turns them on. The ones that come with winxi are plain tones,
not the game's. Each sound is a wav file called by its name: `sounds\move.wav` in an addon's own folder
is used before the one in `libs\winxi\sounds`, so an addon may bring its own. Ashita plays one sound at
a time, at the volume of the file.

## Game status icons and Pivot

Individual game status icons, the game-only sheet, and the mixed custom/game sheet all load their game artwork through the same Pivot-aware DAT reader. Pivot chooses the winning overlay in its configured order; winxi does not guess overlay folders or reorder them. The installed client's FTABLE mapping selects the status DAT (file id 87, normally `ROM/119/57.DAT`). If the DAT cannot be opened or an icon is unsupported/malformed, that icon falls back to Ashita's resource-manager bitmap.

Pivot's `redirect_fopens=true` setting must be enabled for this reader, as it must for winxi's map/cursor reader. Explicit custom status sets still take precedence when enabled: turn custom status icons off to use only game/Pivot artwork. DATs and textures are cached per addon; after changing Pivot overlays, reload the affected addons to rebuild their icons and sheets.

## Custom icons

A status's icon can be the game's own or one of a set of custom icons, chosen under **Custom Icons**
(wxi's Icons tab, under HQ Icons; Styles in an addon's own Winxi Theme tab): **None** for the
game's own, or a set. A set is a folder of `libs\winxi\statusicons` holding `<status number>.png`
for each status it has an icon for (`1.png` for Poison, `33.png` for Haste, and so on); a status the
set has no file for keeps the game's icon. **FFXIV**, the `ffxiv` folder, is the set winxi comes with.

To add a set, make a folder beside `ffxiv` (a name with no dot in it), put the icons in it, and open
the list again: it is found then, no reload needed. The icons are drawn whole, as wide for how tall as
the pictures are, so square ones stay square; keep every icon in a set the same size. A folder may
also hold a `set.lua` to give the set a name in the list, or to say that each icon takes only part of
its picture's width, as ffxiv's do (48 by 64 in the middle of a square of 64):

```lua
return { name = 'FFXIV', left = 8 / 64, right = 56 / 64 };
```

For the winplates addon, which draws statuses from a single picture, a set is put on one sheet a few icons
a frame the first time it is wanted; ffxiv's comes ready made, as `sheet.png`.

## Game data

winxi carries what is known of the game that the client does not say (each area's monsters, items,
spells, abilities, quests and the like), made from the Phoenix server's data, plus an auto-translate
dictionary made from the installed client. Which server's data is used is chosen in wxi's Server Data
tab.
