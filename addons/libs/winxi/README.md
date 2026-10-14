# winxi

Shared drawing for Ashita addons that render with imgui: one look, set once, used by every addon.

Lives in `addons/libs/winxi/`, so any addon can `require('winxi.<module>')`.

| Module | What it gives |
|---|---|
| `winxi.theme` | The shared theme (background, border, text, chosen-tab highlight and Winxi Theme tab colours, padding, drop shadow, the base font and its size, and the styles: window border art and its opacity, window background, bar texture, bar bookends, custom status icons), saved in `config\addons\winxi\theme.lua` and kept in step across addons; or an addon's own |
| `winxi.style` | Puts the theme on imgui's style stack around a window: `PushPlain` (text and icons) or `PushFull` (controls), then `Pop` |
| `winxi.window` | A themed window in one call: `window.Plain` / `window.Full` |
| `winxi.shadow` | The drop shadow, drawn inside a window |
| `winxi.text` | Text with a dark edge all round it: how anything written over a bar, an image or the game itself is written |
| `winxi.fade` | Fading an addon's windows out while the player is idle, from settings the addon keeps (`widgets.Fade` draws their controls) |
| `winxi.organize` | Arranging an addon's windows: an Organize button, labels, an alignment grid, and linking one window against another |
| `winxi.controller` | Working an addon's windows with a controller (XInput, or DirectInput by make): taking button presses, a highlight that moves over things drawn in rows, and a menu of choices |
| `winxi.anchor` | "Grow from": which corner of a self-sizing window stays put |
| `winxi.widgets` | Ready-made settings controls: the theme with its "Use Shared Theme" checkbox (`Appearance`), the Winxi Theme tab that holds it (`BeginThemeTab`), a corner picker (`GrowFrom`), the fade settings (`Fade`) and the rules for hiding (`Hide`) |
| `winxi.sound` | The small sounds a menu makes, off until an addon turns them on |
| `winxi.game` | What is asked of the game itself: the menu on top, whether the map is open or an event running, bag access, and the rules for when windows hide |
| `winxi.packets` | The packets addons send and read, set out once |
| `winxi.debuffs` | Which statuses are on each enemy (or anyone) and for how long yet, worked out from what the server says took hold and wore off; durations from `winxi.debuff_durations`, made by `tools/build_debuff_durations.py` from the server's scripts |
| `winxi.nameplates` | The names the game draws over characters' heads, from the `namehook` plugin: what each is over, where it is on screen, and showing and hiding them by category or one by one |
| `winxi.fonts` | The theme's font: a `.ttf` of `C:\Windows\Fonts` (or imgui's own) and a size (or the base size), pushed around every window `winxi.window` draws. An addon drawing its own windows calls `Push()` before `Begin` and `Pop(pushed)` after `End`. A font or size an addon pushes inside its window overrides it: `imgui.PushFont(nil, size)` keeps the theme's font at the addon's size. A settings window (`kind = window.Settings`, or `Push(true)`) has the font at the base size, so the Font Size slider does not resize it |
| `winxi.borders` | The theme's window border art, from `assets\borders`: nine-slice images drawn in place of a window's own border, on windows of the game kind. `winxi.window` draws it on its own; an addon drawing its own windows asks `Texture(style)` before `Begin`, `Push` around `Begin`, and `Draw` after its content |
| `winxi.titles` | A window's title across its top edge, at the right, as the theme has it: Frame Titles, Title Style (Outlined Text, Break In Border, Break With Shadow, Plate), Title Color, Title Font, Title Size, Title Position X and Y, Title Shadow, Title All Caps. `winxi.window` draws it for a game window given `options.title`; an addon drawing its own windows passes `titles.Breaks(words)` to `borders.Push`, `titles.Gap(words)` to `borders.Draw`, then calls `titles.Draw(words)` |
| `winxi.backgrounds` | The theme's window background style, on windows of the game kind: a gradient, the FFXI-inspired gradient with a fine line every other row, or a greyscale tile of `assets\backgrounds` drawn side by side at its own size, all in the background colour. `winxi.window` (through `winxi.style`, which leaves the window's own background clear under it) draws it on its own; an addon drawing its own windows asks `For(nil)` before `Begin`, pushes a clear `WindowBg` where that is not nil, and calls `Draw(chosen, color)` before its content. Tiles are made by `tools/generate_winxi_backgrounds.py` |
| `winxi.statusicons` | A status's icon to draw: the chosen set of custom icons' (a folder of `statusicons`; `ffxiv`, made by `tools/build_status_icons.py`, to start), or the game's own where the set has none. `Sets()` lists the folders. A set is in one picture as well, for what draws from few pictures: `Sheet()` and `SheetPlace(id)`, ffxiv's `sheet.png` or, for any other set, made at run time a few a frame; and the game's own, made into one at run time a few a frame: `GameSheet()` and `GameSheetPlace(id)`; and the two together as party and buff draw them, the set's icon where it has one and the game's where not, in one picture made at run time a few a frame: `MixedSheet()` and `MixedPlace(id)`, which says too whether the icon is the set's |
| `winxi.mapdat` | The game's own map pictures as a texture to draw: `Load(dat)` with a map's file by its place under the game's folder (`'ROM/283/75.DAT'`), read the way pivot turns towards its overlays, so with XICombinedMaps installed it is the pack's 2048-pixel picture and without it the game's own. DXT and 8-bit bitmaps |
| `winxi.tooltip` | Tooltips in winxi's look: `Hover(text)` after a control, `Show(text)`, or `Begin()` / `End()` around anything else. Whether they show, their delay, colours, padding, text size and width are the shared theme's Tooltip values, set in winxisettings' Tooltips tab, whether or not the addon follows the shared theme |
| `winxi.debounce` | Running a function once things have gone quiet |
| `winxi.legacy` | Bringing settings over for a tool of xitools that has become an addon of its own |
| `winxi.shell` | Everything an addon with one main window would otherwise write for itself: settings, the settings window, the command, the window's frame |

