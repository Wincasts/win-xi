addon.name    = 'glyphtest';
addon.author  = 'win (and claude)';
addon.version = '0.1';
addon.desc    = 'A test, to be thrown away: whether imgui\'s font can be drawn from as Direct3D quads, with the depth test.';

require('common');

local bit   = require('bit');
local d3d   = require('d3d8');
local ffi   = require('ffi');
local imgui = require('imgui');
local nameplates = require('winxi.nameplates');

local C = ffi.C;
local device = d3d.get_device();

-- What it does:
--   on loading, and on /glyphtest, says in the chat log what it finds of the font: its texture, a
--     letter's place in it, and whether a letter of a size not yet used is there to be found
--   draws the whole of the font's texture at the top left of the screen, 256 pixels square
--   writes "glyphtest" under it from the font's letters, as Direct3D quads
--   with the namehook plugin loaded, writes each name in view over its character the same way,
--     20 pixels above the game's, with the depth test on: it should be hidden by what is in front of it
--   /glyphtest depth switches the depth test off and on
--   /glyphtest claim stops the game drawing its own names, and writes these where they were
--   /glyphtest plane <name> draws a see-through pink sheet over the whole screen, as deep in the picture as
--     that name: it should cover what is further off than the name and be hidden by what is nearer.
--     /glyphtest plane off takes it away
--   /glyphtest sheet endscene|beginscene|present draws the sheet at another point in the frame
--   /glyphtest surfaces says what is being drawn on, and with what depth buffer, at each of those points
--   /glyphtest numbers says how deep each name was worked out to be, and what the camera's numbers are
--   /glyphtest big writes them at 30 pixels, and says what a letter of that size is found to be

ffi.cdef[[
    #pragma pack(1)
    struct glyphtest_vertex_t { float x, y, z, rhw; unsigned int diffuse; float u, v; };
]]
local FVF = bit.bor(C.D3DFVF_XYZRHW, C.D3DFVF_DIFFUSE, C.D3DFVF_TEX1);
local MAX = 6 * 512;
local vertices = ffi.new('struct glyphtest_vertex_t[?]', MAX);
local stride = ffi.sizeof('struct glyphtest_vertex_t');
local used = 0;

local depthTest = true;
local claim = false;   -- the game draws no names, and these are written where its own would be
local big = false;     -- the names are written at 30 pixels, a size nothing else is written in
local bigSaid = false;
local plane = nil;     -- a name, or the start of one: a sheet is drawn over the screen as deep as that name is
local numbers = false; -- the next frame says what each name's depth was worked out to be
local sheetAt = 'present'; -- when in the frame the sheet is drawn: 'present', 'endscene' or 'beginscene'
local sheetDepth = nil;    -- how deep the sheet is, as last worked out
local surfaces = {};       -- event -> true while what is being drawn on then is still to be said
local fired = { beginscene = 0, endscene = 0 }; -- how often each has come round since the last frame
local reported = false;
local failed = {}; -- what has gone wrong while drawing, said once each

local function say(...)
    local parts = { ... };
    for i = 1, #parts do parts[i] = tostring(parts[i]); end
    print(('\30\81[glyphtest]\30\01 %s'):format(table.concat(parts, ' ')));
end

local function try(what, f)
    local ok, a, b, c, d = pcall(f);
    if (not ok) then
        say(what .. ': FAILED:', a);
        return nil;
    end
    return a, b, c, d;
end

-- The font's texture as Direct3D has it, and the number imgui knows it by
local function fontTexture()
    local atlas = imgui.GetFont().ContainerAtlas;
    local id = atlas.TexRef:GetTexID();
    if (id == nil or id == 0) then
        id = atlas.TexData:GetTexID();
    end
    return id;
end

