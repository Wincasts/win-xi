-- bars: small bars in a window, a few to a row, drawn as the party addon draws its own: XivParty's images
-- (assets/bars, with its licence), a back, a fill and a front tinted the bar's colour, a soft shadow
-- under them, a silver bookend at each end, and the figure over the bar with winxi's dark edge.
--
--     bars.Draw(list, count)
--
-- list holds count bars, each { fraction, color, figure, figureColor }: how full it is (0 to 1), its
-- colour, the words written over it and theirs. It takes up the room the bars need and moves on, as
-- imgui.Text does.
local ffi = require('ffi')
local d3d8 = require('d3d8')
local imgui = require('imgui')
local outlinedText = require('winxi.text')

local bars = {}

-- A bar, in the party addon's own numbers for its MP bar, from the top left of the bar's frame: see the
-- layout in party's frames.lua for what each is
local size = 0.75 -- how large it is drawn, against the party addon at a scale of 100
local bar = {
    back = 'bars/mp_back.png', fillImage = 'bars/mp_fill.png', front = 'bars/mp_front.png',
    width = 98.4, height = 14.4,
    frontPart = 164 / 170, cap = { 166 / 170, 0, 1, 11 / 24 },
    fill = { x = 4.8, width = 88.8 },
    body = { left = 3.6, top = 3.6, right = 94.8, bottom = 10.8 },
    figureRight = 92.4,
}
local bookend = { width = 3.6, over = 1.8 }
local shadowReach = 3
local perRow = 4
local gap = 6 -- between one bar and the next, in pixels

local white = { 1, 1, 1, 1 }
local black = { 0, 0, 0, 1 }

-- The images, each loaded the first time it is wanted and kept for as long as the addon is loaded
local handles = {} -- file -> the number imgui takes it as, or false where it could not be loaded
local kept = {}

local function Texture(file)
    local handle = handles[file]
    if handle == nil then
        handle = false
        local device = d3d8.get_device()
        if device ~= nil then
            local pointer = ffi.new('IDirect3DTexture8*[1]')
            local path = string.format('%sassets/%s', addon.path, file)
            if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) == ffi.C.S_OK then
                local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]))
                kept[#kept + 1] = texture
                handle = tonumber(ffi.cast('uint32_t', texture))
            end
        end
        handles[file] = handle
    end
    return handle
end

local list = nil
local pointA, pointB = { 0, 0 }, { 0, 0 }
local uvA, uvB = { 0, 0 }, { 1, 1 }
local tint = { 1, 1, 1, 1 }

local function Image(file, x1, y1, x2, y2, color, alpha, u1, v1, u2, v2)
    local handle = Texture(file)
    if not handle or x2 <= x1 then
        return
    end
    tint[1], tint[2], tint[3], tint[4] = color[1], color[2], color[3], color[4] * (alpha or 1)
    pointA[1], pointA[2], pointB[1], pointB[2] = x1, y1, x2, y2
    uvA[1], uvA[2], uvB[1], uvB[2] = u1 or 0, v1 or 0, u2 or 1, v2 or 1
    list:AddImage(handle, pointA, pointB, uvA, uvB, imgui.GetColorU32(tint))
end

-- A bookend, on whole pixels, as tall as the bar's frame
local function Cap(x, y, centre)
    local width = math.max(2, math.floor(bookend.width * size + 0.5))
    local left = math.floor(x + centre * size - width / 2 + 0.5)
    local top = math.floor(y + (bar.body.top - bookend.over) * size + 0.5)
    local bottom = math.floor(y + (bar.body.bottom + bookend.over) * size + 0.5)
    local cap = bar.cap
    Image(bar.front, left, top, left + width, bottom, white, 1, cap[1], cap[2], cap[3], cap[4])
end

-- The layers of a bar, each drawn for every bar before the next, so that what is drawn with one image
-- is drawn together. x and y are the top left of the bar's frame on screen.
local width, height = bar.width * size, bar.height * size
local layers = {
    function(x, y) Image(bar.back, x + 1.2 * size, y + 1.8 * size, x + 1.2 * size + width, y + 1.8 * size + height, black, 0.45) end,
    function(x, y) Image(bar.back, x + 2.4 * size, y + 3 * size, x + 2.4 * size + width, y + 3 * size + height, black, 0.2) end,
    function(x, y, item) Image(bar.back, x, y, x + width, y + height, item.color) end,
    function(x, y, item)
        local left = x + bar.fill.x * size
        local fraction = math.max(0, math.min(1, item.fraction or 0))
        Image(bar.fillImage, left, y, left + bar.fill.width * size * fraction, y + height, item.color)
    end,
    function(x, y, item) Image(bar.front, x, y, x + width, y + height, item.color, 1, 0, 0, bar.frontPart, 1) end,
    function(x, y)
        Cap(x, y, bar.body.left)
        Cap(x, y, bar.body.right)
    end,
}

local room = { 0, 0 }

function bars.Draw(items, count)
    local startX, startY = imgui.GetCursorScreenPos()
    startX, startY = math.floor(startX), math.floor(startY)
    list = imgui.GetWindowDrawList()

    -- a figure is written over its bar, the two ending on one line: the bar is as far down as that takes
    local _, textHeight = imgui.CalcTextSize('0')
    local barTop = math.max(0, textHeight - bar.body.bottom * size)
    local rowHeight = barTop + height + shadowReach * size
    local pitch = width + gap

    local function Place(index)
        return startX + ((index - 1) % perRow) * pitch, startY + math.floor((index - 1) / perRow) * rowHeight
    end

    for _, layer in ipairs(layers) do
        for index = 1, count do
            local x, y = Place(index)
            layer(x, y + barTop, items[index])
        end
    end

    for index = 1, count do
        local item = items[index]
        if item.figure ~= nil then
            local x, y = Place(index)
            local textWidth = imgui.CalcTextSize(item.figure)
            outlinedText.Draw(list, math.floor(x + bar.figureRight * size - textWidth), y, item.figureColor or white, item.figure)
        end
    end

    room[1] = math.min(count, perRow) * pitch - gap
    room[2] = math.ceil(count / perRow) * rowHeight
    imgui.Dummy(room)
end

return bars
