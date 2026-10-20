-- sct: statuses already on as the addon starts are taken as they are; a buff gained scrolls in the buff
-- colour, an enfeeble in the enfeeble colour, a loss in grey with a minus; each line moves from the
-- top of the box to the bottom, fading only near the bottom, and is gone after it
local o = H.options()
local imgui = require('imgui')
local icons = require('winxi.statusicons')
local itemicons = require('winxi.itemicons')
local itemFrames, itemRequests = 0, {}
local itemUV = { 0.25, 0.50, 0.28125, 0.53125 }
itemicons.Frame = function() itemFrames = itemFrames + 1; return 9000 end
itemicons.Place = function(id)
    itemRequests[#itemRequests + 1] = id
    return id == 4096 and itemUV or nil
end

-- a player under Protect (40) as the addon loads
local ids = {}
for slot = 1, 32 do ids[slot] = 255 end
local serverId, zoning = 1, 0
local bags, keyItems = { [0] = { [1] = { Id = 100, Count = 2 } } }, { [123] = true }
local inventory = {
    GetContainerCountMax = function() return 4 end,
    GetContainerItem = function(_, bag, slot) return bags[bag] and bags[bag][slot] end,
}
local memory = { GetParty = function() return { GetMemberServerId = function() return serverId end } end,
    GetPlayer = function() return { GetIsZoning = function() return zoning end, GetStatusIcons = function() return ids end,
        GetLoginStatus = function() return 2 end, HasKeyItem = function(_, id) return keyItems[id] == true end } end,
    GetInventory = function() return inventory end }
AshitaCore.GetMemoryManager = function() return memory end
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Status ' .. id end,
    GetStatusIconByIndex = function() return nil end } end
icons.Get = function(id, useOwn) return 1000 + id, useOwn end

