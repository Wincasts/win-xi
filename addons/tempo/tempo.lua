addon.name    = 'tempo'
addon.author  = 'win'
addon.version = '0.1'
addon.desc    = 'Bars for when your next auto attack comes and when your next resting tick lands.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- A small window in the theme with two bars: one fills to your next auto attack while you fight, the
-- other to your next resting tick while you /heal, with about what it will restore and about when
-- your HP and MP are full. A basic take on Kipling's cadence: its server rules, without its gear
-- tables, enemy timers or TP. It only reads: what the server sends, and what the game holds.
--
--   /tempo           opens or closes the settings
--   /tempo toggle    shows or hides the window

local winxiNeeded = 41
do
    local ok, found = pcall(require, 'winxi.version')
    local number = ok and type(found) == 'table' and found.Number or 0
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number)
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text))
        error(text, 0)
    end
end

require('common')
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local shell = require('winxi.shell')
local text = require('winxi.text')
local theme = require('winxi.theme')
local swing = require('swing')
local rest = require('rest')

local firstColors = {
    attackColor = { 0.95, 0.72, 0.30, 1.0 },
    restColor = { 0.42, 0.80, 0.55, 1.0 },
}

local defaults = T{
    isVisible = T{ true },
    showAttack = T{ true },
    showRest = T{ true },
    showFull = T{ true },
    barWidth = T{ 220 },
    locked = T{ false },
    pos = T{ 300, 400 },
}
for key, color in pairs(firstColors) do
    defaults[key] = T{ color[1], color[2], color[3], color[4] }
end

local app

---------------------------------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------------------------------

local statusEngaged, statusResting = 1, 33

