addon.name    = 'puppet'
addon.author  = 'win (and claude)'
addon.version = '1.0'
addon.desc    = 'The enfeebling spells and the weapon skill an automaton will use next, from the maneuvers up and what is on its target.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A small window for a puppetmaster: the next three spells the automaton will enfeeble with, the
-- weapon skill it will use, and the order of everything it might do next with how each stands. The choosing is predict.lua's, which follows the server's; this gathers
-- what it needs to know (the automaton's parts and skills, the maneuvers up, the debuffs on the
-- target) and shows the answer. Under those, a small bar for the burden of each element, which
-- burden.lua reckons.
--
--   /puppet           shows or hides the window
--   /puppet config    opens or closes the settings

require('common')
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local shell = require('winxi.shell')
local debuffs = require('winxi.debuffs')
local packets = require('winxi.packets')
local predict = require('predict')
local tracker = require('tracker')
local burden = require('burden')
local bars = require('bars')

local windowName = 'winxi.puppet'

local jobPup = 18
local extendedJobPacket = 0x044
local petSyncPacket = 0x068
local zonePacket = 0x00A
local enfeeblesShown = 3
local statusOverdrive = 166

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
local automaton = { head = nil, frame = nil, magic = nil, melee = nil, ranged = nil, attachments = { }, overdrive = false }
local automatonKeys = { 'head', 'frame', 'melee', 'ranged', 'magic' }
local attachmentSlots = 12

local function ReadAutomaton(e)
    if struct.unpack('B', e.data, 0x04 + 1) ~= jobPup then
        return
    end
    automaton.head = struct.unpack('B', e.data, 0x08 + 1)
    automaton.frame = struct.unpack('B', e.data, 0x09 + 1)
    automaton.melee = struct.unpack('H', e.data, 0x70 + 1)
    automaton.ranged = struct.unpack('H', e.data, 0x74 + 1)
    automaton.magic = struct.unpack('H', e.data, 0x78 + 1)

    -- the attachments fitted, by the server's number for each; kept as a list
    automaton.attachments = { }
    local fitted = T{ }
    for slot = 0, attachmentSlots - 1 do
        local attachment = struct.unpack('B', e.data, 0x0A + slot + 1)
        if attachment ~= 0 then
            automaton.attachments[attachment] = true
            fitted[#fitted + 1] = attachment
        end
    end

    local kept = app.options.automaton
    local changed = table.concat(fitted, ',') ~= table.concat(type(kept.attachments) == 'table' and kept.attachments or { }, ',')
    kept.attachments = fitted
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
local syncs = { seen = 0, own = 0, last = nil } -- for the debug information: how many of those packets have come

local function ReadPetSync(e)
    syncs.seen = syncs.seen + 1
    if struct.unpack('I', e.data, 0x08 + 1) ~= AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) then
        return
    end
    fighting = struct.unpack('I', e.data, 0x14 + 1)
    syncs.own, syncs.last = syncs.own + 1, os.clock()
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

-- The automaton as burden.lua takes it: its frame and attachments, and whether Overdrive is up
local function BurdenState()
    automaton.overdrive = false
    for _, status in pairs(AshitaCore:GetMemoryManager():GetPlayer():GetBuffs() or {}) do
        if status == statusOverdrive then
            automaton.overdrive = true
        end
    end
    return automaton
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
-- name, and the rows of the priority list. It is left as it was once the fight is over, for the window
-- to fade out with. burden is the bars, as bars.lua takes them, or nil with no automaton out.
local showing = { enfeebles = nil, weaponskill = nil, priority = { }, burden = nil }

-- The burden bars: one for each element, in its colour. A bar is full at fullBurden; the figure over
-- it is the burden, in the colour of what one more maneuver of that element would risk.
local fullBurden = 100
local riskHigh = 25 -- a chance in a hundred of overloading from which the figure is red
local elementColors = {
    { 1.00, 0.54, 0.48, 1 }, -- fire
    { 0.65, 0.89, 1.00, 1 }, -- ice
    { 0.66, 0.94, 0.63, 1 }, -- wind
    { 0.91, 0.82, 0.48, 1 }, -- earth
    { 0.85, 0.65, 1.00, 1 }, -- thunder
    { 0.56, 0.71, 1.00, 1 }, -- water
    { 1.00, 1.00, 1.00, 1 }, -- light
    { 0.60, 0.56, 0.72, 1 }, -- dark
}
local figureSafe = { 1, 1, 1, 1 }          -- one more maneuver cannot overload
local figureRisk = { 0.95, 0.95, 0.49, 1 } -- it might
local figureHigh = { 0.99, 0.51, 0.51, 1 } -- it is likely to
local figureUnknown = { 1, 1, 1, 0.5 }
local burdenBars = { }
for element = 1, #burden.Elements do
    burdenBars[element] = { color = elementColors[element] }
