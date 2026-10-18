-- atlas: the zone's map with the player, party, alliance and target on it, where the client's table
-- of maps puts them; the floor followed in a zone of several, and another chosen; members out of
-- sight placed by the server's word (0x0A0), and the server asked (0x0D2) only while one is; the
-- wheel zooming round the place under the mouse, a drag panning and no longer following; nothing
-- known for a zone with no map
local o = H.options()
local imgui = require('imgui')
local mapdat = require('winxi.mapdat')
local maps = require('maps')
local markers = require('markers')

-- the addon's own data/maps.lua, read from the project where Ashita would have it under its folder
local addonLoadfile = loadfile
loadfile = function(p)
    if p:sub(1, #addon.path) == addon.path then return addonLoadfile('addons/atlas/' .. p:sub(#addon.path + 1):gsub('\\', '/')) end
    return addonLoadfile(p)
end

-- every image and marker drawn
local drawn = {}
local list = setmetatable({
    AddImage = function(_, handle, a, b, uvA, uvB) drawn[#drawn + 1] = { kind = 'image', handle = handle, uvA = { uvA[1], uvA[2] }, uvB = { uvB[1], uvB[2] } } end,
    AddTriangleFilled = function(_, p1) drawn[#drawn + 1] = { kind = 'arrow', x = p1[1], y = p1[2] } end,
    AddCircleFilled = function(_, c, r) drawn[#drawn + 1] = { kind = 'dot', x = c[1], y = c[2] } end,
    AddCircle = function(_, c) drawn[#drawn + 1] = { kind = 'ring', x = c[1], y = c[2] } end,
    AddQuadFilled = function(_, a, b, c) drawn[#drawn + 1] = { kind = 'diamond', x = a[1], y = b[2] } end,
    AddText = function(_, pos, color, words) drawn[#drawn + 1] = { kind = 'text', words = words } end,
}, { __index = function() return function() end end })
rawset(imgui, 'GetWindowDrawList', function() return list end)
local function count(kind) local n = 0 for _, d in ipairs(drawn) do if d.kind == kind then n = n + 1 end end return n end
local function first(kind) for _, d in ipairs(drawn) do if d.kind == kind then return d end end end
local function said(words) for _, d in ipairs(drawn) do if d.kind == 'text' and d.words == words then return true end end return false end
local function frame()
    H.frames(5) -- past the tenth of a second between looks
    for i = #drawn, 1, -1 do drawn[i] = nil end
    H.frames(1)
end

-- the pictures: each read counted
local pictures = {}
mapdat.Load = function(dat) pictures[#pictures + 1] = dat return {}, 900 + #pictures end

-- the zone, the party and the entities the client is showing
local zone = 0
local members = {}   -- party slot -> { active, zone, index, name, id }
local entities = {}  -- index -> { x, y, z, heading, name }
local targetIndex = 0
local memory = AshitaCore.GetMemoryManager()
local party = {
    GetMemberZone = function(_, i) local m = members[i] return i == 0 and zone or (m and m.zone or 0) end,
    GetMemberIsActive = function(_, i) return members[i] and 1 or 0 end,
    GetMemberTargetIndex = function(_, i) return members[i] and members[i].index or 0 end,
    GetMemberName = function(_, i) return members[i] and members[i].name or '' end,
    GetMemberServerId = function(_, i) return members[i] and members[i].id or 0 end,
}
local entity = {
    GetRenderFlags0 = function(_, i) return entities[i] and 0x200 or 0 end,
    GetLocalPositionX = function(_, i) return entities[i].x end,
    GetLocalPositionY = function(_, i) return entities[i].y end,
    GetLocalPositionZ = function(_, i) return entities[i].z end,
    GetHeading = function(_, i) return entities[i].heading end,
    GetName = function(_, i) return entities[i].name end,
}
memory.GetParty = function() return party end
memory.GetEntity = function() return entity end
memory.GetTarget = function() return { GetTargetIndex = function() return targetIndex end } end
AshitaCore.GetMemoryManager = function() return memory end
local resources = AshitaCore.GetResourceManager()
resources.GetString = function(_, kind, id) return kind == 'zones.names' and ({ [126] = 'Qufim Island', [184] = 'Lower Delkfutt\'s Tower' })[id] or nil end
AshitaCore.GetResourceManager = function() return resources end

-- the client's table of maps: Qufim's (index 19) with a scale of 10 (2 a yalm) and offsets 100, -50;
-- Lower Delkfutt's floors 1 and 2 (74, 75), scale 5 and no offsets
local TABLE, entries = 0x5000, {}
entries[TABLE + 19 * 0x0E] = { zone = 126, floor = 0, scale = 10, x = 100, y = -50 }
entries[TABLE + 74 * 0x0E] = { zone = 184, floor = 1, scale = 5, x = 0, y = 0 }
entries[TABLE + 75 * 0x0E] = { zone = 184, floor = 2, scale = 5, x = 0, y = 0 }
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
-- the client's floor: floor 2 north of y 0, floor 1 south
maps.ClientFloor = function(x, y) return y > 0 and 2 or 1 end

-- packets: the server's word is read with struct, and what is sent is kept
local packed = {}
struct = {
    unpack = function(format, data, at) return data[at] end,
    pack = function(format, ...) local values = { ... } return { totable = function() return values end } end,
}
local outgoing = {}
local packets = AshitaCore.GetPacketManager()
packets.AddOutgoingPacket = function(_, id, data) outgoing[#outgoing + 1] = { id = id, zone = data[2] } end
AshitaCore.GetPacketManager = function() return packets end
-- a 0x0A0 as markers reads it: the bytes' values where they lie (a table stands in for the string)
local function told(id, zoneId, x, height, y)
    local data = {}
    for i = 1, 0x18 do data[i] = 0 end
    data[5], data[9], data[13], data[17], data[21] = id, zoneId, x, height, y
    H.packetData(0x0A0, data)
end

H.play(true)
o.isVisible[1] = true

-- the canvas: 512 pixels at 10, 20 (the harness's cursor), a map unit a pixel at 1x
local X, Y = 10, 20

zone = 280 -- Mog Garden: no map known
members[0] = { index = 1, name = 'Tester', id = 1000 }
entities[1] = { x = 0, y = 0, z = 0, heading = 0, name = 'Tester' }
frame()
H.print('a zone with no map: no picture read', #pictures == 0, count('image') == 0)
H.command('/atlas status')
H.print('status says why', (H.printed[#H.printed] or ''):find('no map is known', 1, true) ~= nil)

zone = 126 -- Qufim: the player at 50, 25 is map 2 * 50 - 100 = 0, -2 * 25 + 50 = 0... placed at 100, -20 instead
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
frame()
local image = first('image')
H.print('Qufim: its picture read once and drawn whole', #pictures == 1, pictures[1] == 'ROM/17/47.DAT', image ~= nil and image.uvA[1] == 0 and image.uvB[1] == 1)
-- map place: 100 * 2 - 100 = 100, 20 * 2 + 50 = 90
local arrow = first('arrow')
H.print('the player\'s arrow where the map table puts them', arrow ~= nil and math.abs(arrow.x - (X + 100 + math.cos(1.0) * 9 * 1.6 * 0.75)) < 0.01,
    arrow ~= nil and math.abs(arrow.y - (Y + 90 + math.sin(1.0) * 9 * 1.6 * 0.75)) < 0.01)
H.print('zone name said over the map', H.calls.Text ~= nil)

-- a party member in sight, an alliance member in sight, and a target
members[1] = { zone = 126, index = 2, name = 'Friend', id = 2000 }
members[6] = { zone = 126, index = 3, name = 'Ally', id = 3000 }
entities[2] = { x = 150, y = -20, z = 0, heading = 0, name = 'Friend' }
entities[3] = { x = 100, y = -70, z = 0, heading = 0, name = 'Ally' }
entities[4] = { x = 130, y = -20, z = 0, heading = 0, name = 'Worm' }
targetIndex = 4
frame()
H.print('party and alliance as dots, the target as a diamond', count('dot') == 4, count('diamond') == 2)
H.print('their names beside them', said('Friend'), said('Ally'), said('Worm'), not said('Tester'))
o.showAlliance[1] = false
o.showNames[1] = false
frame()
H.print('Show Alliance and Show Names off: the alliance and the names gone', count('dot') == 2, not said('Friend'))
o.showAlliance[1], o.showNames[1] = true, true

-- the friend goes out of sight: nothing until the server says, and it is asked
entities[2] = nil
outgoing = {}
frame()
H.print('a member out of sight: the server asked where, for this zone', #outgoing == 1, outgoing[1] and outgoing[1].id == 0x0D2, outgoing[1] and outgoing[1].zone == 126)
H.print('and nothing drawn for them yet', count('ring') == 0)
told(2000, 126, 200, 0, -40)
frame()
H.print('the server\'s word: drawn hollow where it says', count('ring') == 1)
frame()
H.print('asked no more than every few seconds', #outgoing == 1)
o.askServer[1] = false
H.frames(200)
H.print('Party Across Zone off: not asked', #outgoing == 1)
o.askServer[1] = true
entities[2] = { x = 150, y = -20, z = 0, heading = 0, name = 'Friend' }
H.frames(200)
local before = #outgoing
H.frames(200)
H.print('everyone in sight: not asked', #outgoing == before)
targetIndex = 0
members[1], members[6] = nil, nil

-- the wheel zooms round the place under the mouse; a drag pans and stops following
rawset(imgui, 'GetMousePos', function() return X + 100, Y + 100 end)
H.ret.IsItemHovered = { true }
rawset(imgui, 'GetIO', function() return { DisplaySize = { x = 1920, y = 1080 }, MouseWheel = 1 } end)
H.frames(1)
rawset(imgui, 'GetIO', function() return { DisplaySize = { x = 1920, y = 1080 }, MouseWheel = 0 } end)
H.ret.IsItemHovered = { false }
for i = #drawn, 1, -1 do drawn[i] = nil end
H.frames(1)
image = first('image')
H.print('the wheel: 1.25x, a fifth of the map off each side, following the player', image ~= nil and math.abs((image.uvB[1] - image.uvA[1]) - 0.8) < 0.001)
-- the player is at 100, 90: kept at the middle as near as the map's edge lets it, 204.8 from the left
H.print('kept on the map', image ~= nil and math.abs(image.uvA[1]) < 0.001)
H.ret.IsItemActive = { true }
H.ret.IsMouseDown = { true }
H.frames(1)
rawset(imgui, 'GetMousePos', function() return X + 80, Y + 100 end)
H.frames(1)
H.ret.IsItemActive = { false }
H.ret.IsMouseDown = { false }
for i = #drawn, 1, -1 do drawn[i] = nil end
H.frames(1)
image = first('image')
H.print('a drag pans the other way, 20 pixels at 1.25x', image ~= nil and math.abs(image.uvA[1] * 512 - 16) < 0.01)
H.frames(5)
image = first('image')
H.print('and no longer follows', image ~= nil and math.abs(image.uvA[1] * 512 - 16) < 0.01)
rawset(imgui, 'GetMousePos', function() return nil end)

-- Lower Delkfutt's: the floor followed, another chosen
zone = 184
entities[1] = { x = 0, y = 10, z = 0, heading = 0, name = 'Tester' }
frame()
H.print('a zone of several: the player\'s floor (2) drawn', pictures[#pictures] == 'ROM/17/85.DAT')
H.command('/atlas status')
H.print('status names the floor', (H.printed[#H.printed] or ''):find('floor 2', 1, true) ~= nil)
entities[1].y = -10
frame()
H.print('down the stairs: floor 1', pictures[#pictures] == 'ROM/17/84.DAT', count('arrow') == 2)
-- the floor buttons: Auto, then 1, 2, 3 and 15; pressing the third (floor 3)
local pressed = 0
rawset(imgui, 'SmallButton', function(label) if label:find('##atlas.floor3', 1, true) then pressed = pressed + 1 return pressed == 1 end return false end)
frame()
rawset(imgui, 'SmallButton', function() return false end)
frame()
H.print('another floor chosen: its picture, and the player not on it', pictures[#pictures] == 'ROM/17/86.DAT', count('arrow') == 0)
local reads = #pictures
entities[1].y = 10
frame()
H.print('the chosen floor kept as the player moves', #pictures == reads, count('arrow') == 0)

-- a new zone: the chosen floor and the view forgotten
zone = 126
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
frame()
image = first('image')
H.print('a new zone: the whole map again, the player on it', image ~= nil and image.uvA[1] == 0 and image.uvB[1] == 1, count('arrow') == 2)

-- hidden: nothing drawn, nothing asked
H.command('/atlas')
frame()
H.print('/atlas hides it', not o.isVisible[1], count('image') == 0)
