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

-- The automaton as the server last described it. It does so on a change of area or job and when a
-- part is changed, so nothing is known when the addon is loaded part way through a visit to an area.
local automaton = { head = nil, frame = nil, magic = nil, melee = nil, ranged = nil, holdsTp = false }

-- The attachments that have an automaton keep its TP to close its master's skillchain, as the
-- server numbers them: Inhibitor and Inhibitor II, Speedloader and Speedloader II
local tpHolders = { [3] = true, [11] = true, [14] = true, [15] = true }
local attachmentSlots = 12
local masterTpToHold = 900 -- with this much TP the master is waited on, to open the skillchain

local function ReadAutomaton(e)
    if struct.unpack('B', e.data, 0x04 + 1) ~= jobPup then
        return
    end
    automaton.head = struct.unpack('B', e.data, 0x08 + 1)
    automaton.frame = struct.unpack('B', e.data, 0x09 + 1)
    automaton.melee = struct.unpack('H', e.data, 0x70 + 1)
    automaton.ranged = struct.unpack('H', e.data, 0x74 + 1)
    automaton.magic = struct.unpack('H', e.data, 0x78 + 1)

    automaton.holdsTp = false
    for slot = 0, attachmentSlots - 1 do
        if tpHolders[struct.unpack('B', e.data, 0x0A + slot + 1)] then
            automaton.holdsTp = true
        end
    end
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

-- What the window is to show this frame: the spells in order or why there are none, and the weapon skill
local showing = { enfeebles = '', weaponskill = '' }

local function Work(pet)
    local maneuvers = CountManeuvers()

    local target = GetTarget(pet)
    if target == nil then
        showing.enfeebles = 'No enemy targeted.'
    else
        local id = target.ServerId
        local queue, reason = predict.Queue({
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
        showing.enfeebles = reason or table.concat(names, ', ')
    end

    local name, reason = predict.Weaponskill({
        frame = automaton.frame,
        melee = automaton.melee,
        ranged = automaton.ranged,
        maneuvers = maneuvers,
    })
    showing.weaponskill = reason or name or 'None.'
    -- with the master's TP ready, an automaton that holds its own waits for the skillchain to be opened
    if name and automaton.holdsTp and AshitaCore:GetMemoryManager():GetParty():GetMemberTP(0) >= masterTpToHold then
        showing.weaponskill = name .. ' (waiting on your skillchain)'
    end
end

local function DrawLine(label, value)
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
