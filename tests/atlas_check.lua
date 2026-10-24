-- atlas: the zone's map with the player, party, alliance and target on it, where the client's table
-- of maps puts them; the floor followed in a zone of several, and another chosen; members out of
-- sight placed by the server's word (0x0A0), and the server asked (0x0D2) only while one is; the
-- wheel zooming round the place under the mouse, a drag panning and no longer following; nothing
-- known for a zone with no map; /atlas browse giving the map the controller: the d-pad scrolling,
-- the left stick scrolling (kept from the game), optional d-pad scrolling, the shoulders stepping the zoom, the cursor and Y's waypoint, A locking to the player, X the floors, B giving it back
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
    AddTriangleFilled = function(_, p1, p2, p3, color) drawn[#drawn + 1] = { kind = 'arrow', x = p1[1], y = p1[2], color = color } end,
    AddCircleFilled = function(_, c, r, color) drawn[#drawn + 1] = { kind = 'dot', x = c[1], y = c[2], radius = r, color = color } end,
    AddCircle = function(_, c, r, color) drawn[#drawn + 1] = { kind = 'ring', x = c[1], y = c[2], radius = r, color = color } end,
    AddImageRounded = function(_, handle, a, b, uvA, uvB, col, rounding) drawn[#drawn + 1] = { kind = 'image', handle = handle, uvA = { uvA[1], uvA[2] }, uvB = { uvB[1], uvB[2] }, rounding = rounding, w = b[1] - a[1], h = b[2] - a[2] } end,
    AddRectFilled = function() drawn[#drawn + 1] = { kind = 'rect' } end,
    AddLine = function(_, a) drawn[#drawn + 1] = { kind = 'line', x = a[1], y = a[2] } end,
    AddQuadFilled = function(_, a, b, c) drawn[#drawn + 1] = { kind = 'diamond', x = a[1], y = b[2] } end,
    AddText = function(_, pos, color, words) drawn[#drawn + 1] = { kind = 'text', words = words, x = pos[1], y = pos[2] } end,
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

local titles = require('winxi.titles')
local titleDraw, inlineText, dummy, smallButton = titles.Draw, imgui.Text, imgui.Dummy, imgui.SmallButton
local windowTitle, inlineZone, mapGap, controlsAfterGap = nil, false, false, false
titles.Draw = function(words, ...) windowTitle = words; return titleDraw(words, ...) end
imgui.Text = function(words, ...) if words == 'Qufim Island' then inlineZone = true end return inlineText(words, ...) end
imgui.Dummy = function(size, ...) if size[2] == 5 then mapGap = true end return dummy(size, ...) end
imgui.SmallButton = function(label, ...)
    if label == '-##atlas.zoomOut' then controlsAfterGap = mapGap; mapGap = false end
    return smallButton(label, ...)
end
zone = 126 -- Qufim: the player at 50, 25 is map 2 * 50 - 100 = 0, -2 * 25 + 50 = 0... placed at 100, -20 instead
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
frame()
local image = first('image')
H.print('Qufim: its picture read once and drawn whole', #pictures == 1, pictures[1] == 'ROM/17/47.DAT', image ~= nil and image.uvA[1] == 0 and image.uvB[1] == 1)
-- map place: 100 * 2 - 100 = 100, 20 * 2 + 50 = 90
local arrow = first('arrow')
H.print('the player\'s arrow where the map table puts them', arrow ~= nil and math.abs(arrow.x - (X + 100 + math.cos(1.0) * 9 * 1.6 * 0.75)) < 0.01,
    arrow ~= nil and math.abs(arrow.y - (Y + 90 + math.sin(1.0) * 9 * 1.6 * 0.75)) < 0.01)
H.print('zone name is the window title, not inline', windowTitle == 'Qufim Island', not inlineZone)
H.print('buffer before the controls below the map', controlsAfterGap)
titles.Draw, imgui.Text, imgui.Dummy, imgui.SmallButton = titleDraw, inlineText, dummy, smallButton

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
o.partyStyle, o.allianceStyle = 'numbered', 'numbered'
for i = #drawn, 1, -1 do drawn[i] = nil end
H.frames(1)
H.print('member slots reach the map from party memory', said('2'), said('7'))
o.partyStyle, o.allianceStyle = 'dot', 'dot'
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
H.frames(30) -- settle any previous settings writes before testing the zoom-save debounce
local savesBeforeZoom = H.saves()
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
H.print('zoom updates settings immediately without a disk write per wheel tick', o.zoneZoom['126'] == 1.25, H.saves() == savesBeforeZoom)
H.frames(30)
H.print('zoom settings saved after input settles', H.saves() == savesBeforeZoom + 1)
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

-- Lower Delkfutt's: restore a saved zone zoom, follow the floor, then choose another.
o.zoneZoom['184'] = 2
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
H.print('floor changes keep the zone zoom', o.zoneZoom['184'] == 2, math.abs(first('image').uvB[1] - first('image').uvA[1] - 0.5) < 0.001)
local reads = #pictures
entities[1].y = 10
frame()
H.print('the chosen floor kept as the player moves', #pictures == reads, count('arrow') == 0)

-- Returning to a zone: forget the chosen floor and pan, but restore that zone's zoom.
zone = 126
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
frame()
image = first('image')
H.print('return to a zone restores its zoom and follows the player', image ~= nil and math.abs(image.uvB[1] - image.uvA[1] - 0.8) < 0.001, count('arrow') == 2)
H.print('zoom remembered independently per zone', o.zoneZoom['126'] == 1.25, o.zoneZoom['184'] == 2)
local beforeResetButton = imgui.SmallButton
imgui.SmallButton = function(label) return label == 'Whole Map##atlas.reset' end
H.frames(1)
imgui.SmallButton = beforeResetButton
H.print('Whole Map also updates the remembered zoom', o.zoneZoom['126'] == 1)

-- hidden: nothing drawn, nothing asked
H.command('/atlas')
frame()
H.print('/atlas hides it', not o.isVisible[1], count('image') == 0)

-- the controller: /atlas browse opens the map with the controller in hand
local queued = {}
AshitaCore.GetInputManager = function() return { GetXInput = function() return { QueueButtonData = function(_, b, v) queued[#queued + 1] = b .. '=' .. v end } end } end
zone = 126
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
local hint = nil
local textDisabled = imgui.TextDisabled
imgui.TextDisabled = function(t, ...) hint = t; return textDisabled(t, ...) end
H.button(18, 20000) -- walking as browsing begins
H.command('/atlas browse')
H.print('browse: the map shown, and the game told the left stick is centred', o.isVisible[1], queued[1] == '18=0', queued[2] == '19=0')
frame()
imgui.TextDisabled = textDisabled
H.print('the buttons said under the map, the sticks among them', hint ~= nil and hint:find('L Stick: Scroll', 1, true) ~= nil and hint:find('Y: Waypoint', 1, true) ~= nil)
-- the left stick: kept while pushed, neutral let through; right stick and d-pad left to the game
H.print('the left stick kept from the game', H.button(18, 32767) == true, H.button(19, 0) == false)
H.print('the right stick and the d-pad left to the game', H.button(20, 32767) == false, H.button(20, 0) == false, H.tap(H.Button.DpadLeft) == false)
frame()
image = first('image')
H.print('pushed east at 1x: the whole map shown, nothing to scroll', image ~= nil and image.uvA[1] == 0)
H.tap(H.Button.RB)
H.tap(H.Button.RB)
for i = #drawn, 1, -1 do drawn[i] = nil end
H.button(18, 0)
H.frames(1)
image = first('image')
local zoomed = image and (image.uvB[1] - image.uvA[1]) or 0
H.print('RB twice: a step each, 1.5x then 2x', math.abs(zoomed - 1 / 2) < 0.001)
local before = image and image.uvA[1] or 0
H.button(18, 32767)
H.frames(10)
H.button(18, 0)
for i = #drawn, 1, -1 do drawn[i] = nil end
H.frames(1)
image = first('image')
H.print('the left stick east scrolls east, no longer following', image ~= nil and image.uvA[1] > before)
H.tap(H.Button.A)
for i = #drawn, 1, -1 do drawn[i] = nil end
H.frames(1)
image = first('image')
H.print('A: following the player again (100 of 512, as near the middle as the edge lets)', image ~= nil and math.abs(image.uvA[1]) < 0.001)
H.tap(H.Button.LB)
H.tap(H.Button.LB)
for i = #drawn, 1, -1 do drawn[i] = nil end
H.frames(1)
image = first('image')
H.print('LB twice: the whole map', image ~= nil and math.abs(image.uvB[1] - image.uvA[1] - 1) < 0.001)
-- the steps from a zoom the wheel left between them
for i = #drawn, 1, -1 do drawn[i] = nil end
H.tap(H.Button.RB)
H.frames(1)
image = first('image')
local stepped = image and (image.uvB[1] - image.uvA[1]) or 0
H.print('LB at 1x stays at 1x, RB from 1x is 1.5x', math.abs(stepped - 1 / 1.5) < 0.001)
H.tap(H.Button.LB)

-- the cursor: on the player while following, though the edge keeps the view from centring on them;
-- in the middle of the view once scrolled; Y puts a waypoint under it, and Y on it takes it away
-- the cursor's middle: its first line runs across it from the left, the marker size (9) out
local function cursorX() for _, d in ipairs(drawn) do if d.kind == 'line' then return d.x + 9 end end end
frame()
local tip = first('arrow')
H.print('a cursor while browsing, a plain + (two lines, each over a dark edge)', count('line') == 4, count('ring') == 0)
H.print('following: the cursor on the player, at the edge', tip ~= nil and cursorX() ~= nil and math.abs(cursorX() - (tip.x - math.cos(1.0) * 9 * 1.6 * 0.75)) < 0.01)
H.tap(H.Button.RB)
H.button(18, 32767) H.frames(3) H.button(18, 0)
frame()
local middle = cursorX()
H.button(18, 32767) H.frames(3) H.button(18, 0)
frame()
H.print('scrolled: the cursor stays in the middle', middle ~= nil and cursorX() == middle)
H.tap(H.Button.Y)
frame()
H.print('Y: a waypoint under the cursor', count('ring') == 2)
H.tap(H.Button.Y)
frame()
H.print('Y on it again: gone', count('ring') == 0)
H.tap(H.Button.Y)
H.tap(H.Button.LB)
H.tap(H.Button.A)
H.command('/atlas cycle') -- to passthrough: the controller given back, the map left up
frame()
H.print('given back: no cursor, the waypoint still shown', count('line') == 0, count('ring') == 2)
H.command('/atlas cycle')
H.command('/atlas browse')

-- X: the next floor, in a zone of several; then back to the player's
zone = 184
entities[1] = { x = 0, y = 10, z = 0, heading = 0, name = 'Tester' }
frame()
H.tap(H.Button.X)
frame()
H.print('X: the zone\'s first floor, the player (on floor 2) not on it', count('arrow') == 0, count('image') == 1)
H.tap(H.Button.X)
H.tap(H.Button.X)
H.tap(H.Button.X)
H.tap(H.Button.X)
frame()
H.print('past the last: the player\'s floor again', count('arrow') == 2)

-- B: given back, and the map hidden again, as browsing opened it
H.print('B kept from the game', H.tap(H.Button.B) == true)
frame()
H.print('B: the controller given back and the map hidden', not o.isVisible[1], H.tap(H.Button.LB) == false, H.button(18, 30000) == false)
H.button(18, 0)

-- shown already: B leaves it shown
o.isVisible[1] = true
frame()
H.command('/atlas browse')
frame()
H.tap(H.Button.B)
frame()
H.print('browsing an open map: B leaves it open', o.isVisible[1])
o.controller[1] = false
H.command('/atlas browse')
frame()
H.print('Controller Navigation off: not browsing', H.tap(H.Button.LB) == false, (H.printed[#H.printed] or ''):find('Controller Navigation is off', 1, true) ~= nil)
o.controller[1] = true
-- hidden while browsing: the controller given back
H.command('/atlas browse')
frame()
H.command('/atlas')
frame()
o.isVisible[1] = true
frame()
H.print('hidden while browsing: given back', H.tap(H.Button.LB) == false)

-- Analog Stick Control off: the d-pad scrolls, with repeats, while both sticks reach the game.
o.analogStick[1] = false
H.command('/atlas browse')
H.tap(H.Button.A)
H.tap(H.Button.RB)
frame()
local dpadBefore = first('image').uvA[1]
H.print('d-pad mode leaves both sticks to the game', H.button(18, 32767) == false, H.button(20, 32767) == false)
frame()
H.print('analog movement does not pan in d-pad mode', first('image').uvA[1] == dpadBefore)
H.button(18, 0) H.button(20, 0)
H.print('d-pad mode takes the directional buttons', H.button(H.Button.DpadRight, 1) == true)
frame()
local dpadOnce = first('image').uvA[1]
H.print('d-pad right scrolls east', dpadOnce > dpadBefore)
H.frames(20)
H.button(H.Button.DpadRight, 0)
frame()
H.print('holding the d-pad repeats scrolling', first('image').uvA[1] > dpadOnce)
H.tap(H.Button.B)
o.analogStick[1] = true
frame()

-- a DirectInput controller (Controller Type PlayStation): its left stick, axes 0 and 4 (down the more), scrolls
-- in place of XInput's, and its buttons work the map
local dqueued = {}
AshitaCore.GetInputManager = function() return {
    GetXInput = function() return { QueueButtonData = function(_, b, v) queued[#queued + 1] = b .. '=' .. v end } end,
    GetController = function() return { QueueButtonData = function(_, b, v) dqueued[#dqueued + 1] = b .. '=' .. v end } end,
} end
o.controllerType = 'playstation'
zone = 126
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
H.frames(1)
H.dinput(0, 100) -- walking as browsing begins
local xqueued = #queued
H.command('/atlas browse')
H.print('DirectInput: the game told its stick is centred, not XInput\'s', dqueued[1] == '0=0', dqueued[2] == '4=0', #queued == xqueued)
frame()
local function dtap(button) H.dinput(button, 128) H.dinput(button, 0) H.frames(1) end
dtap(53) dtap(53) -- R1: zoomed in twice
H.dinput(0, 0)
frame()
image = first('image')
before = image and image.uvA[1] or 0
local beforeY = image and image.uvA[2] or 0
H.print('DirectInput stick kept from the game, let through as it centres', H.dinput(0, 127) == true, H.dinput(0, 0) == false)
H.dinput(0, 127)
H.frames(10)
H.dinput(0, 0)
frame()
image = first('image')
H.print('DirectInput stick east scrolls east', image ~= nil and image.uvA[1] > before)
before = image.uvA[1]
H.dinput(4, -128)
H.frames(10)
H.dinput(4, 0)
frame()
image = first('image')
H.print('DirectInput stick up scrolls north', image ~= nil and image.uvA[2] < beforeY, image ~= nil and image.uvA[1] == before)
H.print('DirectInput right stick (8, 20) left to the game', H.dinput(8, 127) == false, H.dinput(8, 0) == false, H.dinput(20, -128) == false, H.dinput(20, 0) == false)
H.print('XInput\'s stick left alone while DirectInput is in use', H.button(18, 32767) == false)
H.frames(10)
H.button(18, 0)
frame()
image = first('image')
H.print('and does not scroll', image ~= nil and image.uvA[1] == before)
o.analogStick[1] = false
frame()
H.print('DirectInput d-pad mode leaves the left stick to the game', H.dinput(0, 127) == false, H.dinput(4, -128) == false)
H.dinput(0, 0) H.dinput(4, 0)
local directDpadBefore = image.uvA[1]
H.print('DirectInput d-pad right taken', H.dinput(32, 9000) == true)
H.dinput(32, -1)
frame()
H.print('DirectInput d-pad pans the map', first('image').uvA[1] > directDpadBefore)
o.analogStick[1] = true
frame()
dtap(50) -- circle: B (the map was open already, so it stays)
frame()
H.print('circle: given back, the map left open', o.isVisible[1], H.dinput(0, 127) == false)
H.dinput(0, 0)
-- the triggers left to a crossbar: other addons told so, both of L2's reports let through, and a
-- button pressed while it is held not the map's
H.command('/atlas browse')
frame()
H.print('browsing: the triggers left free, and told so', (H.raised[#H.raised] or ''):find('atlas:1:pass', 1, true) ~= nil,
    H.dinput(54, 128) == false, H.dinput(12, 200) == false)
H.print('R1 with L2 held not the map\'s', H.dinput(53, 128) == false) H.dinput(53, 0)
H.dinput(54, 0) H.dinput(12, 0)
H.print('L2 let go: R1 the map\'s again', H.dinput(53, 128) == true) H.dinput(53, 0)
dtap(50)
frame()
o.controllerType = 'xinput'
H.frames(1)

-- passthrough, the last step of /atlas cycle: the map faded to Passthrough Opacity as the player walks,
-- whole again as they stop or with the mouse over it; in the other steps, never faded
local pushedAlpha = 1
local pushStyleVar = imgui.PushStyleVar
imgui.PushStyleVar = function(var, value, ...) if var == ImGuiStyleVar_Alpha then pushedAlpha = value end return pushStyleVar(var, value, ...) end
local function alphaAfter(count, walk)
    for _ = 1, count do
        if walk then entities[1].x = entities[1].x + 0.2 end
        pushedAlpha = 1
        H.frames(1)
    end
    return pushedAlpha
end
rawset(imgui, 'GetMousePos', function() return 0, 0 end)
zone = 126
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
o.isVisible[1] = true
H.print('shown by /atlas: walking leaves the map whole', alphaAfter(20, true) == 1)
alphaAfter(30)
o.isVisible[1] = false
H.frames(1)
H.command('/atlas cycle')
H.print('cycle from hidden: open, with the controller, whole while walking', o.isVisible[1], H.tap(H.Button.LB) == true, alphaAfter(20, true) == 1)
alphaAfter(30)
H.command('/atlas cycle')
H.print('then passthrough: still shown, the controller the game\'s', o.isVisible[1], H.tap(H.Button.LB) == false)
H.print('standing: whole', alphaAfter(5) == 1)
H.print('walking: down to Passthrough Opacity, a step at a time', alphaAfter(2, true) < 1 and pushedAlpha > 0.3, math.abs(alphaAfter(20, true) - 0.3) < 0.001)
H.print('stopped a moment: still faded', math.abs(alphaAfter(5) - 0.3) < 0.001)
H.print('stood still: whole again', alphaAfter(30) == 1)
rawset(imgui, 'GetMousePos', function() return 150, 250 end) -- inside the window, at 100, 200 and 300 by 150
H.print('the mouse over it: whole while walking', alphaAfter(20, true) == 1)
rawset(imgui, 'GetMousePos', function() return 0, 0 end)
o.passthroughOpacity[1] = 0
local begun = H.calls.Begin or 0
alphaAfter(30, true)
local walking = (H.calls.Begin or 0) - begun
H.print('at 0%: the window not drawn while walking', walking < 30)
o.passthroughOpacity[1] = 30
alphaAfter(30, true)
H.command('/atlas cycle')
H.print('then hidden', not o.isVisible[1])
local closingAlpha = alphaAfter(1)
H.print('cycle hides a moving map without flashing whole first', closingAlpha > 0 and closingAlpha < 0.3)
H.command('/atlas cycle')
local reopeningAlpha = alphaAfter(1)
H.print('cycle reversed mid-fade: smoothly back to open', o.isVisible[1], reopeningAlpha > closingAlpha and reopeningAlpha < 1)
H.print('open settles at full opacity', alphaAfter(20) == 1)
H.command('/atlas cycle')
alphaAfter(20, true)
H.command('/atlas browse')
H.print('passthrough to browsing fades up rather than snapping', alphaAfter(1) > 0.3 and pushedAlpha < 1)
alphaAfter(20)
H.command('/atlas cycle')
alphaAfter(20)
H.command('/atlas cycle')
alphaAfter(20)
o.isVisible[1] = true
H.frames(1)
H.command('/atlas cycle')
H.print('a map shown by /atlas: cycle takes it to open', H.tap(H.Button.LB) == true)
H.command('/atlas cycle')
H.command('/atlas browse')
H.print('browsing ends passthrough: whole while walking', alphaAfter(20, true) == 1)
H.tap(H.Button.B)
alphaAfter(30)
o.controller[1] = false
o.isVisible[1] = false
H.frames(1)
H.command('/atlas cycle')
H.print('Controller Navigation off: open is just shown', o.isVisible[1], H.tap(H.Button.LB) == false, alphaAfter(20, true) == 1)
H.command('/atlas cycle')
H.print('then passthrough', math.abs(alphaAfter(20, true) - 0.3) < 0.001)
o.controller[1] = true
imgui.PushStyleVar = pushStyleVar

-- each mode's frame: open's Width, Height and Shape, and passthrough's own
local frameSize = nil
local invisibleButton = imgui.InvisibleButton
rawset(imgui, 'InvisibleButton', function(id, size, ...) if id == '##atlas.canvas' then frameSize = { size[1], size[2] } end return invisibleButton(id, size, ...) end)
zone = 126
entities[1] = { x = 100, y = -20, z = 5, heading = 1.0, name = 'Tester' }
o.isVisible[1] = false -- out of the passthrough the last check left
H.frames(1)
o.isVisible[1] = true
o.zoneZoom['184'] = 1 -- this frame-size check needs a whole-map view
zone = 184
frame()
o.zoneZoom['126'] = 1
zone = 126
o.openWidth[1], o.openHeight[1] = 512, 256
frame()
image = first('image')
H.print('open 512 by 256: the frame that size', frameSize ~= nil and frameSize[1] == 512 and frameSize[2] == 256)
H.print('at 1x the width the whole map across, half of it down', image ~= nil and image.uvA[1] == 0 and image.uvB[1] == 1 and math.abs(image.uvB[2] - image.uvA[2] - 0.5) < 0.001)
H.print('square: no rounding', image ~= nil and image.rounding == nil)
o.openShape = 'round'
frame()
image = first('image')
H.print('round: the picture rounded by half the shorter side, a pill', image ~= nil and image.rounding == 128)
o.openShape = 'rounded'
frame()
image = first('image')
H.print('rounded: a little', image ~= nil and image.rounding ~= nil and image.rounding > 0 and image.rounding < 40)
o.passthroughWidth[1], o.passthroughHeight[1], o.passthroughShape = 256, 256, 'round'
o.isVisible[1] = false
H.frames(1)
H.command('/atlas cycle')
H.command('/atlas cycle')
frame()
image = first('image')
H.print('passthrough: its own 256 by 256, round, a circle', frameSize[1] == 256 and frameSize[2] == 256, image ~= nil and image.rounding == 128 and image.w == 256)
H.frames(20)
H.command('/atlas cycle')
for i = #drawn, 1, -1 do drawn[i] = nil end
H.frames(1)
image = first('image')
H.print('cycle fade-out keeps the passthrough frame, without a size/shape snap', frameSize[1] == 256 and frameSize[2] == 256, image ~= nil and image.rounding == 128)
o.isVisible[1] = true
frame()
H.print('shown by /atlas: open\'s frame', frameSize[1] == 512 and frameSize[2] == 256)
o.openWidth[1], o.openHeight[1], o.openShape = 512, 512, 'square'
o.passthroughWidth[1], o.passthroughHeight[1], o.passthroughShape = 512, 512, 'square'
rawset(imgui, 'InvisibleButton', invisibleButton)

-- Edge legends use the same 16-unit inset / 32-unit cells as maps.Square, not screen-space cells.
local view = require('view')
local legendState = view.New()
local function legendFrame(shape)
    for i = #drawn, 1, -1 do drawn[i] = nil end
    view.Draw(list, legendState, 0, 0, { picture = 1, markers = {} }, o, shape or 'square')
end
legendFrame()
H.print('whole map: no duplicate grid legend', count('text') == 0)
view.Zoom(legendState, 2)
legendFrame()
H.print('cropped legends: visible column letters and row numbers', said('E'), said('K'), said('5'), said('11'), not said('D'), not said('12'))
local legendText = {}
for _, d in ipairs(drawn) do if d.kind == 'text' then legendText[#legendText + 1] = d end end
H.print('legend has no boxes, only text with a one-pixel shadow', count('rect') == 1,
    #legendText >= 2 and legendText[1].words == legendText[2].words
    and legendText[1].x == legendText[2].x + 1 and legendText[1].y == legendText[2].y + 1)
H.print('overlay grid agrees with map coordinates', maps.Square(160, 160) == 'E-5', maps.Square(352, 352) == 'K-11')
view.Pan(legendState, -128, 0) -- left native legend visible, right one cropped
legendFrame()
local rowsOnLeft = false
for _, d in ipairs(drawn) do
    if d.kind == 'text' and tonumber(d.words) and d.x < 256 then rowsOnLeft = true end
end
H.print('native left legend visible: only replace the cropped right legend', said('5'), not rowsOnLeft)
view.Reset(legendState)
view.Frame(legendState, 512, 256)
legendFrame()
H.print('wide frame crops top/bottom at 1x: replace letters, not visible row legends', said('A'), said('O'), not said('5'))
view.Frame(legendState, 512, 512)
view.Zoom(legendState, 2)
legendFrame('round')
local outside = false
for _, d in ipairs(drawn) do
    if d.kind == 'text' and ((d.x - 256)^2 + (d.y - 256)^2 > 256^2) then outside = true end
end
H.print('round map: legends stay inside the map edge', said('H'), said('8'), not outside)

-- Selectable marker styles; default styles above are still covered by the original checks.
local markerState = view.New()
local testMarker = { kind = 'player', mx = 256, my = 256, heading = 0, near = true, name = 'Marker Test', slot = 2 }
local function markerFrame(alpha)
    for i = #drawn, 1, -1 do drawn[i] = nil end
    view.Draw(list, markerState, 0, 0, { markers = { testMarker } }, o, 'square', alpha)
end
o.playerStyle = 'chevron'
markerFrame()
H.print('player chevron: two edged strokes, no filled triangle', count('line') == 4, count('arrow') == 0)
o.playerStyle = 'dotFacing'
markerFrame()
H.print('player dot plus facing line', count('dot') == 2, count('line') == 2)
o.playerStyle = 'ringArrow'
markerFrame()
H.print('player ring plus arrow', count('ring') == 2, count('arrow') == 2)
o.playerStyle, o.playerSize[1] = 'arrow', 18
markerFrame()
H.print('separate player size controls the arrow', math.abs(first('arrow').x - (256 + 18 * 1.6 * 0.75)) < 0.001)
o.playerSize[1] = 0
markerFrame()
H.print('size zero inherits the existing shared marker size', math.abs(first('arrow').x - (256 + o.markerSize[1] * 1.6 * 0.75)) < 0.001)

testMarker.kind = 'party'
o.partyStyle = 'triangle'
markerFrame()
H.print('party directional triangle', count('arrow') == 2, count('dot') == 0)
testMarker.near, testMarker.heading = false, nil
markerFrame()
H.print('unknown distant facing falls back to a hollow dot', count('arrow') == 0, count('ring') == 1)
testMarker.near, testMarker.heading = true, 0
o.partyStyle = 'hollow'
markerFrame()
H.print('party hollow circle has no filled centre', count('ring') == 2, count('dot') == 0)
o.partyStyle = 'numbered'
markerFrame()
H.print('numbered marker shows the member slot', said('2'), count('dot') == 2)
o.partyStyle, o.partySize[1] = 'dot', 12
markerFrame()
local function lastDot() local found; for _, d in ipairs(drawn) do if d.kind == 'dot' then found = d end end return found end
H.print('separate party marker size', lastDot().radius == 6)
testMarker.kind, o.allianceSize[1], o.allianceStyle = 'alliance', 6, 'hollow'
markerFrame()
H.print('alliance style and size independent of party', count('dot') == 0, first('ring').radius == 3)

local packedColor = imgui.GetColorU32
imgui.GetColorU32 = function(c) return c[4] end -- capture alpha for outline/fade assertions
testMarker.kind, o.partyOutline[1] = 'party', false
markerFrame(0.5)
H.print('outline disabled without hiding the marker', first('dot').color == 0, lastDot().color == o.partyColor[4] * 0.5)
o.partyOutline[1] = true
markerFrame(0.5)
H.print('outline follows window opacity', math.abs(first('dot').color - 0.85 * 0.5) < 0.001)
imgui.GetColorU32 = packedColor

o.showNames[1], o.namesOnHover[1] = true, true
rawset(imgui, 'GetMousePos', function() return 10, 10 end)
markerFrame()
H.print('hover names: hidden away from the marker', not said('Marker Test'))
rawset(imgui, 'GetMousePos', function() return 256, 256 end)
markerFrame()
H.print('hover names: shown near the marker', said('Marker Test'))
o.showNames[1] = false
markerFrame()
H.print('hidden names stay hidden while hovering', not said('Marker Test'))
o.showNames[1], o.namesOnHover[1] = true, false
rawset(imgui, 'GetMousePos', function() return 10, 10 end)
markerFrame()
H.print('always names do not need the mouse', said('Marker Test'))

-- Exercise the actual settings selections, not just the renderer's option values.
local combo, selectable, radio = imgui.BeginCombo, imgui.Selectable, imgui.RadioButton
imgui.BeginCombo = function(id) return id:find('Style', 1, true) ~= nil end
imgui.Selectable = function(label)
    return label == 'Chevron##atlas.playerStyle.chevron' or label == 'Numbered dot##atlas.partyStyle.numbered'
        or label == 'Hollow circle##atlas.allianceStyle.hollow'
end
imgui.RadioButton = function(label) return label == 'On Hover##atlas.namesHover' end
H.command('/atlas config')
H.frames(1)
H.print('settings select player, party and alliance styles', o.playerStyle == 'chevron', o.partyStyle == 'numbered', o.allianceStyle == 'hollow')
H.print('settings select hover names', o.showNames[1], o.namesOnHover[1])
H.command('/atlas config')
imgui.BeginCombo, imgui.Selectable, imgui.RadioButton = combo, selectable, radio
