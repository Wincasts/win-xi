-- luajit tests/harness.lua mark addons/mark/mark.lua tests/mark_map_check.lua
local imgui, maps, hunts = require('imgui'), require('maps'), require('hunts')
local function check(label, ok) assert(ok, label); H.print(label, true) end
local function near(a, b) return math.abs(a - b) < .001 end
local record = {
    level = { 1, 1 }, kinds = 't', respawn = { 300, 300 }, drops = {}, indices = { 295 },
    points = { { 0, 0, 0 } }, areas = { { at = { 0, 0, 0 }, reach = 100, poly = { -100, -100, 100, -100, 100, 100, -100, 100 } } },
    routes = { { points = { { 0, 0, 0 }, { 20, 0, 20 } } } },
    placeholders = { { index = 294, name = 'Hare', points = { { 20, 0, 0 } }, respawn = 180 } },
}
hunts.Monster = function() return record end
hunts.ZoneName = function() return 'Test Zone' end
local floor = { floor = 0, index = 0, dat = 'ROM/1/1.DAT' }
maps.Floors = function() return { floor } end
maps.Entry = function() return { scale = 1, x = -256, y = -256 } end
maps.Texture = function() return 1 end
local memory = AshitaCore:GetMemoryManager()
local party = memory:GetParty()
party.GetMemberZone = function() return 100 end
party.GetMemberTargetIndex = function() return 1024 end
memory.GetParty = function() return party end
memory.GetEntity = function()
    return { GetRenderFlags0 = function(_, i) return (i == 294 or i == 295) and 0x200 or 0 end,
        GetHPPercent = function() return 100 end, GetDistance = function() return 100 end,
        GetLocalPositionX = function() return 0 end, GetLocalPositionY = function() return 0 end,
        GetLocalPositionZ = function() return 0 end }
