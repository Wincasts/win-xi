# winxi

Shared drawing for Ashita addons that render with imgui: one look, set once, used by every addon.

Lives in `addons/libs/winxi/`, so any addon can `require('winxi.<module>')`.

| Module | What it gives |
|---|---|
| `winxi.theme` | The shared theme (background, border and text colours, padding, drop shadow), saved in `config\addons\winxi\theme.lua` and kept in step across addons |
| `winxi.style` | Puts the theme on imgui's style stack around a window: `PushPlain` (text and icons) or `PushFull` (controls), then `Pop` |
| `winxi.window` | A themed window in one call: `window.Plain` / `window.Full` |
| `winxi.shadow` | The drop shadow, drawn inside a window |
| `winxi.fade` | Fading an addon's windows out while the player is idle |
| `winxi.anchor` | "Grow from": which corner of a self-sizing window stays put |
| `winxi.icons` | Loading image files as textures and drawing them cheaply |
| `winxi.widgets` | Ready-made settings controls: the theme (`Appearance`) and a corner picker (`GrowFrom`) |

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

## Notes

- Each addon runs in its own Lua state, so each loads its own copy of the library; only the theme file
  is shared.
- An addon that uses winxi needs this folder installed alongside it.
- Each module's own header comment is its reference.
