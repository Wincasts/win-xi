addon.name    = 'puppet'
addon.author  = 'win'
addon.version = '1.2'
addon.desc    = 'The enfeebling spells and the weapon skill an automaton will use next, from the maneuvers up and what is on its target.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- A small window for a puppetmaster: the next three spells the automaton will enfeeble with, the
-- weapon skill it will use, and the order of everything it might do next with how each stands. The
-- choosing is predict.lua's, which follows the server's; this gathers what it needs to know (the
-- automaton's parts and skills, the maneuvers up, the debuffs on the target) and shows the answer.
-- Under those, the burden of each element as a figure in the element's colour, which burden.lua
-- reckons. With Transparent on the window has no backdrop, border or shadow, and every line is winxi's
-- outlined text, so that it reads over the game.
--
--   /puppet           shows or hides the window
--   /puppet config    opens or closes the settings

require('common')
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local tips = require('winxi.tooltip')
local shell = require('winxi.shell')
local theme = require('winxi.theme')
local outlined = require('winxi.text')
local debuffs = require('winxi.debuffs')
local packets = require('winxi.packets')
local predict = require('predict')
local tracker = require('tracker')
local burden = require('burden')

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
-- to fade out with. burden is the figures, one for each element, or nil with no automaton out.
local showing = { enfeebles = nil, weaponskill = nil, priority = { }, burden = nil }

-- The burden figures: one for each element, in the elements' order, each the burden in the element's
-- colour. The chance of one more maneuver of it overloading is told when the mouse rests on it.
local elementNames = { 'Fire', 'Ice', 'Wind', 'Earth', 'Thunder', 'Water', 'Light', 'Dark' }
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
local figureUnknown = { 1, 1, 1, 0.5 } -- a burden not known
local burdenFigures = { }
for element = 1, #burden.Elements do
    burdenFigures[element] = { name = elementNames[element], color = elementColors[element] }
end
local figures = { } -- a burden -> the words for it

local function WorkBurden()
    local state = BurdenState()
    for element, item in ipairs(burdenFigures) do
        local value = burden.Get(element, state)
        if value == nil then
            item.figure, item.color, item.chance = '?', figureUnknown, nil
        else
            value = math.floor(value + 0.5)
            figures[value] = figures[value] or tostring(value)
            item.figure, item.chance, item.color = figures[value], burden.Chance(element, state), elementColors[element]
        end
    end
    showing.burden = burdenFigures
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
        masterHpp = memory:GetParty():GetMemberHPPercent(0),
        hpp = pet.HPPercent,
        mpp = memory:GetPlayer():GetPetMPPercent(),
        since = tracker.Since,
        attachments = automaton.attachments,
    })
end

-- Dummy data, for seeing how the window looks with every part of it filled: switched on in the
-- settings, and not kept, so that it is off again the next time the addon is loaded. The rows show
-- every state a row can be in, and the figures every element's colour, and one not known.
local dummy = { on = { false }, was = false }
dummy.priority = {
    { name = 'Bash', state = 'waiting', wait = 142 },
    { name = 'Heal', state = 'idle', wait = 0 },
    { name = 'Enfeeble', state = 'ready', wait = 0, ready = true },
    { name = 'Nuke', state = 'waiting', wait = 12 },
    { name = 'Erase', state = 'ready', wait = 0 },
    { name = 'Shot', state = 'waiting', wait = 7 },
}
dummy.burden = { }
for element, figure in ipairs({ { 0, 0 }, { 8, 0 }, { 22, 17 }, { 35, 24 }, { 51, 46 }, { 78, 73 }, { 100, 95 }, { nil } }) do
    dummy.burden[element] = { name = elementNames[element], figure = figure[1] and tostring(figure[1]) or '?',
        color = figure[1] and elementColors[element] or figureUnknown, chance = figure[2] }
end

local function ShowDummy()
    showing.enfeebles, showing.weaponskill = 'Dia II, Poison, Silence', 'Slapstick'
    showing.priority, showing.burden = dummy.priority, dummy.burden
end

