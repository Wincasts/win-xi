-- The icons the game puts before a name (linkshell pearl, party flags, bazaar, GM and the rest), drawn
-- from the game's own picture of them.
--
--   icons.Find()                               once, on loading: where the game keeps its font
--   icons.Begin()                              each frame before any are drawn
--   icons.Has(byte)                            whether this byte of a name is an icon
--   icons.Draw(drawList, byte, x, y, size, color)   one icon, in a square of size pixels
--
-- In the game's font an icon is a single character, of code 0x8E or more. Its letters and its icons
-- are in two pictures; the icons' is 256 pixels square with each icon in a cell of 32, though the game
-- draws them at 16. They are drawn here from all 32.
--
-- The game's picture is not used as it is: nothing in it is more than about half solid, since the
-- game draws it at twice its strength. A copy is made, once, with that put right.
local d3d   = require('d3d8');
local ffi   = require('ffi');

local C = ffi.C;

local icons = {};

-- The game's function that measures a character opens by reading where the font is kept
local FONT_SIGNATURE = '568BF18B462C85C0751C68????????B9????????E8';
local FONT_OFFSET    = 16;

-- In the font
local FONT_ICON_PICTURE = 0x20; -- the picture the icons are in
local FONT_ICON_FIRST   = 0x28; -- the first character that is an icon
local FONT_SHAPES       = 0x2C; -- the shapes of the characters: where in its picture each one is

-- In a picture
local PICTURE_DATA    = 0x20; -- its pixels as they came from the game's files, 8 bytes on from here
local PICTURE_WIDTH   = 0x24;
local PICTURE_HEIGHT  = 0x26;
local PICTURE_TEXTURE = 0x40; -- the Direct3D texture made from it, here or 4 bytes on

-- In the shapes: a list of them by character, the first being the character 0x20
local SHAPES_COUNT    = 0x1C;
local FIRST_CHARACTER = 0x20;

-- In a shape: a chain of pieces, each with four corners of 0x1C bytes holding where in the picture
local SHAPE_PIECES   = 0x04;
local PIECE_SKIP     = 0x14;
local PIECE_CORNERS  = 0x10;
local CORNER_UV      = 0x64;
local CORNER_SIZE    = 0x1C;

local DXT3_IN_FILE = 0x44585433; -- "3TXD", as the game's files spell it
local DDS_HEADER   = 128;

local font     = 0;
local picture  = 0;   -- the game's picture the copy was made from
local shapes   = 0;   -- the shapes the places below were read from
local texture  = nil; -- the copy, kept so that it is not let go
local handle   = nil; -- what imgui is given to draw from
local places   = {};  -- character -> { u1, v1, u2, v2 }, or false for one that has no shape
local first    = 0x8E;
local count    = 0;

local read8, read16, read32, readFloat = ashita.memory.read_uint8, ashita.memory.read_uint16, ashita.memory.read_uint32, ashita.memory.read_float;

function icons.Find()
    local found = ashita.memory.find('FFXiMain.dll', 0, FONT_SIGNATURE, 0, 0);
    if (found ~= 0) then
        font = read32(found + FONT_OFFSET);
    end
    return font ~= 0;
end

