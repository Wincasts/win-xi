# xiui

Shared drawing for Ashita addons that render with imgui: one look, set once, used by every addon.

Lives in `addons/libs/xiui/`, so any addon can `require('xiui.<module>')`.

| Module | What it gives |
|---|---|
| `xiui.theme` | The shared theme (background, border and text colours, padding, drop shadow), saved in `config\addons\xiui\theme.lua` and kept in step across addons |
| `xiui.style` | Puts the theme on imgui's style stack around a window: `PushPlain` (text and icons) or `PushFull` (controls), then `Pop` |
| `xiui.window` | A themed window in one call: `window.Plain` / `window.Full` |
| `xiui.shadow` | The drop shadow, drawn inside a window |
| `xiui.fade` | Fading an addon's windows out while the player is idle |
| `xiui.anchor` | "Grow from": which corner of a self-sizing window stays put |
| `xiui.icons` | Loading image files as textures and drawing them cheaply |
| `xiui.widgets` | Ready-made settings controls: the theme (`Appearance`) and a corner picker (`GrowFrom`) |

## A window

```lua
local window = require('xiui.window');
local style = require('xiui.style');

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
local widgets = require('xiui.widgets');

if imgui.BeginTabItem('Appearance') then
    widgets.Appearance();
    imgui.EndTabItem();
end
```

A change made there shows at once in that addon, and reaches every other addon using xiui when the
control is let go: the theme file is saved and a `xiui_theme_changed` plugin event tells the others to
load it.

## Notes

- Each addon runs in its own Lua state, so each loads its own copy of the library; only the theme file
  is shared.
- An addon that uses xiui needs this folder installed alongside it.
- Each module's own header comment is its reference.