-- How the words are written: imgui's own text over the backdrop, or winxi's outlined text when the
-- window is transparent and they go straight over the game. The dimmed words are then the theme's text
-- colour at a little over half strength, as imgui dims them.
local transparent = false -- this frame
local faint = { 1, 1, 1, 0.6 }
local function Faint()
    local color = theme.Get().TextColor
    faint[1], faint[2], faint[3], faint[4] = color[1], color[2], color[3], color[4] * 0.6
    return faint
end
local function Write(words, color)
    if transparent then
        outlined.Outlined(words, color)
    elseif color ~= nil then
        imgui.TextColored(color, words)
    else
        imgui.Text(words)
    end
end
local function WriteFaint(words)
    if transparent then
        outlined.Outlined(words, Faint())
    else
        imgui.TextDisabled(words)
    end
end

-- The window's tables share one padding and one left edge: no outer padding, the same gap between
-- columns and rows, and the lines' and the list's first column as wide as the widest label, so that
-- what each row says lines up down the window
local tableFlags = bit.bor(ImGuiTableFlags_SizingFixedFit, ImGuiTableFlags_NoPadOuterX)
local cellPadding = { 6, 1 }
local widestLabel = '> Enfeeble'
local labelWidth = 0 -- measured each frame, for the font may change

-- The priority list: everything the automaton might do, in the order it tries them, and how each
-- stands: the name and the timer. The one it will do next is marked and in full colour; the rest are
-- dimmed.
local function DrawPriority()
    if #showing.priority == 0 or not imgui.BeginTable('##puppet.priority', 2, tableFlags) then
        return
    end
    imgui.TableSetupColumn('', ImGuiTableColumnFlags_WidthFixed, labelWidth)
    for _, row in ipairs(showing.priority) do
        local write = row.ready and Write or WriteFaint
        local state = 'Ready'
        if row.state == 'waiting' then
            state = ('%ds'):format(math.ceil(row.wait))
        elseif row.state == 'idle' then
            state = '-'
        elseif row.ready then
            state = 'Next'
        end
        imgui.TableNextRow()
        imgui.TableNextColumn(); write((row.ready and '> ' or '  ') .. row.name)
        imgui.TableNextColumn(); write(state)
    end
    imgui.EndTable()
end

-- The burden figures, one for each element in the elements' order, on one line, each as wide as the
-- widest can be so that the line does not move about as they change. Resting the mouse on one names
-- its element and says the chance of one more maneuver of it overloading.
local hovered = { } -- an element -> the words for it when hovered, as last made

local function DrawBurden()
    if not imgui.BeginTable('##puppet.burden', #showing.burden, tableFlags) then
        return
    end
    local figureWidth = imgui.CalcTextSize('100')
    for element = 1, #showing.burden do
        imgui.TableSetupColumn('', ImGuiTableColumnFlags_WidthFixed, figureWidth)
    end
    imgui.TableNextRow()
    for element, item in ipairs(showing.burden) do
        imgui.TableNextColumn()
        Write(item.figure, item.color)
        if imgui.IsItemHovered() then
            local words = hovered[element]
            if words == nil or words.figure ~= item.figure or words.chance ~= item.chance then
                words = { figure = item.figure, chance = item.chance }
                if item.chance == nil then
                    words.text = item.name .. ': not known yet. A maneuver of it says.'
                else
                    words.text = ('%s: burden %s, %d%% chance of overloading'):format(item.name, item.figure, item.chance)
                end
                hovered[element] = words
            end
            tips.Show(words.text)
        end
    end
    imgui.EndTable()
end

-- The two lines on top, the labels in one column and what they name in the other, so that the two
-- line up whatever the labels' widths
local function DrawLines()
    if (showing.enfeebles == nil and showing.weaponskill == nil) or not imgui.BeginTable('##puppet.lines', 2, tableFlags) then
        return
    end
    imgui.TableSetupColumn('', ImGuiTableColumnFlags_WidthFixed, labelWidth)
    for _, line in ipairs({ { 'Enfeeble', showing.enfeebles }, { 'WS', showing.weaponskill } }) do
        if line[2] ~= nil then
            imgui.TableNextRow()
            imgui.TableNextColumn(); WriteFaint(line[1])
            imgui.TableNextColumn(); Write(line[2])
        end
    end
    imgui.EndTable()
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
    labelWidth = imgui.CalcTextSize(widestLabel)
    imgui.PushStyleVar(ImGuiStyleVar_CellPadding, cellPadding)
    DrawLines()
    -- the window is there with nothing to name while it is always shown: it is not left empty
    if showing.enfeebles == nil and showing.weaponskill == nil then
        WriteFaint('Nothing to show.')
    end
    if options.showBurden[1] and showing.burden ~= nil then
        DrawBurden()
    end
    if options.showPriority[1] then
        DrawPriority()
    end
    imgui.PopStyleVar()
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
    showBurden = T{ true }, -- the burden of each element, as a figure in its colour
    transparent = T{ false }, -- no backdrop, border or shadow: outlined text straight over the game
    showDebug = T{ false }, -- under it, what the addon knows: for finding out what is wrong
}

