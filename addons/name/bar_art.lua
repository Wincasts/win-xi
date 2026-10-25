-- The bars' textures: winxi's Bar Textures (party's HP art, libs\winxi\assets\bars\<set>\: a back, a
-- fill and a front), drawn through the plugin as winxi.bars draws them with imgui.
--
--   art.Choices()          { key =, label = } each: Plain (the bar as it always was) and winxi's sets
--   art.Valid(key)         whether key is one of them
--   art.Begin(options)     once a frame: the sheet's address, or nil while no bar wants a texture
--                          (or it would not load). The plugin's eight textures are all taken, so the
--                          sets in use share special's with its signs: special.SetRegion says where
--                          they now are in it.
--   art.Draw(key, x, y, width, height, fraction, color)
--                          the back, the fill (fraction of it) and the front, each tinted color; false
--                          where the set is not in the sheet (the caller draws the plain bar)
--   art.Release()          lets the sheet go
--
-- The images are read back from Direct3D (D3DX reads the PNG) and packed with special.png's signs into
-- one sheet of the addon's own (gdi.atlas), at their own size and at a half and a quarter of it: the
-- plugin samples without mipmaps, so a bar a few pixels high is drawn from the copy nearest its height.
local ffi = require('ffi');
local nameplates = require('winxi.nameplates');
local special = require('special');
local image = require('gdi.image');

local art = {};

-- The images' measures, in their own pixels, as winxi.bars has them: the back and front 220 wide (the
-- front's image 226, its last six the bookend, not drawn), the fill 204 wide from 8 in; all 28 high
local ART_HEIGHT, ART_WIDTH, FRONT_WIDTH, INSET, SLICE = 28, 220, 226, 8, 12;
local LEVELS = 3;            -- the images at a whole, a half and a quarter of their size
local PLAIN = 'plain';
local RETRY = 5;             -- seconds before a sheet that would not be made is tried again

local choices = nil;
local sheet = nil;           -- { texture, at, signature, sets = key -> levels }
local failed = {};           -- signature -> when to try it again

local function themeSets()
    local ok, theme = pcall(require, 'winxi.theme');
    return ok and type(theme) == 'table' and theme.BarTextures or {};
end