local function report()
    say('font size', try('GetFontSize', imgui.GetFontSize));
    local baked = try('GetFontBaked', imgui.GetFontBaked);
    if (baked ~= nil) then
        say('baked: Size', try('Size', function () return baked.Size; end), '| Ascent', try('Ascent', function () return baked.Ascent; end), '| Descent', try('Descent', function () return baked.Descent; end));
        local glyph = try('FindGlyph A', function () return baked:FindGlyph(65); end);
        if (glyph ~= nil) then
            try('glyph A', function ()
                say(('glyph A: X0 %.2f Y0 %.2f X1 %.2f Y1 %.2f | U0 %.5f V0 %.5f U1 %.5f V1 %.5f | AdvanceX %.2f | Visible %s'):format(
                    glyph.X0, glyph.Y0, glyph.X1, glyph.Y1, glyph.U0, glyph.V0, glyph.U1, glyph.V1, glyph.AdvanceX, tostring(glyph.Visible)));
            end);
        end
    end

    local atlas = try('ContainerAtlas', function () return imgui.GetFont().ContainerAtlas; end);
    if (atlas ~= nil) then
        say('atlas: TexRef id', try('TexRef:GetTexID', function () local id = atlas.TexRef:GetTexID(); return type(id) .. ' ' .. tostring(id); end));
        say('atlas: TexData id', try('TexData:GetTexID', function () local id = atlas.TexData:GetTexID(); return type(id) .. ' ' .. tostring(id); end),
            '| size', try('TexData size', function () return atlas.TexData.Width .. 'x' .. atlas.TexData.Height; end),
            '| format', try('TexData.Format', function () return atlas.TexData.Format; end),
            '| bytes per pixel', try('BytesPerPixel', function () return atlas.TexData.BytesPerPixel; end));
        say('atlas: TexIsBuilt', try('TexIsBuilt', function () return atlas.TexIsBuilt; end), '| RendererHasTextures', try('RendererHasTextures', function () return atlas.RendererHasTextures; end));
    end

    -- a size nothing has been written in: is a letter there before it is first drawn?
    try('a size not yet used', function ()
        local fresh = imgui.GetFont():GetFontBaked(37);
        local before = fresh:FindGlyphNoFallback(81);
        say('size 37, letter Q, asked for without drawing it:', before ~= nil and ('found, U0 %.5f V0 %.5f'):format(before.U0, before.V0) or 'not there');
        local asked = fresh:FindGlyph(81);
        say('size 37, letter Q, by FindGlyph:', asked ~= nil and ('found, U0 %.5f V0 %.5f, X1-X0 %.2f'):format(asked.U0, asked.V0, asked.X1 - asked.X0) or 'not there');
        say('texture after asking: id', tostring(fontTexture()), '| size', imgui.GetFont().ContainerAtlas.TexData.Width .. 'x' .. imgui.GetFont().ContainerAtlas.TexData.Height);
    end);
end

local function vertex(x, y, z, rhw, color, u, v)
    if (used >= MAX) then
        return;
    end
    local at = vertices[used];
    at.x, at.y, at.z, at.rhw, at.diffuse, at.u, at.v = x - 0.5, y - 0.5, z, rhw, color, u, v;
    used = used + 1;
end

local function quad(x0, y0, x1, y1, z, rhw, color, u0, v0, u1, v1)
    vertex(x0, y0, z, rhw, color, u0, v0);
    vertex(x1, y0, z, rhw, color, u1, v0);
    vertex(x0, y1, z, rhw, color, u0, v1);
    vertex(x1, y0, z, rhw, color, u1, v0);
    vertex(x1, y1, z, rhw, color, u1, v1);
    vertex(x0, y1, z, rhw, color, u0, v1);
end

-- How wide the words are, in the font and size in use
local function measure(baked, words)
    local width = 0;
    for i = 1, #words do
        local glyph = baked:FindGlyph(words:byte(i));
        if (glyph ~= nil) then
            width = width + glyph.AdvanceX;
        end
    end
    return width;
end

-- The words from the font's letters, their top left at x, y: a dark copy towards each corner, then themselves
local function write(baked, words, x, y, z, rhw, color)
    for pass = 1, 5 do
        local dx = (pass == 1 or pass == 3) and -1 or ((pass == 2 or pass == 4) and 1 or 0);
        local dy = (pass == 1 or pass == 2) and -1 or ((pass == 3 or pass == 4) and 1 or 0);
        local ink = pass == 5 and color or 0xE6000000;
        local pen = math.floor(x) + dx;
        local top = math.floor(y) + dy;
        for i = 1, #words do
            local glyph = baked:FindGlyph(words:byte(i));
            if (glyph ~= nil) then
                if (glyph.Visible ~= 0 and glyph.Visible ~= false) then
                    quad(pen + glyph.X0, top + glyph.Y0, pen + glyph.X1, top + glyph.Y1, z, rhw, ink, glyph.U0, glyph.V0, glyph.U1, glyph.V1);
                end
                pen = pen + glyph.AdvanceX;
            end
        end
    end
end

