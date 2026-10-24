-- Compact rounded badges: white fill, genuinely transparent glyph cutout.
-- Glyphs come from the renderer's fixed Arial Bold indicator font.
local ffi = require('ffi');
local image = require('gdi.image');
local atlas = require('gdi.atlas');
local diag = require('diag');
local badges = { Slot = 5, Font = 'arialbd.ttf', Scale = 0.68, Pair = 1.5, Padding = 1 }; -- Pair: a double letter's box, in sides
local SAMPLES = 4; -- 4x4 area samples, at atlas-build time only
local cached, pendingKey, failedKey, nextRetry, warned = nil, nil, nil, 0, false;
local identity;

local function dispose(owned)
    if owned and owned.texture then
        local texture = owned.texture;
        owned.texture = nil;
        atlas.release(texture);
    end
end

function badges.Release()
    dispose(cached);
    cached, pendingKey, failedKey, nextRetry, warned, identity = nil, nil, nil, 0, false, nil;
end

-- Bilinear glyph coverage with transparent samples outside its atlas rectangle.
-- Copying alpha once per glyph avoids repeatedly reading the source for every
-- supersample; these helpers and the raster loops can be compiled by LuaJIT.
local function pixel(cell, x, y)
    if x < 0 or y < 0 or x >= cell.sw or y >= cell.sh then return 0 end
    return cell.pixels[y * cell.sw + x + 1];
end

local function alpha(cell, x, y)
    if x <= -1 or y <= -1 or x >= cell.sw or y >= cell.sh then return 0 end
    local x0, y0 = math.floor(x), math.floor(y);
    local fx, fy = x - x0, y - y0;
    return (pixel(cell, x0, y0) * (1 - fx) + pixel(cell, x0 + 1, y0) * fx) * (1 - fy)
        + (pixel(cell, x0, y0 + 1) * (1 - fx) + pixel(cell, x0 + 1, y0 + 1) * fx) * fy;
end

-- A transparent-white guard is part of the texture, NOT the badge's layout.
-- Atlas extrusion then repeats transparent pixels instead of an opaque straight
-- edge, allowing bilinear filtering to soften the entire rotated box silhouette.
function badges.Padded(badge)
    local pad = badges.Padding;
    local padded = image.new(badge.w + pad * 2, badge.h + pad * 2);
    padded:blit(badge, pad, pad);
    return padded;
end

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
    local out = image.new(wide, side);
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
        local pixels = {};
        for y = 0, sh - 1 do
            for x = 0, sw - 1 do
                pixels[#pixels + 1] = math.floor(source:get(sx + x, sy + y) / 0x1000000);
            end
        end
        cells[at] = { pixels = pixels, sw = sw, sh = sh };
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
    for y = 0, side - 1 do
        for x = 0, wide - 1 do
            local filled = 0;
            for sampleY = 0, SAMPLES - 1 do
                for sampleX = 0, SAMPLES - 1 do
                    local px, py = x + (sampleX + 0.5) / SAMPLES, y + (sampleY + 0.5) / SAMPLES;
                    local dx = math.max(0, math.abs(px - wide / 2) - (wide / 2 - radius));
                    local dy = math.max(0, math.abs(py - side / 2) - (side / 2 - radius));
                    if dx * dx + dy * dy <= radius * radius then
                        local coverage = 0;
                        for _, cell in ipairs(cells) do
                            local gx, gy = (px - cell.left) / scale - 0.5, (py - cell.top) / scale - 0.5;
                            local one = alpha(cell, gx, gy);
                            if bold then
                                local shifted = alpha(cell, gx - 1, gy);
                                one = 255 - (255 - one) * (255 - shifted) / 255;
                            end
                            coverage = math.max(coverage, one);
                        end
                        filled = filled + 1 - coverage / 255;
                    end
                end
            end
            out:set_alpha(x, y, filled / (SAMPLES * SAMPLES));
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
                entries[entry] = { name = entry, img = badges.Padded(badge) };
                offsets[definition.height][letter] = { entry = entry,
                    width = badge.w, height = badge.h, padding = badges.Padding,
                    top = (glyph[2] + glyph[4] - badge.h) * 0.5 };
            end
        end
        for place = 0, (definition.pairs or 0) - 1 do
            local pair = badges.PairAt(place);
            local first, second = pair and definition.glyphs[pair:sub(1, 1)], pair and definition.glyphs[pair:sub(2, 2)];
            if first and second and first[10] and second[10] then
                local entry = #entries + 1;
                local badge = badges.Raster(source, { first, second }, definition.height, definition.bold);
                entries[entry] = { name = entry, img = badges.Padded(badge) };
                offsets[definition.height][pair] = { entry = entry,
                    width = badge.w, height = badge.h, padding = badges.Padding,
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
    return { key = key, texture = owned, width = sheet.w, height = sheet.h,
        address = tonumber(ffi.cast('uint32_t', owned)), regions = offsets };
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
    dispose(cached);
    cached, failedKey, warned = result, nil, false;
    return cached;
end

function badges.Diagnostics()
    return (cached and ('%dx%d cached'):format(cached.width,cached.height) or 'no atlas')
        .. (failedKey and '; build failed, plain-letter fallback' or (cached and '; ready' or (pendingKey and '; preparing' or '; inactive')));
end
return badges;
