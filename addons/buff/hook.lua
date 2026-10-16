-- The buffhook plugin, by way of the block it keeps in its DLL: it draws the anchored bar where, and
-- when, the game draws its own row of status icons, in their place, so that the menus the game opens
-- over them are drawn over the bar too. See plugins/buffhook/README.md.
--
--   hook.Block()          the plugin's block, or nil while it is not loaded, or not one this reads,
--                         or has not taken the game's drawing of its icons
--   hook.Problem()        a sentence for the settings while there is no block, or nil
--   hook.Drawn(block)     whether the game drew its icons, with the bar in their place, last frame
--   hook.Origin(block)    where it put the first of them, in imgui's pixels: x, y, or nil before it has
--   hook.Scale(block)     how many of the game's pixels there are to one of imgui's: x, y
--
-- Every frame the bar is to take the game's icons' place, whether there is anything in it or not:
--   hook.Begin(block)     starts the bar afresh
--   hook.Texture(address) the slot for a Direct3D texture's address, or nil when the slots are full
--   hook.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot)   a rectangle of it, in the game's pixels
--                         from where the game puts its first icon; color as 0xAARRGGBB
--   hook.Finish()         hands it over
-- A frame without one gives the game its own icons back, a frame or two later.
local ffi = require('ffi');
local imgui = require('imgui');

ffi.cdef[[
    typedef struct {
        float    X0, Y0, X1, Y1;
        float    U0, V0, U1, V1;
        uint32_t Color;
        uint32_t Texture;
    } buffhook_quad_t;

    typedef struct {
        char     Magic[16];
        uint32_t Version;
        uint32_t Size;
        uint32_t Hooked;
        uint32_t Frame;
        uint32_t DrawnFrame;
        float    OriginX, OriginY;
        float    Width, Height;
        uint32_t SubmitFrame;
        uint32_t Count;
        uint32_t Textures[48];
        buffhook_quad_t Quads[1024];
    } buffhook_t;
]]

local hook = {};

hook.Plugin = 'buffhook';

local MAGIC = '42554646484F4F4B2D53484152454400'; -- "BUFFHOOK-SHARED" and its 0
local VERSION = 1;
local TEXTURES, QUADS = 48, 1024;
local DRAW_FRAMES = 2;
local LOOK_EVERY = 1; -- seconds between looks for the block while it is not found

local block = nil;
local why = 'unloaded';
local lookedAt = -LOOK_EVERY;

local problems = {
    unloaded = 'Load the buffhook plugin (/load buffhook) for the anchored bar to go under the menus that open over it, as the game\'s icons do. Without it the bar is drawn over everything.',
    old      = 'The buffhook plugin loaded is not one this addon reads: install the plugin that came with it.',
    mismatch = 'The buffhook plugin loaded is older or newer than this addon: install the plugin that came with it.',
    unhooked = 'The buffhook plugin did not recognise this client\'s status icons: the anchored bar is drawn over everything.',
};

-- The block lives in the plugin's DLL, so it is let go of the moment the plugin is no longer loaded.
local function Find()
    if not AshitaCore:GetPluginManager():IsLoaded(hook.Plugin) then
        block, why, lookedAt = nil, 'unloaded', -LOOK_EVERY;
        return nil;
    end
    if block ~= nil then
        return block;
    end
    local now = os.clock();
    if now - lookedAt < LOOK_EVERY then
        return nil;
    end
    lookedAt = now;

    local found = ashita.memory.find(hook.Plugin .. '.dll', 0, MAGIC, 0, 0);
    if found == nil or found == 0 then
        why = 'old';
        return nil;
    end
    local candidate = ffi.cast('buffhook_t*', found);
    if candidate.Version ~= VERSION or candidate.Size ~= ffi.sizeof('buffhook_t') then
        why = 'mismatch';
        return nil;
    end
    block, why = candidate, nil;
    return block;
end

function hook.Block()
    local found = Find();
    if found ~= nil and found.Hooked == 0 then
        why = 'unhooked';
        return nil;
    end
    return found;
end

function hook.Problem()
    if hook.Block() ~= nil then
        return nil;
    end
    return problems[why];
end

function hook.Drawn(found)
    return found.DrawnFrame ~= 0 and found.Frame - found.DrawnFrame <= DRAW_FRAMES;
end

function hook.Scale(found)
    local display = imgui.GetIO().DisplaySize;
    local w, h = display.x or display[1], display.y or display[2];
    if found.Width <= 0 or found.Height <= 0 or not w or not h or w <= 0 or h <= 0 then
        return 1, 1;
    end
    return found.Width / w, found.Height / h;
end

function hook.Origin(found)
    if found.DrawnFrame == 0 then
        return nil;
    end
    local sx, sy = hook.Scale(found);
    return found.OriginX / sx, found.OriginY / sy;
end

-- The bar being written: the textures it uses so far, by address, and how many quads; and how many
-- textures the last bar handed over had, whose slots are emptied if this one has fewer
local writing = nil;
local slots = {};
local slotCount, count, lastSlotCount = 0, 0, TEXTURES;

function hook.Begin(found)
    writing = found;
    for address in pairs(slots) do slots[address] = nil; end
    slotCount, count = 0, 0;
end

function hook.Texture(address)
    if writing == nil or address == nil or address == 0 then
        return nil;
    end
    local slot = slots[address];
    if slot == nil then
        if slotCount >= TEXTURES then
            return nil;
        end
        slot = slotCount;
        slots[address], slotCount = slot, slotCount + 1;
    end
    return slot;
end

function hook.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot)
    if writing == nil or slot == nil or count >= QUADS then
        return;
    end
    local quad = writing.Quads[count];
    quad.X0, quad.Y0, quad.X1, quad.Y1 = x0, y0, x1, y1;
    quad.U0, quad.V0, quad.U1, quad.V1 = u0, v0, u1, v1;
    quad.Color, quad.Texture = color, slot;
    count = count + 1;
end

function hook.Finish()
    if writing == nil then
        return;
    end
    for address, slot in pairs(slots) do
        writing.Textures[slot] = address;
    end
    for slot = slotCount, lastSlotCount - 1 do
        writing.Textures[slot] = 0;
    end
    lastSlotCount = slotCount;
    writing.Count = count;
    writing.SubmitFrame = writing.Frame;
    writing = nil;
end

return hook;
