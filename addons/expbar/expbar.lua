addon.name = 'expbar'
addon.author = 'win'
addon.version = '0.3.0'
addon.desc = 'A basic experience bar with session XP and XP per hour.'
addon.link = 'https://github.com/Wincasts/win-xi'

-- The winxi this addon was made with, or a newer one (winxi.version)
local winxiNeeded = 66 -- shell's extra.pos and bars.Draw's texture
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
local imgui = require('imgui')
local shell = require('winxi.shell')
local widgets = require('winxi.widgets')
local text = require('winxi.text')
local bars = require('winxi.bars')
local theme = require('winxi.theme')
local tracker = require('tracker').New()
local commas = require('winxi.infopanel.exp').Commas
local app
local positionPending = false
local defaults = T{
    isVisible = T{ true }, pos = T{ 300, 300 },
    showRate = T{ true }, locked = T{ false }, width = T{ 300 },
    overlay = T{ false }, height = T{ 52 }, texture = '',
    barColor = T{ 0.42, 0.75, 0.95, 1 },
}
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD',
    'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' }
local transparent = { 0, 0, 0, 0 }

local function JobLabel(player)
    local label = ('%s%d'):format(jobs[player:GetMainJob()] or '???', player:GetMainJobLevel())
    local sub = player:GetSubJob()
    if sub and sub > 0 then
        label = label .. ('/%s%d'):format(jobs[sub] or '???', player:GetSubJobLevel())
    end
    return label
end

local function Player()
    local memory = AshitaCore:GetMemoryManager()
    local player, party = memory:GetPlayer(), memory:GetParty()
    if not player or not party then return nil end
    local id = party:GetMemberServerId(0)
    if not tracker:Identity(id, player:GetMainJob()) then return nil end
    if player:GetMainJobLevel() == 0 then return nil end
    return player, id
end

local function Reset()
    tracker:Reset()
    app:Say('XP session reset. The rate starts with your next XP gain.')
end

local function Draw(options)
    local player = Player()
    if not player then return end
    local current, needed = player:GetExpCurrent(), player:GetExpNeeded()
    local fill = needed > 0 and math.max(0, math.min(1, current / needed)) or 0
    local job = JobLabel(player)
    local values = ('XP %s / %s  (%.1f%%)'):format(commas(current), commas(needed), fill * 100)
    local session = 'Session: +' .. commas(tracker.total) .. ' XP'
    local rate = options.showRate[1] and (commas(tracker:Rate(os.clock())) .. ' XP/hr') or nil
    local line = session .. (rate and ('  |  ' .. rate) or '')
    local valuesWidth, valuesHeight = imgui.CalcTextSize(values)
    local jobWidth, jobHeight = imgui.CalcTextSize(job)
    local sessionWidth, sessionHeight = imgui.CalcTextSize(session)
    local rateWidth, rateHeight = 0, 0
    if rate then rateWidth, rateHeight = imgui.CalcTextSize(rate) end
    local width, height = options.width[1], 16
    local x, y = imgui.GetCursorScreenPos()
    local top = y
    if options.overlay[1] then
        -- Reserve room for the labels too, so none overlap or clip at large fonts.
        width = math.max(width, valuesWidth + 20, jobWidth,
            sessionWidth + (rate and (16 + rateWidth) or 0))
        height = math.max(options.height[1], valuesHeight + 12)
        y = top + jobHeight + 4
    else
        text.Outlined(job .. '  ' .. values)
        x, y = imgui.GetCursorScreenPos()
    end
    local list, color = imgui.GetWindowDrawList(), options.barColor
    if not bars.Draw(list, x, y, width, height, fill, color, options.texture ~= '' and options.texture or nil) then
        list:AddRectFilled({ x, y }, { x + width, y + height }, imgui.GetColorU32({ 0.15, 0.15, 0.18, 1 }), 3)
        if fill > 0 then
            list:AddRectFilled({ x, y }, { x + width * fill, y + height }, imgui.GetColorU32(color), 3)
        end
    end
    if options.overlay[1] then
        local color = theme.Get().TextColor
        text.Draw(list, x, top, color, job)
        text.Draw(list, x + (width - valuesWidth) / 2, y + (height - valuesHeight) / 2, color, values)
        local bottom = y + height + 4
        text.Draw(list, x, bottom, color, session)
        if rate then text.Draw(list, x + width - rateWidth, bottom, color, rate) end
        imgui.Dummy({ width, jobHeight + 4 + height + 4 + math.max(sessionHeight, rateHeight) })
    else
        imgui.Dummy({ width, height })
        text.Outlined(line)
    end
end

