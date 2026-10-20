addon.name    = 'mobcast'
addon.author  = 'win'
addon.version = '0.1'
addon.desc    = 'Says in a small window what the enemies about you are casting, readying and using.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- A small window in the theme that says, for a few seconds each, what the enemies about you do: a
-- spell begun, finished or broken off, a weaponskill readied, done or broken off, an ability used.
-- The lines are the chat log's own words, each kind in a colour of its own, so that what is coming
-- can be seen where it is wanted rather than found in the log. It needs only winxi.
--
--   /mobcast           opens or closes the settings
--   /mobcast test      says a line of each kind, to see the box by
--
-- What is said is read from the action packets, as trigger reads them for its triggers; the box is
-- trigger's indicator, with a line that is replaced by what comes of it.

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 30
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
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local shell = require('winxi.shell')
local shared = require('shared')
local box = require('box')
local reader = require('reader')

local Boxed, Colored = shared.Boxed, shared.Colored

-- What each setting starts as. The numbers and colours are kept apart from the defaults table, which
-- Ashita may hand back as the settings themselves, for making good a saved setting that is not right.
local firstSeconds, firstLines = 6, 5
local firstPos = { 100, 300 }
local firstColors = {
    spellColor = { 0.60, 0.80, 1.00, 1.0 },
    skillColor = { 1.00, 0.65, 0.45, 1.0 },
    abilityColor = { 0.95, 0.90, 0.55, 1.0 },
}

local defaults = T{
    showSpells = T{ true },
    showSkills = T{ true },
    showAbilities = T{ true },
    showTargets = T{ true },
    onlyTarget = T{ false },
    seconds = T{ firstSeconds },
    maxLines = T{ firstLines },
    grow = 'Left',
    pos = T{ firstPos[1], firstPos[2] },
    locked = T{ false },
    fontSize = T{ 0 },
}
for key, color in pairs(firstColors) do
    defaults[key] = T{ color[1], color[2], color[3], color[4] }
end

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

local function Save()
    shared.app:Save()
end

local function Check(label, id, setting, tip)
    widgets.Label(label)
    if imgui.Checkbox(id, setting) then Save() end
    tooltip.Hover(tip)
end

local growIds = { } -- a side the box grows from -> its button's label
for _, grow in ipairs(box.Grows) do
    growIds[grow] = grow .. '##mobcast.grow'
end

local function DrawEnemies(options)
    Check('Show Spells', '##mobcast.showSpells', options.showSpells,
        'A spell an enemy begins, with whom it is cast on; the line becomes the spell cast, or the casting interrupted.')
    Check('Show Weaponskills', '##mobcast.showSkills', options.showSkills,
        'A weaponskill an enemy readies, with whom it is aimed at; the line becomes the weaponskill used, or interrupted.')
    Check('Show Abilities', '##mobcast.showAbilities', options.showAbilities,
        'An ability an enemy uses, which comes with no warning.')
    Check('Show Targets', '##mobcast.showTargets', options.showTargets,
        'Says whom a spell or weaponskill is aimed at, as the chat log does. Off, the lines say only what is coming.')
    Check('Only My Target', '##mobcast.onlyTarget', options.onlyTarget,
        'Only what the enemy you have targeted does. Off, every enemy about you.')
end