local function flush(texture, depth)
    if (used == 0) then
        return;
    end

    local _, zEnable = device:GetRenderState(C.D3DRS_ZENABLE);
    local _, zFunc = device:GetRenderState(C.D3DRS_ZFUNC);
    local _, zWrite = device:GetRenderState(C.D3DRS_ZWRITEENABLE);

    device:SetTexture(0, ffi.cast('IDirect3DBaseTexture8*', texture));
    -- the colour is the vertex's and the texture gives only how solid, whichever way the texture is kept
    device:SetTextureStageState(0, C.D3DTSS_COLOROP, C.D3DTOP_SELECTARG2);
    device:SetTextureStageState(0, C.D3DTSS_COLORARG2, C.D3DTA_DIFFUSE);
    device:SetTextureStageState(0, C.D3DTSS_ALPHAOP, C.D3DTOP_MODULATE);
    device:SetTextureStageState(0, C.D3DTSS_ALPHAARG1, C.D3DTA_TEXTURE);
    device:SetTextureStageState(0, C.D3DTSS_ALPHAARG2, C.D3DTA_DIFFUSE);
    device:SetRenderState(C.D3DRS_ZENABLE, depth and 1 or 0);
    device:SetRenderState(C.D3DRS_ZFUNC, C.D3DCMP_LESSEQUAL);
    device:SetRenderState(C.D3DRS_ZWRITEENABLE, 0);
    device:SetRenderState(C.D3DRS_ALPHABLENDENABLE, 1);
    device:SetRenderState(C.D3DRS_SRCBLEND, C.D3DBLEND_SRCALPHA);
    device:SetRenderState(C.D3DRS_DESTBLEND, C.D3DBLEND_INVSRCALPHA);
    device:SetVertexShader(FVF);
    device:DrawPrimitiveUP(C.D3DPT_TRIANGLELIST, used / 3, vertices, stride);

    device:SetRenderState(C.D3DRS_ZENABLE, zEnable or 0);
    device:SetRenderState(C.D3DRS_ZFUNC, zFunc or C.D3DCMP_LESSEQUAL);
    device:SetRenderState(C.D3DRS_ZWRITEENABLE, zWrite or 1);
    used = 0;
end

local function drawSheet(depth)
    local display = imgui.GetIO().DisplaySize;
    used = 0;
    quad(0, 0, display.x, display.y, depth, 1, 0x70FF40C0, 0, 0, 0, 0);
    local _, zEnable = device:GetRenderState(C.D3DRS_ZENABLE);
    local _, zFunc = device:GetRenderState(C.D3DRS_ZFUNC);
    local _, zWrite = device:GetRenderState(C.D3DRS_ZWRITEENABLE);
    device:SetTexture(0, nil);
    device:SetTextureStageState(0, C.D3DTSS_COLOROP, C.D3DTOP_SELECTARG2);
    device:SetTextureStageState(0, C.D3DTSS_COLORARG2, C.D3DTA_DIFFUSE);
    device:SetTextureStageState(0, C.D3DTSS_ALPHAOP, C.D3DTOP_SELECTARG2);
    device:SetTextureStageState(0, C.D3DTSS_ALPHAARG2, C.D3DTA_DIFFUSE);
    device:SetRenderState(C.D3DRS_ZENABLE, 1);
    device:SetRenderState(C.D3DRS_ZFUNC, C.D3DCMP_LESSEQUAL);
    device:SetRenderState(C.D3DRS_ZWRITEENABLE, 0);
    device:SetRenderState(C.D3DRS_ALPHABLENDENABLE, 1);
    device:SetRenderState(C.D3DRS_SRCBLEND, C.D3DBLEND_SRCALPHA);
    device:SetRenderState(C.D3DRS_DESTBLEND, C.D3DBLEND_INVSRCALPHA);
    device:SetVertexShader(FVF);
    device:DrawPrimitiveUP(C.D3DPT_TRIANGLELIST, 2, vertices, stride);
    device:SetRenderState(C.D3DRS_ZENABLE, zEnable or 0);
    device:SetRenderState(C.D3DRS_ZFUNC, zFunc or C.D3DCMP_LESSEQUAL);
    device:SetRenderState(C.D3DRS_ZWRITEENABLE, zWrite or 1);
    used = 0;
end

-- What is being drawn on, and the depth buffer that goes with it
local function saySurfaces(event, arg)
    local function describe(what, get)
        return try(what, function ()
            local _, surface = get(device);
            if (surface == nil) then
                return what .. ' none';
            end
            local _, desc = surface:GetDesc();
            local said = ('%s %s %dx%d format %d multisample %d'):format(what, tostring(ffi.cast('void*', surface)), desc.Width, desc.Height, tonumber(desc.Format), tonumber(desc.MultiSampleType));
            surface:Release();
            return said;
        end);
    end
    say(('at %s (given %s; begun %d, ended %d times since the last frame):'):format(event, tostring(arg), fired.beginscene, fired.endscene));
    say('  ', describe('target', device.GetRenderTarget));
    say('  ', describe('depth', device.GetDepthStencilSurface));
end