-- A copy of the game's picture with everything in it twice as solid, or nil if the picture is not
-- kept in the one way this knows (DXT3, in which each block of 16 pixels opens with their 16 alphas,
-- four bits each).
local function copyPicture(from)
    local data = read32(from + PICTURE_DATA);
    local width, height = read16(from + PICTURE_WIDTH), read16(from + PICTURE_HEIGHT);
    if (data == 0 or width < 64 or width > 1024 or height < 64 or height > 1024 or width % 4 ~= 0 or height % 4 ~= 0) then
        return nil;
    end
    if (read32(data - 4) ~= DXT3_IN_FILE) then
        return nil;
    end

    local size = width * height;
    local file = ffi.new('uint8_t[?]', DDS_HEADER + size);

    -- the header of a DDS file, which is what Direct3D will read this as
    local header = ffi.cast('uint32_t*', file);
    header[0]  = 0x20534444; -- "DDS "
    header[1]  = 124;
    header[2]  = 0x00081007; -- caps, height, width, pixel format, linear size
    header[3]  = height;
    header[4]  = width;
    header[5]  = size;
    header[19] = 32;
    header[20] = 0x00000004; -- a four character code follows
    header[21] = 0x33545844; -- "DXT3"
    header[27] = 0x00001000; -- a texture

    local pixels = file + DDS_HEADER;
    ffi.copy(pixels, ffi.cast('const uint8_t*', data + 8), size);

    for block = 0, size - 16, 16 do
        for i = block, block + 7 do
            local both = pixels[i];
            local low, high = bit.band(both, 0x0F) * 2, bit.rshift(both, 4) * 2;
            pixels[i] = (low > 15 and 15 or low) + (high > 15 and 15 or high) * 16;
        end
    end

    local made = ffi.new('IDirect3DTexture8*[1]');
    if (C.D3DXCreateTextureFromFileInMemory(d3d.get_device(), file, DDS_HEADER + size, made) ~= C.S_OK) then
        return nil;
    end

    return d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', made[0]));
end

-- Looks at what the game has now. Its picture and its shapes are loaded when first wanted, and may be
-- loaded again; whatever was worked out from the old ones is dropped.
function icons.Begin()
    if (font == 0) then
        return;
    end

    local nowPicture = read32(font + FONT_ICON_PICTURE);
    if (nowPicture ~= picture) then
        picture, texture, handle = nowPicture, nil, nil;

        if (picture ~= 0) then
            texture = copyPicture(picture);
            if (texture ~= nil) then
                handle = tonumber(ffi.cast('uint32_t', texture));
            else
                -- the game's own, then: fainter than it should be, but there
                local own = read32(picture + PICTURE_TEXTURE);
                if (own == 0) then
                    own = read32(picture + PICTURE_TEXTURE + 4);
                end
                handle = own ~= 0 and own or nil;
            end
        end
    end

    local nowShapes = read32(font + FONT_SHAPES);
    if (nowShapes ~= shapes) then
        shapes, places = nowShapes, {};
        first, count = 0x8E, 0;

        if (shapes ~= 0) then
            first = read32(font + FONT_ICON_FIRST);
            count = read32(shapes + SHAPES_COUNT);
            if (first < 0x80 or first > 0xFF or count > 0xE0) then
                first, count = 0x8E, 0;
            end
        end
    end
end

local function place(byte)
    local found = places[byte];
    if (found ~= nil) then
        return found;
    end

    found = false;
    if (byte >= first and byte < FIRST_CHARACTER + count) then
        local shape = read32(read32(shapes) + (byte - FIRST_CHARACTER) * 4);
        local piece = shape ~= 0 and read32(shape + SHAPE_PIECES) or 0;

        -- the first piece of the chain that is not one to pass over
        local tries = 0;
        while (piece ~= 0 and read8(piece + PIECE_SKIP) ~= 0 and tries < 8) do
            piece = read32(piece);
            tries = tries + 1;
        end

        local corners = (piece ~= 0 and read8(piece + PIECE_SKIP) == 0) and read32(piece + PIECE_CORNERS) or 0;
        if (corners ~= 0) then
            local last = corners + 3 * CORNER_SIZE;
            found = {
                readFloat(corners + CORNER_UV), readFloat(corners + CORNER_UV + 4),
                readFloat(last + CORNER_UV), readFloat(last + CORNER_UV + 4),
            };
        end
    end

    places[byte] = found;
    return found;
end

function icons.Has(byte)
    return handle ~= nil and place(byte) ~= false;
end

local cornerA, cornerB, uvA, uvB = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };

function icons.Draw(drawList, byte, x, y, size, color)
    local at = handle ~= nil and place(byte);
    if (not at) then
        return;
    end

    cornerA[1], cornerA[2], cornerB[1], cornerB[2] = x, y, x + size, y + size;
    uvA[1], uvA[2], uvB[1], uvB[2] = at[1], at[2], at[3], at[4];
    drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, color);
end

return icons;
