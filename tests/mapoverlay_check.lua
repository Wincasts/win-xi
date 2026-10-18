-- mapoverlay: the zone's map drawn only where it has traced ground, its picture read with that mask,
-- fitted to the ground, the player marked where the client's map table puts them, the floor chosen
-- in a zone of several, nothing in a zone with no ground traced, and the overlay switched off
local o = H.options()
local imgui = require('imgui')
local mapdat = require('winxi.mapdat')
local position = require('position')
local data = require('data.walkable')

-- every image and triangle drawn
local drawn = {}
local list = {
    AddImage = function(_, handle, a, b, uvA, uvB) drawn[#drawn + 1] = { kind = 'image', handle = handle, a = { a[1], a[2] }, b = { b[1], b[2] }, uvA = { uvA[1], uvA[2] }, uvB = { uvB[1], uvB[2] } } end,
    AddTriangleFilled = function(_, p1) drawn[#drawn + 1] = { kind = 'triangle', x = p1[1], y = p1[2] } end,
    AddRect = function() end,
}
rawset(imgui, 'GetWindowDrawList', function() return list end)
local function frame()
    H.frames(9) -- past the quarter second between looks
    for i = #drawn, 1, -1 do drawn[i] = nil end
    H.frames(1)
end
local function images() local n, last = 0, nil for _, d in ipairs(drawn) do if d.kind == 'image' then n, last = n + 1, d end end return n, last end
local function triangles() local n = 0 for _, d in ipairs(drawn) do if d.kind == 'triangle' then n = n + 1 end end return n end

-- the picture: each load counted, with the mask it was given
local loads = {}
mapdat.Load = function(dat, mask) loads[#loads + 1] = { dat = dat, mask = mask } return {}, 500 + #loads end

-- the zone the player is in
local zone = 0
local memory = AshitaCore.GetMemoryManager()
local party = memory.GetParty()
party.GetMemberZone = function() return zone end
memory.GetParty = function() return party end
AshitaCore.GetMemoryManager = function() return memory end

-- the player, and the client's table of maps: Qufim's entry (index 19) with a scale of 2 and offsets 100, -50
local player = { Movement = { LocalPosition = { X = 400, Y = -300, Z = 10 } }, Heading = 0 }
GetPlayerEntity = function() return player end
local TABLE, entries = 0x5000, {}
entries[TABLE + 19 * 0x0E] = { zone = 126, floor = 0, scale = 2, x = 100, y = -50 }
local function Entry(address) for base, e in pairs(entries) do if address >= base and address < base + 0x0E then return e, address - base end end end
ashita.memory.find = function() return 0x1000 end
ashita.memory.read_uint32 = function(address) if address == 0x1000 + 0x1C then return TABLE end return 0 end
ashita.memory.read_uint16 = function(address)
    local e, at = Entry(address)
    if not e then return 0 end
    if at == 0 then return e.zone end
    local v = at == 10 and e.x or e.y
    return v < 0 and v + 65536 or v
end
ashita.memory.read_uint8 = function(address)
    local e, at = Entry(address)
    if not e then return 0 end
    return at == 2 and e.floor or e.scale
end
local floor = 5
position.Floor = function() return floor end

H.play(true)
zone = 100 -- West Ronfaure: no ground traced
frame()
H.print('a zone with no ground traced: nothing drawn, nothing read', images() == 0, #loads == 0)
H.command('/mapoverlay status')
H.print('status says why', (H.printed[#H.printed] or ''):find('no walkable ground has been traced', 1, true) ~= nil)

zone = 126 -- Qufim Island
frame()
local n, image = images()
local qufim = data.maps['126_m_126_00_34add5a30bac']
H.print('Qufim: its map read once, from its file, with a mask', n == 1, #loads == 1, loads[1].dat == qufim.dat, loads[1].mask ~= nil)
local mask = loads[1].mask
-- the middle of the widest run of ground in the data, well inside it
local widest = { length = 0 }
for y, runs in pairs(qufim.rows) do
    local x, inside = 0, false
    for length in runs:gmatch('%d+') do
        length = tonumber(length)
        if inside and length > widest.length then widest = { length = length, x = x + math.floor(length / 2), y = y } end
        x, inside = x + length, not inside
    end
end
H.print('the mask is 1024 square, 255 on the ground, 0 far from it', mask.width == 1024, mask.height == 1024, mask.values[widest.y * 1024 + widest.x] == 255, mask.values[0] == 0)
H.print('the picture drawn is the one read, the overlay\'s size', image.handle == 501, image.b[1] - image.a[1] == o.size[1], image.b[2] - image.a[2] == o.size[1])

-- fitted: the ground's bounds and a margin of 6, made square, as UVs of the map
local b = mask.bounds
local half = math.max(b[3] - b[1], b[4] - b[2]) / 2 + 6
local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
local near = function(a, e) return math.abs(a - e) < 1e-6 end
H.print('fitted to the ground, a square round its middle', near(image.uvA[1], (cx - half) / 512), near(image.uvA[2], (cy - half) / 512),
    near(image.uvB[1] - image.uvA[1], 2 * half / 512), near(image.uvB[2] - image.uvA[2], 2 * half / 512))

-- the player at world (400, -300): map (400 * 2/5 - 100, 300 * 2/5 + 50) = (60, 170): left of Qufim's ground, off the view
H.print('the player off the part shown: no marker', triangles() == 0)
player.Movement.LocalPosition.X, player.Movement.LocalPosition.Y = (cx + 100) * 2.5, -((cy - 50) * 2.5)
frame()
local marker = nil
for _, d in ipairs(drawn) do if d.kind == 'triangle' then marker = d end end
local sx = image.a[1] + o.size[1] / 2
H.print('the player in the middle of the ground: marked there, outlined and filled', triangles() == 2, marker and math.abs(marker.x - (sx + o.playerSize[1] * 0.6)) < 0.01)
H.print('the picture not read again', #loads == 1)

o.fit[1] = false
frame()
n, image = images()
H.print('Fit To Walkable Area off: the whole map', near(image.uvA[1], 0), near(image.uvB[1], 1), near(image.uvB[2], 1))
o.zoom[1] = 2
frame()
n, image = images()
H.print('zoomed in: half the map, the player in its middle', near(image.uvB[1] - image.uvA[1], 0.5), near((image.uvA[1] + image.uvB[1]) / 2, cx / 512))
o.zoom[1], o.fit[1] = 1, true

zone = 157 -- Middle Delkfutt's Tower: the floor chosen
frame()
H.print('Delkfutt: the map of the floor the client says (5)', #loads == 2, loads[2].dat == data.maps['157_m_157_05_15410fa1f436'].dat)
floor = 3
frame()
H.print('a floor with no ground traced: nothing drawn', images() == 0)
H.command('/mapoverlay status')
H.print('status names the floor', (H.printed[#H.printed] or ''):find('floor 3', 1, true) ~= nil)
floor = 5
frame()
H.print('back to floor 5: drawn from the texture kept', images() == 1, #loads == 2)

H.command('/mapoverlay')
frame()
H.print('/mapoverlay hides it', o.isVisible[1] == false, images() == 0)
H.command('/mov')
frame()
H.print('/mov shows it again', o.isVisible[1] == true, images() == 1)
