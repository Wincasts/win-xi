-- Coordinate-space regression matrix; run through tests/harness.lua with the Party addon.
-- This does not emulate D3D presentation, Windows DPI, or the game's actual renderer.
local imgui = require('imgui')
local frames, roster, options = require('frames'), require('roster'), require('options')
local saved = H.options()
local function StatusTexture() return 1, true end
local members = {}
for index = 1, 6 do
    members[index] = { name = 'Sample ' .. index, serverId = 0,
        isInZone = true, isActive = true, isPartyLeader = index == 1,
        job = 'WAR', zoneId = 0, hpp = 80, mpp = 60, hp = 1200, mp = 500,
        tp = 1500, noMp = false, statusIds = {40,41,33} }
end
local oldIO, oldDummy, oldCursor = imgui.GetIO, imgui.Dummy, imgui.GetCursorScreenPos
local oldClock = os.clock
local now = oldClock()
os.clock = function() now = now + 0.01; return now end
local display, origin, room = {}, { 100, 100 }, {}
imgui.GetIO = function() return { DisplaySize = display } end
imgui.GetCursorScreenPos = function() return origin[1], origin[2] end
imgui.Dummy = function(size) room[1], room[2] = size[1], size[2] end
local oldList = imgui.GetWindowDrawList
local list = oldList()
local oldClip = list.PushClipRect
local clips = 0
list.PushClipRect = function(self, minimum, maximum, intersect)
    assert(minimum[1] == 0 and minimum[2] == 0)
    assert(maximum[1] == display.x and maximum[2] == display.y, 'clip uses output resolution')
    clips = clips + 1
    return oldClip(self, minimum, maximum, intersect)
end
imgui.GetWindowDrawList = function() return list end
local sizes = {
    {640,480}, {1024,768}, {1280,1024}, -- 4:3 and 5:4
    {1280,720}, {1920,1080}, {2560,1440}, {3840,2160}, -- 16:9
    {1280,800}, {1920,1200}, -- 16:10
    {2560,1080}, {3440,1440}, {5120,1440}, -- ultrawide / super ultrawide
}
local baseline = {}
local combinations = 0
for _, size in ipairs(sizes) do
    display.x, display.y = size[1], size[2]
    for _, scale in ipairs({50,75,100,125,150,200}) do
        local style = options.Style(saved)
        style.scale = scale
        style.trimLast = true
        local before = clips
        frames.Draw(members, 'party', StatusTexture, style)
        assert(clips == before + 1, 'visible frame draws')
        assert(room[1] > 0 and room[2] > 0)
        local fullWidth, fullHeight = frames.FullSize(6, 'party', style)
        assert(fullWidth == room[1] and fullHeight >= room[2], 'full-layout reservation covers rendered rows')
        if not baseline[scale] then baseline[scale] = {room[1],room[2]} end
        assert(room[1] == baseline[scale][1] and room[2] == baseline[scale][2],
            'pixel geometry must not stretch with output aspect ratio')
        combinations = combinations + 1
    end
    -- A window wholly outside the output is measured, not rendered.
    origin[1] = display.x + 100
    local before = clips
    frames.Draw(members, 'party', StatusTexture, options.Style(saved))
    assert(clips == before)
    origin[1] = 100
end
for scale, size in pairs(baseline) do
    assert(math.abs(size[1] - baseline[100][1] * scale / 100) <= 1)
    assert(math.abs(size[2] - baseline[100][2] * scale / 100) <= 1)
end
-- Defaults are absolute pixels, not normalized anchors: explicitly record the limitation.
local defaults = options.Defaults()
assert(defaults.party.pos1[1] == 2098 and defaults.party.pos1[2] == 1215)
assert(defaults.party.pos1[1] > 1920, 'default main frame is outside a 1920-wide output')
list.PushClipRect = oldClip
imgui.GetIO, imgui.Dummy, imgui.GetCursorScreenPos = oldIO, oldDummy, oldCursor
imgui.GetWindowDrawList, os.clock = oldList, oldClock
H.print('Party output resolution/aspect-ratio matrix:', combinations, 'geometry and clipping checks passed')
local positioning = require('positioning')
for _, size in ipairs(sizes) do
    local layout = positioning.Layout(size[1], size[2], 300, 50, 240)
    local x,y = positioning.Place('party1',200,300,layout)
    assert(x == size[1]-15-200 and y == size[2]-15-300)
    if layout.allianceTop >= 0 then
        local _,targetTop = positioning.Place('main',200,50,layout)
        local _,a2 = positioning.Place('party2',200,240,layout)
        local _,a3 = positioning.Place('party3',200,240,layout,nil,a2+240)
        assert(targetTop == y-5-50)
        assert(a3 == a2+240+5)
        assert(targetTop-(a3+240) == 35, 'full expansion leaves exactly 35px without overlap')
        -- Main party shrinking moves Target, never the alliance's root.
        local _,smallMain = positioning.Place('party1',200,40,layout)
        local _,smallTarget = positioning.Place('main',200,50,layout,smallMain)
        local _,staticAlliance = positioning.Place('party2',200,240,layout,smallMain)
        assert(smallTarget == smallMain-5-50 and staticAlliance == a2)
    end
    assert(not positioning.Managed('sub') and not positioning.Managed('tot'))
    for _, frame in ipairs({ {300,400}, {800,800}, {60,40} }) do
        local x,y = positioning.Clamp(100000,-100,frame[1],frame[2],size[1],size[2])
        assert(x >= 0 and y >= 0)
        assert(x + frame[1] <= size[1] or x == 0)
        assert(y + frame[2] <= size[2] or y == 0)
    end
    assert(not positioning.Layout(0,0,300,50,240))
    assert(not positioning.Layout(0/0,math.huge,300,50,240))
end
-- Exercise the actual window path, not just the positioning helpers.
local windows = require('windows')
local oldPosition, oldSize, oldSet, oldBegin = imgui.GetWindowPos, imgui.GetWindowSize, imgui.SetWindowPos, imgui.Begin
local settings = options.Defaults()
settings.automaticPositioning[1], settings.fade.Enabled = true, false
windows.Use(settings)
local moved
imgui.GetIO = function() return {DisplaySize={x=1280,y=720}} end
imgui.GetWindowPos = function() return 1200, 650 end
imgui.GetWindowSize = function() return 300, 200 end
local sharedPosition
imgui.SetWindowPos = function(name, point)
    if sharedPosition then assert(point == sharedPosition, 'automatic windows must reuse the position vector') end
    sharedPosition = point
    moved = {name,point[1],point[2]}
end
imgui.Begin = function() return true end
local manualX, manualY = settings.party.pos1[1], settings.party.pos1[2]
windows.UpdatePositions(300,50,240)
windows.Draw(windows.List.party1, function() end)
assert(moved and moved[1] == windows.List.party1.name and moved[2] == 965 and moved[3] == 505,
    'main party is 15px from bottom and right')
assert(settings.party.pos1[1] == manualX and settings.party.pos1[2] == manualY, 'manual layout preserved')
windows.Draw(windows.List.main, function() end)
assert(moved[2] == 965 and moved[3] == 300, 'Target follows actual main party with a 5px gap')
imgui.GetWindowPos, imgui.GetWindowSize, imgui.SetWindowPos, imgui.Begin = oldPosition, oldSize, oldSet, oldBegin
imgui.GetIO = oldIO
windows.Use(saved)
H.print('Automatic edge positioning: margins, live Target link, static alliance root, 35px full-layout gap and clamping passed')
H.print('Background/menu resolutions are not inputs to Party geometry; native presentation still needs in-game validation')
