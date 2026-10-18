-- Non-text format tokens. Keep measurement and drawing on exactly the same geometry.
local nameplates = require('winxi.nameplates');
local icons = require('icons');
local tokens = {};

local function geometry(part, count, height, scale, defaultSize, defaultSpace)
    if (count == 0) then return 0, 0, 0; end
    local size = math.floor(height * (part.size or defaultSize) / 100 + 0.5);
    local gap = math.floor((part.gap or 2) * scale + 0.5);
    local space = math.floor((part.space or defaultSpace) * scale + 0.5);
    return count * size + (count - 1) * gap + space, size, gap;
end

function tokens.IconWidth(part, written, height, scale, defaultSize, defaultSpace)
    return geometry(part, #written.icons, height, scale, defaultSize, defaultSpace);
end

function tokens.WriteIcons(part, written, x, top, height, scale, defaultSize, defaultSpace, pearlColor)
    local width, size, gap = geometry(part, #written.icons, height, scale, defaultSize, defaultSpace);
    local y = top + math.floor((height - size) * 0.5);
    for index = 1, #written.icons do
        local byte = written.icons[index];
        local color = part.color or (byte == 0x92 and pearlColor or 0xFFFFFFFF);
        local at = icons.Place(byte);
        if (at) then
            nameplates.Quad(x, y, x + size, y + size, at[1], at[2], at[3], at[4], color, 1, true, 0.75);
        end
        local layers = at and icons.Overlays(byte);
        if (layers) then
            for _, layer in ipairs(layers) do
                nameplates.Quad(x + layer[1]*size, y + layer[2]*size,
                    x + layer[3]*size, y + layer[4]*size,
                    layer[5], layer[6], layer[7], layer[8], color, 1, true, 0.75);
            end
        end
        x = x + size + gap;
    end
    return width;
end

function tokens.Distance(part, written)
    local decimals = part.decimals or 1;
    if (decimals == 1) then return written.far or ''; end
    if (written.distanceValue == nil) then return ''; end
    written.preciseDistance = written.preciseDistance or {};
    local factor = decimals == 0 and 1 or 100;
    local rounded = math.floor(written.distanceValue * factor + 0.5);
    local cached = written.preciseDistance[decimals];
    if (cached == nil or cached.value ~= rounded) then
        cached = { value = rounded, text = (decimals == 0 and '%d' or '%.2f'):format(rounded / factor) };
        written.preciseDistance[decimals] = cached;
    end
    return cached.text;
end

return tokens;
