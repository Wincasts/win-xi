-- sct: statuses already on as the addon starts are taken as they are; a buff gained scrolls in the buff
-- colour, an enfeeble in the enfeeble colour, a loss in grey with a minus; each line moves from the
-- top of the box to the bottom, fading only near the bottom, and is gone after it
local o = H.options()
local imgui = require('imgui')
local icons = require('winxi.statusicons')

-- a player under Protect (40) as the addon loads
local ids = {}
for slot = 1, 32 do ids[slot] = 255 end
local serverId, zoning = 1, 0
local memory = { GetParty = function() return { GetMemberServerId = function() return serverId end } end,
    GetPlayer = function() return { GetIsZoning = function() return zoning end, GetStatusIcons = function() return ids end,
        GetLoginStatus = function() return 2 end } end }
AshitaCore.GetMemoryManager = function() return memory end
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Status ' .. id end,
    GetStatusIconByIndex = function() return nil end } end
icons.Get = function(id, useOwn) return 1000 + id, useOwn end

-- every text and image drawn, with its colour and place
local drawn = {}
local list = {
    AddText = function(_, pos, color, words) drawn[#drawn + 1] = { kind = 'text', y = pos[2], color = color, words = words } end,
    AddImage = function(_, handle, a) drawn[#drawn + 1] = { kind = 'image', handle = handle, y = a[2] } end,
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
o.locked[1], o.showBox[1], o.showOutline[1] = false, false, true
frame(); local on = rects
o.showOutline[1] = false; rects = 0; frame(); local off = rects
o.showOutline[1], o.locked[1] = true, true; rects = 0; frame()
H.print('outline drawn unlocked', on > 0, '| hidden with Show Outline off', off == 0, '| and locked', rects == 0)