end
local figures = { } -- a burden -> the words for it

local function WorkBurden()
    local state = BurdenState()
    for element, item in ipairs(burdenBars) do
        local value = burden.Get(element, state)
        if value == nil then
            item.fraction, item.figure, item.figureColor = 0, '?', figureUnknown
        else
            value = math.floor(value + 0.5)
            local chance = burden.Chance(element, state)
            figures[value] = figures[value] or tostring(value)
            item.fraction, item.figure = value / fullBurden, figures[value]
            item.figureColor = (chance >= riskHigh and figureHigh) or (chance > 0 and figureRisk) or figureSafe
        end
    end
    showing.burden = burdenBars
end

local function Work(pet, id)
    local maneuvers = CountManeuvers()

    local queue = predict.Queue({
        head = automaton.head,
        frame = automaton.frame,
        skill = automaton.magic,
        maneuvers = maneuvers,
        -- with no enemy yet, the spells are those for one with nothing on it
        has = function(kind) return id ~= nil and debuffs.Get(id, kind) ~= nil end,
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

    local memory = AshitaCore:GetMemoryManager()
    showing.priority = predict.Priority({
        head = automaton.head,
        frame = automaton.frame,
        maneuvers = maneuvers,
        enfeeble = queue[1],
        weaponskill = showing.weaponskill,
        masterHpp = memory:GetParty():GetMemberHPPercent(0),
        hpp = pet.HPPercent,
        mpp = memory:GetPlayer():GetPetMPPercent(),
        tp = memory:GetPlayer():GetPetTP(),
        since = tracker.Since,
        attachments = automaton.attachments,
    })
end

-- Dummy data, for seeing how the window looks with every part of it filled: switched on in the
-- settings, and not kept, so that it is off again the next time the addon is loaded. The rows show
-- every state a row can be in, and the bars every colour a figure can be, and one not known.
local dummy = { on = { false }, was = false }
dummy.priority = {
    { name = 'Shield Bash', detail = 'when the enemy casts', state = 'waiting', wait = 142 },
    { name = 'Heal', detail = 'you at 40%', state = 'idle', wait = 0 },
    { name = 'Enfeeble', detail = 'Dia II', state = 'ready', wait = 0, ready = true },
    { name = 'Nuke', detail = '', state = 'waiting', wait = 12 },
    { name = 'Status Removal', detail = 'if you have an ailment', state = 'ready', wait = 0 },
    { name = 'Weaponskill', detail = 'Slapstick (TP 640)', state = 'idle', wait = 0 },
    { name = 'Ranged Attack', detail = '', state = 'waiting', wait = 7 },
}
dummy.burden = { }
for element, bar in ipairs({
    { 0, figureSafe }, { 8, figureSafe }, { 22, figureRisk }, { 35, figureRisk },
    { 51, figureHigh }, { 78, figureHigh }, { 100, figureHigh }, { nil, figureUnknown },
}) do
    dummy.burden[element] = { color = elementColors[element], fraction = (bar[1] or 0) / fullBurden,
        figure = bar[1] and tostring(bar[1]) or '?', figureColor = bar[2] }
end

local function ShowDummy()
    showing.enfeebles, showing.weaponskill = 'Dia II, Poison, Silence', 'Slapstick'
    showing.priority, showing.burden = dummy.priority, dummy.burden
end

-- The priority list: everything the automaton might do, in the order it tries them, and how each
-- stands. The one it will do next is marked and in full colour; the rest are dimmed.
local function DrawPriority()
    if #showing.priority == 0 or not imgui.BeginTable('##puppet.priority', 3) then
        return
    end
    for _, row in ipairs(showing.priority) do
        local text = row.ready and imgui.Text or imgui.TextDisabled
        local state = 'Ready'
        if row.state == 'waiting' then
            state = ('%ds'):format(math.ceil(row.wait))
        elseif row.state == 'idle' then
            state = '-'
        elseif row.ready then
            state = 'Next'
        end
        imgui.TableNextRow()
        imgui.TableNextColumn(); text((row.ready and '> ' or '  ') .. row.name)
        imgui.TableNextColumn(); text(row.detail)
        imgui.TableNextColumn(); text(state)
    end
    imgui.EndTable()
end

local function DrawLine(label, value)
    if value == nil then
        return
    end
    imgui.TextDisabled(label)
    imgui.SameLine()
    imgui.Text(value)
end

-- What the addon knows, shown as the debug information: why the window says what it does, or nothing
local known = { pet = false, maneuvers = '' }

local function DrawKnown()
    imgui.Separator()
    if automaton.head == nil then
        imgui.TextDisabled('Automaton: not described yet')
    else
        imgui.TextDisabled(('Automaton: head %d, frame %d, melee %d, ranged %d, magic %d'):format(
            automaton.head, automaton.frame or -1, automaton.melee or -1, automaton.ranged or -1, automaton.magic or -1))
    end
    imgui.TextDisabled(('Pet out: %s   Fighting: %s'):format(known.pet and 'yes' or 'no', fighting ~= 0 and tostring(fighting) or 'nothing'))
    imgui.TextDisabled(('Pet packets: %d seen, %d mine, last %s'):format(
        syncs.seen, syncs.own, syncs.last and ('%.0fs ago'):format(os.clock() - syncs.last) or 'never'))
    imgui.TextDisabled('Maneuvers: ' .. (known.maneuvers ~= '' and known.maneuvers or 'none'))
end

local function DrawWindow(options)
    DrawLine('Next Enfeeble:', showing.enfeebles)
    DrawLine('Next Weaponskill:', showing.weaponskill)
    -- the window is there with nothing to name while it is always shown: it is not left empty
    if showing.enfeebles == nil and showing.weaponskill == nil then
        imgui.TextDisabled('Nothing to show.')
    end
    if options.showBurden[1] and showing.burden ~= nil then
        bars.Draw(showing.burden, #showing.burden)
    end
    if options.showPriority[1] then
        DrawPriority()
    end
    if options.showDebug[1] then
        DrawKnown()
    end
end

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    automaton = T{ }, -- the automaton as last described: see ReadAutomaton
    alwaysShow = T{ true }, -- the window whether the automaton is fighting or not
    showPriority = T{ true }, -- everything the automaton might do next, in its order, and how each stands
    showBurden = T{ true }, -- a small bar for the burden of each element
    showDebug = T{ false }, -- under it, what the addon knows: for finding out what is wrong
}

local function DrawSettings(options)
    widgets.Label('Visible')
    imgui.Checkbox('##puppet.visible', options.isVisible)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows at all. /puppet switches this.')
    end
    widgets.Label('Position')
    if imgui.InputInt2('##puppet.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos)
    end

    widgets.Gap()
    widgets.Label('Always Show')
    imgui.Checkbox('##puppet.alwaysShow', options.alwaysShow)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('On, the window is there whether the automaton is fighting or not: outside a fight it shows what the automaton would open with.\nOff, it is there only while the automaton is fighting, and fades out afterwards.')
    end
    widgets.Label('Show Priority List')
    imgui.Checkbox('##puppet.showPriority', options.showPriority)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Everything the automaton might do next, in the order it tries them: shield bash, its spells, weapon skill, ranged attack.\nEach shows what it is waiting on: Ready, the seconds left of a timer, or - when there is nothing for it to do. The one marked > comes next.\nA timer is only known once the automaton has been seen to act.')
    end
    widgets.Label('Show Burden')
    imgui.Checkbox('##puppet.showBurden', options.showBurden)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('A small bar for the burden of each element: fire, ice, wind and earth, then thunder, water, light and dark.\nThe figure is the burden. It is yellow when one more maneuver of that element might overload, and red when it is likely to.\nA ? is an element not known of yet: the automaton was out before the addon was loaded. A maneuver of it says.')
    end
    widgets.Label('Show Dummy Data')
    imgui.Checkbox('##puppet.showDummy', dummy.on)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('For seeing how the window looks: every part of it filled with made-up data, whether there is an automaton out or not.\nThe parts switched off above stay off. It is not kept: it is off again when the addon is next loaded.')
    end
    widgets.Label('Show Debug Information')
    imgui.Checkbox('##puppet.showDebug', options.showDebug)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('For finding out what is wrong: what the addon knows, under the window\'s own lines.\nThe automaton as the server described it, whether it is out and what it is fighting,\nhow many of the pet\'s packets have come, and the maneuvers up.')
    end
end

app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Puppet Settings',
    command = '/puppet',
    help = '/puppet shows or hides the window; /puppet config opens or closes the settings.',
    drawSettings = DrawSettings,
    -- with Always Show off the window is only there in a fight, and the command would seem to do nothing
    toggleSays = {
        shown = 'The window is on.',
        hidden = 'The window is off. /puppet turns it back on.',
    },
    onSettings = function(options)
        -- the automaton as it was when last described, this character's
        if type(options.automaton) ~= 'table' then
            options.automaton = T{ }
        end
        if type(options.alwaysShow) ~= 'table' then
            options.alwaysShow = T{ true }
        end
        if type(options.showDebug) ~= 'table' then
            options.showDebug = T{ false }
        end
        if type(options.showPriority) ~= 'table' then
            options.showPriority = T{ true }
        end
        if type(options.showBurden) ~= 'table' then
            options.showBurden = T{ true }
        end
        burden.Clear()
        automaton.attachments = { }
        if type(options.automaton.attachments) == 'table' then
            for _, attachment in ipairs(options.automaton.attachments) do
                automaton.attachments[attachment] = true
            end
        end
        tracker.Clear()
        for _, key in ipairs(automatonKeys) do
            automaton[key] = type(options.automaton[key]) == 'number' and options.automaton[key] or nil
        end
        fighting = 0
    end,
})

-- The automaton's id, as last seen: its timers are another automaton's no longer
local petId = nil
-- An automaton brought into an area is a new one to the server, with a new one's burden: the next to
-- be seen after a change of area is taken for that
local newArea = false

ashita.events.register('packet_in', 'puppet_packet_in', function(e)
    -- an action is parsed once, for the debuffs it leaves and for what the automaton did
    if e.id == packets.inbound.action.id then
        local action = packets.inbound.action.parse(e.data_raw)
        debuffs.Action(action)
        tracker.Action(action, petId)
        if action.actor_id == AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) then
            burden.Action(action, BurdenState())
        end
        return
    end

    debuffs.HandlePacket(e)
    if e.id == extendedJobPacket then
        ReadAutomaton(e)
    elseif e.id == petSyncPacket then
        ReadPetSync(e)
    elseif e.id == zonePacket then
        fighting = 0
        tracker.Clear()
        burden.Clear()
        newArea = true
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
    local options = app.options
    local pet = GetAutomaton()
    local id = pet ~= nil and pet.ServerId or nil
    if id ~= petId then
        petId = id
        tracker.Clear()
        if id ~= nil and newArea then
            burden.Spawned()
            newArea = false
        end
    end
    if pet ~= nil and options.showBurden[1] then
        WorkBurden()
    else
        showing.burden = nil
    end
    -- the dummy data goes over whatever was worked out, and is cleared away when it is switched off
    if dummy.on[1] then
        ShowDummy()
    elseif dummy.was then
        showing.enfeebles, showing.weaponskill, showing.priority = nil, nil, { }
        if target ~= nil or (pet ~= nil and options.alwaysShow[1]) then
            Work(pet, target)
        end
    end
    dummy.was = dummy.on[1]
    local target = GetTarget(pet)
    -- outside a fight, with the window always shown, it says what the automaton would open with
    if target ~= nil or (pet ~= nil and options.alwaysShow[1]) then
        Work(pet, target)
    end

    if options.showDebug[1] then
        known.pet = pet ~= nil
        local parts = {}
        for element, count in pairs(CountManeuvers()) do
            parts[#parts + 1] = element .. ' ' .. count
        end
        table.sort(parts)
        known.maneuvers = table.concat(parts, ', ')
    end

    wanted[1] = options.isVisible[1]
        and (dummy.on[1] or options.alwaysShow[1] or (target ~= nil and (showing.enfeebles ~= nil or showing.weaponskill ~= nil)))
    app:Window(wanted, DrawWindow)
end)
