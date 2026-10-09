# winxi

Shared drawing for Ashita addons that render with imgui: one look, set once, used by every addon.

Lives in `addons/libs/winxi/`, so any addon can `require('winxi.<module>')`.

| Module | What it gives |
|---|---|
| `winxi.theme` | The shared theme (background, border and text colours, padding, drop shadow), saved in `config\addons\winxi\theme.lua` and kept in step across addons; or an addon's own |
| `winxi.style` | Puts the theme on imgui's style stack around a window: `PushPlain` (text and icons) or `PushFull` (controls), then `Pop` |
| `winxi.window` | A themed window in one call: `window.Plain` / `window.Full` |
| `winxi.shadow` | The drop shadow, drawn inside a window |
| `winxi.fade` | Fading an addon's windows out while the player is idle, from settings the addon keeps (`widgets.Fade` draws their controls) |
| `winxi.organize` | Arranging an addon's windows: an Organize button, labels, an alignment grid, and linking one window against another |
| `winxi.controller` | Working an addon's windows with a controller (XInput, or DirectInput by make): taking button presses, a highlight that moves over things drawn in rows, and a menu of choices |
| `winxi.anchor` | "Grow from": which corner of a self-sizing window stays put |
| `winxi.icons` | Loading image files as textures and drawing them cheaply |
| `winxi.widgets` | Ready-made settings controls: the theme with its "Use Shared Theme" checkbox (`Appearance`) and a corner picker (`GrowFrom`) |

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
border colour. Options (padding, background, alpha, shadow, growFrom) are described at the top of
`window.lua`.

## The theme in a settings window

```lua
local widgets = require('winxi.widgets');

if imgui.BeginTabItem('Appearance') then
    widgets.Appearance();
    imgui.EndTabItem();
end
```

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
set it is the box's top left corner that goes there, for a place under the thing.

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

## Letting an addon keep its own theme

Every addon that uses winxi gives its user the choice: follow the shared theme, or keep colours,
padding and shadow of its own. That takes two settings of the addon's, a flag and a table:

```lua
local theme = require('winxi.theme');
local widgets = require('winxi.widgets');

-- in the addon's settings: UseSharedTheme = true, Theme = {}

-- once a frame, before anything is drawn (cheap: nothing happens unless one of the two has changed)
theme.Configure(settings.UseSharedTheme, settings.Theme);

-- in the Appearance tab
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

## Converting an addon: checklist

1. Draw its windows with `winxi.window`, or `winxi.style` pushes around its own `Begin`.
2. Add the `UseSharedTheme` flag and `Theme` table to its settings, saved and loaded with the rest.
3. Call `theme.Configure` once a frame.
4. Give it an Appearance tab in three sections. `widgets.Appearance`, given both functions, draws the
   first two: **Theme** (the "Use Shared Theme" checkbox) and **Window** (colours, padding, drop
   shadow, and Reset Appearance, which asks first when it is the shared theme being reset). The addon
   draws the third itself, under `widgets.Header('Addon')`, for its own appearance options. Its
   settings are named with `widgets.Label` (the name on the left, then a colon, in line with winxi's)
   and its families of settings kept apart with `widgets.Gap`.
5. Remove the addon's own colour, padding and shadow settings and the code that drew with them.

## Naming options

Every option's name has each word capitalised ("Shadow Opacity", "Fade When Idle"), in winxi and in
every addon's own settings.

## Notes

- Each addon runs in its own Lua state, so each loads its own copy of the library; only the theme file
  is shared.
- An addon that uses winxi needs this folder installed alongside it.
- Each module's own header comment is its reference.
