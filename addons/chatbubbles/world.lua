-- Independent namehook world layer: never write to the name replacement buffer.
local ffi = require('ffi');
local abi = require('winxi.abi');
local imgui = require('imgui');
local nameplates = require('winxi.nameplates');
local fonts = require('winxi.fonts');
local bubbles = require('bubbles');
local colors = require('colors');
local skin = require('skin');
ffi.cdef[[
    typedef struct {
        char Magic[16];
        uint32_t Version, Size, DrawSize;
        uint32_t ServerIds[0x900];
        namehook_draw_t Draw;
    } chatbubbles_world_t;
]];
local M = {};
local block;
local blockGeneration; -- nameplates.Generation() when block was found
local problem;
local remaining = 0;
local lookedAt = -math.huge;

function M.Problem() return problem; end

function M.Begin(hook)
    if (hook == nil) then block = nil; problem = 'namehook unavailable'; return nil; end
    -- found in a namehook since unloaded or loaded again: gone with it
    if (block ~= nil and blockGeneration ~= nameplates.Generation()) then block = nil; lookedAt = -math.huge; end
    if (block == nil) then
        local now = os.clock();
        if (now - lookedAt < 1) then return nil; end
        lookedAt = now;
        -- Exactly 16 bytes: "NAMEBUBBLES" (11 bytes) followed by five zeros.
        local address = ashita.memory.find('namehook.dll', 0, '4E414D45425542424C45530000000000', 0, 0);
        if (not address or address == 0) then
            problem = 'World bubbles require namehook 1.25 or later. Replace namehook.dll and reload the plugin.';
            return nil;
        end
        local candidate = ffi.cast('chatbubbles_world_t*', address);
        -- version 2: a texture may be winxi.fonts.TextureMark, which version 1 took for an address
        if (not abi.Accepts(candidate, 'chatbubbles_world_t', 2, 'Draw') or candidate.DrawSize < ffi.offsetof('namehook_draw_t', 'TexturesExtra')) then
            problem = 'Incompatible namehook world-bubble buffer: World bubbles require namehook 1.25 or later.';
            return nil;
        end
        block, blockGeneration = candidate, nameplates.Generation();
    end
    -- Reuse the quad writer, but point it at this separate buffer, not hook.Draw.
    local target = {
        Hooked = hook.Hooked, Frame = hook.Frame,
        Draw = tonumber(ffi.cast('uintptr_t', ffi.cast('uint8_t*', block) + ffi.offsetof('chatbubbles_world_t', 'Draw'))),
        Width = hook.Width, TargetWidth = hook.TargetWidth, TargetHeight = hook.TargetHeight,
    };
    local scale = nameplates.BeginDrawing(target, true);
    problem = nil;
    if (not scale) then problem = 'namehook world renderer is not hooked'; end
    remaining = math.min(16384, tonumber(block.Draw.QuadsMax));
    return scale;
end

function M.Clear()
    -- Validate plugin lifetime and generation before dereferencing a cached DLL address.
    if (nameplates.Hook() ~= nil and block ~= nil and blockGeneration == nameplates.Generation()) then block.Draw.QuadCount = 0; end
    block = nil;
    lookedAt = -math.huge;
end

local function whiteUV(atlas)
    if (imgui.GetFontTexUvWhitePixel) then
        local x, y = imgui.GetFontTexUvWhitePixel();
        if (type(x) == 'number') then return x, y; end
        if (x ~= nil) then return x.x, x.y; end
    end
    local white = atlas.TexUvWhitePixel;
    return white.x, white.y;
end

local function codepoint(character)
    local a, b, c, d = character:byte(1, 4);
    if (a < 128) then return a; end
    if (a < 224) then return (a - 192) * 64 + b - 128; end
    if (a < 240) then return (a - 224) * 4096 + (b - 128) * 64 + c - 128; end
    return (a - 240) * 262144 + (b - 128) * 4096 + (c - 128) * 64 + d - 128;
end

local function color(rgba)
    local function byte(value) return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5); end
    return byte(rgba[4]) * 0x1000000 + byte(rgba[1]) * 0x10000 + byte(rgba[2]) * 0x100 + byte(rgba[3]);
end