## A window

```lua
local window = require('winxi.window');
local style = require('winxi.style');

local open = { true };

ashita.events.register('d3d_present', 'example_present', function()
    window.Plain('example', open, style.TitlelessFlags(), function()
        imgui.Text('Hello');
    end);
end);
```

Use `window.Full` for a window with tabs, tables, buttons or inputs: it also tints those from the
border colour. Options (padding, background, alpha, shadow, growFrom, kind) are described at the top
of `window.lua`.

Every window is one of two kinds, given as `kind` in its options:

| kind | for | border | font |
|---|---|---|---|
| `window.Game` (the default) | what is drawn on the screen as the game is played | the theme's Window Border art, colours, padding and shadow | the theme's Font at its Font Size |
| `window.Settings` | settings windows, and anything else for changing how things are set | the plain border; the theme's settings window colours and padding; no shadow | the theme's Settings Font at its Settings Font Size |

```lua
window.Full('Example Settings', showConfig, flags, DrawSettings, { kind = window.Settings });
```

The theme keeps the two apart: a settings window's colours, padding, font and font size are values of
its own (`theme.SettingsKeys`: `SettingsBackgroundColor` for `BackgroundColor`, and so on, with
`ThemeTabColor` a settings window's alone), and `theme.For(key, settingsKind)` gives either. So what is
chosen for the game's windows does not change the window it is chosen in. `widgets.Appearance` sets the
game's windows, `widgets.SettingsAppearance` the settings windows; the `winxisettings` addon has both,
a tab each. A theme saved before the two were apart gives its colours and font to both. `winxi.shell`'s settings window is one already.

A settings window can always be resized, whatever flags it is given (`AlwaysAutoResize` and
`NoResize` are taken off). It fits its content as it changes, until a grip or an edge is taken hold
of; from then it keeps the size it is given, never bigger than the screen, with `widgets.PushControlWidth`
controls narrowed to fit and anything still too big scrolling. A double-click on a grip or an edge
fits it to its content again. `window.IsResized()` says, while its content is drawn, whether it has
been resized.

## Text over bars and images

Text written over a bar, an image or the game itself has a dark edge all round it, so it can be read
whatever is behind it. That is the standard for winxi addons; plain text is for the plain background
of a window.

```lua
local text = require('winxi.text');

text.Outlined('1250');                              -- in a window, where imgui.Text would put it
text.Draw(drawList, x, y, color, '1250', edge);     -- anywhere, on a draw list of the addon's choosing
```

`text.Outlined` uses the theme's text colour unless given one. `edge` is the edge's thickness in
pixels, 1 unless given. The edge is `text.OutlineColor`.

## The theme in a settings window

```lua
local widgets = require('winxi.widgets');

if widgets.BeginThemeTab() then
    widgets.Appearance();
    widgets.EndThemeTab();
end
```

`BeginThemeTab` names the tab "Winxi Theme", colours it apart from the addon's own tabs in the theme's Theme Tab Color, and holds it
against the right edge of the tab bar, so it is the last tab whatever order the tabs are begun in. Any other tab, when chosen, and the line
imgui draws under the tab bar are in the theme's Highlight Color.

A change made there shows at once in that addon, and reaches every other addon using winxi when the
control is let go: the theme file is saved and a `winxi_theme_changed` plugin event tells the others to
load it.

## Fading while idle

```lua
local fade = require('winxi.fade');
local widgets = require('winxi.widgets');

fade.Complete(settings.Fade);            -- once, after loading: fills in whatever is missing

fade.Update(settings.Fade);              -- once a frame
window.Plain('example', open, flags, draw, { alpha = fade.Alpha() });

widgets.Fade(settings.Fade, SaveSettings);   -- in the settings window
```

The fade settings are each addon's own, not shared like the theme. An addon with several windows can
give `fade.Alpha()` to only some of them.

Idle is standing still, unless the Moving setting is off: then moving about does not keep the windows
up, and they fade on the move too once nothing else has kept them up. What else counts as not idle is
each a setting: being engaged, having a target (a change of target brings the windows back as well),
being below full HP, resting, and a change to the party list (someone joining, leaving or changing
area).

A window can also fade in as it appears and out as it goes:

```lua
local alpha = fade.Presence('example', wanted);     -- every frame the window might be drawn
if alpha > 0 then
    window.Plain('example', open, flags, draw, { alpha = alpha * fade.Alpha() });
end
```

Fading in needs nothing more. Fading out means drawing the window a little longer than it is wanted:
keep calling with `wanted` false, and keep drawing, while `fade.Lingering('example')` is true.

## Arranging windows

```lua
local organize = require('winxi.organize');

organize.SetLinks(settings.Links);       -- once, after loading: a list the addon saves
organize.SetLabels({ ['example'] = 'Example' });

-- every frame
organize.BeginFrame();
organize.Place('example', settings.Pos);                -- before the window's Begin
window.Plain('example', open, flags, function()
    organize.Label('example');
    DrawContent(organize.IsActive());                   -- sample data while organizing
    organize.Track('example', settings.Pos);
end);
organize.EndFrame();

organize.Controls();                     -- the Organize button, in the settings window
```

While organizing, windows are labelled, a grid can be shown, and dropping one window onto another
links them: the dropped one is held against the side it was dropped towards. Links are between the
windows of one addon.

## Controller input

```lua
local controller = require('winxi.controller');

local grid = controller.NewGrid();
local menu = nil;

controller.Bind({
    active  = function() return windowIsShowing end,    -- take the controller only while there is reason to
    actions = controller.StandardActions(),             -- d-pad, A confirm, B back, X sort, LB previous, RB next
    repeats = controller.StandardRepeats(),             -- the d-pad repeats while held
    press   = function(action)
        if menu then
            menu = menu:Press(action);                  -- the menu to show next, or nil once closed
        elseif action == 'confirm' then
            menu = controller.NewMenu('Title', { { label = 'Use', run = Use }, { label = 'Cancel' } });
        elseif action == 'back' then
            windowIsShowing = false;
        else
            grid:Move(action);
        end
    end,
});

-- drawing
grid:Begin();
for _, thing in ipairs(things) do
    local x, y = imgui.GetCursorScreenPos();
    local index = grid:Add(x, y);
    Draw(thing, grid:IsOn(index));                      -- highlighted when the grid is on it
end
grid:End();
if menu then
    local x, y = grid:Position();
    menu:Draw(x + 40, y);
end
```

`controller.Label(text, x, y, below)` draws a small floating box with a line of text, its bottom left
corner at x, y: given the top left of the highlighted thing, it names it from just above. With `below`
set it is the box's top left corner that goes there, for a place under the thing. A function may be
given in place of the text, to draw more than a line, with a fifth argument that changes when what it
draws does.

Only the buttons in `actions` are taken, and only while `active` says so: they are kept from the game,
and the sticks and every other button still reach it. A button already down when the addon takes the
controller is not counted as a press.

To show which window the buttons will act in, mark it while its binding has the controller: a bright
line is drawn around its edge. Keep what `controller.Bind` returns, and either give it to
`winxi.window` as the `controller` option, or call it while drawing a window of the addon's own:

```lua
local binding = controller.Bind({ ... });

window.Full(name, open, flags, draw, { controller = binding });
-- or, between a window's Begin and End:
controller.Highlight(binding);
```

Buttons are named as an Xbox controller's are. XInput is the default. For a DirectInput controller,
the addon says which make it is, and its buttons are read as the Xbox buttons in the same positions:

```lua
controller.SetLayout(settings.ControllerType);    -- 'xinput', 'playstation', 'switch' or 'stadia'
-- controller.Layouts lists them, each with a key and a label, for a settings window to offer
```

## Menu sounds

```lua
local sound = require('winxi.sound');

sound.SetEnabled(settings.MenuSounds);    -- off until an addon turns it on
sound.Play('move');                       -- 'open', 'move', 'tab', 'confirm', 'back' or 'error'
```

The controller's grid and menu play these by themselves as they are worked, and a binding plays
`open` as it takes the controller (as its window opens), so an addon using those need only turn the
sounds on. Anything else an addon does with a menu (changing tabs, refusing
something) it plays itself.

Each sound is a wav file called by its name. `sounds\move.wav` in the addon's own folder is used
before the one in `libs\winxi\sounds`, so an addon may bring its own; `sound.Set(name, path)` gives a
name any file, and `sound.Refresh()` looks for the files again. The ones that come with winxi are
plain tones made by `sounds/generate.py`, not the game's.

Ashita plays one sound at a time, at the volume of the file.

## The game, packets and bursts

Three small modules hold what an addon would otherwise copy from another:

```lua
local game = require('winxi.game');
local packets = require('winxi.packets');
local debounce = require('winxi.debounce');

-- when the addon's windows should get out of the way (map open, chat opened out, loading, events,
-- the game's interface hidden): rules kept in the addon's settings, with controls from widgets.Hide
game.CompleteHide(settings.hide);
if game.IsHidden(settings.hide) then return end

game.HasBagAccess(bag);    -- also MenuName, IsMapOpen, IsChatExpanded, IsEventHappening, IsInterfaceHidden, IsLoading

AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.inventorySort:make(bag));

debounce(Refresh);         -- Refresh runs once, a second after the last time it was asked for
```

`winxi.packets` has only what an addon has needed so far (the bags, the treasure pool, and actions and
the messages that follow them); add to it as others are needed.

For a tool of xitools that has become an addon of its own, `winxi.legacy` brings over what xitools kept
for it, once for each character:

```lua
local legacy = require('winxi.legacy');

if not options.importedFromXitools and settings.logged_in then
    options.importedFromXitools = true;
    legacy.FromXitools('inv', options, { 'isVisible', 'pos' });    -- the tool's settings to copy
    settings.save();
end
```

It also copies xitools' theme, its rules for hiding and whether the tool faded, where the addon's
settings have `useSharedTheme`, `theme`, `hide` and `fadeInOut` to take them.

## Debuffs on an enemy

The server never says what is on an enemy, so `winxi.debuffs` keeps count from what it does say: the
spells cast nearby and whether each took hold, effects wearing off, and enemies being defeated.

```lua
local debuffs = require('winxi.debuffs');

ashita.events.register('packet_in', 'example_packet_in', function(e)
    debuffs.HandlePacket(e);                          -- every packet in
end);

debuffs.Remaining(serverId, debuffs.Kinds.Dia);       -- seconds left, or nil when it is not on
debuffs.Get(serverId, 'slow');                        -- { kind, name, expires, by, element }, or nil
debuffs.Active(serverId);                             -- a list of those, the first to run out first
debuffs.On(serverId);                                 -- kind -> entry as kept, or nil: nothing made or sorted
debuffs.StatusIds[kind];                              -- the game's number for the status, for its icon
```

Apart from those kinds, any status the server says took hold on anyone, by spell, ability, weapon
skill, monster's move or additional effect, is kept by its number, and taken off when the server says
it wore off, was dispelled or erased, or its owner was defeated:

```lua
debuffs.Statuses(serverId);                           -- status -> { id, expires, by, category, param }, as kept
debuffs.StatusRemaining(serverId, status);            -- seconds left, or nil when it is not on
```

How long each lasts is the server's base duration for the spell or monster's move that put it there,
or the usual one for the status, from `winxi.debuff_durations` (`tools/build_debuff_durations.py`
makes it from `references/Phoenix`), or 180 seconds where nothing says. Merits, gear and partial
resists are not known.

`debuffs.On` is for an addon that asks about many enemies every frame. An entry in it may have run
out: `os.time() < entry.expires` says whether it is still on.

`name` is the spell that put it there and `by` the server id of who cast it. An enemy's server id is
its entity's `ServerId`. An addon that parses actions itself hands the result to `debuffs.Action` in
place of the packet, and likewise `debuffs.Message`.

Each addon is its own Lua state: every addon that wants the count keeps its own, from the packets it
hands over. It knows nothing of a debuff that landed out of range or before the area was entered, of
one put there by anything but a spell, or of one cut short by a partial resist until the server says
it has worn off. Everything is forgotten on a change of area.

## Letting an addon keep its own theme

Every addon that uses winxi gives its user the choice: follow the shared theme, or keep colours,
padding and shadow of its own. That takes two settings of the addon's, a flag and a table:

```lua
local theme = require('winxi.theme');
local widgets = require('winxi.widgets');

-- in the addon's settings: UseSharedTheme = true, Theme = {}

-- once a frame, before anything is drawn (cheap: nothing happens unless one of the two has changed)
theme.Configure(settings.UseSharedTheme, settings.Theme);

-- in the Winxi Theme tab
widgets.Appearance({
    onUseShared = function(useShared)       -- the "Use Shared Theme" checkbox was changed
        settings.UseSharedTheme = useShared;
        SaveSettings();
    end,
    onOwnChanged = function()                -- the addon's own theme was changed
        SaveSettings();
    end,
});
```

The table is filled in by winxi the first time it is handed over, starting from the shared theme's
values, so switching the shared theme off changes nothing until something is changed. The addon only
has to save and load it with the rest of its settings.

## An addon in a few lines: the shell

For an addon with one main window, `winxi.shell` does everything that is not the addon's own: the
settings for each character, the theme, the rules for hiding, fading in and out, the window's place, a
settings window with Settings and Winxi Theme tabs, and the command.

```lua
local shell = require('winxi.shell');

local app = shell.New({
    defaults     = T{ isVisible = T{ true }, pos = T{ 100, 100 } },   -- the addon's own settings
    window       = 'winxi.example',
    configTitle  = 'Example Settings',
    command      = '/example',                          -- alone: show or hide; 'config': the settings
    help         = '/example shows or hides the window; /example config opens the settings.',
    drawSettings = function(options) ... end,           -- the Settings tab, above the hiding rules
});

ashita.events.register('d3d_present', 'example_present', function()
    if not app:BeginFrame() then return end             -- false while the windows should hide
    app:Window(app.options.isVisible, Draw);            -- Draw(options) draws what the window holds
end);
```

`app.options` is the settings table; read it from `app` each time, as it is another table after a change
of character. Optional in the spec: `drawAppearance` (more for the Winxi Theme tab's Addon section),
`commands` (more verbs), `onSettings` (called when the settings are loaded or swapped), `toggleSays`
(`{ shown = '...', hidden = '...' }`, said in the chat log as the command shows or hides the window: for
a window that is only there some of the time, where the change cannot otherwise be seen) and `import` (a
tool's settings to bring over from xitools, once) and `formerName` (an addon's name before it was renamed:
what it saved under that name is brought over, once for each character). `shell.ControllerSettings(options, tooltip, between)`
draws the controller settings an addon's Settings tab has. `inventory` and `treas` are written this way.

An addon with settings and no window of its own leaves `window` out of the spec: its command alone then
opens or closes the settings, which say nothing of hiding or fading, and it calls `app:BeginFrame()`
each frame for the settings window alone. `trigger` is written this way (its optional indicator uses `winxi.window` as well).

## Tooltips

```lua
local tooltip = require('winxi.tooltip');

imgui.Button('Go');
tooltip.Hover('Goes.');                      -- in place of: if imgui.IsItemHovered() then imgui.SetTooltip('Goes.') end

if imgui.IsItemHovered() and tooltip.Begin() then
    imgui.Image(icon, size);                 -- anything, in a tooltip of winxi's look
    tooltip.End();
end
```

Words go on to another line at the Max Width. `Begin` returns false while tooltips are off or the
mouse has not rested for the Delay yet; `End` is called only when it returned true. winxi's own
tooltips (`winxi.widgets`, `winxi.shell`, `winxi.organize`) all go through it.

## Converting an addon: checklist

An addon with one main window can use `winxi.shell` (above), which does all of this. Otherwise:

1. Draw its windows with `winxi.window`, or `winxi.style` pushes around its own `Begin`.
2. Add the `UseSharedTheme` flag and `Theme` table to its settings, saved and loaded with the rest.
3. Call `theme.Configure` once a frame.
4. Give it a Winxi Theme tab (`widgets.BeginThemeTab`) in five sections. `widgets.Appearance`, given
   both functions, draws the first four: **Theme** (the "Use Shared Theme" checkbox), **Window**
   (colours, padding, drop shadow), **Font** (the base font and size) and **Styles** (window border, frame titles, bar texture, bar bookends and their
   style, Custom Icons), then Reset Appearance, which asks first when it is the shared theme
   being reset. An addon that draws HP and MP bars or statuses reads the styles from `theme.Get()`:
   `BarTexture`, `Bookends`, `BookendStyle`, `StatusIcons` (whether custom icons are drawn) and `StatusIconSet` (which set). The addon draws the last section itself, under `widgets.Header('Addon')`, for its own appearance options. Its
   settings are named with `widgets.Label` (the name on the left, then a colon, in line with winxi's)
   and its families of settings kept apart with `widgets.Gap`.
5. Remove the addon's own colour, padding and shadow settings and the code that drew with them.

## Custom icons

A status's icon can be the game's own or one of a set of custom icons, chosen under **Custom Icons**
(winxisettings' Icons tab, under HQ Icons; Styles in an addon's own Winxi Theme tab): **None** for the
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

For the name addon, which draws statuses from a single picture, a set is put on one sheet a few icons
a frame the first time it is wanted; ffxiv's comes ready made, as `sheet.png`.

## Sections collapse

Every section of a menu is a `widgets.Header`, and every one can be collapsed: its title starts `[-]`
while open and `[+]` while collapsed, and a click on the title changes which. `widgets.Header`
returns whether it is open, and the section is drawn only then:

```lua
if widgets.Header('Window') then
    -- the section's settings
end
```

A header whose return is not used still shows `[-]`, but collapsing it hides nothing: always draw a
section inside its `if`. Which sections are collapsed is kept while the addon is loaded. The titles are
in the theme's `SettingsHeaderColor`, Sub-Category Color on winxisettings' Settings Windows tab.

## Naming options

Every option's name has each word capitalised ("Shadow Opacity", "Fade When Idle"), in winxi and in
every addon's own settings.

## Checks

`tests/run.sh`, at the top of the project, loads `inventory`, `treas` and parts of winxi against a stand-in for
Ashita and prints what it finds: that they load, draw, answer their commands and take the controller as
expected. It does not show that anything looks right or that the game agrees. Run it after changing
winxi.

## Notes

- Each addon runs in its own Lua state, so each loads its own copy of the library; only the theme file
  is shared.
- An addon that uses winxi needs this folder installed alongside it.
- Each module's own header comment is its reference.