local function DrawSettings(options)
    widgets.Label('Visible')
    imgui.Checkbox('##puppet.visible', options.isVisible)
    tips.Hover('Whether the window shows at all. /puppet switches this.');
    widgets.Label('Position')
    if imgui.InputInt2('##puppet.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos)
    end

    widgets.Gap()
    widgets.Label('Transparent')
    imgui.Checkbox('##puppet.transparent', options.transparent)
    tips.Hover('On, the window has no backdrop, border or shadow: its words are written straight over the game, with the theme\'s dark edge (Text Outline) round them so that they read.\nOff, it is a window of the theme\'s like any other.');
    widgets.Label('Always Show')
    imgui.Checkbox('##puppet.alwaysShow', options.alwaysShow)
    tips.Hover('On, the window is there whether the automaton is fighting or not: outside a fight it shows what the automaton would open with.\nOff, it is there only while the automaton is fighting, and fades out afterwards.');
    widgets.Label('Show Priority List')
    imgui.Checkbox('##puppet.showPriority', options.showPriority)
    tips.Hover('Everything the automaton might do next, in the order it tries them: Bash (shield bash), its spells, Shot (ranged attack), each with its timer.\nA row says Ready, the seconds left of its timer, or - when there is nothing for it to do. The one marked > comes next.\nThe weapon skill is not a row: it is named on top, and comes whenever the automaton has the TP.\nA timer is only known once the automaton has been seen to act.');
    widgets.Label('Show Burden')
    imgui.Checkbox('##puppet.showBurden', options.showBurden)
    tips.Hover('The burden of each element as a figure in its colour, in one line: fire, ice, wind, earth, thunder, water, light, dark.\nA ? is an element not known of yet: the automaton was out before the addon was loaded. A maneuver of it says.\nResting the mouse on a figure names its element and gives the chance of one more maneuver of it overloading.');
    widgets.Label('Show Dummy Data')
    imgui.Checkbox('##puppet.showDummy', dummy.on)
    tips.Hover('For seeing how the window looks: every part of it filled with made-up data, whether there is an automaton out or not.\nThe parts switched off above stay off. It is not kept: it is off again when the addon is next loaded.');
    widgets.Label('Show Debug Information')
    imgui.Checkbox('##puppet.showDebug', options.showDebug)
    tips.Hover('For finding out what is wrong: what the addon knows, under the window\'s own lines.\nThe automaton as the server described it, whether it is out and what it is fighting,\nhow many of the pet\'s packets have come, and the maneuvers up.');
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
        if type(options.transparent) ~= 'table' then
            options.transparent = T{ false }
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
local clear = { 0, 0, 0, 0 } -- no backdrop and no border, for a transparent window

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

    -- transparent: nothing of the window's own is drawn, and the words are written outlined over the game
    transparent = options.transparent[1] and true or false
    local windowStyle = app.windowStyle
    if transparent then
        windowStyle.background, windowStyle.border, windowStyle.shadow = clear, clear, false
    else
        windowStyle.background, windowStyle.border, windowStyle.shadow = nil, nil, nil
    end

    wanted[1] = options.isVisible[1]
        and (dummy.on[1] or options.alwaysShow[1] or (target ~= nil and (showing.enfeebles ~= nil or showing.weaponskill ~= nil)))
    app:Window(wanted, DrawWindow)
end)
