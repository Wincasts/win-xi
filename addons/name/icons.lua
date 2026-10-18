-- Player-name icons and mastery stars use a bundled atlas, just like mob aggro icons.
-- No signature scans, borrowed game textures, or runtime font/shape memory reads.
-- The mapping was exported with the PNG from the client's high-resolution fontshp.
local rectangles = require('assets.player-icons');
local overlays = require('assets.player-icon-overlays');
local icons = {};
local places = {};
local handle = nil;

for byte, rect in pairs(rectangles) do
    places[byte] = { rect[1] / 256, rect[2] / 256, rect[3] / 256, rect[4] / 256 };
end

-- Kept for the addon's load-time initialization; mapping discovery is now deterministic.
function icons.Find()
    return true;
end

-- Use the same owned file-texture loader/cache as the other icon sheets. Failed loads
-- are retried by that loader; UVs remain available independently of texture readiness.
function icons.Begin(loadSheet)
    if (loadSheet ~= nil) then
        local loaded = loadSheet('player-icons.png');
        handle = loaded ~= nil and loaded ~= 0 and loaded or nil;
    end
    return handle ~= nil;
end

function icons.Texture()
    return handle;
end

function icons.Place(byte)
    return handle ~= nil and (places[byte] or false) or false;
end

-- Composite status badges have their own geometry; a neighbouring byte is not
-- another full-size layer. The caller draws these only when the base texture is ready.
function icons.Overlays(byte)
    return overlays[byte];
end

function icons.Has(byte)
    return icons.Place(byte) ~= false;
end

local cornerA, cornerB, uvA, uvB = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };

function icons.Draw(drawList, byte, x, y, size, color)
    local at = icons.Place(byte);
    if (not at) then
        return;
    end
    cornerA[1], cornerA[2], cornerB[1], cornerB[2] = x, y, x + size, y + size;
    uvA[1], uvA[2], uvB[1], uvB[2] = at[1], at[2], at[3], at[4];
    drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, color);
    local layers = overlays[byte];
    if (layers) then
        for _, layer in ipairs(layers) do
            cornerA[1], cornerA[2] = x+layer[1]*size, y+layer[2]*size;
            cornerB[1], cornerB[2] = x+layer[3]*size, y+layer[4]*size;
            uvA[1], uvA[2], uvB[1], uvB[2] = layer[5], layer[6], layer[7], layer[8];
            drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, color);
        end
    end
end

return icons;
