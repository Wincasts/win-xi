-- Standalone real FFI/quad writer test; Linux + LuaJIT, no client/GPU needed.
package.path = './addons/chatbubbles/?.lua;./addons/libs/?.lua;' .. package.path;
local ffi = require('ffi');
package.preload['winxi.theme'] = function() return { For = function() return ''; end, Get = function() return {}; end }; end; -- winxi.fonts' theme, which needs Ashita
local codes = {};
local atlas = {
    TexData = { UniqueID = 2, Status = 0, Width = 512, Height = 256 },
    TexUvWhitePixel = { x = 0.5, y = 0.5 },
};
local font = { ContainerAtlas = atlas };
local baked = { FindGlyph = function(_, code)
    codes[code] = true;
    return { X0 = 0, Y0 = 0, X1 = 8, Y1 = 16, AdvanceX = 8,
        U0 = 0, V0 = 0, U1 = 1, V1 = 1, Visible = true };
end };
package.loaded.imgui = {
    GetIO = function() return { DisplaySize = { x = 1920, y = 1080 } }; end,
    GetFont = function() return font; end,
    GetFontSize = function() return 16; end,
    GetFontBaked = function() return baked; end,
    CalcTextSize = function(s) return #s * 8, 16; end,
};
local nameplates = require('winxi.nameplates');
local world = require('world');
ffi.cdef('void* mmap(void*, size_t, int, int, int, long); int munmap(void*, size_t);');
local size = ffi.sizeof('chatbubbles_world_t');
local low = ffi.C.mmap(nil, size, 3, 0x62, -1, 0);
assert(low ~= ffi.cast('void*', -1));
local block = ffi.cast('chatbubbles_world_t*', low);
ffi.copy(block.Magic, 'NAMEBUBBLES', 11);
block.Version, block.Size, block.DrawSize = 2, size, ffi.sizeof('namehook_draw_t');
block.Draw.QuadsMax = 16384;
local address = tonumber(ffi.cast('uintptr_t', low));
local available = true;
ashita = { memory = { find = function(_, _, magic)
    -- Derive the expected signature from the native struct, not another copy
    -- of the Lua search string: an extra zero previously escaped this test.
    local bytes = magic:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)); end);
    assert(#bytes == 16 and bytes == ffi.string(block.Magic, 16), 'signature must match native 16-byte Magic');
    -- When a built DLL is available, check the actual optimized binary too.
    local dll = io.open('plugins/namehook/build/namehook.dll', 'rb');
    if (dll) then
        local binary = dll:read('*a'); dll:close();
        local first = assert(binary:find(bytes, 1, true), 'bubble signature missing from built DLL');
        local header = ffi.new('uint32_t[3]');
        ffi.copy(header, binary:sub(first + 16, first + 27), 12);
        assert(header[0] == 2 and header[1] == size and header[2] == ffi.sizeof('namehook_draw_t'),
            'compiled bubble ABI must match Lua');
    end
    return available and address or 0;
end } };
local hook = { Hooked = 1, Frame = 100, Width = 640, Height = 480,
    TargetWidth = 2048, TargetHeight = 2048, Draw = 0x1234 };
local loaded = true;
nameplates.Hook = function() return loaded and hook or nil; end;
local scale = world.Begin(hook);
assert(math.abs(scale - 2048 / 1080) < 0.001 and world.Problem() == nil);
assert(hook.Draw == 0x1234); -- name's draw buffer must never be touched
local name = { EntityIndex = 5, ServerId = 12345, Scale = 1 };
assert(world.Draw(name, { text = 'Hi', expires = 108 }, 100, scale));
assert(block.Draw.Frame == 100 and block.Draw.QuadCount == 11);
assert(block.ServerIds[5] == 12345 and block.Draw.Entities[5].Count == 11);
assert(block.Draw.Textures[0] == 1 and block.Draw.Entities[5].Alpha == 1);
assert(codes[72] and codes[105]);
local bg = block.Draw.Quads[0];
assert(math.abs((bg.X1 - bg.X0) * 1920 / 2048 - 36) < 0.01);
assert(math.abs((bg.Y1 - bg.Y0) * 1080 / 2048 - 32) < 0.01);
assert(bg.Color == 0xEB15171F and bg.U0 == bg.U1 and bg.V0 == bg.V1);
-- Appearance is supplied independently of layout, ready for future style fields.
world.Begin(hook);
assert(world.Draw(name, { text = 'White', expires = 108 }, 100, scale,
    { background = { 1, 1, 1, 1 }, text = { 0, 0, 0, 1 } }));
assert(block.Draw.Quads[0].Color == 0xFFFFFFFF and block.Draw.Quads[9].Color == 0xFF000000);
assert(block.Draw.Quads[1].Color == 0xFFFFFFFF); -- pointer follows the background
local colors = require('colors');
local oldColor = colors.ForMessage;
colors.ForMessage = function(message, appearance)
    assert(message.mode == 3 and appearance.gameTextColors[1]);
    return 0xFF123456;