function M.Draw(name, message, now, scale, appearance)
    local font = imgui.GetFont();
    local size = imgui.GetFontSize();
    local baked = imgui.GetFontBaked();
    local lines = bubbles.Wrap(message.text, 280, function(text) return imgui.CalcTextSize(text); end);
    local runs, width, glyphCount = {}, 0, 0;
    -- Materialize glyphs before obtaining the atlas texture, which may grow.
    for _, line in ipairs(lines) do
        local run = { glyphs = {}, width = 0 };
        for character in line:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
            local glyph = baked:FindGlyph(codepoint(character));
            if (glyph) then
                if (glyph.Visible ~= 0 and glyph.Visible ~= false) then
                    glyphCount = glyphCount + 1;
                    run.glyphs[#run.glyphs + 1] = { glyph.X0 + run.width, glyph.Y0,
                        glyph.X1 + run.width, glyph.Y1, glyph.U0, glyph.V0, glyph.U1, glyph.V1 };
                end
                run.width = run.width + glyph.AdvanceX;
            end
        end
        runs[#runs + 1] = run;
        width = math.max(width, run.width);
    end
    -- Reserve the background (the skin's quads, or one) + 8 stepped pointer quads. Never publish
    -- truncated text.
    local skinned = appearance ~= nil and appearance.skin ~= nil and appearance.skin[1] == 'parchment';
    local padding = appearance ~= nil and appearance.padding ~= nil and appearance.padding[1] or 10;
    local borderTexture, linesTexture;
    if (appearance ~= nil) then borderTexture, linesTexture = skin.Textures(appearance); end
    local arrow = message.waiting == true;
    local height = #runs * size + 2 * padding + (arrow and skin.ArrowSize + 2 or 0);
    local reserved = 8 + (appearance ~= nil and skin.Quads(width + 2 * padding, height, appearance, borderTexture, linesTexture) or 1)
        + (arrow and skin.ArrowQuads or 0);
    if (glyphCount + reserved > 256) then
        problem = 'Bubble text exceeds the 256-quad per-entity budget';
        return false;
    end
    if (glyphCount + reserved > remaining) then
        problem = 'World bubble buffer is full this frame';
        return false;
    end
    local atlas = font.ContainerAtlas;
    -- every font is in the one atlas: the texture is the same whichever font is in use, and the
    -- plugin is given its mark and reads it itself
    local id, why = fonts.Texture();
    if (id == nil) then
        problem = why;
        return false;
    end
    local uvOK, u, v = pcall(whiteUV, atlas);
    if (not uvOK or type(u) ~= 'number' or type(v) ~= 'number') then
        problem = 'ImGui atlas white-pixel UV is unavailable';
        return false;
    end
    local fit = scale * math.max(0.65, math.min(1, tonumber(name.Scale)));
    local left, bottom = -(width + 2 * padding) / 2, -34;
    local top = bottom - height;
    local alpha = math.min(1, math.max(0, (message.expires - now) / 0.6));
    -- the plain skin's rectangle is the background colour; the parchment's pointer its bottom colour
    local background = appearance and color(skinned and appearance.skinBottom or appearance.background) or 0xEB15171F;
    local gameColor = colors.ForMessage(message, appearance);
    local foreground = gameColor or (appearance and color(appearance.text) or 0xFFFFFFFF);
    -- Preserve the selected RGB even on white bubbles; outline the glyphs rather
    -- than silently changing light chat colors to dark colors for contrast.
    local outline = gameColor ~= nil and skin.Light(appearance, skinned);
    nameplates.SetTexture(0, id);
    nameplates.SetTexture(1, borderTexture or 0);
    nameplates.SetTexture(2, linesTexture or 0);
    if (not nameplates.BeginName(name.EntityIndex, alpha, outline and fit or 0, 0xD0000000)) then return false; end
    block.ServerIds[name.EntityIndex] = name.ServerId;
    local function quad(x0, y0, x1, y1, u0, v0, u1, v1, color, edged, slot)
        nameplates.Quad(x0 * fit, y0 * fit, x1 * fit, y1 * fit, u0, v0, u1, v1, color, slot or 0, edged or false);
    end
    local function plain(x0, y0, x1, y1, u0, v0, u1, v1, color, slot) quad(x0, y0, x1, y1, u0, v0, u1, v1, color, false, slot); end
    if (appearance ~= nil) then
        skin.World(plain, u, v, left, top, width + 2 * padding, height, appearance, borderTexture and 1 or nil, linesTexture and 2 or nil);
    else
        quad(left, top, left + width + 2 * padding, bottom, u, v, u, v, background);
    end
    for i = 0, 7 do
        local half = (8 - i) * 0.75;
        quad(-half, bottom + i, half, bottom + i + 1, u, v, u, v, background);
    end
    for i, run in ipairs(runs) do
        for _, glyph in ipairs(run.glyphs) do
            local x, y = left + padding, top + padding + (i - 1) * size;
            quad(x + glyph[1], y + glyph[2], x + glyph[3], y + glyph[4],
                glyph[5], glyph[6], glyph[7], glyph[8], foreground, outline);
        end
    end
    if (arrow and skin.ArrowShown(now)) then
        skin.ArrowWorld(plain, u, v, left + width + 2 * padding - math.max(2, padding), bottom - 2, foreground);
    end
    nameplates.EndName();
    remaining = remaining - glyphCount - reserved;
    return true;
end

return M;
