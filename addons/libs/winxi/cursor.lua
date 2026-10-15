-- FFXI's animated cursors, read from the client's menu DAT. Every group draws the same six cells of the
-- `anc` atlas; they differ only in the corners each cell is drawn to around its pivot. anc_s is the
-- right-pointing party/subtarget cursor, anc_l the downward target cursor hung over a model.
-- Uses mapdat's pivot-aware reader; no bundled replacement artwork or game-memory writes.
-- Parse(buffer, length, group) -> mapdat-compatible picture buffer, length, frames, or nil, reason.
-- Neutral(image, length) -> a grey copy of a parsed picture, for tinting by multiply, or nil, reason.
-- Get(forceRetry, group, neutral) -> texture handle, frame, or nil, reason. group defaults to anc_s.
-- A frame is { u1, v1, u2, v2, width, height, rect = { left, top, right, bottom } in atlas pixels,
-- corners = { x, y } * 4 for the cell's top-left, top-right, bottom-left and bottom-right, from the pivot }.
local ffi = require('ffi')
local mapdat = require('winxi.mapdat')
local cursor = {}
local function U16(b, at) return b[at] + b[at+1]*256 end
local function U32(b, at) return U16(b,at) + U16(b,at+2)*65536 end
local function S16(b, at) local v = U16(b,at) return v >= 32768 and v - 65536 or v end
local function Name(group) return ('anc     %-8s'):format(group) end

function cursor.Parse(buffer, length, group)
    group = group or 'anc_s'
    if length < 16 then return nil, 'short menu DAT' end
    local b = ffi.cast('const uint8_t*', buffer)
    local picture, pictureSize, shapes, shapeSize
    local at = 0
    while at + 16 <= length do
        local meta = U32(b,at+4)
        local kind, size = meta % 128, math.floor(meta/128) % 0x80000 * 16
        if size < 16 or at+size > length then return nil, 'invalid menu DAT chunk' end
        if kind == 0x20 and size >= 85 and ffi.string(b+at+17,16):lower() == 'anc     anc     ' then
            picture, pictureSize = at, size
        elseif kind == 0x31 and size >= 35 and ffi.string(b+at+16,16):lower() == Name(group) then
            shapes, shapeSize = at, size
        end
        at = at + size
    end
    if not picture or not shapes then return nil, 'cursor texture or ' .. group .. ' sprites missing' end
    -- Menu texture headers start at +33; maps use +65. Padding lets the shared loader
    -- validate and upload the image without duplicating Direct3D texture handling.
    local imageLength = pictureSize + 32
    local image = ffi.new('uint8_t[?]',imageLength)
    ffi.copy(image+32,b+picture,pictureSize)
    local header, why = mapdat.Header(image,imageLength)
    if not header then return nil, why end
    -- This cursor atlas is DXT3. Refuse other formats rather than guess alpha semantics.
    if header.kind ~= 0x44585433 then return nil, 'cursor is not a DXT3 atlas' end
    -- FFXI doubles texture alpha. Do the same in each DXT3 alpha nibble, saturating.
    for block = header.at, header.at + header.rows*header.row - 1, 16 do
        for i = 0,7 do
            local a = image[block+i]
            image[block+i] = math.min(15,(a%16)*2) + math.min(15,math.floor(a/16)*2)*16
        end
    end
    local tableAt = shapes + 33 + b[shapes+32]*16
    local finish = shapes+shapeSize
    if tableAt+2 > finish then return nil, 'truncated cursor sprite table' end
    local count = b[tableAt]
    if count < 1 or count > 32 then return nil, 'invalid cursor frame count' end
    local pos, frames = tableAt+2, {}
    for i = 1,count do
        if pos+62 > finish or b[pos] ~= 1 then return nil, 'unsupported cursor sprite' end
        local piece = pos+1
        local w,h,x,y = U16(b,piece+16),U16(b,piece+18),U16(b,piece+20),U16(b,piece+22)
        if b[piece+24] ~= 0 or ffi.string(b+piece+45,16):lower() ~= 'anc     anc     '
            or w == 0 or h == 0 or x+w > header.width or y+h > header.height then
            return nil, 'invalid cursor sprite rectangle'
        end
        local corners = {}
        for c = 0,7 do corners[c+1] = S16(b,piece+c*2) end
        frames[i] = {x/header.width,y/header.height,(x+w)/header.width,(y+h)/header.height,w,h,
            rect = {x,y,x+w,y+h}, corners = corners}
        pos = piece+61
    end
    return image,imageLength,frames
end

-- Each DXT3 block's colours are blends of its two RGB565 end colours, so greying the ends greys every
-- pixel without touching alpha. Brightness is scaled so the brightest end is white, as tints multiply.
function cursor.Neutral(image, length)
    local header, why = mapdat.Header(image,length)
    if not header then return nil, why end
    if header.kind ~= 0x44585433 then return nil, 'cursor is not a DXT3 atlas' end
    local grey = ffi.new('uint8_t[?]',length)
    ffi.copy(grey,image,length)
    local finish = header.at + header.rows*header.row - 1
    local function Luma(at)
        local v = U16(grey,at)
        local r, g, b = math.floor(v/2048)/31, math.floor(v/32)%64/63, v%32/31
        return 0.299*r + 0.587*g + 0.114*b
    end
    local brightest = 0
    for block = header.at, finish, 16 do
        brightest = math.max(brightest, Luma(block+8), Luma(block+10))
    end
    if brightest <= 0 then return grey end
    for block = header.at, finish, 16 do
        for _,at in ipairs({block+8, block+10}) do
            local l = math.min(1, Luma(at)/brightest)
            local v = math.floor(l*31+0.5)*2048 + math.floor(l*63+0.5)*32 + math.floor(l*31+0.5)
            grey[at], grey[at+1] = v%256, math.floor(v/256)
        end
    end
    return grey
end

-- Each group read from the DAT once, whichever colour asks first; the grey copy is made from the same.
local parsed = {}
-- One entry per group and colour: the texture once made, or why it could not be and when to try again.
local loaded = {}
function cursor.Get(forceRetry, group, neutral)
    group = group or 'anc_s'
    local colours = loaded[group]
    if not colours then
        colours = {}
        loaded[group] = colours
    end
    local which = neutral and 2 or 1
    local entry = colours[which]
    if not entry then
        entry = { retryAt = 0, failure = 'not loaded yet' }
        colours[which] = entry
    end
    local frames = entry.frames
    if entry.handle then return entry.handle,frames[math.floor(os.clock()*15)%#frames+1] end
    if not forceRetry and os.clock() < entry.retryAt then return nil,entry.failure end
    entry.retryAt = os.clock()+10
    local function Failed(stage, reason)
        entry.failure = stage .. ': ' .. tostring(reason)
        return nil,entry.failure
    end
    local d3d8 = require('d3d8')
    local device = d3d8.get_device()
    if not device then return Failed('device', 'Direct3D device unavailable') end
    local sprites = parsed[group]
    if not sprites then
        local buffer,length = mapdat.Read('ROM/119/51.DAT')
        if not buffer then return Failed('DAT read', length) end
        local image,imageLength,frames = cursor.Parse(buffer,length,group)
        if not image then return Failed('DAT parse', imageLength) end
        sprites = { image = image, length = imageLength, frames = frames }
        parsed[group] = sprites
    end
    local image = sprites.image
    if neutral then
        local grey,why = cursor.Neutral(image,sprites.length)
        if not grey then return Failed('DAT parse', why) end
        image = grey
    end
    local made,why = mapdat.Texture(device,image,sprites.length)
    if not made then return Failed('texture upload', why) end
    entry.texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*',made))
    entry.handle,entry.frames = tonumber(ffi.cast('uint32_t',entry.texture)),sprites.frames
    frames = entry.frames
    return entry.handle,frames[math.floor(os.clock()*15)%#frames+1]
end
return cursor