end;
world.Begin(hook);
assert(world.Draw(name, { text = 'Tell', mode = 3, expires = 108 }, 100, scale,
    { background = { 1,1,1,1 }, text = { 0,0,0,1 }, gameTextColors = { true } }));
assert(block.Draw.Quads[0].Color == 0xFFFFFFFF and block.Draw.Quads[9].Color == 0xFF123456);
assert(block.Draw.Quads[0].Flags == 0 and block.Draw.Quads[9].Flags == 1);
assert(block.Draw.Entities[5].Edge > 0); -- contrast outline without changing the selected RGB
colors.ForMessage = oldColor;
-- The parchment skin: a gradient in strips, the lines tile and the border's nine slices from the
-- textures winxi loads, in the plugin's slots 1 and 2, before the pointer and the text
local skin = require('skin');
skin.LoadBorder = function() return 0x7001; end;
skin.LoadLines = function() return 0x7002; end;
local parchment = { background = { 1, 1, 1, 1 }, text = { 0.2, 0.1, 0.1, 1 }, skin = { 'parchment' },
    skinTop = { 0.9, 0.8, 0.7, 1 }, skinBottom = { 0.7, 0.6, 0.4, 1 } };
world.Begin(hook);
assert(world.Draw(name, { text = 'Hi', expires = 108 }, 100, scale, parchment));
assert(block.Draw.Textures[1] == 0x7001 and block.Draw.Textures[2] == 0x7002);
assert(block.Draw.QuadCount == 12 + 1 + 8 + 8 + 2, 'twelve strips, one tile, eight slices, the pointer and two letters');
local first, last = block.Draw.Quads[0], block.Draw.Quads[11];
assert(first.Color == 0xFFE3CAAF and last.Color == 0xFFB59B69, 'the strips go from the top colour to the bottom');
assert(block.Draw.Quads[12].Texture == 2 and block.Draw.Quads[13].Texture == 1 and block.Draw.Quads[20].Texture == 1);
assert(block.Draw.Quads[21].Color == 0xFFB39966 and block.Draw.Quads[21].Texture == 0, 'the pointer is the bottom colour');
assert(block.Draw.Quads[29].Color == 0xFF331A1A, 'the text its own colour');
world.Begin(hook);
assert(not world.Draw(name, { text = ('a'):rep(228), expires = 108 }, 100, scale, parchment), 'the skin counts against the budget');
-- UTF-8 decoded to glyph codepoints, not one glyph per byte.
hook.Frame = 101;
world.Begin(hook);
assert(world.Draw(name, { text = 'éあ', expires = 101.3 }, 101, scale));
assert(codes[0xE9] and codes[0x3042] and block.Draw.QuadCount == 11);
assert(math.abs(block.Draw.Entities[5].Alpha - 0.5) < 0.001);
-- Refuse an over-budget message rather than publishing partial text.
assert(not world.Draw(name, { text = ('a'):rep(248), expires = 108 }, 101, scale));
-- Both common Lua bindings for white-pixel UVs are supported, with clear errors.
local imgui = package.loaded.imgui;
imgui.GetFontTexUvWhitePixel = function() return 0.5, 0.5; end;
world.Begin(hook);
assert(world.Draw(name, { text = 'API', expires = 108 }, 101, scale));
imgui.GetFontTexUvWhitePixel = function() return { x = 0.5, y = 0.5 }; end;
world.Begin(hook);
assert(world.Draw(name, { text = 'Vector', expires = 108 }, 101, scale));
imgui.GetFontTexUvWhitePixel = nil;
local white = atlas.TexUvWhitePixel;
atlas.TexUvWhitePixel = nil;
world.Begin(hook);
assert(not world.Draw(name, { text = 'UV missing', expires = 108 }, 101, scale));
assert(world.Problem():find('white%-pixel'));
atlas.TexUvWhitePixel = white;
atlas.TexData.Status = 2; -- imgui has it not ready
world.Begin(hook);
assert(not world.Draw(name, { text = 'Texture missing', expires = 108 }, 101, scale));
assert(world.Problem():find('texture'));
atlas.TexData.Status = 0;
hook.Hooked = 0;
assert(world.Begin(hook) == nil and world.Problem():find('not hooked', 1, true));
hook.Hooked = 1;
-- Empty frames and clear/unload remove all published quads.
world.Begin(hook);
assert(block.Draw.QuadCount == 0);
world.Clear();
available = false;
assert(world.Begin(hook) == nil and world.Problem():find('1.25', 1, true));
available = true;
world.Clear();
block.Version = 1; -- an older plugin, which would take the font's mark for an address
assert(world.Begin(hook) == nil and world.Problem():find('Incompatible', 1, true));
block.Version = 2;
world.Clear();
assert(world.Begin(hook));
loaded = false;
world.Clear(); -- must not dereference plugin memory after it is unloaded
ffi.C.munmap(low, size);
print('chatbubbles world: independent ABI, UTF-8 glyphs, quads, the parchment skin, aspect, alpha, limits and compatibility checks passed');