end
AshitaCore.GetMemoryManager = function() return memory end
H.play(true)
local o = H.options()
o.viewZone, o.viewName = 100, 'Test NM'
o.showMap[1], o.isVisible[1], o.pinMap[1] = true, false, false
local hovered, active, down, wheel, mx, my = true, false, false, 0, 266, 276
local clicked, togglePin, mapFrames, positioned = nil, false, 0, 0
local positionedAt = nil
local image, circles, lines, rects, clips, tooltip
local depth = 0
local draw = imgui.GetWindowDrawList()
rawset(draw, 'AddImage', function(_, _, a, b)
    image = { a[1], a[2], b[1], b[2] }
end)
rawset(draw, 'AddCircleFilled', function(_, p) circles[#circles + 1] = { p[1], p[2] } end)
rawset(draw, 'AddLine', function(_, a, b) lines[#lines + 1] = { a[1], a[2], b[1], b[2] } end)
rawset(draw, 'AddRectFilled', function(_, a, b) rects[#rects + 1] = { a[1], a[2], b[1], b[2] } end)
rawset(draw, 'PushClipRect', function(_, a, b, intersect)
    depth = depth + 1; clips = { a[1], a[2], b[1], b[2], intersect }
end)
rawset(draw, 'PopClipRect', function() depth = depth - 1 end)
rawset(imgui, 'InvisibleButton', function(label)
    if label == '##mark.mapCanvas' then mapFrames = mapFrames + 1 end
end)
rawset(imgui, 'IsItemHovered', function() return hovered end)
rawset(imgui, 'IsItemActive', function() return active end)
rawset(imgui, 'IsMouseDown', function() return down end)
rawset(imgui, 'GetMousePos', function() return mx, my end)
rawset(imgui, 'GetIO', function() return { MouseWheel = wheel, DisplaySize = { x = 1920, y = 1080 } } end)
rawset(imgui, 'SmallButton', function(label) return clicked == label end)
rawset(imgui, 'Button', function(label) return clicked == label end)
rawset(imgui, 'Checkbox', function(label, value)
    if label == 'Pin Map##mark.mapPin' and togglePin then value[1] = not value[1]; return true end
    return false
end)
rawset(imgui, 'SetTooltip', function(text) tooltip = text end)
rawset(imgui, 'SetNextWindowPos', function(pos, condition)
    if condition == ImGuiCond_Always then
        positioned = positioned + 1
        positionedAt = { pos[1], pos[2] }
    end
end)
local transforms = 0
local toMap = maps.ToMap
maps.ToMap = function(...) transforms = transforms + 1; return toMap(...) end
local function frame(count)
    image, circles, lines, rects, clips, tooltip = nil, {}, {}, {}, nil, nil
    H.frames(count or 1)
    assert(depth == 0, 'viewport clip stack balanced')
end
frame(9)
check('unpinned map hidden with closed main window', image == nil and mapFrames == 0)
local saves = H.saves()
H.command('/mark pin')
check('pin command opens and saves independent map', o.pinMap[1] and o.showMap[1] and H.saves() - saves == 1)
frame()
check('pinned map renders while main window closed', image ~= nil and not o.isVisible[1])
check('map image starts at fit view', image[1] == 10 and image[2] == 20 and image[3] == 522 and image[4] == 532)
check('viewport intersects existing clipping', clips[1] == 10 and clips[2] == 20 and clips[3] == 522 and clips[4] == 532 and clips[5])
check('fit tooltip maps viewport center to world center', tooltip == 'H-8 (0, 0)')
frame()
local baseline = transforms
wheel = 1
frame()
wheel = 0
local zoomTransforms = transforms - baseline
check('wheel zoom anchored to mouse', near(image[1], -54) and near(image[2], -44) and near(image[3], 586) and near(image[4], 596))
check('zoomed tooltip remains at same world coordinate', tooltip == 'H-8 (0, 0)')
check('spawn points and live markers share map transform', near(circles[4][1], 266) and near(circles[4][2], 276) and near(circles[#circles][1], 266))
check('routes use zoomed coordinates', near(lines[1][1], 266) and near(lines[1][3], 291))
check('region fill uses zoomed coordinates', near(rects[1][1], -54 + 156 * 1.25))
baseline = transforms
frame()
check('zoom does not rebuild static map geometry', transforms - baseline == zoomTransforms)
local oldLeft = image[1]
hovered, wheel = false, 1
frame()
wheel = 0
check('wheel outside canvas ignored', image[1] == oldLeft)
hovered, active, down = true, true, true
frame() -- grab without jumping
mx, my = mx - 20, my - 10
frame()
check('left drag pans image without moving window', near(image[1], oldLeft - 20) and near(image[2], -54) and positioned == 1)
check('tooltip inverse transform remains correct after drag', tooltip == 'H-8 (0, 0)')
active, down = false, false
frame()
clicked = 'Reset View##mark.mapReset'
frame()
clicked = nil
check('reset returns to complete map', image[1] == 10 and image[3] == 522)
-- At a smaller viewport, reference-space input and rendering must stay aligned.
o.mapSize[1], mx, my, wheel = 256, 138, 148, 1
frame()
wheel = 0
check('zoom works at smaller viewport size', near(image[1], -22) and near(image[3], 298) and tooltip == 'H-8 (0, 0)')
clicked = '+##mark.mapZoomIn'
frame()
clicked = nil
check('zoom-in button works', image[3] - image[1] > 320)
clicked = '-##mark.mapZoomOut'
frame()
clicked = nil
check('zoom-out button works', near(image[3] - image[1], 320))
o.viewName = 'Another NM'
frame()
check('new monster resets pan and zoom', image[1] == 10 and image[3] == 266)
local floor2 = { floor = 1, index = 1, dat = 'ROM/1/2.DAT' }
maps.Floors = function() return { floor, floor2 } end
maps.ClientFloor = function() return 0 end
wheel = 1; frame(); wheel = 0
rawset(imgui, 'RadioButton', function(_, on) return not on end)
frame()
rawset(imgui, 'RadioButton', function() return false end)
check('new floor resets pan and zoom', image[1] == 10 and image[3] == 266)

saves = H.saves()
togglePin = true
frame()
togglePin = false
check('map toolbar unpins and saves', not o.pinMap[1] and H.saves() > saves)
frame()
check('unpin hides map when main is closed', image == nil)
o.isVisible[1] = true
frame()
check('unpinned map follows visible main window', image ~= nil)
clicked = 'x##mark.close'
frame()
clicked = nil
check('main header close hides unpinned map', not o.isVisible[1] and image == nil)
H.command('/mark pin')
frame()
clicked = 'x##mark.mapClose'
frame()
clicked = nil
check('pinned map has independent close button', not o.showMap[1] and o.pinMap[1] and not o.isVisible[1])
H.command('/mark map')
frame()
check('map command reopens pinned map without reopening main', image ~= nil and not o.isVisible[1])
H.play(false)
frame()
check('pinned map respects loading hide rule', image == nil)
H.play(true)
frame()
check('pinned map resumes after loading', image ~= nil)
local mainX, mainY = o.pos[1], o.pos[2]
saves = H.saves()
down = true
H.ret.GetWindowPos = { 345, 250 }
frame()
check('window drag updates independent position without saving each frame',
    o.mapPos[1] == 345 and o.mapPos[2] == 250 and o.pos[1] == mainX and o.pos[2] == mainY and H.saves() == saves)
down = false
frame()
check('window position saved once on drag release', H.saves() - saves == 1)
H.ret.GetWindowPos = { 100, 200 }
-- Reload resets transient view, but preserves the pin and independent saved window position.
o.mapPos = { 321, 234 }
H.resettle()
frame()
check('pin survives settings reload and window position is restored',
    o.pinMap[1] and image ~= nil and positioned == 2 and positionedAt[1] == 321 and positionedAt[2] == 234)
o.pinMap, o.mapPos = nil, { 0 / 0, math.huge }
H.resettle()
check('old or malformed map settings normalized', o.pinMap[1] == false and o.mapPos[1] == o.pos[1] + 60)
H.unload()
