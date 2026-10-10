addon.name    = 'puppet'
addon.author  = 'win (and claude)'
addon.version = '1.0'
addon.desc    = 'The enfeebling spells and the weapon skill an automaton will use next, from the maneuvers up and what is on its target.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A small window for a puppetmaster: the next three spells the automaton will enfeeble with, and the
-- weapon skill it will use. The choosing is predict.lua's, which follows the server's; this gathers
-- what it needs to know (the automaton's parts and skills, the maneuvers up, the debuffs on the
-- target) and shows the answer.
--
--   /puppet           shows or hides the window (it only appears while the automaton is fighting)
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
local petSyncPacket = 0x068
local zonePacket = 0x00A
local enfeeblesShown = 3

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

local app -- made below, once the settings can be drawn

-- The automaton as the server last described it: its head and frame, and its skills. The server does
-- so on a change of area or job and when a part is changed, and not when the addon is loaded, so what
-- it said is kept in the settings to start from the next time.
local automaton = { head = nil, frame = nil, magic = nil, melee = nil, ranged = nil }
local automatonKeys = { 'head', 'frame', 'melee', 'ranged', 'magic' }

local function ReadAutomaton(e)
    if struct.unpack('B', e.data, 0x04 + 1) ~= jobPup then
        return
    end
    automaton.head = struct.unpack('B', e.data, 0x08 + 1)
    automaton.frame = struct.unpack('B', e.data, 0x09 + 1)
    automaton.melee = struct.unpack('H', e.data, 0x70 + 1)
    automaton.ranged = struct.unpack('H', e.data, 0x74 + 1)
    automaton.magic = struct.unpack('H', e.data, 0x78 + 1)

    local kept = app.options.automaton
    local changed = false
    for _, key in ipairs(automatonKeys) do
        if kept[key] ~= automaton[key] then
            kept[key] = automaton[key]
            changed = true
        end
    end
    if changed then
        app:Save()
    end
end

-- What the automaton is fighting, as the server's id for it, or 0. The game is not told what a pet
-- has for a target as it is of a player's: the server says so only to the pet's master, in the packet
-- that keeps the two in step, which gives the enemy while the pet is attacking and nothing otherwise.
local fighting = 0

local function ReadPetSync(e)
    if struct.unpack('I', e.data, 0x08 + 1) ~= AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) then
        return
    end
    fighting = struct.unpack('I', e.data, 0x14 + 1)
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

-- The id of the enemy the automaton is fighting, or nil when it is fighting nothing. An enemy's place
-- among the game's entities is the low twelve bits of its id: if it is there and has no HP left, the
-- fight is over, whatever was last said.
local function GetTarget(pet)
    if pet == nil then
        fighting = 0
    end
    if fighting == 0 then
        return nil
    end
    local enemy = GetEntity(bit.band(fighting, 0xFFF))
    if enemy ~= nil and enemy.ServerId == fighting and enemy.HPPercent == 0 then
        fighting = 0
        return nil
    end
    return fighting
end

-- What the window shows: the spells in order and the weapon skill, either nil when there is none to
-- name. It is left as it was once the fight is over, for the window to fade out with.
local showing = { enfeebles = nil, weaponskill = nil }

local function Work(pet, id)
    local maneuvers = CountManeuvers()

    local queue = predict.Queue({
        head = automaton.head,
        frame = automaton.frame,
        skill = automaton.magic,
        maneuvers = maneuvers,
        has = function(kind) return debuffs.Get(id, kind) ~= nil end,
        hpp = pet.HPPercent,
        mpp = AshitaCore:GetMemoryManager():GetPlayer():GetPetMPPercent(),
    })
    local names = {}
    for i = 1, math.min(#queue, enfeeblesShown) do
        names[i] = queue[i]
    end
    showing.enfeebles = #names > 0 and table.concat(names, ', ') or nil

    showing.weaponskill = predict.Weaponskill({
        frame = automaton.frame,
        melee = automaton.melee,
        ranged = automaton.ranged,
        maneuvers = maneuvers,
    })
end

local function DrawLine(label, value)
    if value == nil then
        return
    end
    imgui.TextDisabled(label)
    imgui.SameLine()
    imgui.Text(value)
end

local function DrawWindow()
    DrawLine('Next Enfeeble:', showing.enfeebles)
    DrawLine('Next Weaponskill:', showing.weaponskill)
end

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    automaton = T{ }, -- the automaton as last described: see ReadAutomaton
}

local function DrawSettings(options)
    widgets.Label('Visible')
    imgui.Checkbox('##puppet.visible', options.isVisible)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows while the automaton is fighting. /puppet switches this.')
    end
    widgets.Label('Position')
    if imgui.InputInt2('##puppet.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos)
    end

end

app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Puppet Settings',
    command = '/puppet',
    help = '/puppet shows or hides the window; /puppet config opens or closes the settings.',
    drawSettings = DrawSettings,
    onSettings = function(options)
        -- the automaton as it was when last described, this character's
        if type(options.automaton) ~= 'table' then
            options.automaton = T{ }
        end
        for _, key in ipairs(automatonKeys) do
            automaton[key] = type(options.automaton[key]) == 'number' and options.automaton[key] or nil
        end
        fighting = 0
    end,
})

ashita.events.register('packet_in', 'puppet_packet_in', function(e)
    debuffs.HandlePacket(e)
    if e.id == extendedJobPacket then
        ReadAutomaton(e)
    elseif e.id == petSyncPacket then
        ReadPetSync(e)
    elseif e.id == zonePacket then
        fighting = 0
    end
end)

-- Whether the window is wanted this frame: a table, as the shell takes it
local wanted = { false }

ashita.events.register('d3d_present', 'puppet_present', function()
    if not app:BeginFrame() then
        return
    end

    -- the window is there while the automaton is fighting something and there is something to say of
    -- it; otherwise it fades out, showing what it last did
    local pet = GetAutomaton()
    local target = GetTarget(pet)
    if target ~= nil then
        Work(pet, target)
    end

    wanted[1] = app.options.isVisible[1] and target ~= nil and (showing.enfeebles ~= nil or showing.weaponskill ~= nil)
    app:Window(wanted, DrawWindow)
end)
