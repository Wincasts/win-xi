-- Experimental GDI glyph atlas. Rasterize only when family/size rungs change;
-- the plugin still supplies tint, outlines, fading and world-depth rendering.
local ffi = require('ffi');
local atlas = require('gdi.atlas');
local backend = {};
local gdi, current;
local traceFile;
local function checkpoint(stage)
    if (traceFile ~= nil) then
        traceFile:write(stage .. '\n');
        traceFile:flush(); -- leave the last attempted native call on disk even after an AV
    end
end

local function library()
    if (gdi == nil) then
        gdi = require('gdifonts.include');
        gdi:set_auto_render(false);
    end
    return gdi;
end

local function build(family, heights, bold)
    local key = family .. ':' .. table.concat(heights, ',') .. ':' .. tostring(bold == true);
    if (current ~= nil and current.key == key) then return current; end
    checkpoint('initialize GDI library');
    local lib = library();
    checkpoint('check font family: ' .. family);
    assert(lib:get_font_available(family), 'Font family not installed: ' .. family);
    local items, sets = {}, {};
    for _, height in ipairs(heights) do
        if (sets[height] == nil) then
            checkpoint('create font object at height ' .. height .. (bold and ' (bold)' or ' (regular)'));
            local obj = lib:create_object({ font_family = family, font_height = height,
                font_flags = bold and lib.FontFlags.Bold or lib.FontFlags.None,
                font_color = 0xFFFFFFFF, outline_width = 0, outline_color = 0,
                background = { visible = false } }, true);
            local function width(str)
                obj:set_text(str);
                checkpoint(('measure height %d text %q'):format(height, str));
                local _, rect = obj:get_texture();
                assert(rect ~= nil, 'GDI could not measure text');
                return tonumber(rect.right);
            end
            local base = width('00');
            local advance0 = width('000') - base;
            local glyphs = {};
            sets[height] = { glyphs = glyphs };
            for byte = 32, 126 do
                local ch = string.char(byte);
                local advance = width('0' .. ch .. '0') - base;
                local offset = byte == 32 and 0 or advance - advance0 - (width(ch .. '0') - base);
                local glyph = { offset, 0, offset, 0, 0, 0, 0, 0, advance, false };
                glyphs[byte] = glyph;
                if (byte ~= 32) then
                    -- Never rasterize punctuation by itself. The reference DLL's
                    -- ink scanner can miss a low glyph (notably comma), derive a
                    -- negative crop width, then fault inside its texture copy.
                    -- Visible sentinels give its scanner a full-height path. Their
                    -- advances/bearings also locate the middle cell in the capture.
                    obj:set_text('0' .. ch .. '0');
                    checkpoint(('rasterize sentinel cell height %d byte %d'):format(height, byte));
                    local tex, rect = obj:get_texture();
                    assert(tex ~= nil and rect ~= nil, 'GDI could not rasterize glyph');
                    local width, bottom = tonumber(rect.right), tonumber(rect.bottom);
                    checkpoint(('read texture height %d byte %d'):format(height, byte));
                    local img, err = atlas.read(tex);
                    assert(img ~= nil, err);
                    assert(width > 0 and bottom > 0 and width <= img.w and bottom <= img.h,
                        'GDI returned an invalid glyph rectangle');
                    local left = math.floor(advance0 + offset + 0.5);
                    local right = math.floor(advance0 + advance + 0.5);
                    assert(left >= 0 and right > left and right <= width,
                        'GDI returned invalid sentinel cell metrics');
                    img = img:sub(left, 0, right - left, bottom);
                    items[#items + 1] = { name = height .. ':' .. byte, img = img, glyph = glyph };
                end
            end
            -- Adapter for the existing lazy glyph reader; input is currently ASCII.
            sets[height].baked = { FindGlyph = function () return nil; end };
        end
    end
    checkpoint('pack glyph atlas');
    local sheet, regions = atlas.pack(items);
    local d3d = require('d3d8');
    checkpoint('upload glyph atlas');
    local texture = d3d.gc_safe_release(atlas.upload(sheet));
    for _, item in ipairs(items) do
        local r, gl = regions[item.name], item.glyph;
        gl[3], gl[4] = gl[1] + r.w, r.h;
        gl[5], gl[6], gl[7], gl[8], gl[10] = r.u0, r.v0, r.u1, r.v1, true;
    end
    -- Swap only after the new atlas is complete; the plugin holds the old texture
    -- while it is still drawing it. Keep one configuration rather than an unbounded cache.
    current = { key = key, sets = sets, texture = texture,
        address = tonumber(ffi.cast('uint32_t', texture)) };
    return current;
end

function backend.Prepare(family, heights, bold)
    local key = family .. ':' .. table.concat(heights, ',') .. ':' .. tostring(bold == true);
    if (current ~= nil and current.key == key) then return current; end
    -- Temporary diagnostic trace for the experimental native path. Cached frames
    -- do no file I/O. This file is overwritten only when building another atlas.
    if (addon ~= nil and addon.path ~= nil) then
        traceFile = io.open(addon.path .. 'gdi-diagnostic.txt', 'w');
    end
    local ok, result = pcall(build, family, heights, bold);
    checkpoint(ok and 'atlas complete' or ('Lua error: ' .. tostring(result)));
    if (traceFile ~= nil) then traceFile:close(); traceFile = nil; end
    if (not ok) then error(result); end
    return result;
end

function backend.Shutdown()
    current = nil;
    if (gdi ~= nil) then
        gdi:set_auto_render(false);
        gdi:destroy_interface();
        gdi = nil;
    end
end

return backend;
