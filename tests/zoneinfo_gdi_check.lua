-- Mocked GDI renderer integration; does not load the Windows DLL on Linux.
local p = require('presentation');
local backend = require('gdi_banner');
local lib = { FontFlags = { None = 0, Bold = 1 }, Alignment = { Left = 0, Center = 1, Right = 2 }, created = 0, renders = 0, destroyed = 0 };
function lib:set_auto_render(enabled) assert(not enabled, 'GDI must not register an automatic tick'); end
function lib:get_font_available(family) return family == 'Arial' or family == 'Calibri'; end
function lib:create_object(options)
    self.created = self.created + 1;
    local obj = { settings = options, is_dirty = false };
    function obj:get_texture()
        if self.is_dirty then lib.builds = (lib.builds or 0) + 1; self.is_dirty = false; end
        return {}, { bottom = self.settings.font_height + 2, right = #self.settings.text * 8 };
    end
    return setmetatable(obj, { __index = function(_, key)
        assert(key:sub(1, 4) == 'set_', key);
        return function(o, value)
            local field = key:sub(5);
            if field ~= 'visible' and field ~= 'opacity' and field ~= 'position_x' and field ~= 'position_y' then
                lib.style_calls = (lib.style_calls or 0) + 1;
                if o.settings[field] ~= value then o.is_dirty = true; end
            end
            o.settings[field] = value;
        end;
    end });
end
function lib:render(before_text)
    if before_text then before_text('mock sprite'); end
    self.renders = self.renders + 1;
end
function lib:destroy_object() self.destroyed = self.destroyed + 1; end
function lib:destroy_interface() self.closed = true; end
local instance = backend.new(function() return lib; end);
backend.new = function() return instance; end
local imgui = require('imgui');
imgui.PushFont = function() error('GDI must not push an ImGui font'); end
imgui.AddFontFromFileTTF = function() error('GDI must not load an ImGui font'); end
local checks = 0;
local function check(label, ok) assert(ok, label); checks = checks + 1; H.print(label, ok); end
local d = p.app.options.display;
check('experimental renderer is opt-in', d.renderer == 'imgui');
package.loaded['gdi_families'] = { List = function() return { 'Arial', 'Calibri', 'Verdana' }; end };
local original_combo, original_selectable = imgui.BeginCombo, imgui.Selectable;
local active_combo, combos, selections = nil, {}, 0;
imgui.BeginCombo = function(id)
    active_combo = id;
    if id:find('GdiFamily', 1, true) then combos[id] = true; return true; end
    return false;
end;
imgui.Selectable = function(label)
    if active_combo == '##zone.zoneTitleGdiFamily' and label == 'Calibri' then selections = selections + 1; return true; end
    return false;
end;
d.renderer = 'gdi';
H.command('/zone'); H.tab(2);
local textboxes = H.calls.InputText or 0;
H.frames(1);
local combo_count = 0; for _ in pairs(combos) do combo_count = combo_count + 1; end
check('four family dropdowns and only the background filename textbox', combo_count == 4 and (H.calls.InputText or 0) == textboxes + 1);
check('dropdown selection updates saved family', selections == 1 and d.zoneTitleGdiFamily[1] == 'Calibri' and H.saves() > 0);
H.command('/zone');
imgui.BeginCombo, imgui.Selectable = original_combo, original_selectable;
d.renderer, d.centered[1], d.position[1], d.position[2], d.alignment = 'gdi', false, 400, 200, 'right';
d.zoneTitleGdiFamily[1] = 'Missing Font';
local state = { title = 'West Ronfaure', region = 'Ronfaure', weather = 'Clear', banner_is_area = false };
p.start(state, 100);
check('GDI draws without ImGui font APIs', p.draw(state, nil, 100.1));
check('one full-string object per line', lib.created == 3 and lib.renders == 1);
local title = instance.objects.zoneTitle.settings;
check('family fallback and native bold applied', title.font_family == 'Arial' and title.font_flags == 1);
check('position and alignment honored', title.position_x == 400 and title.position_y == 222 and title.font_alignment == 2);
check('per-frame fade uses sprite opacity', math.abs(title.opacity - .5) < .000001);
local styles, builds = lib.style_calls, lib.builds;
p.draw(state, nil, 100.4);
check('objects reused rather than recreated every frame', lib.created == 3);
check('fade does not reapply styles or rebuild textures', lib.style_calls == styles and lib.builds == builds);
d.zoneTitleSize[1] = 33; p.draw(state, nil, 100.5);
check('GDI size edit updates and rebuilds only its line', lib.style_calls == styles + 1 and lib.builds == builds + 1);
styles, builds = lib.style_calls, lib.builds;
state.title = 'A new zone'; p.draw(state, nil, 100.6);
check('GDI text edit updates and rebuilds only its line', lib.style_calls == styles + 1 and lib.builds == builds + 1);
state.banner_is_area, state.title, state.zone_title = true, 'Knightwell', 'West Ronfaure';
d.perLineTiming[1] = true; d.areaTitleDelay[1] = 2;
p.start(state, 200); p.draw(state, nil, 200.5);
check('sub-zone title delay is honored', not instance.objects.areaTitle.settings.visible);
check('previous zone objects are hidden', not instance.objects.zoneTitle.settings.visible);
p.draw(state, nil, 202.5);
check('delayed sub-zone title becomes visible', instance.objects.areaTitle.settings.visible);
local background = require('banner_background');
local original_background, background_drawn = background.draw_gdi, false;
background.draw_gdi = function(sprite, image, options, width, alpha)
    background_drawn = sprite == 'mock sprite' and image.handle == 42 and options == d and width == 1920 and alpha == .5;
end;
instance:draw({ { key = 'areaTitle', words = 'Knightwell', title = true, size = 32, alpha = .5 } },
    d, 1920, d.titleColor, d.detailColor, true, { handle = 42 }, .5);
check('GDI image draws through sprite before text rendering', background_drawn);
background.draw_gdi = original_background;
d.renderer = 'imgui';
check('expired renderer switch skips drawing', not p.draw(state, nil, state.visible_until));
check('idle renderer switch releases private manager and objects', lib.closed and lib.destroyed == lib.created);
p.shutdown();
check('shutdown after renderer switch is idempotent', lib.destroyed == lib.created);
H.print(('zoneinfo experimental GDI: %d assertions passed'):format(checks));
