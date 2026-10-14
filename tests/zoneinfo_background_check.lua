local p = require('presentation');
local bg = require('banner_background');
local imgui = require('imgui');
local d = p.app.options.display;
local function check(label, ok) H.print(label, ok); assert(ok, label); end
check('background is optional by default', not d.backgroundEnabled[1]);
for _, file in ipairs({ '../x.png', 'C:\\x.png', 'folder/x.png', 'x.lua', 'x\n.png' }) do
    check('unsafe filename rejected: ' .. file:gsub('\n', '?'), not bg.valid_file(file));
end
check('supported filenames accepted', bg.valid_file('Banner.PNG') and bg.valid_file('banner.jpg') and bg.valid_file('banner.bmp'));
local state = { title = 'Test', region = 'Region', weather = 'Clear', banner_is_area = false };
p.start(state, 100);
p.draw(state, nil, 100.5);
check('disabled image performs no loading', H.background_loads == 0);
d.backgroundEnabled[1], d.backgroundFile[1] = true, 'banner.png';
local draw = imgui.GetWindowDrawList();
local original_image, original_text = draw.AddImage, draw.AddText;
local image, first, opacity;
local color = imgui.GetColorU32;
imgui.GetColorU32 = function(c) opacity = c[4]; return color(c); end;
draw.AddImage = function(_, handle, a, b, uv1, uv2, tint)
    image = { handle = handle, a = a, b = b, opacity = opacity };
    first = first or 'image';
    return original_image(draw, handle, a, b, uv1, uv2, tint);
end;
draw.AddText = function(...) first = first or 'text'; return original_text(...); end;
p.draw(state, nil, 100.1);
check('image precedes text', first == 'image' and image.handle == 42);
check('centered size and offset honored', image.a[1] == 640 and image.a[2] == 94 and image.b[1] == 1280 and image.b[2] == 234);
check('image uses configured opacity with shared window fade', image.opacity == .6);
p.draw(state, nil, 100.2);
check('unchanged frames load only once', H.background_loads == 1);
d.alignment, d.centered[1], d.position[1] = 'right', false, 800;
p.draw(state, nil, 100.3);
check('right anchor honored', image.a[1] == 160);
local loads = H.background_loads;
p.draw(state, nil, 200);
check('expired banner performs no image work', H.background_loads == loads);
d.backgroundFile[1] = 'missing.png';
p.draw(state, nil, 100.4); p.draw(state, nil, 100.5);
check('missing image backs off and text still renders', H.background_loads == loads + 1 and H.background_cache.error ~= nil);
d.backgroundFile[1] = 'second.png'; p.draw(state, nil, 100.6);
check('new filename replaces cache immediately', H.background_loads == loads + 2 and H.background_cache.error == nil);
local end_before, pop_before = H.calls.End or 0, H.calls['draw.PopClipRect'] or 0;
draw.AddImage = function() error('injected image draw failure'); end;
local ok = pcall(p.draw, state, nil, 100.7);
check('image failure restores clipping and ends window', not ok and H.calls.End == end_before + 1 and H.calls['draw.PopClipRect'] == pop_before + 1);
draw.AddImage, draw.AddText, imgui.GetColorU32 = original_image, original_text, color;
d.backgroundEnabled[1] = false; p.draw(state, nil, 100.8);
check('disabling background releases image reference', H.background_cache.image == nil);
-- Exercise native scaling/opacity math without creating a Windows device.
local ffi = require('ffi');
if not pcall(ffi.typeof, 'RECT') then ffi.cdef('typedef struct { int32_t left, top, right, bottom; } RECT;'); end
if not pcall(ffi.typeof, 'D3DXVECTOR2') then ffi.cdef('typedef struct { float x, y; } D3DXVECTOR2;'); end
local d3d = require('d3d8');
local original_argb, native_alpha = d3d.D3DCOLOR_ARGB, nil;
d3d.D3DCOLOR_ARGB = function(alpha) native_alpha = alpha; return alpha; end;
local native_ok = false;
local sprite = { Draw = function(_, texture, rect, scale, center, rotation, pos)
    native_ok = texture == 'mock texture' and rect.right == 320 and rect.bottom == 70
        and scale.x == 2 and scale.y == 2 and pos.x == 160 and pos.y == 94;
end };
bg.draw_gdi(sprite, { texture = 'mock texture', width = 320, height = 70 }, d, 1920, .5);
check('native image scaling, anchor and fade opacity honored', native_ok and native_alpha == 77);
d3d.D3DCOLOR_ARGB = original_argb;
p.shutdown();
check('shutdown clears cached image', H.background_cache.image == nil);
d.backgroundSize[1], d.backgroundSize[2], d.backgroundOpacity[1] = -1, math.huge, 5;
d.backgroundFile[1] = '../bad.png'; p.complete(p.app.options);
check('saved image settings validated and clamped', d.backgroundSize[1] == 1 and d.backgroundSize[2] == 140 and d.backgroundOpacity[1] == 1 and d.backgroundFile[1] == '');