function art.Choices()
    if choices == nil then
        choices = { { key = PLAIN, label = 'Plain' } };
        for _, set in ipairs(themeSets()) do
            choices[#choices + 1] = { key = set.key, label = set.label };
        end
    end
    return choices;
end

function art.Valid(key)
    for _, choice in ipairs(art.Choices()) do
        if choice.key == key then return true; end
    end
    return false;
end

-- Where winxi's art is: as winxi.bars finds it
function art.Folder()
    local ok, bars = pcall(require, 'winxi.bars');
    if ok and type(bars) == 'table' and bars.Folder then return bars.Folder(); end
    return ('%s\\addons\\libs\\winxi\\assets\\bars\\'):format(AshitaCore:GetInstallPath());
end

local function powerOfTwo(n)
    local p = 1;
    while p < n do p = p * 2; end
    return p;
end

-- A PNG as a CPU image at its own size, or nil. A field, so the checks can stand in for it. D3DX is
-- given a texture of a power of two at least as large and told not to scale, so the image is in its
-- top left as it is in the file.
function art.LoadImage(path)
    local ok, found = pcall(function ()
        local d3d = require('d3d8');
        local atlas = require('gdi.atlas');
        local C = ffi.C;
        local info = ffi.new('D3DXIMAGE_INFO[1]');
        if C.D3DXGetImageInfoFromFileA(path, info) ~= C.S_OK then return nil; end
        local w, h = tonumber(info[0].Width), tonumber(info[0].Height);
        if w < 1 or h < 1 or w > 1024 or h > 1024 then return nil; end
        local made = ffi.new('IDirect3DTexture8*[1]');
        local FILTER_NONE = 1;
        if C.D3DXCreateTextureFromFileExA(d3d.get_device(), path, powerOfTwo(w), powerOfTwo(h), 1, 0,
                C.D3DFMT_A8R8G8B8, C.D3DPOOL_MANAGED, FILTER_NONE, FILTER_NONE, 0, nil, nil, made) ~= C.S_OK then
            return nil;
        end
        local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', made[0]));
        local read = atlas.read(texture, 1024);
        atlas.release(texture);
        if read == nil or read.w < w or read.h < h then return nil; end
        local own = image.new(w, h);
        for y = 0, h - 1 do
            ffi.copy(own.px + y * w, read.px + y * read.w, w * 4);
        end
        return own;
    end);
    return ok and found or nil;
end

-- Half the image's size, each pixel the four under it; their colours by how solid each is, so that the
-- clear pixels round a shape do not darken its edge
local function half(source)
    local w, h = math.max(1, math.ceil(source.w / 2)), math.max(1, math.ceil(source.h / 2));
    local out = image.new(w, h);
    local px, sw, sh = source.px, source.w, source.h;
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local a, r, g, b, n = 0, 0, 0, 0, 0;
            for dy = 0, 1 do
                for dx = 0, 1 do
                    local sx, sy = math.min(sw - 1, x * 2 + dx), math.min(sh - 1, y * 2 + dy);
                    local p = tonumber(px[sy * sw + sx]);
                    local pa = math.floor(p / 0x1000000);
                    a = a + pa;
                    r = r + math.floor(p / 0x10000) % 0x100 * pa;
                    g = g + math.floor(p / 0x100) % 0x100 * pa;
                    b = b + p % 0x100 * pa;
                    n = n + 1;
                end
            end
            local value = 0x00FFFFFF;
            if a > 0 then
                value = math.floor(a / n + 0.5) * 0x1000000 + math.floor(r / a + 0.5) * 0x10000
                    + math.floor(g / a + 0.5) * 0x100 + math.floor(b / a + 0.5);
            end
            out.px[y * w + x] = value;
        end
    end
    return out;
end

-- The sets bars now want, in a steady order, and what to call them together
local wanted, wantedCount = {}, 0;
local function want(key)
    if key == nil or key == PLAIN or not art.Valid(key) then return; end
    for i = 1, wantedCount do if wanted[i] == key then return; end end
    wantedCount = wantedCount + 1;
    wanted[wantedCount] = key;
end

local function wants(options)
    wantedCount = 0;
    if options.showHealthBar and options.showHealthBar[1] and options.healthBarTexture then want(options.healthBarTexture[1]); end
    if options.showCastBar and options.showCastBar[1] and options.castBarTexture then want(options.castBarTexture[1]); end
    for i = wantedCount + 1, #wanted do wanted[i] = nil; end
    if wantedCount == 0 then return nil; end
    table.sort(wanted);
    return table.concat(wanted, ',');
end

function art.Release()
    special.SetRegion(nil);
    if sheet ~= nil and sheet.texture ~= nil then
        nameplates.SetTexture(special.Slot, 0); -- never left published once let go
        art.Free(sheet.texture);
    end
    sheet = nil;
end

-- The sheet for these sets, made: the special signs and every set's images at each level
local function make(signature, signsPath)
    local signs = art.LoadImage(signsPath);
    if signs == nil then return nil; end
    local items = { { name = 'signs', img = signs } };
    local folder = art.Folder();
    for _, key in ipairs(wanted) do
        for _, part in ipairs({ 'back', 'fill', 'front' }) do
            local level = art.LoadImage(folder .. key .. '\\' .. part .. '.png');
            if level == nil then return nil; end
            for at = 1, LEVELS do
                items[#items + 1] = { name = ('%s:%s:%d'):format(key, part, at), img = level };
                if at < LEVELS then level = half(level); end
            end
        end
    end
    local atlas = require('gdi.atlas');
    local ok, packed, regions = pcall(atlas.pack, items);
    if not ok then return nil; end
    local made = { signature = signature, sets = {}, regions = regions, signs = regions.signs };
    for _, key in ipairs(wanted) do
        local levels = {};
        for at = 1, LEVELS do
            levels[at] = {
                height = ART_HEIGHT / 2 ^ (at - 1),
                back = regions[('%s:back:%d'):format(key, at)],
                fill = regions[('%s:fill:%d'):format(key, at)],
                front = regions[('%s:front:%d'):format(key, at)],
            };
        end
        made.sets[key] = levels;
    end
    made.sheet = packed;
    return made;
end

-- A field, so the checks can make the sheet without Direct3D: its texture and address
function art.Upload(packed)
    local ok, texture = pcall(function ()
        local d3d = require('d3d8');
        return d3d.gc_safe_release(require('gdi.atlas').upload(packed));
    end);
    if not ok or texture == nil then return nil, 0; end
    return texture, tonumber(ffi.cast('uint32_t', texture));
end

-- And lets it go: a field, as Upload
function art.Free(texture)
    require('gdi.atlas').release(texture);
end

function art.Begin(options)
    local signature = wants(options);
    if signature == nil then
        if sheet ~= nil then art.Release(); end
        special.SetRegion(nil);
        return nil;
    end
    if sheet == nil or sheet.signature ~= signature then
        local now = os.clock();
        if failed[signature] ~= nil and now < failed[signature] then
            special.SetRegion(nil);
            return nil;
        end
        art.Release();
        local made = make(signature, addon.path .. 'assets/' .. special.Sheet);
        if made ~= nil then
            made.texture, made.at = art.Upload(made.sheet);
            made.sheet = nil;
            if made.at == 0 then made = nil; end
        end
        if made == nil then
            failed[signature] = now + RETRY;
            special.SetRegion(nil);
            return nil;
        end
        failed[signature], sheet = nil, made;
    end
    special.SetRegion(sheet.signs);
    return sheet.at;
end

-- Part of an image: the pixels from u1 to u2 of imageWidth across, all of its height
local function piece(region, x1, y1, x2, y2, u1, u2, imageWidth, color, soft)
    if x2 <= x1 then return; end
    local span = region.u1 - region.u0;
    nameplates.Quad(x1, y1, x2, y2, region.u0 + span * u1 / imageWidth, region.v0, region.u0 + span * u2 / imageWidth,
        region.v1, color, special.Slot, false, nil, soft);
end

-- An image in three: its ends (SLICE of its pixels each, of imageWidth across, used to used) kept to the
-- height's scale, the middle stretched between
local function sliced(region, x, y, width, height, imageWidth, used, color)
    local ends = math.min(SLICE * height / ART_HEIGHT, width / 2);
    piece(region, x, y, x + ends, y + height, 0, SLICE, imageWidth, color);
    piece(region, x + ends, y, x + width - ends, y + height, SLICE, used - SLICE, imageWidth, color);
    piece(region, x + width - ends, y, x + width, y + height, used - SLICE, used, imageWidth, color);
end

function art.Draw(key, x, y, width, height, fraction, color)
    local levels = sheet ~= nil and key ~= nil and sheet.sets[key];
    if not levels or width <= 0 or height <= 0 then return false; end
    -- the smallest copy no smaller than the bar
    local level = levels[1];
    for at = 2, LEVELS do
        if levels[at].height >= height then level = levels[at]; end
    end
    sliced(level.back, x, y, width, height, ART_WIDTH, ART_WIDTH, color);
    fraction = math.max(0, math.min(1, fraction or 0));
    if fraction > 0 then
        -- the whole fill image, squeezed to how far it goes, as party draws it; its end softened as the
        -- plain bar's is (namehook 1.37; an older one draws it hard)
        local edge = math.min(INSET * height / ART_HEIGHT, width / 2);
        local length = (width - 2 * edge) * fraction;
        local fill = level.fill;
        nameplates.Quad(x + edge, y, x + edge + length, y + height, fill.u0, fill.v0, fill.u1, fill.v1, color, special.Slot,
            false, nil, true);
    end
    sliced(level.front, x, y, width, height, FRONT_WIDTH, ART_WIDTH, color);
    return true;
end

-- For the checks: the sheet as it is
function art.Sheet()
    return sheet;
end

return art;