local function Settings(options)
    local position = { options.pos[1], options.pos[2] }
    if imgui.InputInt('Position X', position) then
        options.pos[1] = position[1]
        positionPending = true
        app:Save()
    end
    local vertical = { options.pos[2] }
    if imgui.InputInt('Position Y', vertical) then
        options.pos[2] = vertical[1]
        positionPending = true
        app:Save()
    end
    if imgui.Button('Reset position') then
        options.pos[1], options.pos[2] = 300, 300
        positionPending = true
        app:Save()
    end
    imgui.TextWrapped('Position is the top-left of the whole display, including outside labels. You can also drag it when unlocked.')
    local selected = 'Follow shared theme'
    for _, choice in ipairs(theme.BarTextures) do
        if options.texture == choice.key then selected = choice.label end
    end
    if imgui.BeginCombo('Bar texture', selected) then
        if imgui.Selectable('Follow shared theme', options.texture == '') then
            options.texture = ''; app:Save()
        end
        for _, choice in ipairs(theme.BarTextures) do
            if imgui.Selectable(choice.label, options.texture == choice.key) then
                options.texture = choice.key; app:Save()
            end
        end
        imgui.EndCombo()
    end
    if imgui.Checkbox('Overlay mode (XP inside bar)', options.overlay) then app:Save() end
    if imgui.Checkbox('Show XP/hour', options.showRate) then app:Save() end
    if imgui.SliderInt('Bar width', options.width, 180, 1200, '%d px') then app:Save() end
    if options.overlay[1] then
        if imgui.SliderInt('Overlay bar height', options.height, 40, 160, '%d px') then app:Save() end
        imgui.TextWrapped('The overlay grows as needed to fit its text. Lock it to make it click-through.')
    end
    if imgui.ColorEdit4('Bar colour', options.barColor, ImGuiColorEditFlags_NoInputs) then app:Save() end
    widgets.Lock(options.locked, '##expbar.locked', { onChanged = function() app:Save() end })
    if imgui.Button('Reset XP session') then Reset() end
    imgui.TextWrapped('Session rate starts at the first XP gain, includes idle time, and uses at least 60 seconds to avoid an inflated first-kill rate. Limit points are not counted.')
end

app = shell.New({
    defaults = defaults, window = 'expbar.window', configTitle = 'Experience Bar Settings',
    command = '/expbar', bareOpensConfig = true, drawSettings = Settings,
    help = '/expbar: settings; /expbar pos <x> <y>; /expbar mode window|overlay; /expbar toggle; /expbar show|hide; /expbar rate [on|off]; /expbar reset.',
    commands = {
        reset = Reset,
        pos = function(options, args)
            local x, y = tonumber(args[3]), tonumber(args[4])
            if not x or not y or x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge then
                app:Say('Usage: /expbar pos <x> <y>')
                return
            end
            options.pos[1], options.pos[2] = math.floor(x), math.floor(y)
            positionPending = true
            app:Save()
        end,
        mode = function(options, args)
            local value = args[3] and args[3]:lower()
            if value ~= 'window' and value ~= 'overlay' then
                app:Say('Usage: /expbar mode window|overlay')
                return
            end
            options.overlay[1] = value == 'overlay'
            app:Save()
        end,
        show = function(options) options.isVisible[1] = true; app:Save() end,
        hide = function(options) options.isVisible[1] = false; app:Save() end,
        rate = function(options, args)
            local value = args[3] and args[3]:lower()
            if value ~= nil and value ~= 'on' and value ~= 'off' then
                app:Say('Usage: /expbar rate [on|off]')
                return
            end
            if value then options.showRate[1] = value == 'on'
            else options.showRate[1] = not options.showRate[1] end
            app:Save()
        end,
    },
})

ashita.events.register('packet_in', 'expbar_packet', function(e)
    if e.id ~= 0x02D then return end
    local player, id = Player()
    if player then tracker:Packet(e.id, e.data, id, player:GetMainJob(), os.clock()) end
end)

ashita.events.register('d3d_present', 'expbar_present', function()
    -- Track identity even while the bar is hidden; hiding never pauses the session.
    local player = Player()
    if not app:BeginFrame() or not player then return end
    local options, look = app.options, app.windowStyle
    -- Remove all window chrome, not just ImGui's background. Restore the theme
    -- when switching back to window mode without touching the saved theme.
    look.background = options.overlay[1] and transparent or nil
    look.border = options.overlay[1] and transparent or nil
    look.padding = options.overlay[1] and 0 or nil
    if options.overlay[1] then look.shadow = false else look.shadow = nil end
    local drawn = app:Window(options.isVisible, Draw, {
        pos = positionPending and options.pos or nil,
        locked = options.locked[1], clickThrough = options.locked[1],
        flags = options.overlay[1] and ImGuiWindowFlags_NoBackground or nil,
    })
    if drawn then positionPending = false end
end)
