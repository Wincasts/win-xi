-- Saved placeholder death times survive settings reloads, logout and zoning, without stale sightings.
-- luajit tests/harness.lua mark addons/mark/mark.lua tests/mark_persistence_check.lua
require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's sets, from the repository's data
local realLoadfile = loadfile
loadfile = function(path)
    local own = path:match('^C:\\ashita\\addons\\mark\\(.*)$')
    return realLoadfile(own and ('addons/mark/' .. own) or path)
end
local function check(label, ok)
    assert(ok, label)
    H.print(label, true)
end
local now = 1700000000
local realTime = os.time
os.time = function(date) return date and realTime(date) or now end
local zone, entities, reads = 100, {}, 0
local memory = AshitaCore:GetMemoryManager()
local party = memory:GetParty()
party.GetMemberZone = function() return zone end
party.GetMemberTargetIndex = function() return 1024 end
memory.GetParty = function() return party end
memory.GetEntity = function()
    return {
        GetRenderFlags0 = function(_, index) reads = reads + 1; return entities[index] and 0x200 or 0 end,
        GetHPPercent = function(_, index) return entities[index] and entities[index].hp or 0 end,
        GetDistance = function() return 100 end,
        GetLocalPositionX = function() return 0 end, GetLocalPositionY = function() return 0 end,
        GetLocalPositionZ = function() return 0 end,
    }
end
AshitaCore.GetMemoryManager = function() return memory end
local hunts = require('hunts')
local monster = hunts.Monster
-- A second zone with the same placeholder index proves the saved key includes the zone.
hunts.Monster = function(z, name) return monster(z == 101 and 100 or z, name) end
local texts = {}
local imgui = require('imgui')
rawset(imgui, 'TextColored', function(_, text) texts[#texts + 1] = text end)
rawset(imgui, 'TextDisabled', function(text) texts[#texts + 1] = text end)
local function wrote(whole)
    for _, text in ipairs(texts) do if text == whole then return true end end
    return false
end
local o = H.options()
o.viewZone, o.viewName = 100, 'Jaggedy-Eared Jack'
o.marks, o.tods = {}, {}
o.sound[1] = false
local function poll() texts = {}; reads = 0; H.frames(9) end
local function saved(z)
    for _, tod in ipairs(o.phTods) do if tod.zone == z and tod.index == 294 then return tod.at end end
end
local function reload()
    -- Round-trip the persisted records through Lua text, as settings files do, then reset observations.
    local rows = {}
    for _, tod in ipairs(o.phTods) do
        rows[#rows + 1] = ('{zone=%d,index=%d,at=%d}'):format(tod.zone, tod.index, tod.at)
    end
    o.phTods = assert(loadstring('return {' .. table.concat(rows, ',') .. '}'))()
    H.resettle()
end
H.play(true)
entities[294] = { hp = 0 }
local saves = H.saves()
poll()
local death = now
check('observed placeholder death persisted immediately', saved(100) == death and H.saves() - saves == 1)
saves = H.saves()
poll()
check('countdown ticks do not write settings', H.saves() == saves)
now = now + 60
reload()
saves = H.saves()
poll()
check('settings reload preserves original corpse death and elapsed time',
    saved(100) == death and wrote('In 2:00') and H.saves() == saves)

H.play(false)
H.login(1)
saves = H.saves()
poll()
check('logout does not read retained entities or change saved death', reads == 0 and saved(100) == death and H.saves() == saves)
H.command('/mark ph 126 clear')
check('placeholder commands cannot change stale login-screen data', saved(100) == death)
now = now + 20
H.play(true) -- character-selection previews can also expose an entity
poll()
check('character selection is not polled', reads == 0 and saved(100) == death)
H.login(2)
local settings = require('settings')
settings.logged_in = false
poll()
check('character settings must be loaded before polling', reads == 0 and saved(100) == death)
settings.logged_in = true
poll()
check('login restores countdown without recounting the corpse', saved(100) == death and wrote('In 1:40'))
entities[294] = nil

zone, o.viewZone = 101, 101
poll()
check('same index in another zone has no timer from the first zone', saved(100) == death and saved(101) == nil and wrote('Unknown'))
saves = H.saves()
H.command('/mark ph 126 2')
check('manual placeholder TOD saved immediately under its zone', saved(101) == now - 120 and saved(100) == death and H.saves() - saves == 1)
reload()
poll()
check('second zone restores its own timer', wrote('In 1:00'))
zone, o.viewZone = 100, 100
poll()
check('returning to first zone restores its timer', wrote('In 1:40') and #o.phTods == 2)
saves = H.saves()
H.command('/mark ph 126 clear')
check('clear persists and leaves other zones untouched', saved(100) == nil and saved(101) == now - 120 and H.saves() - saves == 1)
reload()
poll()
check('cleared timer stays cleared after reload', wrote('Unknown') and saved(100) == nil)

H.command('/mark ph 126')
saves = H.saves()
entities[294] = { hp = 100 }
poll()
check('observed respawn removes saved death once', saved(100) == nil and H.saves() - saves == 1)
saves = H.saves()
poll()
check('live placeholder does not keep saving', H.saves() == saves)
entities[294] = nil
H.command('/mark ph 126 34') -- 31 minutes beyond the three-minute respawn
reload()
saves = H.saves()
poll()
check('expired saved timer discarded and persisted', saved(100) == nil and wrote('Unknown') and H.saves() - saves == 1)

-- A settings change to another character cannot inherit the previous character's sightings/timers.
H.command('/mark ph 126')
check('previous character has a saved death', saved(100) == now)
o.phTods = {}
H.resettle()
poll()
check('character with no saved deaths inherits no placeholder state', wrote('Unknown') and saved(100) == nil)

-- UI TOD and clear use the same persisted mutation path as chat commands.
local clicked = 'TOD##mark.phTod1'
rawset(imgui, 'SmallButton', function(label) return label == clicked end)
H.frames(1)
clicked = nil
check('placeholder UI TOD saved', saved(100) == now)
poll()
clicked = 'x##mark.phClear1'
H.frames(1)
clicked = nil
check('placeholder UI clear removes saved TOD', saved(100) == nil)
o.showMap[1] = false

-- Old settings files have no phTods; malformed or duplicate records must not poison runtime state.
o.phTods = nil
H.resettle()
check('old settings initialize an empty placeholder list', type(o.phTods) == 'table' and #o.phTods == 0)
o.phTods = {
    'bad', { zone = 100, index = 294 }, { zone = 0, index = 294, at = now },
    { zone = 100, index = 0, at = now }, { zone = 100, index = 4096, at = now },
    { zone = 100, index = 294.5, at = now }, { zone = 100, index = 294, at = 0 / 0 },
    { zone = 100, index = 294, at = math.huge }, { zone = math.huge, index = 294, at = now },
    { zone = 100, index = 294, at = now - 30 }, { zone = 100, index = 294, at = now - 10 },
}
H.resettle()
check('malformed deaths removed and duplicate zone/index collapsed', #o.phTods == 1 and saved(100) == now - 10)
o.phTods = 'bad'
H.resettle()
check('malformed placeholder list replaced', type(o.phTods) == 'table' and #o.phTods == 0)
H.unload()