local function DrawBox(options)
    widgets.PushControlWidth()
    widgets.Label('Duration')
    imgui.SliderInt('##mobcast.seconds', options.seconds, 1, 30, '%d s')
    if imgui.IsItemDeactivatedAfterEdit() then Save() end
    tooltip.Hover('How long a line stays in the box, in seconds. A line said again starts its time over.')

    widgets.Label('Max Lines')
    imgui.SliderInt('##mobcast.maxLines', options.maxLines, 1, 10)
    if imgui.IsItemDeactivatedAfterEdit() then Save() end
    tooltip.Hover('How many lines the box holds at once. When there are more, the oldest goes.')
    widgets.PopControlWidth()

    widgets.Label('Grow From')
    for index, grow in ipairs(box.Grows) do
        if index > 1 then
            imgui.SameLine()
        end
        if imgui.RadioButton(growIds[grow], options.grow == grow) and options.grow ~= grow then
            options.grow = grow
            Save()
        end
    end
    tooltip.Hover('The side of the box that stays where it is as what it says gets longer or shorter. Its lines are set to that side too.')

    widgets.Lock(options.locked, '##mobcast.locked', { onChanged = Save })

    widgets.PushControlWidth()
    local _, done = widgets.FontSize(options, 'fontSize', '##mobcast.fontSize',
        { tooltip = 'How large the lines are, in pixels; Theme Size (0) follows Winxi Theme.' })
    if done then Save() end
    widgets.PopControlWidth()

    for _, kind in ipairs(shared.kinds) do
        widgets.Label(kind.single .. ' Color')
        imgui.ColorEdit4('##mobcast.' .. kind.color, options[kind.color], ImGuiColorEditFlags_NoInputs)
        if imgui.IsItemDeactivatedAfterEdit() then Save() end
        tooltip.Hover(('The colour of the lines about %s.'):format(kind.label:lower()))
    end

    widgets.Label('Test')
    if imgui.Button('Test##mobcast.test') then
        box.Test()
    end
    tooltip.Hover('Says a line of each kind, as if an enemy had done it. /mobcast test does the same.')
end

local function DrawVisibility(options)
    widgets.Label('Fade In And Out')
    if imgui.Checkbox('##mobcast.fadeInOut', options.fadeInOut) then Save() end
    tooltip.Hover('The box fades in as it appears and out as it goes.')
    widgets.Hide(options.hide, Save)
end

local function DrawSettings(options)
    -- the box is shown while the settings are, to put it where it is wanted
    box.sample = true
    if widgets.Header('Enemies', true) then
        DrawEnemies(options)
    end
    if widgets.Header('Box') then
        DrawBox(options)
    end
    if widgets.Header('Visibility') then
        DrawVisibility(options)
    end
end

-- Whatever saved settings lack, or have as the wrong kind of thing
local function Complete(options)
    -- Appearance is managed globally by winxisettings, including for older saved profiles.
    options.useSharedTheme = true
    Boxed(options, 'showSpells', 'boolean', true)
    Boxed(options, 'showSkills', 'boolean', true)
    Boxed(options, 'showAbilities', 'boolean', true)
    Boxed(options, 'showTargets', 'boolean', true)
    Boxed(options, 'onlyTarget', 'boolean', false)
    Boxed(options, 'seconds', 'number', firstSeconds)
    options.seconds[1] = math.max(1, math.min(30, math.floor(options.seconds[1])))
    Boxed(options, 'maxLines', 'number', firstLines)
    options.maxLines[1] = math.max(1, math.min(10, math.floor(options.maxLines[1])))
    Boxed(options, 'locked', 'boolean', false)
    Boxed(options, 'fontSize', 'number', 0)
    if type(options.pos) ~= 'table' or type(options.pos[1]) ~= 'number' or type(options.pos[2]) ~= 'number' then
        options.pos = T{ firstPos[1], firstPos[2] }
    end
    local grows = false
    for _, grow in ipairs(box.Grows) do
        grows = grows or options.grow == grow
    end
    if not grows then options.grow = box.DefaultGrow end
    for _, kind in ipairs(shared.kinds) do
        Colored(options, kind.color, firstColors[kind.color])
    end
    box.Reset()
end

shared.app = shell.New({
    defaults = defaults,
    configTitle = 'Mobcast Settings',
    command = '/mobcast',
    help = '/mobcast opens or closes the settings; /mobcast test says a line of each kind.',
    drawSettings = DrawSettings,
    hideAppearance = true,
    onSettings = Complete,
    commands = { test = box.Test },
})

---------------------------------------------------------------------------------------------------
-- What sets it all going
---------------------------------------------------------------------------------------------------

ashita.events.register('packet_in', 'mobcast_packet_in', reader.Read)

ashita.events.register('d3d_present', 'mobcast_present', function()
    local app = shared.app
    if not app:BeginFrame() then
        return
    end
    box.Frame(os.clock())
end)