-- What stops your attacks, and what the bar says for it (cadence's list): sleep, petrification,
-- stun, Sleep II, terror, penalty and Lullaby
local stoppedBy = { { 2, 'Asleep' }, { 7, 'Petrified' }, { 10, 'Stunned' }, { 19, 'Asleep' }, { 28, 'Terror' },
    { 159, 'Penalty' }, { 193, 'Asleep' } }

-- 0x029 messages for a round that cannot happen
local cantAttack = { [4] = 'Too Far', [5] = 'Not Facing' }
-- the first result of a spell finish with no spell: a weapon skill out of range, or paralysis and
-- intimidation (of a round or of an ability)
local weaponskillTooFar, paralyzed = 78, { [84] = true, [106] = true }

local function Memory()
    return AshitaCore:GetMemoryManager()
end

local function Buffs()
    local found = {}
    local buffs = Memory():GetPlayer():GetBuffs()
    if buffs == nil then return found end
    for index = 0, 32 do
        local id = buffs[index]
        if id ~= nil and id > 0 and id ~= 255 then found[id] = true end
    end
    return found
end

-- A weapon in a slot (0 main, 1 sub), as swing.Estimate wants it, or nil
local function Weapon(slot)
    local inventory = Memory():GetInventory()
    local equipped = inventory:GetEquippedItem(slot)
    if equipped == nil or equipped.Index == 0 then return nil end
    local item = inventory:GetContainerItem(bit.rshift(equipped.Index, 8), bit.band(equipped.Index, 0xFF))
    if item == nil or item.Id == 0 or item.Id == 65535 then return nil end
    local info = AshitaCore:GetResourceManager():GetItemById(item.Id)
    if info == nil or (info.Delay or 0) == 0 then return nil end
    return { id = item.Id, delay = info.Delay, skill = info.Skill }
end

local function Loadout()
    local player = Memory():GetPlayer()
    return {
        main = Weapon(0), sub = Weapon(1), buffs = Buffs(),
        mainJob = player:GetMainJob(), mainLevel = player:GetMainJobLevel(),
        subJob = player:GetSubJob(), subLevel = player:GetSubJobLevel(),
    }
end

local function Delay()
    local loadout = Loadout()
    return swing.Estimate(loadout), swing.Key(loadout)
end

local function Vitals()
    local party, player = Memory():GetParty(), Memory():GetPlayer()
    return party:GetMemberHP(0), party:GetMemberMP(0), player:GetHPMax(), player:GetMPMax()
end

local lastStatus, buffsAt, myId = nil, 0, nil

local function Track(now)
    local entity = GetPlayerEntity()
    if entity == nil then return end
    local status = entity.Status

    if status ~= lastStatus then
        if status == statusEngaged then
            local estimate, key = Delay()
            -- with no status seen yet, the fight began before tempo was there
            swing.Engage(now, estimate, key, lastStatus == nil)
        elseif lastStatus == statusEngaged then
            swing.Disengage()
        end
        if status == statusResting then
            local hp, mp, hpMax, mpMax = Vitals()
            rest.Start(now, hp, mp, hpMax, mpMax, lastStatus == nil)
        elseif lastStatus == statusResting then
            rest.Stop()
        end
        lastStatus = status
    end

    if rest.IsActive() then
        rest.Frame(now, Vitals())
    end

    -- sleep and the like, five times a second, while fighting
    if swing.IsActive() and now - buffsAt >= 0.2 then
        buffsAt = now
        local buffs, why = Buffs(), nil
        for _, stop in ipairs(stoppedBy) do
            if buffs[stop[1]] then
                why = stop[2]
                break
            end
        end
        swing.Stopped(now, why)
    end
end

---------------------------------------------------------------------------------------------------
-- Packets
---------------------------------------------------------------------------------------------------

local Bits = ashita.bits.unpack_be
-- the action packet: who at bit 40, the kind at 82, what at 86, the first result's message at 230
local actionActor, actionCategory, actionWhat, actionFirstMessage = 40, 82, 86, 230
local castBegin, castBroken = 0x6163, 0x7073 -- 'ca' and 'sp', the low 16 bits of what a start is
local castKinds = { [8] = 'spell', [9] = 'item', [12] = 'ranged' }

local function OnAction(e, now)
    local raw = e.data_raw or e.data
    if raw == nil or #e.data < 32 then return end
    if Bits(raw, actionActor, 32) ~= myId then return end
    local category = Bits(raw, actionCategory, 4)
    local what = Bits(raw, actionWhat, 16)

    if category == 1 then
        swing.Round(now, Delay())
    elseif category == 3 or category == 6 then
        swing.Ability(now)
    elseif castKinds[category] ~= nil then
        if what == castBegin then
            swing.CastBegin(now, castKinds[category])
        elseif what == castBroken then
            swing.CastEnd(now)
        end
    elseif category == 4 and what == 0 then
        local message = Bits(raw, actionFirstMessage, 10)
        if message == weaponskillTooFar then
            swing.Ability(now)
        elseif paralyzed[message] then
            swing.Paralyzed(now)
        end
    elseif category == 4 or category == 5 or category == 2 then
        swing.CastEnd(now)
    end
end

ashita.events.register('packet_in', 'tempo_packet_in', function(e)
    local now = os.clock()
    if e.id == 0x00A then
        swing.Reset()
        rest.Stop()
        lastStatus = nil
        local id = #e.data >= 8 and struct.unpack('L', e.data, 0x04 + 1) or nil
        if id ~= nil and myId ~= nil and id ~= myId then swing.Forget() end
        myId = id or myId
        return
    end
    myId = myId or Memory():GetParty():GetMemberServerId(0)
    if e.id == 0x028 then
        OnAction(e, now)
    elseif e.id == 0x029 and #e.data >= 26 then
        local actor = struct.unpack('L', e.data, 0x04 + 1)
        local message = struct.unpack('H', e.data, 0x18 + 1)
        if actor == myId and cantAttack[message] then
            swing.OutOfReach(cantAttack[message])
        end
    end
end)

---------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------

local barBack = { 0, 0, 0, 0.45 }
local from, to = { 0, 0 }, { 0, 0 }
local room = { 0, 0 }

-- A bar the window's width, filled so far, with words at its left and right in the theme's outline
local function Bar(fill, left, right, color)
    local options = app.options
    local width = options.barWidth[1]
    local height = imgui.GetFontSize() + 6
    local x, y = imgui.GetCursorScreenPos()
    local list = imgui.GetWindowDrawList()
    from[1], from[2], to[1], to[2] = x, y, x + width, y + height
    list:AddRectFilled(from, to, imgui.GetColorU32(barBack), 3)
    fill = math.max(0, math.min(1, fill or 0))
    if fill > 0 then
        to[1] = x + width * fill
        list:AddRectFilled(from, to, imgui.GetColorU32(color), 3)
    end
    local words = theme.Get().TextColor
    text.Draw(list, x + 5, y + 3, words, left)
    if right ~= nil then
        text.Draw(list, x + width - 5 - imgui.CalcTextSize(right), y + 3, words, right)
    end
    room[1], room[2] = width, height
    imgui.Dummy(room)
end

local function Clock(seconds)
    if seconds >= 60 then
        return ('%d:%02d'):format(math.floor(seconds / 60), math.floor(seconds % 60))
    end
    return ('%.0fs'):format(seconds)
end

-- What each bar showed last, kept for the window to fade out with; and what it shows with the
-- settings open and nothing going on, to see it by
local shownAttack, shownRest = { }, { }
local sampleAttack = { fill = 0.6, left = 1.24, delay = 3.1, learned = true }
local sampleRest = { fill = 0.35, left = 6.2, hp = 14, mp = 16, full = 47 }

local function DrawAttack(options, now, sample, fading)
    local s = shownAttack
    local fill, left, delay, learned, why = swing.Progress(now)
    if fill ~= nil then
        s.fill, s.left, s.delay, s.learned, s.why = fill, left, delay, learned, why
    elseif sample then
        s = sampleAttack
    elseif not fading or s.fill == nil then
        s.fill = nil
        return
    end
    local label = ('Attack  %s%.2fs'):format(s.learned and '' or '~', s.delay)
    local right = s.why or (s.left == nil and '...') or (s.left <= 0 and 'Ready') or ('%.1f'):format(s.left)
    Bar(s.fill, label, right, options.attackColor)
end

local function DrawRest(options, now, sample, fading)
    local s = shownRest
    local fill, left, hp, mp, full = rest.Progress(now)
    if fill ~= nil then
        s.fill, s.left, s.hp, s.mp, s.full = fill, left, hp, mp, full
    elseif sample then
        s = sampleRest
    elseif not fading or s.fill == nil then
        s.fill = nil
        return
    end
    local label = (s.hp == nil and 'Resting') or (s.mp ~= nil and ('+%d HP  +%d MP'):format(s.hp, s.mp)) or ('+%d HP'):format(s.hp)
    Bar(s.fill, label, s.left and ('%.1f'):format(s.left) or '...', options.restColor)
    if options.showFull[1] and s.full ~= nil then
        text.Outlined(s.full <= 0 and 'Full' or ('Full in ~%s'):format(Clock(s.full)))
    end
end

-- the window is wanted while it has something to show, or the settings are open
local wanted = { false }
local windowExtra = { }

local function Draw(options)
    local now, sample, fading = os.clock(), app.showConfig[1], not wanted[1]
    if options.showAttack[1] then DrawAttack(options, now, sample, fading) end
    if options.showRest[1] then DrawRest(options, now, sample, fading) end
end

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

local function Save()
    app:Save()
end

local function Check(label, id, setting, tip)
    widgets.Label(label)
    if imgui.Checkbox(id, setting) then Save() end
    tooltip.Hover(tip)
end

local function DrawSettings(options)
    if widgets.Header('Timers', true) then
        Check('Show Attack Timer', '##tempo.showAttack', options.showAttack,
            'While you fight, a bar that fills to your next auto attack. The delay is worked out from your weapons, job traits and haste, marked ~ until three of your own rounds have shown the real one.')
        Check('Show Resting Ticks', '##tempo.showRest', options.showRest,
            'While you /heal, a bar that fills to your next resting tick, with about what it restores. Ticks land every 9, 9 and 12 seconds; the first restores nothing.')
        Check('Show Time To Full', '##tempo.showFull', options.showFull,
            'Under the resting bar, about how long until your HP and MP are full.')
    end
    if widgets.Header('Window') then
        widgets.PushControlWidth()
        widgets.Label('Bar Width')
        imgui.SliderInt('##tempo.barWidth', options.barWidth, 120, 400, '%d px')
        if imgui.IsItemDeactivatedAfterEdit() then Save() end
        tooltip.Hover('How wide the bars are, in pixels.')
        widgets.PopControlWidth()
        widgets.Label('Attack Color')
        imgui.ColorEdit4('##tempo.attackColor', options.attackColor, ImGuiColorEditFlags_NoInputs)
        if imgui.IsItemDeactivatedAfterEdit() then Save() end
        tooltip.Hover('The colour the attack bar fills with.')
        widgets.Label('Rest Color')
        imgui.ColorEdit4('##tempo.restColor', options.restColor, ImGuiColorEditFlags_NoInputs)
        if imgui.IsItemDeactivatedAfterEdit() then Save() end
        tooltip.Hover('The colour the resting bar fills with.')
        widgets.Lock(options.locked, '##tempo.locked', { onChanged = Save })
    end
end

local function Boxed(options, key, kind, default)
    if type(options[key]) ~= 'table' or type(options[key][1]) ~= kind then
        options[key] = T{ default }
    end
end

-- Whatever saved settings lack, or have as the wrong kind of thing
local function Complete(options)
    options.useSharedTheme = true
    Boxed(options, 'isVisible', 'boolean', true)
    Boxed(options, 'showAttack', 'boolean', true)
    Boxed(options, 'showRest', 'boolean', true)
    Boxed(options, 'showFull', 'boolean', true)
    Boxed(options, 'locked', 'boolean', false)
    Boxed(options, 'barWidth', 'number', 220)
    options.barWidth[1] = math.max(120, math.min(400, math.floor(options.barWidth[1])))
    if type(options.pos) ~= 'table' or type(options.pos[1]) ~= 'number' or type(options.pos[2]) ~= 'number' then
        options.pos = T{ 300, 400 }
    end
    for key, default in pairs(firstColors) do
        local color = options[key]
        if type(color) ~= 'table' then
            color = T{ }
            options[key] = color
        end
        for index = 1, 4 do
            local part = tonumber(color[index])
            if part == nil or part < 0 or part > 1 then color[index] = default[index] end
        end
    end
end

app = shell.New({
    defaults = defaults,
    window = 'tempo.window',
    configTitle = 'Tempo Settings',
    command = '/tempo',
    bareOpensConfig = true,
    help = '/tempo opens or closes the settings; /tempo toggle shows or hides the window.',
    toggleSays = { shown = 'The window will show while you fight or rest.', hidden = 'The window is hidden.' },
    drawSettings = DrawSettings,
    hideAppearance = true,
    onSettings = Complete,
})

ashita.events.register('d3d_present', 'tempo_present', function()
    local now = os.clock()
    Track(now)
    if not app:BeginFrame() then return end
    local options = app.options
    local active = (options.showAttack[1] and swing.IsActive()) or (options.showRest[1] and rest.IsActive())
    wanted[1] = options.isVisible[1] and (active or app.showConfig[1]) and true or false
    windowExtra.locked = options.locked[1] or nil
    windowExtra.clickThrough = windowExtra.locked
    app:Window(wanted, Draw, windowExtra)
end)
