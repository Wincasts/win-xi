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
| `winxi.anchor` | "Grow from": which corner of a self-sizing window stays put |
| `winxi.icons` | Loading image files as textures and drawing them cheaply |
| `winxi.widgets` | Ready-made settings controls: the theme with its "Use shared theme" checkbox (`Appearance`) and a corner picker (`GrowFrom`) |

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
    onUseShared = function(useShared)       -- the "Use shared theme" checkbox was changed
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
4. Give it an Appearance tab with `widgets.Appearance` and both functions, so the "Use shared theme"
   checkbox is there.
5. Remove the addon's own colour, padding and shadow settings and the code that drew with them.

## Notes

- Each addon runs in its own Lua state, so each loads its own copy of the library; only the theme file
  is shared.
- An addon that uses winxi needs this folder installed alongside it.
- Each module's own header comment is its reference.
