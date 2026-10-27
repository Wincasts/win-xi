addon.name    = 'mobcast'
addon.author  = 'win'
addon.version = '0.4'
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
local winxiNeeded = 65 -- winxi.widgets' described rows
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
    newest = 'Bottom',
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

local function Check(name, sentence, setting, id)
    if widgets.Check(name, sentence, setting, id) then Save() end
end

local lockSpec = { onChanged = Save }
local fontSizeSpec = { description = 'How big the lines are. Theme Size follows the Winxi Theme.' }

local colorChanged = false -- a colour has been changed since it was last saved
local kindSentences = { } -- a kind of line -> the sentence of its colour's row
for _, kind in ipairs(shared.kinds) do
    kindSentences[kind.key] = ('The colour of the lines about %s.'):format(kind.label:lower())
end

local function DrawWindow(options)
    widgets.Lock(options.locked, '##mobcast.locked', lockSpec)
    if widgets.Numbers('Position', 'Where the top of the box is on the screen. Dragging the box sets it too.', options.pos, '##mobcast.position') then
        box.Move(options)
        Save()
    end
    local grow = widgets.Dropdown('Grow From', 'The side of the box that stays put as its lines change length.',
        box.Grows, options.grow, '##mobcast.grow')
    if grow ~= nil then
        options.grow = grow
        Save()
    end
    local _, done = widgets.FontSize(options, 'fontSize', '##mobcast.fontSize', fontSizeSpec)
    if done then Save() end
end

local function DrawEnemies(options)
    Check('Show Spells', 'Shows a spell an enemy begins casting, then whether it was cast or interrupted.',
        options.showSpells, '##mobcast.showSpells')
    Check('Show Weaponskills', 'Shows a weaponskill an enemy readies, then whether it was used or interrupted.',
        options.showSkills, '##mobcast.showSkills')
    Check('Show Abilities', 'Shows an ability an enemy uses.',
        options.showAbilities, '##mobcast.showAbilities')
    Check('Show Targets', 'Names who a spell or weaponskill is aimed at. Off, the lines say only what is coming.',
        options.showTargets, '##mobcast.showTargets')
    Check('Only My Target', 'Shows only what your target does. Off, every enemy near you.',
        options.onlyTarget, '##mobcast.onlyTarget')
end

local function DrawLines(options)
    local _, done = widgets.Slider('Duration', 'How long a line stays. A line said again starts its time over.',
        options.seconds, 1, 30, '##mobcast.seconds', widgets.Seconds)
    if done then Save() end
    _, done = widgets.Slider('Max Lines', 'How many lines the box holds at once. Past that, the oldest goes.',
        options.maxLines, 1, 10, '##mobcast.maxLines')
    if done then Save() end
    local newest = widgets.Dropdown('Newest Line', 'Where a new line goes, at the top or the bottom of the box.',
        box.Newests, options.newest, '##mobcast.newest')
    if newest ~= nil then
        options.newest = newest
        Save()
    end

    widgets.Gap()
    for _, kind in ipairs(shared.kinds) do
        if widgets.Color(kind.single .. ' Color', kindSentences[kind.key], options[kind.color], '##mobcast.' .. kind.color) then
            colorChanged = true
        end
    end
    -- a colour is saved once the mouse is up: the picker is a popup of its own, not the swatch
    if colorChanged and not imgui.IsMouseDown(0) then
        colorChanged = false
        Save()
    end

    widgets.Gap()
    if widgets.Action('Test', 'Says a line of each kind, as if an enemy had done it. /mobcast test does the same.', 'Test##mobcast.test') then
        box.Test()
    end
end

-- The shell gives a Visibility tab only to an addon with a window of its own; the box is drawn here,
-- so the tab is this addon's, laid out as the shell's is
local function DrawVisibility(options)
    if widgets.Header('Visibility', true) then
        Check('Fade In And Out', 'The box fades in as it appears and out as it goes.', options.fadeInOut, '##mobcast.fadeInOut')
        widgets.Gap()
        widgets.Hide(options.hide, Save)
    end
end

local function DrawSettings(options)
    -- the box is shown while the settings are, to put it where it is wanted
    box.sample = true
    if widgets.Header('Window', true) then
        DrawWindow(options)
    end
    if widgets.Header('Enemies') then
        DrawEnemies(options)
    end
    if widgets.Header('Lines') then
        DrawLines(options)
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
    local newests = false
    for _, newest in ipairs(box.Newests) do
        newests = newests or options.newest == newest
    end
    if not newests then options.newest = box.DefaultNewest end
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
    tabs = { { label = 'Visibility', draw = DrawVisibility } },
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
