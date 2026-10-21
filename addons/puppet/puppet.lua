addon.name    = 'puppet'
addon.author  = 'win'
addon.version = '1.6'
addon.desc    = 'Everything an automaton might do next, in the order it tries them, with the timer on each: its spells, weapon skill, shot and what its attachments do, from the maneuvers up and what is on its target.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- A small window for a puppetmaster: the burden of each element as a figure in the element's colour,
-- which burden.lua reckons; under it the action the automaton will take next; then what the maneuvers
-- choose, in the order it tries them, with the timer on each (its spells with the next three enfeebles
-- named, the weapon skill); then the cooldowns running on what is not chosen (its shield bash, its shot,
-- what its attachments do when their maneuver is up), each there only while its timer runs. A thing
-- that answers to a maneuver has its name in the maneuver's colour. The choosing is predict.lua's, which follows the server's; this gathers what it
-- needs to know (the automaton's parts and skills, the maneuvers up, the debuffs on the target) and
-- shows the answer. With Transparent on the window has no backdrop, border or shadow, and every line is winxi's
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

-- What the window shows: the rows of the priority list, worked out from the spells in order and the
-- weapon skill (kept here too, for the dummy data). It is left as it was once the fight is over, for
-- the window to fade out with. burden is the figures, one for each element, or nil with no automaton out.
local showing = { enfeebles = nil, weaponskill = nil, weaponskillElement = nil, priority = { }, burden = nil }

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
-- the same colours by the elements' names, for the name of a thing that answers to a maneuver
local maneuverColors = { }
for element, name in ipairs(burden.Elements) do
    maneuverColors[name] = elementColors[element]
end
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
    showing.enfeebles = #names > 0 and names or nil

    showing.weaponskill, showing.weaponskillElement = predict.Weaponskill({
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
        enfeebles = showing.enfeebles,
        weaponskill = showing.weaponskill,
        weaponskillElement = showing.weaponskillElement,
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
-- every state a row can be in and a name in a maneuver's colour, and the figures every element's
-- colour, and one not known.
local dummy = { on = { false }, was = false }
dummy.priority = {
    { name = 'Bash', section = 'cooldown', element = 'earth', state = 'waiting', wait = 142 },
    { name = 'Heal', section = 'queue', element = 'light', state = 'idle', wait = 0 },
    { name = 'Enfeeble', section = 'queue', detail = { { name = 'Dia II', element = 'light' }, { name = 'Poison', element = 'water' }, { name = 'Silence', element = 'wind' } },
        state = 'ready', wait = 0, ready = true },
    { name = 'Nuke', section = 'queue', element = 'ice', state = 'waiting', wait = 12 },
    { name = 'Erase', section = 'queue', element = 'water', state = 'ready', wait = 0 },
    { name = 'WS', section = 'queue', detail = { name = 'Slapstick', element = 'thunder' }, state = 'idle', wait = 0 },
    { name = 'Shot', section = 'cooldown', element = 'wind', state = 'waiting', wait = 7 },
    { name = 'Provoke', section = 'cooldown', element = 'fire', state = 'waiting', wait = 24 },
    { name = 'Flash', section = 'cooldown', element = 'light', state = 'waiting', wait = 31 },
    { name = 'Stoneskin', section = 'cooldown', element = 'earth', state = 'idle', wait = 0 }, -- not shown: not running
}
dummy.burden = { }
for element, figure in ipairs({ { 0, 0 }, { 8, 0 }, { 22, 17 }, { 35, 24 }, { 51, 46 }, { 78, 73 }, { 100, 95 }, { nil } }) do
    dummy.burden[element] = { name = elementNames[element], figure = figure[1] and tostring(figure[1]) or '?',
        color = figure[1] and elementColors[element] or figureUnknown, chance = figure[2] }
end

local function ShowDummy()
    showing.enfeebles, showing.weaponskill, showing.weaponskillElement = { 'Dia II', 'Poison', 'Silence' }, 'Slapstick', 'thunder'
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
local widestLabel = 'Next Action:'
local labelWidth = 0 -- measured each frame, for the font may change

-- What a row would do, written in the maneuvers' colours: the weapon skill's name, or the spells one
-- after another with commas between; in the Next Action line the first spell alone
local comma = ', '
local function WriteDetail(detail, firstOnly)
    if detail == nil then
        return
    end
    if detail.name ~= nil then
        Write(detail.name, maneuverColors[detail.element])
        return
    end
    local count = firstOnly and math.min(1, #detail) or #detail
    for i = 1, count do
        local part = detail[i]
        if i > 1 then
            WriteFaint(comma)
            imgui.SameLine(0, 0)
        end
        Write(part.name, maneuverColors[part.element])
        if i < count then
            imgui.SameLine(0, 0)
        end
    end
end

-- The list, in three parts. First the action the automaton will take next: the row that comes first
-- with something to do and nothing to wait for, or, with nothing ready, the weapon skill it would use
-- once it has the TP. Then what the maneuvers choose (the spells, the weapon
-- skill), in the order it tries them, each the name, what it would do and the timer. Then, after a gap,
-- the cooldowns: what is not chosen but runs on a timer of its own (the bash, the shot, the attachments'
-- actions), each there only while its timer runs, with the seconds left. A name that answers to a
-- maneuver is in the maneuver's colour.
local sectionGap = { 0, 4 }
local function DrawPriority()
    if #showing.priority == 0 or not imgui.BeginTable('##puppet.priority', 3, tableFlags) then
        return
    end
    imgui.TableSetupColumn('', ImGuiTableColumnFlags_WidthFixed, labelWidth)

    local next, weaponskill = nil, nil
    for _, row in ipairs(showing.priority) do
        if row.ready then
            next = row
        end
        if row.name == 'WS' then
            weaponskill = row
        end
    end
    next = next or weaponskill
    imgui.TableNextRow()
    imgui.TableNextColumn(); WriteFaint('Next Action:')
    imgui.TableNextColumn()
    if next == nil then
        WriteFaint('-')
    else
        Write(next.name, maneuverColors[next.element])
        if next.detail ~= nil then
            imgui.SameLine()
            WriteDetail(next.detail, true)
        end
    end
    imgui.TableNextColumn()

    local function draw(row, state)
        imgui.TableNextRow()
        imgui.TableNextColumn(); Write(row.name, maneuverColors[row.element])
        imgui.TableNextColumn(); WriteDetail(row.detail)
        imgui.TableNextColumn(); WriteFaint(state)
    end
    for _, row in ipairs(showing.priority) do
        if row.section == 'queue' then
            local state = 'Ready'
            if row.state == 'waiting' then
                state = ('%ds'):format(math.ceil(row.wait))
            elseif row.state == 'idle' then
                state = '-'
            elseif row.ready then
                state = 'Next'
            end
            draw(row, state)
        end
    end
    -- the cooldowns running, after a gap when there is one
    local gapped = false
    for _, row in ipairs(showing.priority) do
        if row.section == 'cooldown' and row.state == 'waiting' then
            if not gapped then
                gapped = true
                imgui.TableNextRow()
                imgui.TableNextColumn(); imgui.Dummy(sectionGap)
            end
            draw(row, ('%ds'):format(math.ceil(row.wait)))
        end
    end
    imgui.EndTable()
end

-- The burden figures, one for each element in the elements' order, on one line centred in the window,
-- each in a slot as wide as the widest can be so that the line does not move about as they change, and
-- centred in its slot. Resting the mouse on one names its element and says the chance of one more
-- maneuver of it overloading.
local hovered = { } -- an element -> the words for it when hovered, as last made
local slotGap = 8 -- between one figure's slot and the next, in pixels

local function DrawBurden()
    local count = #showing.burden
    local slot = imgui.CalcTextSize('100')
    local width = count * slot + (count - 1) * slotGap
    local left = imgui.GetCursorPosX() + math.max(0, (imgui.GetContentRegionAvail() - width) / 2)
    for element, item in ipairs(showing.burden) do
        local figureWidth = imgui.CalcTextSize(item.figure)
        imgui.SetCursorPosX(left + (element - 1) * (slot + slotGap) + (slot - figureWidth) / 2)
        Write(item.figure, item.color)
        if element < count then
            imgui.SameLine(0, 0)
        end
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
    if options.showBurden[1] and showing.burden ~= nil then
        DrawBurden()
    end
    if options.showPriority[1] then
        DrawPriority()
    end
    -- the window is there with nothing to say while it is always shown: it is not left empty
    if #showing.priority == 0 and (showing.burden == nil or not options.showBurden[1]) then
        WriteFaint('Nothing to show.')
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
    tips.Hover('Next Action: what the automaton will do next. Under it, what the maneuvers choose, in the order it tries them: its spells (the next three enfeebles named) and WS (the weapon skill, named), each with its timer:\nReady, the seconds left, Next, or - when there is nothing for it to do.\nThen the cooldowns running on what is not chosen: Bash (shield bash), Shot (ranged attack) and what each attachment fitted does when its maneuver is up (Provoke for a Strobe, Flash for a Flashbulb, Stoneskin for a Shock Absorber, and so on), each there only while its timer runs.\nA name in a colour answers to the maneuver of that colour. A timer is only known once the automaton has been seen to act.');
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
        showing.enfeebles, showing.weaponskill, showing.weaponskillElement, showing.priority = nil, nil, nil, { }
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
        and (dummy.on[1] or options.alwaysShow[1] or (target ~= nil and #showing.priority > 0))
    app:Window(wanted, DrawWindow)
end)
