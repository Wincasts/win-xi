-- Cached text masks: area-average a high-resolution ImGui glyph into native
-- drawing pixels, with a transparent-white filtering guard. Uses font slot 0;
-- the original ImGui texture remains in sign slot 4 for icons/fallback glyphs.
local ffi = require('ffi');
local image = require('gdi.image');
local atlas = require('gdi.atlas');
local diag = require('diag');
local text = { SourceScale = 4 };
local characters = {};
for byte = 32, 126 do characters[#characters + 1] = string.char(byte); end
text.Characters = table.concat(characters);
local cached, pending, failed, retry, warned;

local function dispose(owned)
    if owned and owned.texture then
        local texture = owned.texture;
        owned.texture = nil;
        atlas.release(texture);
    end
end

-- Drop our GPU reference promptly instead of waiting for Lua's GC (which does
-- not account for the size of GPU allocations). ImGui owns its source atlas.
function text.Release()
    dispose(cached);
    cached, pending, failed, retry, warned = nil, nil, nil, nil, false;
end

-- Exact box integration, not a fixed number of point samples. Every source
-- texel covered by an output pixel contributes, including fractional overlaps.
function text.Raster(source, glyph)
    local width, height = glyph[3] - glyph[1], glyph[4] - glyph[2];
    if not glyph[10] or width <= 0 or height <= 0 then return nil end
    local w, h = math.max(1, math.ceil(width)), math.max(1, math.ceil(height));
    local sx, sy = math.floor(glyph[5] * source.w + 0.5), math.floor(glyph[6] * source.h + 0.5);
    local sw = math.floor(glyph[7] * source.w + 0.5) - sx;
    local sh = math.floor(glyph[8] * source.h + 0.5) - sy;
    assert(sw > 0 and sh > 0 and sx >= 0 and sy >= 0
        and sx + sw <= source.w and sy + sh <= source.h, 'invalid filtered glyph UVs');
    local out = image.new(w + 2, h + 2);
    local dx, dy = sw / w, sh / h;
    for y = 0, h - 1 do
        local top, bottom = y * dy, (y + 1) * dy;
        for x = 0, w - 1 do
            local left, right = x * dx, (x + 1) * dx;
            local coverage = 0;
            for iy = math.floor(top), math.min(sh - 1, math.ceil(bottom) - 1) do
                local wy = math.min(bottom, iy + 1) - math.max(top, iy);
                for ix = math.floor(left), math.min(sw - 1, math.ceil(right) - 1) do
                    local wx = math.min(right, ix + 1) - math.max(left, ix);
                    local alpha = math.floor(source:get(sx + ix, sy + iy) / 0x1000000);
                    coverage = coverage + alpha * wx * wy;
                end
            end
            out:set_alpha(x + 1, y + 1, coverage / (255 * dx * dy));
        end
    end
    -- One texture pixel of padding in the glyph's native coordinate system.
    return out, width / w, height / h;
end

local function build(address, definitions)
    local d3d = require('d3d8');
    local source, reason = atlas.read(ffi.cast('IDirect3DTexture8*', address), 8192);
    assert(source, reason);
    local entries = { { name = 1, img = image.new(3, 3):fill(function() return 1 end) } };
    local regions = {};
    for _, definition in ipairs(definitions) do
        if regions[definition.height] == nil then
            local letters = {};
            regions[definition.height] = letters;
            for byte = 32, 126 do
                local glyph = definition.glyphs[byte];
                if glyph then
                    local mask, padX, padY = text.Raster(source, glyph);
                    if mask then
                        local entry = #entries + 1;
                        entries[entry] = { name = entry, img = mask };
                        letters[byte] = { entry = entry, padX = padX, padY = padY };
                    end
                end
            end
        end
    end
    assert(#entries > 1, 'font has no filterable glyphs');
    local sheet, packed = atlas.pack(entries);
    local owned = d3d.gc_safe_release(atlas.upload(sheet));
    for _, letters in pairs(regions) do
        for _, region in pairs(letters) do region.uv = packed[region.entry]; end
    end
    local white = packed[1];
    return { texture = owned, width = sheet.w, height = sheet.h, address = tonumber(ffi.cast('uint32_t', owned)), regions = regions,
        white = { u = (white.x + 1.5) / sheet.w, v = (white.y + 1.5) / sheet.h } };
end

-- Immutable definitions must be replaced whenever font/size/source UVs change.
-- Never read a texture mark as a pointer. Wait one stable frame for ImGui's upload,
-- like letter_badges; failures fall back to direct font rendering with bounded retry.
function text.Prepare(address, definitions)
    if type(address) ~= 'number' or address < 0x10000 or definitions == nil then return nil end
    if cached and cached.source == address and cached.definitions == definitions then return cached end
    local same = pending and pending.source == address and pending.definitions == definitions;
    if not same then
        pending = { source = address, definitions = definitions };
        return nil;
    end
    if failed == pending and os.clock() < retry then return nil end
    local ok, result = pcall(build, address, definitions);
    if not ok then
        failed, retry = pending, os.clock() + 1;
        if not warned then
            print('[name] Smooth Font filtering unavailable; using direct glyphs: ' .. tostring(result));
            diag.Note('Filtered text unavailable; using direct glyphs: %s', tostring(result));
            warned = true;
        end
        return nil;
    end
    result.source, result.definitions = address, definitions;
    dispose(cached);
    cached, failed, warned = result, nil, false;
    return cached;
end

function text.Diagnostics()
    return (cached and ('%dx%d cached'):format(cached.width,cached.height) or 'no atlas')
        .. (failed and '; build failed, direct fallback' or (cached and '; ready' or (pending and '; preparing' or '; inactive')));
end
return text;
