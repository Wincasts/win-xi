-- Player-name artwork and fontshp mapping from the active menu DAT.
-- mapdat.Read uses fopen_s so Pivot overlays apply when redirect_fopens is enabled.
-- Parse is CPU-only; Load owns a single texture, never a borrowed game pointer.
local ffi = require('ffi');
local mapdat = require('winxi.mapdat');
local dat = {};
local function u16(b, at) return b[at] + b[at + 1] * 256; end
local function u32(b, at) return u16(b, at) + u16(b, at + 2) * 65536; end
local function s16(b, at)
    local value = u16(b, at);
    return value >= 32768 and value - 65536 or value;
end

function dat.Parse(buffer, length)
    if buffer == nil or type(length) ~= 'number' or length < 16 or length > 0x2000000 then
        return nil, 'invalid menu DAT size';
    end
    local b = ffi.cast('const uint8_t*', buffer);
    local picture, pictureSize, shapes, shapeSize;
    local at = 0;
    while at + 16 <= length do
        local meta = u32(b, at + 4);
        local kind, size = meta % 128, math.floor(meta / 128) % 0x80000 * 16;
        if size < 16 or at + size > length then return nil, 'invalid menu DAT chunk'; end
        if kind == 0x20 and size >= 85 and ffi.string(b + at + 17, 16):lower() == 'menu    ustatshd' then
            picture, pictureSize = at, size;
        elseif kind == 0x31 and size >= 35 and ffi.string(b + at + 16, 16):lower() == 'font    fontshp ' then
            shapes, shapeSize = at, size;
        end
        at = at + size;
    end
    if not picture or not shapes then return nil, 'player icon texture or fontshp mapping missing'; end
    -- Menu image headers start at +33; map images at +65. Pad by 32 bytes
    -- to reuse the validated shared uploader, including non-stock atlas sizes.
    local imageLength = pictureSize + 32;
    local image = ffi.new('uint8_t[?]', imageLength);
    ffi.copy(image + 32, b + picture, pictureSize);
    local header, why = mapdat.Header(image, imageLength);
    if not header then return nil, why; end
    if header.kind ~= 0x44585433 then return nil, 'player icons are not a supported DXT3 atlas'; end
    -- Match the game's doubled alpha without decompressing/recompressing colours.
    for block = header.at, header.at + header.rows * header.row - 1, 16 do
        for i = 0, 7 do
            local alpha = image[block + i];
            image[block + i] = math.min(15, (alpha % 16) * 2)
                + math.min(15, math.floor(alpha / 16) * 2) * 16;
        end
    end
    local tableAt, finish = shapes + 32 + b[shapes + 32] * 16, shapes + shapeSize;
    if tableAt + 3 > finish then return nil, 'truncated player icon character table'; end
    local first, count = b[tableAt], b[tableAt + 1];
    if count == 0 or first + count > 256 then return nil, 'invalid player icon character range'; end
    local cursor, places, overlays = tableAt + 3, {}, {};
    for byte = first, first + count - 1 do
        if cursor + 1 > finish then return nil, 'truncated player icon piece count'; end
        local pieces, base = b[cursor], nil;
        cursor = cursor + 1;
        if cursor + pieces * 61 > finish then return nil, 'truncated player icon shape'; end
        for _ = 1, pieces do
            if byte >= 0x8E and byte <= 0xB1 and b[cursor + 24] == 0 then
                if ffi.string(b + cursor + 45, 16):lower() ~= 'menu    ustatshd' then
                    return nil, 'unsupported player icon texture reference';
                end
                local w, h, x, y = u16(b, cursor + 16), u16(b, cursor + 18), u16(b, cursor + 20), u16(b, cursor + 22);
                if w == 0 or h == 0 or x + w > header.width or y + h > header.height then
                    return nil, 'invalid player icon UV rectangle';
                end
                local xs, ys = {}, {};
                for corner = 0, 3 do
                    xs[corner + 1], ys[corner + 1] = s16(b, cursor + corner * 4), s16(b, cursor + corner * 4 + 2);
                end
                local left, right = math.min(unpack(xs)), math.max(unpack(xs));
                local top, bottom = math.min(unpack(ys)), math.max(unpack(ys));
                if right <= left or bottom <= top then return nil, 'invalid player icon geometry'; end
                local uv = { x / header.width, y / header.height, (x + w) / header.width, (y + h) / header.height };
                if not base then
                    base = { left, top, right - left, bottom - top };
                    places[byte] = uv;
                else
                    local layers = overlays[byte] or {};
                    overlays[byte] = layers;
                    layers[#layers + 1] = {
                        (left - base[1]) / base[3], (top - base[2]) / base[4],
                        (right - base[1]) / base[3], (bottom - base[2]) / base[4],
                        uv[1], uv[2], uv[3], uv[4],
                    };
                end
            end
            cursor = cursor + 61;
        end
    end
    if not places[0x92] or not places[0xAD] then return nil, 'player pearl/mastery-star mapping missing'; end
    return { image = image, length = imageLength, places = places, overlays = overlays,
        width = header.width, height = header.height };
end

function dat.Load()
    local d3d = require('d3d8');
    local device = d3d.get_device();
    if device == nil then return nil, 'Direct3D device unavailable'; end
    local path = 'ROM/119/51.DAT';
    -- Menu DAT's file ID in the client FTABLE; respect remapped ROM paths too.
    local ok, mapped = pcall(function() return AshitaCore:GetResourceManager():GetFilePath(39542); end);
    if ok and type(mapped) == 'string' then
        path = mapped:match('([Rr][Oo][Mm]%d*[\\/]%d+[\\/]%d+%.[Dd][Aa][Tt])$') or path;
    end
    local buffer, length = mapdat.Read(path);
    if not buffer then return nil, 'DAT read: ' .. tostring(length); end
    local parsed, why = dat.Parse(buffer, length);
    if not parsed then return nil, 'DAT parse: ' .. tostring(why); end
    local texture;
    texture, why = mapdat.Texture(device, parsed.image, parsed.length);
    if not texture then return nil, 'texture upload: ' .. tostring(why); end
    local owned = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture));
    return { texture = owned, address = tonumber(ffi.cast('uint32_t', owned)),
        places = parsed.places, overlays = parsed.overlays, width = parsed.width, height = parsed.height };
end

function dat.Release(pack)
    if pack and pack.texture then
        local texture = pack.texture;
        pack.texture = nil;
        require('gdi.atlas').release(texture);
    end
end

return dat;
