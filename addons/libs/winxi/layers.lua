-- winxi.layers: drawing into the world through the namehook plugin (1.46 and newer), anchored to an entity or
-- to a point of the world, each drawing placed and hidden as a name is (as deep in the picture as its point,
-- behind what is in front of it unless drawn over everything, at its own shape under lens's warp). Up to four
-- addons each take a layer; layers are drawn by their order, lowest first.
--
--   local owner = nameplates.OwnerOf(addon.name)
--   layer = layer or layers.Take(owner, order)          -- nil and why where none is free or the plugin is older
--   local scale = layer and layers.Begin(layer, owner)  -- each frame: nil once the layer is no longer the addon's
--   if scale then
--       layers.SetTexture(0, texture)                    -- 0 to 31
--       if layers.AtEntity(index, serverId, 0, 0.5, 0, alpha, edge, edgeColor) then   -- offset in the world
--           layers.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, ...)  -- as nameplates.Quad, in pixels
--           layers.End()                                                     -- of the game's picture, by scale
--       end
--       if layers.AtWorld(x, y, z, alpha, edge, edgeColor, over) then ... layers.End() end
--   else layer = nil end
--   layers.Release(layer, owner)                         -- on unload
--
-- A layer not begun again within half a second lapses, and the plugin frees it. Quads are laid out as
-- nameplates.BeginDrawing(hook, true) lays out names: uniform in the picture's height, their X put right for
-- a picture of another shape than the screen.
local ffi = require('ffi');
local abi = require('winxi.abi');
local nameplates = require('winxi.nameplates');

ffi.cdef[[
    typedef struct {
        uint32_t Flags;
        uint32_t EntityIndex;
        uint32_t ServerId;
        float    X, Y, Z;
        namehook_drawing_t Drawing;
    } namehook_layer_drawing_t;

    typedef struct {
        uint32_t Frame;
        uint32_t QuadCount;
        uint32_t QuadsMax;
        uint32_t Reserved;
        uint32_t Textures[32];
        uint32_t Count;
        uint32_t DrawingsMax;
        namehook_layer_drawing_t Drawings[512];
        namehook_quad_t Quads[8192];
    } namehook_layer_draw_t;

    typedef struct {
        uint32_t Owner;
        uint32_t ClaimFrame;
        uint32_t Order;
        uint32_t Draw;
        uint32_t Reserved[4];
    } namehook_layer_slot_t;

    typedef struct {
        char     Magic[16];
        uint32_t Version;
        uint32_t Size;
        uint32_t SlotSize;
        uint32_t SlotsMax;
        uint32_t Reserved[4];
        namehook_layer_slot_t Slots[4];
    } namehook_layers_t;
]];

local layers = {};

local MAGIC = '4E414D45484F4F4B4C41594552530000'; -- "NAMEHOOKLAYERS" and the two 0s after it
local LOOK_EVERY = 1;
local AT_ENTITY, AT_WORLD, DRAW_OVER = 1, 2, 4;
local DRAWINGS_MAX, QUADS_MAX, QUADS_PER_DRAWING, TEXTURES = 512, 8192, 256, 32;

local block, blockGeneration, lookedAt = nil, nil, -LOOK_EVERY;
local draw, drawing, horizontalFit, quadLimit = nil, nil, 1, 0;

local function Find()
    local names = nameplates.Hook();
    if (names == nil) then block, lookedAt = nil, -LOOK_EVERY; return nil, 'The namehook plugin is not loaded: /load namehook'; end
    local generation = nameplates.Generation();
    if (block ~= nil and blockGeneration ~= generation) then block, lookedAt = nil, -LOOK_EVERY; end
    if (block == nil) then
        local now = os.clock();
        if (now - lookedAt < LOOK_EVERY) then return nil, 'Looking for namehook\'s layers.'; end
        lookedAt = now;
        local found = ashita.memory.find(nameplates.Plugin .. '.dll', 0, MAGIC, 0, 0);
        if (found == nil or found == 0) then return nil, 'Drawing into the world needs namehook 1.46 or newer.'; end
        local candidate = ffi.cast('namehook_layers_t*', found);
        if (not abi.Accepts(candidate, 'namehook_layers_t', 1) or candidate.SlotSize ~= ffi.sizeof('namehook_layer_slot_t')) then
            return nil, 'namehook keeps its layers another way than this addon reads: one of the two is older than the other.';
        end
        block, blockGeneration = candidate, generation;
    end
    return block, names;
end

local function SlotOf(layer)
    local b, names = Find();
    if (b == nil or layer == nil or layer < 1 or layer > math.min(b.SlotsMax, 4)) then return nil; end
    return b.Slots[layer - 1], names;
end

