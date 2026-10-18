-- mapoverlay: the zone's ground painted flat where it is traced, fitted to the ground, the game's grid
-- lines over it, the player marked where the client's map table puts them,
-- the floor chosen in a zone of several, nothing in a zone with no ground traced, painted again when
-- its colours change, the map's own picture with Map Art, and the overlay switched off
local o = H.options()
local imgui = require('imgui')
local mapdat = require('winxi.mapdat')
local flat = require('flat')
local position = require('position')
local data = require('data.walkable')

-- every image and triangle drawn
local drawn = {}
local list = {
    AddImage = function(_, handle, a, b, uvA, uvB) drawn[#drawn + 1] = { kind = 'image', handle = handle, a = { a[1], a[2] }, b = { b[1], b[2] }, uvA = { uvA[1], uvA[2] }, uvB = { uvB[1], uvB[2] } } end,
    AddTriangleFilled = function(_, p1) drawn[#drawn + 1] = { kind = 'triangle', x = p1[1], y = p1[2] } end,
    AddLine = function(_, a, b) drawn[#drawn + 1] = { kind = 'line', a = { a[1], a[2] }, b = { b[1], b[2] } } end,
    AddText = function(_, pos, color, words) drawn[#drawn + 1] = { kind = 'text', x = pos[1], y = pos[2], words = words } end,
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

-- the ground painted, or the picture read: each counted, with the mask and colours it was given
local loads, pictures = {}, {}
flat.Load = function(mask, fill, edge) loads[#loads + 1] = { mask = mask, fill = { fill[1], fill[2], fill[3] }, edge = { edge[1], edge[2], edge[3] } } return {}, 500 + #loads end
mapdat.Load = function(dat, mask) pictures[#pictures + 1] = { dat = dat, mask = mask } return {}, 900 + #pictures end
local function lines() local n = 0 for _, d in ipairs(drawn) do if d.kind == 'line' then n = n + 1 end end return n end
local function texts() local n = 0 for _, d in ipairs(drawn) do if d.kind == 'text' then n = n + 1 end end return n end

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
H.print('Qufim: its ground painted once, in the fill and edge colours', n == 1, #loads == 1, loads[1].mask ~= nil,
    loads[1].fill[1] == o.fillColor[1], loads[1].edge[1] == o.edgeColor[1], #pictures == 0)
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
local rimStart = widest.x - math.floor(widest.length / 2)
H.print('the rim is the ground\'s edge, three pixels deep, not its middle', mask.edge[widest.y * 1024 + rimStart] == 255, mask.edge[widest.y * 1024 + rimStart + 2] == 255,
    mask.edge[widest.y * 1024 + rimStart + 3] == 0, mask.edge[widest.y * 1024 + widest.x] == 0, mask.edge[0] == 0)
H.print('the picture drawn is the one read, the overlay\'s size', image.handle == 501, image.b[1] - image.a[1] == o.size[1], image.b[2] - image.a[2] == o.size[1])

-- fitted: the ground's bounds and a margin of 6, made square, as UVs of the map
local b = mask.bounds
local half = math.max(b[3] - b[1], b[4] - b[2]) / 2 + 6
local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
local near = function(a, e) return math.abs(a - e) < 1e-6 end
H.print('fitted to the ground, a square round its middle', near(image.uvA[1], (cx - half) / 512), near(image.uvA[2], (cy - half) / 512),
    near(image.uvB[1] - image.uvA[1], 2 * half / 512), near(image.uvB[2] - image.uvA[2], 2 * half / 512))

-- the grid: the game's lines, 16 + 32k map units, only where they cross the ground, at their places
local vx, vy, vs = cx - half, cy - half, 2 * half
local function toMap(sx, sy) return vx + (sx - image.a[1]) / o.size[1] * vs, vy + (sy - image.a[2]) / o.size[1] * vs end
local onGround, onLine, full, expected = true, true, 0, 0
for k = 0, 15 do
    local u = 16 + 32 * k
    if u >= vx and u <= vx + vs then expected = expected + #mask.grid.across[k] / 2 end
    if u >= vy and u <= vy + vs then expected = expected + #mask.grid.down[k] / 2 end
end
for _, d in ipairs(drawn) do
    if d.kind == 'line' then
        local ax, ay = toMap(d.a[1], d.a[2])
        local bx, by = toMap(d.b[1], d.b[2])
        local mx, my = (ax + bx) / 2, (ay + by) / 2
        onGround = onGround and mask.values[math.floor(my * 2) * 1024 + math.floor(mx * 2)] > 0
        local fixed = d.a[1] == d.b[1] and ax or ay
        onLine = onLine and math.abs((fixed - 16) / 32 - math.floor((fixed - 16) / 32 + 0.5)) < 1e-6
        if math.abs(d.b[2] - d.a[2]) >= o.size[1] - 1e-6 or math.abs(d.b[1] - d.a[1]) >= o.size[1] - 1e-6 then full = full + 1 end
    end
end
H.print('the grid: a line for each stretch on the ground in view, each on a grid line, its middle on the ground, none across the whole overlay',
    lines() == expected, expected > 4, onLine, onGround, full == 0)
H.print('no letters or numbers', texts() == 0)
o.showGrid[1] = false
frame()
H.print('Show Grid off: no lines', lines() == 0)
o.showGrid[1] = true

-- the player at world (400, -300): map (400 * 2/5 - 100, 300 * 2/5 + 50) = (60, 170): left of Qufim's ground, off the view
H.print('the player off the part shown: no marker', triangles() == 0)
player.Movement.LocalPosition.X, player.Movement.LocalPosition.Y = (cx + 100) * 2.5, -((cy - 50) * 2.5)
frame()
local marker = nil
for _, d in ipairs(drawn) do if d.kind == 'triangle' then marker = d end end
local sx = image.a[1] + o.size[1] / 2
H.print('the player in the middle of the ground: marked there, outlined and filled', triangles() == 2, marker and math.abs(marker.x - (sx + o.playerSize[1] * 0.6)) < 0.01)
H.print('the ground not painted again', #loads == 1)

-- a colour changed: painted again, but not more often than every fifth of a second while it changes
o.fillColor[1] = 0.5
H.frames(1)
H.print('Fill Color changed: painted again in it', #loads == 2, loads[2].fill[1] == 0.5)
o.fillColor[1] = 0.4
H.frames(1)
H.print('changed again at once: not painted again yet', #loads == 2)
frame()
H.print('a moment later: painted in the newest', #loads == 3, loads[3].fill[1] == 0.4)

o.style = 'art'
frame()
n, image = images()
H.print('Map Art: the map\'s picture read with the mask', #pictures == 1, pictures[1].dat == qufim.dat, pictures[1].mask == mask, image.handle == 901)
o.style = 'flat'

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
H.print('Delkfutt: the ground of the floor the client says (5)', #loads == 4, loads[4].mask.bounds ~= nil and loads[4].mask.bounds[1] ~= mask.bounds[1])
floor = 3
frame()
H.print('a floor with no ground traced: nothing drawn', images() == 0)
H.command('/mapoverlay status')
H.print('status names the floor', (H.printed[#H.printed] or ''):find('floor 3', 1, true) ~= nil)
floor = 5
frame()
H.print('back to floor 5: drawn from the texture kept', images() == 1, #loads == 4)

H.command('/mapoverlay')
frame()
H.print('/mapoverlay hides it', o.isVisible[1] == false, images() == 0)
H.command('/mov')
frame()
H.print('/mov shows it again', o.isVisible[1] == true, images() == 1)

-- flat.Texture into a stand-in device: the rim in the edge colour, the rest in the fill, the mask the alpha
local ffi = require('ffi')
local texture
local device = { CreateTexture = function(_, w, h, levels, usage, format, pool)
    texture = { w = w, h = h, format = format, pool = pool, pitch = w * 4 + 8 }
    texture.bits = ffi.new('uint8_t[?]', texture.pitch * h)
    function texture:LockRect() return 0, { pBits = self.bits, Pitch = self.pitch } end
    function texture:UnlockRect() self.unlocked = true end
    function texture:Release() end
    return 0, texture
end }
local small = { width = 2, height = 2, values = ffi.new('uint8_t[4]', { 255, 128, 0, 64 }), edge = ffi.new('uint8_t[4]', { 255, 0, 0, 0 }) }
flat.Texture(device, small, { 1, 0.5, 0 }, { 0, 0, 1 })
local b = texture.bits
H.print('flat: A8R8G8B8, managed, the mask\'s size', texture.format == 21, texture.pool == 1, texture.w == 2, texture.h == 2, texture.unlocked == true)
H.print('flat: the rim in the edge colour (blue), solid', b[0] == 255, b[1] == 0, b[2] == 0, b[3] == 255)
H.print('flat: the ground in the fill colour (orange), half there', b[4] == 0, b[5] == 128, b[6] == 255, b[7] == 128)
H.print('flat: the second row past the pitch, off the ground clear', b[texture.pitch + 3] == 0, b[texture.pitch + 7] == 64)
