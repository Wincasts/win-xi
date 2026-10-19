-- Compact rounded badges: white fill, genuinely transparent glyph cutout.
-- Glyphs come from the renderer's fixed Arial Bold indicator font.
local ffi = require('ffi');
local image = require('gdi.image');
local atlas = require('gdi.atlas');
local diag = require('diag');
local badges = { Slot = 5, Font = 'arialbd.ttf', Scale = 0.68, Pair = 1.5 }; -- Pair: a double letter's box, in sides
local cached, pendingKey, failedKey, nextRetry, warned = nil, nil, nil, 0, false;
local identity;

-- Glyph layout is the same ten-element array used by custom.lua.
-- Sample just inside UV boundaries so adjacent atlas glyphs cannot bleed in.
-- glyph is one letter's, for a square badge, or a list of two letters' for a
-- wider badge with both cut out of the one box.
function badges.Raster(source, glyph, height, bold)
    local glyphs = type(glyph[1]) == 'table' and glyph or { glyph };
    local pad = math.max(1, math.floor(height * 0.09 + 0.5));
    local side = math.max(3, math.floor(height * badges.Scale + 0.5));
    local wide = #glyphs == 1 and side or math.max(side + 1, math.floor(side * badges.Pair + 0.5));
    local radius = math.max(0.75, side * 0.08);
    local out = image.new(wide, side):fill(function() return 1 end);
    local stroke = bold and 1 or 0;
    local gap = (#glyphs - 1) * math.max(1, math.floor(height * 0.04 + 0.5));
    local cells, across, tallest = {}, 0, 0;
    for at, one in ipairs(glyphs) do
        local sx = math.floor(one[5] * source.w + 0.5);
        local sy = math.floor(one[6] * source.h + 0.5);
        local sw = math.floor(one[7] * source.w + 0.5) - sx;
        local sh = math.floor(one[8] * source.h + 0.5) - sy;
        assert(sw > 0 and sh > 0 and sx >= 0 and sy >= 0
            and sx + sw <= source.w and sy + sh <= source.h, 'invalid badge glyph UVs');
        cells[at] = { sx = sx, sy = sy, sw = sw, sh = sh };
        across, tallest = across + sw + stroke, math.max(tallest, sh);
    end
    local scale = math.min(1, math.max(1, wide - 2 * pad - gap) / across,
        math.max(1, side - 2 * pad) / tallest);
    scale = scale * 0.95; -- slightly smaller letter; box size and corner radius stay unchanged
    local left = (wide - across * scale - gap) / 2;
    for at, cell in ipairs(cells) do
        cell.left, cell.top = left, (side - cell.sh * scale) / 2;
        left = left + (cell.sw + stroke) * scale + gap / math.max(1, #cells - 1);
    end
    local function alpha(cell, x, y)
        local sw, sh = cell.sw, cell.sh;
        if x < 0 or y < 0 or x >= sw or y >= sh then return 0 end
        local x0, y0 = math.floor(x), math.floor(y);
        local x1, y1 = math.min(sw - 1, x0 + 1), math.min(sh - 1, y0 + 1);
        local fx, fy = x - x0, y - y0;
        local function at(a, b) return math.floor(source:get(cell.sx + a, cell.sy + b) / 0x1000000) end
        return (at(x0, y0) * (1 - fx) + at(x1, y0) * fx) * (1 - fy)
            + (at(x0, y1) * (1 - fx) + at(x1, y1) * fx) * fy;
    end
    for y = 0, side - 1 do
        for x = 0, wide - 1 do
            local coverage = 0;
            for _, cell in ipairs(cells) do
                local gx, gy = (x + 0.5 - cell.left) / scale - 0.5, (y + 0.5 - cell.top) / scale - 0.5;
                local one = alpha(cell, gx, gy);
                if bold then
                    local shifted = alpha(cell, gx - 1, gy);
                    one = 255 - (255 - one) * (255 - shifted) / 255;
                end
                coverage = math.max(coverage, one);
            end
            -- Signed distance to a rounded rectangle, antialiased over one pixel.
            local dx = math.max(0, math.abs(x + 0.5 - wide / 2) - (wide / 2 - radius));
            local dy = math.max(0, math.abs(y + 0.5 - side / 2) - (side / 2 - radius));
            local corner = math.max(0, math.min(1, radius + 0.5 - math.sqrt(dx * dx + dy * dy)));
            out:set_alpha(x, y, corner * (1 - coverage / 255));
        end
    end
    return out;
end

-- The double letter at this place, AA being the first, or nil past ZZ
function badges.PairAt(place)
    if (place < 0 or place >= 676) then return nil; end
    return string.char(65 + math.floor(place / 26), 65 + place % 26);
end

-- The badges drawn and put in a texture of their own. Apart from badges.Prepare, which is asked
-- every frame: a function with another made inside it is one LuaJIT will not compile.
local function build(texture, definitions, key)
    local d3d = require('d3d8'); -- defines the native texture type before the cast
    -- ImGui's font atlas can exceed the 2048px UI asset packing limit.
    local source, reason = atlas.read(ffi.cast('IDirect3DTexture8*', texture), 8192);
    assert(source, reason);
    local entries, offsets = {}, {};
    for _, definition in ipairs(definitions) do
        offsets[definition.height] = {};
        for byte = 65, 90 do
            local letter = string.char(byte);
            local glyph = definition.glyphs[letter];
            if glyph and glyph[10] then
                local entry = #entries + 1;
                local badge = badges.Raster(source, glyph, definition.height, definition.bold);
                entries[entry] = { name = entry, img = badge };
                offsets[definition.height][letter] = { entry = entry,
                    top = (glyph[2] + glyph[4] - badge.h) * 0.5 };
            end
        end
        for place = 0, (definition.pairs or 0) - 1 do
            local pair = badges.PairAt(place);
            local first, second = pair and definition.glyphs[pair:sub(1, 1)], pair and definition.glyphs[pair:sub(2, 2)];
            if first and second and first[10] and second[10] then
                local entry = #entries + 1;
                local badge = badges.Raster(source, { first, second }, definition.height, definition.bold);
                entries[entry] = { name = entry, img = badge };
                offsets[definition.height][pair] = { entry = entry,
                    top = (first[2] + first[4] - badge.h) * 0.5 };
            end
        end
    end
    assert(#entries > 0, 'font has no badge glyphs');
    local sheet, regions = atlas.pack(entries);
    local owned = d3d.gc_safe_release(atlas.upload(sheet));
    for _, letters in pairs(offsets) do
        for _, region in pairs(letters) do
            region.uv = regions[region.entry];
        end
    end
    return { key = key, texture = owned, address = tonumber(ffi.cast('uint32_t', owned)), regions = offsets };
end

-- Definitions contain { height, glyphs = { A = glyph, ... }, bold, pairs }: pairs is how
-- many double letters are wanted as well, AA being the first, or nil for none.
-- immutable opts into an identity-key shortcut. Callers must replace definitions
-- when their glyphs change; mutable/default callers still compare every value.
-- texture is a Direct3D texture's address: anything else (none, or winxi.fonts.TextureMark) is
-- refused here, as Direct3D would be asked to read from it, and a fault there cannot be caught.
local LOWEST_ADDRESS = 0x10000;

function badges.Prepare(texture, definitions, fontKey, immutable)
    if type(texture) ~= 'number' or texture < LOWEST_ADDRESS then
        return nil;
    end
    local key;
    if immutable and identity and identity.texture == texture
        and identity.definitions == definitions and identity.fontKey == fontKey then
        key = identity.key;
    else
        local parts = { tostring(texture), tostring(fontKey) };
        for _, definition in ipairs(definitions) do
            parts[#parts + 1] = tostring(definition.height);
            parts[#parts + 1] = tostring(definition.bold);
            parts[#parts + 1] = tostring(definition.pairs or 0);
            for byte = 65, 90 do
                local glyph = definition.glyphs[string.char(byte)];
                if glyph then
                    for i = 1, 8 do parts[#parts + 1] = tostring(glyph[i]); end
                else
                    parts[#parts + 1] = 'missing';
                end
            end
        end
        key = table.concat(parts, ':');
        identity = immutable and { texture = texture, definitions = definitions, fontKey = fontKey, key = key } or nil;
    end
    if cached and cached.key == key then return cached end
    if failedKey == key and os.clock() < nextRetry then return nil end
    -- ImGui can repack its CPU glyphs before uploading their texture later in
    -- this frame. Wait one stable frame before reading, or we'd permanently
    -- cache cutouts sampled from the old pixels at the new UV coordinates.
    if pendingKey ~= key then pendingKey = key; return nil end
    local ok, result = pcall(build, texture, definitions, key);
    if not ok then
        failedKey, nextRetry = key, os.clock() + 1;
        if not warned then
            print('[name] Letter badges unavailable; using plain letters: ' .. tostring(result));
            diag.Note('Letter badges not built: %s', tostring(result));
            warned = true;
        end
        return nil;
    end
    cached, failedKey, warned = result, nil, false;
    return cached;
end

return badges;