-- every text and image drawn, with its colour and place
local drawn = {}
local list = {
    AddText = function(_, pos, color, words) drawn[#drawn + 1] = { kind = 'text', y = pos[2], color = color, words = words } end,
    AddImage = function(_, handle, a, b, uvA, uvB, color)
        drawn[#drawn + 1] = { kind = 'image', handle = handle, y = a[2],
            width = b[1] - a[1], height = b[2] - a[2], color = color,
            uv = { uvA[1], uvA[2], uvB[1], uvB[2] } }
    end,
    AddRect = function() end,
}
rawset(imgui, 'GetWindowDrawList', function() return list end)
local colors = {}
rawset(imgui, 'GetColorU32', function(c) local key = ('%.2f,%.2f,%.2f,%.2f'):format(c[1], c[2], c[3], c[4]) colors[key] = { c[1], c[2], c[3], c[4] } return key end)

local function frame()
    for i = #drawn, 1, -1 do drawn[i] = nil end
    H.frames(1)
end
-- the lines' words in the colour they were drawn in (the last AddText of each colour: the edge comes first)
local function words()
    local seen = {}
    for _, d in ipairs(drawn) do
        if d.kind == 'text' and d.words ~= '+' and d.words ~= '-' then
            local c = colors[d.color]
            if c and c[1] ~= 0 then seen[#seen + 1] = { words = d.words, color = c, y = d.y } end
        end
    end
    return seen
end

o.locked[1] = true
H.play(true)
ids[1] = 40
H.frames(10)
H.print('statuses on at load not taken as gained: nothing drawn', #words() == 0)
for _ = 1, 70 do H.frames(1) end -- past the settle
H.print('still nothing for Protect', #words() == 0)

-- Haste (33) gained
ids[2] = 33
frame()
local w = words()
H.print('Haste gained: one line', #w == 1, w[1] and w[1].words, '| buff colour', w[1] and w[1].color[3] == o.buffColor[3] and w[1].color[1] == o.buffColor[1])
local signs, image = 0, nil
for _, d in ipairs(drawn) do if d.words == '+' then signs = signs + 1 end if d.kind == 'image' then image = d.handle end end
H.print('a plus sign drawn', signs > 0, '| the icon winxi chooses', image == 1033)
local firstY = w[1].y

-- the line moves down
for _ = 1, 20 do frame() end
w = words()
H.print('it moves down the box', w[1] and w[1].y > firstY, '| still opaque before the fade', w[1] and w[1].color[4] == 1)

-- Paralysis (4) gained: the enfeeble colour, waiting behind Haste rather than on top of it
ids[3] = 4
frame()
for _ = 1, 15 do frame() end
w = words()
local para
for _, line in ipairs(w) do if line.words == 'Status 4' then para = line end end
H.print('Paralysis in the enfeeble colour', para ~= nil and para.color[1] == o.enfeebleColor[1] and para.color[2] == o.enfeebleColor[2])

-- Haste lost: grey, with a minus
ids[2] = 255
frame()
for _ = 1, 20 do frame() end
local minus, grey = false, false
for _, d in ipairs(drawn) do if d.words == '-' then minus = true end end
for _, line in ipairs(words()) do if line.words == 'Status 33' and line.color[1] == o.lostColor[1] then grey = true end end
H.print('Haste lost: a minus', minus, '| in grey', grey)

-- near the bottom a line fades, and once there it is gone
local faded = false
for _ = 1, 100 do
    frame()
    for _, line in ipairs(words()) do if line.color[4] < 1 and line.color[4] > 0 then faded = true end end
end
H.print('fades near the bottom', faded, '| all gone after', #words() == 0)

-- between areas: the list empties and fills again, which is not taken as gained or lost
zoning = 1; for _ = 1, 5 do frame() end
zoning = 0; ids[4] = 251; for _ = 1, 5 do frame() end
H.print('coming into an area: nothing scrolls', #words() == 0)
for _ = 1, 80 do frame() end

-- off: nothing gained or lost is shown
o.showGained[1] = false
ids[5] = 41; frame(); frame()
H.print('Show Gained off: nothing', #words() == 0)
o.showGained[1] = true

-- the test command sends three lines
H.print('/sct test taken', H.command('/sct test'))
for _ = 1, 40 do frame() end
H.print('test lines drawn', #words() >= 2)

-- the settings window draws
H.command('/sct config'); H.frames(2)
H.print('settings drawn', (H.calls.ColorEdit4 or 0) >= 3, '| sliders drawn', (H.calls.SliderInt or 0) > 0)

-- Scroll Speed: a line twice as fast is twice as far down after the same time
local function fall(speed)
    o.speed[1] = speed
    for _ = 1, 400 do frame() end -- the box empties
    H.command('/sct test'); frame()
    local top
    for _, line in ipairs(words()) do top = line.y end
    for _ = 1, 10 do frame() end
    for _, line in ipairs(words()) do if line.words == 'Status 33' then return line.y - top end end
end
local slow, fast = fall(60), fall(120)
H.print('Scroll Speed: twice as fast, twice as far', slow and fast and math.abs(fast - 2 * slow) < 0.01, slow, fast)

-- Line Spacing: the second line follows the first by its height and the spacing
local function gap(spacing)
    o.spacing[1] = spacing; o.speed[1] = 90
    for _ = 1, 400 do frame() end
    H.command('/sct test')
    local a, b
    for _ = 1, 60 do
        frame()
        local w = words()
        if #w >= 2 then a, b = w[1].y, w[2].y break end
    end
    -- the second has just left the top: how far down the first was then
    return a and b and a - b
end
local near, far = gap(0), gap(30)
H.print('Line Spacing: lines further apart', near and far and far > near + 25, near, far)

-- Scroll Time, from before Scroll Speed, comes over as the speed that took that long
o.duration = { 2 }; o.height[1] = 300
H.resettle()
H.print('Scroll Time of 2 s brought over as a speed', o.duration == nil, o.speed[1])

-- Show Outline: the edge is drawn unlocked, and not with it off or locked
local rects = 0
list.AddRect = function() rects = rects + 1 end
o.locked[1], o.boxStyle, o.showOutline[1] = false, 'text', true
frame(); local on = rects
o.showOutline[1] = false; rects = 0; frame(); local off = rects
o.showOutline[1], o.locked[1] = true, true; rects = 0; frame()
H.print('outline drawn unlocked', on > 0, '| hidden with Show Outline off', off == 0, '| and locked', rects == 0)

-- Text Only: no background, border or shadow; Full Background: the theme's
local window = require('winxi.window')
local plain, seen = window.Plain, nil
window.Plain = function(name, open, flags, draw, options)
    seen = { background = options.background, border = options.border, shadow = options.shadow, padding = options.padding }
    return plain(name, open, flags, draw, options)
end
H.command('/sct test'); o.boxStyle = 'text'; seen = nil; frame()
local function clear(c) return c ~= nil and c[4] == 0 end
H.print('Text Only: no background', clear(seen.background), '| no border', clear(seen.border), '| no shadow', seen.shadow == false, '| no padding', seen.padding == 0)
o.boxStyle = 'background'; seen = nil; frame()
H.print('Full Background: the theme\'s background, border and shadow', seen.background == nil and seen.border == nil and seen.shadow == nil)
window.Plain = plain


-- Show Box, from before Box Style, comes over
o.showBox = { true }; H.resettle(); local was = o.boxStyle
o.showBox = { false }; H.resettle()
H.print('Show Box on brought over as Full Background', was == 'background', '| off as Text Only', o.boxStyle == 'text', o.showBox == nil)

-- Actual acquisitions share the status queue or use an independent popup.
H.command('/sct config') -- stop showing placement outlines for the settings window
local resources = AshitaCore:GetResourceManager()
resources.GetItemById = function(_, id)
    if id == 4096 then return { Name = { 'Fire Crystal' } } end
end
AshitaCore.GetResourceManager = function() return resources end
local function receive(id, quantity)
    local old = bags[0][2]
    bags[0][2] = { Id = id, Count = (old and old.Id == id and old.Count or 0) + quantity }
    H.packet(0x01F)
end
local windows = {}
window.Plain = function(name, open, flags, draw, options)
    windows[name] = true
    return plain(name, open, flags, draw, options)
end
local function empty()
    for _ = 1, 400 do frame() end
    windows = {}
end
o.locked[1], o.dropsLocked[1] = true, true
empty()
receive(4096, 3); frame()
w = words()
H.print('received item in current area with quantity and color', #w == 1 and w[1].words == 'Fire Crystal x3' and w[1].color[1] == o.dropColor[1], '| no separate popup', not windows['winxi.sct.drops'])
local picture
for _, d in ipairs(drawn) do if d.kind == 'image' then picture = d end end
H.print('received item uses its own picture', picture and picture.handle == 9000,
    '| size follows Icon Size', picture and picture.width == o.iconSize[1] and picture.height == o.iconSize[1],
    '| correct atlas UVs', picture and table.concat(picture.uv, ',') == table.concat(itemUV, ','))
local fadedPicture = false
for _ = 1, 120 do
    frame()
    for _, d in ipairs(drawn) do
        if d.kind == 'image' and d.handle == 9000 then
            local c = colors[d.color]
            if c and c[4] > 0 and c[4] < 1 then fadedPicture = true end
        end
    end
end
H.print('item picture fades with the line', fadedPicture)
empty()
H.packetData(0x0D2, string.rep('\0', 0x1C)); frame()
H.print('treasure pool never triggers notification', #words() == 0)
bags[1] = { [1] = bags[0][2] }; bags[0][2] = nil
H.packet(0x020); frame()
H.print('moving between bags is not an acquisition', #words() == 0)
o.showDrops[1] = false
receive(4096, 1); frame()
H.print('item tracking can be disabled', #words() == 0)
o.showDrops[1], o.dropsSeparate[1] = true, true
windows = {}; receive(4096, 1); for _ = 1, 10 do frame() end
H.print('separate drop popup', windows['winxi.sct.drops'] == true, '| status area stays empty', not windows['winxi.sct'], '| item name', words()[1] and words()[1].words == 'Fire Crystal')
empty(); frame()
H.print('locked popup disappears when empty', not windows['winxi.sct.drops'])
receive(65500, 1); frame()
H.print('unknown item fallback', words()[1] and words()[1].words == 'Item 65500')
local missingPicture = true
for _, d in ipairs(drawn) do if d.kind == 'image' then missingPicture = false end end
H.print('missing item picture falls back to text', missingPicture)
empty()
local beforeKey = #itemRequests
keyItems[124] = true; H.packet(0x055); frame()
H.print('new key item shown', words()[1] and words()[1].words == 'Key Item: Status 124')
H.print('key items never use a regular item picture with the same ID', #itemRequests == beforeKey)
empty()
H.packet(0x055); frame()
H.print('key item refresh does not replay gains', #words() == 0)
keyItems[124] = nil; H.packet(0x055); frame()
H.print('key item loss is silent', #words() == 0)
keyItems[124] = true; H.packet(0x055); frame()
H.print('key item can be gained again', words()[1] and words()[1].words == 'Key Item: Status 124')
empty()
H.packet(0x00A); bags[0][3] = { Id = 4096, Count = 12 }; keyItems[125] = true; frame()
H.print('zoning refresh establishes baseline only', #words() == 0)
H.print('/sct testdrop taken', H.command('/sct testdrop')); frame()
H.print('test drop uses popup', words()[1] and words()[1].words == 'Fire Crystal x2')
-- Drawing items in both areas still starts the atlas only once per present.
o.dropsSeparate[1] = false
H.command('/sct testdrop')
local beforeFrame = itemFrames
frame()
H.print('item atlas started once across both areas', itemFrames == beforeFrame + 1)
empty()
H.command('/sct test'); frame()
local statusUV
for _, d in ipairs(drawn) do if d.kind == 'image' then statusUV = d.uv end end
H.print('status icon UVs restored after drawing items', statusUV and statusUV[2] == 0 and statusUV[4] == 1)
window.Plain = plain