-- Takes a free layer for owner (or the one it holds already), drawn at order among the others (lower first):
-- the layer's number, or nil and why not
function layers.Take(owner, order)
    local b, why = Find();
    if (b == nil) then return nil, why; end
    local names = nameplates.Hook();
    local free = nil;
    for i = 0, math.min(b.SlotsMax, 4) - 1 do
        if (b.Slots[i].Owner == owner) then return i + 1; end
        if (free == nil and b.Slots[i].Owner == 0) then free = i; end
    end
    if (free == nil) then return nil, 'Every one of namehook\'s layers is taken by another addon.'; end
    local s = b.Slots[free];
    s.Order, s.ClaimFrame = order or 0, names.Frame;
    s.Owner = owner; -- last: the layer is the addon's once the rest is in place
    return free + 1;
end

-- Renews the layer and begins this frame's drawings: the scale from the screen's pixels to the picture's, or
-- nil where the layer is no longer the owner's
local imgui = nil;
function layers.Begin(layer, owner, order)
    draw, drawing, horizontalFit = nil, nil, 1;
    local s, names = SlotOf(layer);
    if (s == nil or s.Owner ~= owner or s.Draw == 0) then return nil; end
    s.ClaimFrame = names.Frame;
    if (order ~= nil) then s.Order = order; end
    draw = ffi.cast('namehook_layer_draw_t*', s.Draw);
    draw.Frame = names.Frame;
    draw.Count = 0;
    draw.QuadCount = 0;
    draw.Reserved = 0;
    quadLimit = math.min(draw.QuadsMax, QUADS_MAX);
    imgui = imgui or require('imgui');
    local display = imgui.GetIO().DisplaySize;
    local width = display.x > 0 and display.x or names.Width;
    local height = display.y > 0 and display.y or names.Height;
    if (names.TargetWidth > 0 and names.TargetHeight > 0 and width > 0 and height > 0) then
        local scaleX, scaleY = names.TargetWidth / width, names.TargetHeight / height;
        horizontalFit = scaleX / scaleY;
        draw.Reserved = math.max(1, math.min(0xFFFFFFFF, math.floor(horizontalFit * 65536 + 0.5)));
        return scaleY;
    end
    return 1;
end

-- slot 0 to 31: a Direct3D texture's address, or winxi.fonts.TextureMark for imgui's font texture
function layers.SetTexture(slot, texture)
    if (draw == nil or slot < 0 or slot >= TEXTURES) then return false; end
    draw.Textures[slot] = texture or 0;
    return true;
end

local function Start(flags, entityIndex, serverId, x, y, z, alpha, edge, edgeColor, over)
    drawing = nil;
    if (draw == nil or draw.Count >= math.min(draw.DrawingsMax, DRAWINGS_MAX) or draw.QuadCount >= quadLimit) then return false; end
    local d = draw.Drawings[draw.Count];
    d.Flags = flags + (over and DRAW_OVER or 0);
    d.EntityIndex, d.ServerId = entityIndex, serverId;
    d.X, d.Y, d.Z = x or 0, y or 0, z or 0;
    d.Drawing.Frame = draw.Frame;
    d.Drawing.First = draw.QuadCount;
    d.Drawing.Count = 0;
    d.Drawing.Alpha = alpha or 1;
    d.Drawing.Edge = edge or 0;
    d.Drawing.EdgeColor = edgeColor or 0;
    drawing = d.Drawing;
    draw.Count = draw.Count + 1;
    return true;
end

-- A drawing at an entity's name point, offset by (dx, dy, dz) in the world: drawn while serverId is still the
-- entity at that index
function layers.AtEntity(entityIndex, serverId, dx, dy, dz, alpha, edge, edgeColor, over)
    return Start(AT_ENTITY, entityIndex, serverId, dx, dy, dz, alpha, edge, edgeColor, over);
end

-- A drawing at a point of the world
function layers.AtWorld(x, y, z, alpha, edge, edgeColor, over)
    return Start(AT_WORLD, 0, 0, x, y, z, alpha, edge, edgeColor, over);
end

function layers.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled)
    if (drawing == nil or drawing.Count >= QUADS_PER_DRAWING or drawing.First + drawing.Count >= quadLimit) then return false; end
    nameplates.FillQuad(draw.Quads[drawing.First + drawing.Count], horizontalFit,
        x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled);
    drawing.Count = drawing.Count + 1;
    return true;
end

function layers.End()
    if (drawing ~= nil) then
        draw.QuadCount = drawing.First + drawing.Count;
        drawing = nil;
    end
end

-- Gives the layer back, its drawings cleared, where it is still the owner's
function layers.Release(layer, owner)
    draw, drawing, quadLimit = nil, nil, 0;
    local s, names = SlotOf(layer);
    if (s == nil or s.Owner ~= owner) then return; end
    if (s.Draw ~= 0) then
        local target = ffi.cast('namehook_layer_draw_t*', s.Draw);
        target.Count, target.QuadCount = 0, 0;
        ffi.fill(target.Textures, ffi.sizeof(target.Textures));
        target.Frame = names.Frame - 9;
    end
    s.Owner = 0;
end

return layers;
