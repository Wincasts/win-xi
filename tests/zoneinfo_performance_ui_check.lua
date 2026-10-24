-- Structural performance assertions; no hardware-specific timing thresholds.
local imgui = require('imgui');
local catalog = require('map_catalog');
local g = require('area_geometry');
local view = require('debug_view');
local path = os.tmpname(); os.remove(path);
local e = require('boundary_editor').new(catalog, path);
local map = catalog.list[1];
for _, candidate in ipairs(catalog.list) do if #candidate.areas > #map.areas then map = candidate; end end
local s = { debug = true, enabled = true, zone = map.zone_id, map_key = map.key,
    approach_yalms = 30, approach_pixels = 30,
    entry = { scale = 5, floor_id = map.floor_id, offset_x = 0, offset_y = 0 } };
imgui.GetWindowPos = function() return 0, 0; end;
imgui.GetWindowSize = function() return 4096, 4096; end;
imgui.GetMousePos = function() return 0, 0; end;
local built, original = 0, g.approach_outline;
g.approach_outline = function(...) built = built + 1; return original(...); end;
local function check(label, ok) H.print(label, ok); assert(ok, label); end
view.clear(); view.browser.follow[1] = true;
local colors = H.calls.GetColorU32 or 0;
view.draw(s, e);
check('draw colors converted once per palette, not per edge', H.calls.GetColorU32 - colors == 10);
check('initial visible geometry computed once per area', built == #map.areas);
for _ = 1, 10 do view.draw(s, e); end
check('idle frames do not rebuild outlines', built == #map.areas);
e:configure(e.selected.name .. ' edited', e.selected.enabled ~= false);
view.draw(s, e);
check('metadata changes do not rebuild geometry', built == #map.areas);
e.edit_mode[1] = true;
e:begin(1);
local p = e.selected.polygon[1];
check('tiny vertex change accepted', e:move(p[1] + .25, p[2]));
view.draw(s, e);
check('one vertex edit rebuilds only its own outline', built == #map.areas + 1);
view.zoom[1] = 3; view.draw(s, e);
check('zoom does not rebuild map-space outlines', built == #map.areas + 1);
local lines = H.calls['draw.AddLine'] or 0;
imgui.GetWindowPos = function() return 10000, 10000; end;
imgui.GetWindowSize = function() return 100, 100; end;
view.draw(s, e);
check('offscreen outlines submit no line primitives', (H.calls['draw.AddLine'] or 0) == lines);
local ui_calls = H.calls.Begin or 0;
s.debug = false; view.draw(s, e);
check('closed debug window does not build UI', (H.calls.Begin or 0) == ui_calls);
g.approach_outline = original;
view.clear(); os.remove(path); os.remove(path .. '.tmp'); os.remove(path .. '.bak');