local function atScene(event, e)
    fired[event] = fired[event] + 1;
    if (surfaces[event]) then
        surfaces[event] = nil;
        saySurfaces(event, type(e) == 'table' and 'a table' or e);
    end
    if (sheetAt == event and sheetDepth ~= nil) then
        local ok, problem = pcall(drawSheet, sheetDepth);
        if (not ok and not failed[tostring(problem)]) then
            failed[tostring(problem)] = true;
            say('the sheet FAILED at', event, ':', tostring(problem));
        end
    end
end

local function draw()
    local baked = imgui.GetFontBaked();
    local texture = fontTexture();
    if (baked == nil or texture == nil or texture == 0) then
        error('no font or no texture: ' .. tostring(baked) .. ' ' .. tostring(texture));
    end

    -- the whole texture, and a word, flat on the screen
    quad(20, 120, 276, 376, 0, 1, 0xFFFFFFFF, 0, 0, 1, 1);
    write(baked, 'glyphtest', 20, 384, 0, 1, 0xFFFFFF80);
    flush(texture, false);

    -- each name in view, over its character, as deep in the picture as the character is
    if (nameplates.Hook() == nil or nameplates.Count() == 0) then
        return;
    end

    local _, v = device:GetTransform(C.D3DTS_VIEW);
    local _, p = device:GetTransform(C.D3DTS_PROJECTION);
    local m11 = v._11 * p._11 + v._12 * p._21 + v._13 * p._31 + v._14 * p._41;
    local m12 = v._11 * p._12 + v._12 * p._22 + v._13 * p._32 + v._14 * p._42;
    local m13 = v._11 * p._13 + v._12 * p._23 + v._13 * p._33 + v._14 * p._43;
    local m14 = v._11 * p._14 + v._12 * p._24 + v._13 * p._34 + v._14 * p._44;
    local m21 = v._21 * p._11 + v._22 * p._21 + v._23 * p._31 + v._24 * p._41;
    local m22 = v._21 * p._12 + v._22 * p._22 + v._23 * p._32 + v._24 * p._42;
    local m23 = v._21 * p._13 + v._22 * p._23 + v._23 * p._33 + v._24 * p._43;
    local m24 = v._21 * p._14 + v._22 * p._24 + v._23 * p._34 + v._24 * p._44;
    local m31 = v._31 * p._11 + v._32 * p._21 + v._33 * p._31 + v._34 * p._41;
    local m32 = v._31 * p._12 + v._32 * p._22 + v._33 * p._32 + v._34 * p._42;
    local m33 = v._31 * p._13 + v._32 * p._23 + v._33 * p._33 + v._34 * p._43;
    local m34 = v._31 * p._14 + v._32 * p._24 + v._33 * p._34 + v._34 * p._44;
    local m41 = v._41 * p._11 + v._42 * p._21 + v._43 * p._31 + v._44 * p._41;
    local m42 = v._41 * p._12 + v._42 * p._22 + v._43 * p._32 + v._44 * p._42;
    local m43 = v._41 * p._13 + v._42 * p._23 + v._43 * p._33 + v._44 * p._43;
    local m44 = v._41 * p._14 + v._42 * p._24 + v._43 * p._34 + v._44 * p._44;

    if (claim) then
        nameplates.Claim(nameplates.Category.All);
    end

    -- a size of its own is the font's while it is pushed
    if (big) then
        imgui.PushFont(nil, 30);
        baked = imgui.GetFontBaked();
        if (not bigSaid) then
            bigSaid = true;
            local glyph = baked:FindGlyph(65);
            say(('at 30: baked Size %s | glyph A: X0 %.2f Y0 %.2f X1 %.2f Y1 %.2f | U0 %.5f V0 %.5f U1 %.5f V1 %.5f | AdvanceX %.2f | texture %s'):format(
                tostring(baked.Size), glyph.X0, glyph.Y0, glyph.X1, glyph.Y1, glyph.U0, glyph.V0, glyph.U1, glyph.V1, glyph.AdvanceX, tostring(fontTexture())));
        end
    end
    local height = imgui.GetFontSize();
    local raise = claim and height * 0.5 or 20 + height;

    local display = imgui.GetIO().DisplaySize;

    if (numbers) then
        say(('projection: _33 %.6f _43 %.6f _34 %.3f _44 %.3f | near %.4f far %.1f'):format(p._33, p._43, p._34, p._44, -p._43 / p._33, -p._43 / (p._33 - 1)));
        try('viewport', function ()
            local _, port = device:GetViewport();
            say(('viewport: %d,%d %dx%d | MinZ %.4f MaxZ %.4f | display %dx%d'):format(port.X, port.Y, port.Width, port.Height, port.MinZ, port.MaxZ, display.x, display.y));
        end);
        local _, zEnable = device:GetRenderState(C.D3DRS_ZENABLE);
        local _, zFunc = device:GetRenderState(C.D3DRS_ZFUNC);
        local _, zWrite = device:GetRenderState(C.D3DRS_ZWRITEENABLE);
        say('as the game left it: ZENABLE', zEnable, '| ZFUNC', zFunc, '| ZWRITEENABLE', zWrite);
    end

    local planeDepth, planeName = nil, nil;
    local said = 0;
    for _, name in nameplates.Each() do
        local w = name.X * m14 + name.Y * m24 + name.Z * m34 + m44;
        if (w > 0.01) then
            local depth = (name.X * m13 + name.Y * m23 + name.Z * m33 + m43) / w;
            local words = nameplates.Name(name);
            if (numbers and said < 14) then
                said = said + 1;
                say(('%s: distance %.2f | depth %.6f'):format(words, w, depth));
            end
            if (plane ~= nil and planeDepth == nil and words:lower():sub(1, #plane) == plane) then
                planeDepth, planeName = depth, words;
            end
        end
    end
    numbers = false;

    -- the sheet, before the names so that they are written over it
    sheetDepth = planeDepth;
    if (planeDepth ~= nil) then
        if (sheetAt == 'present') then
            drawSheet(planeDepth);
        end
        write(baked, ('sheet as deep as %s: %.6f, drawn at %s'):format(planeName, planeDepth, sheetAt), 20, 410, 0, 1, 0xFFFF80E0);
        flush(texture, false);
    end

    for _, name in nameplates.Each() do
        local x, y, z = name.X, name.Y, name.Z;
        local w = x * m14 + y * m24 + z * m34 + m44;
        if (w > 0.01) then
            local words = nameplates.Name(name);
            local screenX = (1 + (x * m11 + y * m21 + z * m31 + m41) / w) * display.x * 0.5;
            local screenY = (1 - (x * m12 + y * m22 + z * m32 + m42) / w) * display.y * 0.5;
            local depth = (x * m13 + y * m23 + z * m33 + m43) / w;
            write(baked, words, screenX - measure(baked, words) * 0.5, screenY - raise, depth, 1 / w, 0xFF80FFFF);
        end
    end
    if (big) then
        imgui.PopFont();
        -- the texture may be another once letters of a new size have been put in it
        texture = fontTexture();
    end
    flush(texture, depthTest);
end

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1]:lower() ~= '/glyphtest') then
        return;
    end
    e.blocked = true;

    if (args[2] ~= nil and args[2]:lower() == 'depth') then
        depthTest = not depthTest;
        say('depth test', depthTest and 'on' or 'off');
    elseif (args[2] ~= nil and args[2]:lower() == 'claim') then
        claim = not claim;
        say('the game\'s names', claim and 'claimed: only these are drawn' or 'left to the game');
    elseif (args[2] ~= nil and args[2]:lower() == 'plane') then
        local word = args[3] and args[3]:lower() or 'off';
        plane = word ~= 'off' and word or nil;
        say('sheet', plane and ('as deep as the first name beginning ' .. plane) or 'off');
    elseif (args[2] ~= nil and args[2]:lower() == 'sheet') then
        local word = args[3] and args[3]:lower() or 'present';
        if (word == 'endscene' or word == 'beginscene' or word == 'present') then
            sheetAt = word;
        end
        say('the sheet is drawn at', sheetAt);
    elseif (args[2] ~= nil and args[2]:lower() == 'surfaces') then
        surfaces = { beginscene = true, endscene = true, present = true };
    elseif (args[2] ~= nil and args[2]:lower() == 'numbers') then
        numbers = true;
    elseif (args[2] ~= nil and args[2]:lower() == 'big') then
        big = not big;
        bigSaid = false;
        say('names at', big and '30 pixels' or 'the usual size');
    else
        report();
    end
end);

ashita.events.register('d3d_beginscene', 'beginscene_cb', function (e)
    atScene('beginscene', e);
end);

ashita.events.register('d3d_endscene', 'endscene_cb', function (e)
    atScene('endscene', e);
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    if (surfaces.present) then
        surfaces.present = nil;
        saySurfaces('present', nil);
    end
    fired.beginscene, fired.endscene = 0, 0;

    if (not reported) then
        reported = true;
        report();
    end

    local ok, problem = pcall(draw);
    if (not ok) then
        used = 0;
        problem = tostring(problem);
        if (not failed[problem]) then
            failed[problem] = true;
            say('drawing FAILED:', problem);
        end
    end
end);
