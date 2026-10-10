addon.name    = 'puppet'
addon.author  = 'win (and claude)'
addon.version = '1.0'
addon.desc    = 'The enfeebling spell an automaton will cast next, from the maneuvers up and what is on its target.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A small window for a puppetmaster: the spell the automaton will enfeeble with next, and those after
-- it. The choosing is predict.lua's, which follows the server's; this gathers what it needs to know
-- (the head and frame, the maneuvers up, the debuffs on the target) and shows the answer.
--
--   /puppet           shows or hides the window (it only appears while an automaton is out)
--   /puppet config    opens or closes the settings

require('common')
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local shell = require('winxi.shell')
local debuffs = require('winxi.debuffs')
local predict = require('predict')

local windowName = 'winxi.puppet'

local jobPup = 18
local extendedJobPacket = 0x044
local spawnFlagMob = 0x10

-- The maneuvers, by the status each shows as on the player
local maneuverElements = {
    [300] = 'fire',
    [301] = 'ice',
    [302] = 'wind',
    [303] = 'earth',
    [304] = 'thunder',
    [305] = 'water',
    [306] = 'light',
    [307] = 'dark',
}

-- The automaton as the server last described it. It does so on a change of area or job and when a
-- part is changed, so nothing is known when the addon is loaded part way through a visit to an area.
local automaton = { head = nil, frame = nil, skill = nil }

local function ReadAutomaton(e)
    if struct.unpack('B', e.data, 0x04 + 1) ~= jobPup then
        return
    end
    automaton.head = struct.unpack('B', e.data, 0x08 + 1)
    automaton.frame = struct.unpack('B', e.data, 0x09 + 1)
    automaton.skill = struct.unpack('H', e.data, 0x78 + 1)
end

local function CountManeuvers()
    local up = {}
    for _, status in pairs(AshitaCore:GetMemoryManager():GetPlayer():GetBuffs() or {}) do
        local element = maneuverElements[status]
        if element then
            up[element] = (up[element] or 0) + 1
        end
    end
    return up
end

-- The player's automaton, or nil when there is none out
local function GetAutomaton()
    local memory = AshitaCore:GetMemoryManager()
    if memory:GetPlayer():GetMainJob() ~= jobPup then
        return nil
    end
    local me = GetEntity(memory:GetParty():GetMemberTargetIndex(0))
    if me == nil or me.PetTargetIndex == nil or me.PetTargetIndex == 0 then
        return nil
    end
    return GetEntity(me.PetTargetIndex)
end

local function IsEnemy(entity)
    return entity ~= nil and entity.SpawnFlags ~= nil and bit.band(entity.SpawnFlags, spawnFlagMob) ~= 0
end

-- What the automaton is fighting, or failing that the enemy the player has targeted (which is what
-- it would be sent against)
local function GetTarget(pet)
    local fighting = pet.TargetedIndex ~= nil and pet.TargetedIndex ~= 0 and GetEntity(pet.TargetedIndex) or nil
    if IsEnemy(fighting) then
        return fighting
    end
    local targeted = GetEntity(AshitaCore:GetMemoryManager():GetTarget():GetTargetIndex(0))
    if IsEnemy(targeted) then
        return targeted
    end
    return nil
end

-- What the window is to show this frame: the target's name, the spells in order, or why there are none
local showing = { target = nil, queue = {}, reason = nil }

local function Work(pet)
    local target = GetTarget(pet)
    if target == nil then
        showing.target, showing.queue, showing.reason = nil, {}, 'No enemy targeted.'
        return
    end

    local id = target.ServerId
    showing.target = target.Name
    showing.queue, showing.reason = predict.Queue({
        head = automaton.head,
        frame = automaton.frame,
        skill = automaton.skill,
        maneuvers = CountManeuvers(),
        has = function(kind) return debuffs.Get(id, kind) ~= nil end,
        hpp = pet.HPPercent,
        mpp = AshitaCore:GetMemoryManager():GetPlayer():GetPetMPPercent(),
    })
end

local function DrawWindow(options)
    if options.showTarget[1] and showing.target then
        imgui.TextDisabled(showing.target)
    end

    if #showing.queue == 0 then
        imgui.Text(showing.reason or '')
        return
    end

    imgui.TextDisabled('Next')
    imgui.SameLine()
    imgui.Text(showing.queue[1])

    if options.showFollowing[1] and #showing.queue > 1 then
        local following = {}
        for i = 2, math.min(#showing.queue, 1 + options.followingCount[1]) do
            following[#following + 1] = showing.queue[i]
        end
        imgui.TextDisabled('Then')
        imgui.SameLine()
        imgui.Text(table.concat(following, ', '))
    end
end

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    showTarget = T{ true },
    showFollowing = T{ true },
    followingCount = T{ 3 },
}

local function DrawSettings(options)
    widgets.Label('Visible')
    imgui.Checkbox('##puppet.visible', options.isVisible)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows while an automaton is out. /puppet switches this.')
    end
    widgets.Label('Position')
    if imgui.InputInt2('##puppet.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos)
    end

    widgets.Gap()
    widgets.Label('Show Target Name')
    imgui.Checkbox('##puppet.target', options.showTarget)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The enemy the spells are worked out for: the one the automaton is fighting, or else the one targeted.')
    end
    widgets.Label('Show What Follows')
    imgui.Checkbox('##puppet.following', options.showFollowing)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The spells that come after the next, in the order they will be cast.')
    end
    widgets.Label('Spells To Follow')
    if imgui.SliderInt('##puppet.followingCount', options.followingCount, 1, 8) then
        options.followingCount[1] = math.max(1, math.min(8, options.followingCount[1]))
    end
end

local app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Puppet Settings',
    command = '/puppet',
    help = '/puppet shows or hides the window; /puppet config opens or closes the settings.',
    drawSettings = DrawSettings,
})

ashita.events.register('packet_in', 'puppet_packet_in', function(e)
    debuffs.HandlePacket(e)
    if e.id == extendedJobPacket then
        ReadAutomaton(e)
    end
end)

ashita.events.register('d3d_present', 'puppet_present', function()
    if not app:BeginFrame() then
        return
    end

    -- the window is there only while there is an automaton to speak for
    local pet = GetAutomaton()
    if pet == nil then
        return
    end

    Work(pet)
    app:Window(app.options.isVisible, DrawWindow)
end)
