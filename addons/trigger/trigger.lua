addon.name    = 'trigger'
addon.author  = 'win'
addon.version = '1.1-pre1'
addon.desc    = 'Plays a sound when something happens: a tell, an invite, a trade, being examined, an item you are after dropping, low HP and the like.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- A sound for each of a few things worth hearing about. Each event has its own switch and its own
-- sound, any wav in the addon's sounds folder. It needs only winxi.
--
--   /trigger           opens or closes the settings
--   /trigger test      plays every event's sound in turn, to hear them
--
-- Beside the events there are triggers, which are experimental: a sound of your choosing when a mob
-- of a kind of your choosing begins a spell or a weaponskill of your choosing, or uses an ability,
-- in any area. They are made in the settings' Triggers tab, from what the server's triggermobs set says each kind can do.
-- A trigger can be seen as well as heard: the indicator, a small window in the theme that says for a
-- few seconds what the mob does, as the chat log does.
--
-- What sets a sound off is read from packets (chat, invitations, trades, being examined, messages,
-- treasure, actions) and from the party's numbers as the game keeps them (TP, HP and MP), looked at
-- a few times a second.
--
-- Normally sounds wait for Ashita's single playback channel. The experimental Overlap Sounds
-- option uses up to eight independent Windows voices instead.

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 1
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
local playing = require('playing')
local mobdata = require('mobdata')
local triggers = require('triggers')
local readers = require('readers')
local vitals = require('vitals')
local indicator = require('indicator')
local controls = require('controls')
local triggertab = require('triggertab')

local events, Boxed = shared.events, shared.Boxed
local PlayFile, Try, Renamed = playing.PlayFile, playing.Try, playing.Renamed
local SoundRow = controls.SoundRow

local defaults = T{
    events = T{ },
    lowHpPercent = T{ 25 },
    lowMpPercent = T{ 20 },
    dropItems = T{ '' },
    volume = 'Medium',
    overlapSounds = T{ false },
    triggers = T{ },
    showIndicator = T{ false },
    indicatorSeconds = T{ 5 },
    indicatorPos = T{ 100, 300 },
    indicatorGrow = 'Left',
}
for _, event in ipairs(events) do
    defaults.events[event.key] = T{ enabled = T{ true }, sound = event.file }
end

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

local ids = { } -- the hidden labels of the controls: made once
for _, event in ipairs(events) do
    ids[event.key] = {
        enabled = ('##trigger.%s.enabled'):format(event.key),
        sound = ('##trigger.%s.sound'):format(event.key),
        test = ('Test##trigger.%s.test'):format(event.key),
        threshold = ('##trigger.%s.threshold'):format(event.key),
        items = ('##trigger.%s.items'):format(event.key),
    }
end

-- The rows under an event, which mean something while it is switched on: their specs take the
-- event's switch as their parent each draw
local soundSentence = 'The sound it plays. Test plays it now.'
local itemsSentence = 'The items to listen for, by name, with a comma between one and the next.'
local dependent = { }
local thresholdSpec = { format = '%d%%' }

local function DrawEvent(options, event)
    local chosen = options.events[event.key]
    local id = ids[event.key]

    -- what sets the event off
    if widgets.Check(event.label, event.sentence, chosen.enabled, id.enabled) then
        shared.app:Save()
    end

    dependent.parent, thresholdSpec.parent = chosen.enabled, chosen.enabled
    if SoundRow('Sound', soundSentence, id.sound, chosen, event.key, id.test, dependent) then
        Try(chosen.sound)
    end

    if event.threshold ~= nil then
        local _, done = widgets.Slider(event.thresholdLabel, event.thresholdSentence, options[event.threshold], 5, 90, id.threshold, thresholdSpec)
        if done then shared.app:Save() end
    end

    -- and so the names of the items listened for
    if event.items ~= nil then
        widgets.BeginRow('Items', itemsSentence, dependent)
        imgui.InputText(id.items, options[event.items], 1024)
        if imgui.IsItemDeactivatedAfterEdit() then
            shared.app:Save()
        end
        widgets.EndRow()
    end
end

local volumeLevels = { 'High', 'Medium', 'Low' }
local function DrawVolume(options)
    local chosen = widgets.Dropdown('Volume', 'How loud every sound is, tests and previews too. Medium is the sound as it was made.',
        volumeLevels, options.volume, '##trigger.volume')
    if chosen ~= nil then
        options.volume = chosen
        shared.app:Save()
    end
end

local overlapSpec = { experimental = true }

local function DrawSettings(options)
    local group, open = nil, true
    for _, event in ipairs(events) do
        if event.group ~= group then
            -- the first heads the tab: no blank line over it
            open = widgets.Header(event.group, group == nil)
            group = event.group
        end
        if open then
            DrawEvent(options, event)
        end
    end
    if not widgets.Header('Playback') then return end
    DrawVolume(options)
    if widgets.Check('Overlap Sounds', 'Plays up to eight sounds at once instead of one after another. Off, each waits for the one before it.',
        options.overlapSounds, '##trigger.overlap', overlapSpec) then
        shared.app:Save()
    end
end

-- Whatever saved settings lack, or have as the wrong kind of thing
local function Complete(options)
    -- Appearance is managed globally by winxisettings, including for older saved profiles.
    options.useSharedTheme = true
    if type(options.events) ~= 'table' then options.events = T{ } end
    for _, event in ipairs(events) do
        local chosen = options.events[event.key]
        if type(chosen) ~= 'table' then
            chosen = T{ }
            options.events[event.key] = chosen
        end
        Boxed(chosen, 'enabled', 'boolean', true)
        if type(chosen.sound) ~= 'string' or chosen.sound == '' then chosen.sound = event.file end
        chosen.sound = Renamed(chosen.sound)
        if event.threshold ~= nil then
            Boxed(options, event.threshold, 'number', defaults[event.threshold][1])
        end
        if event.items ~= nil then
            Boxed(options, event.items, 'string', '')
        end
    end

    if options.volume ~= 'High' and options.volume ~= 'Medium' and options.volume ~= 'Low' then
        options.volume = 'Medium'
    end
    Boxed(options, 'overlapSounds', 'boolean', false)
    Boxed(options, 'showIndicator', 'boolean', false)
    Boxed(options, 'indicatorSeconds', 'number', defaults.indicatorSeconds[1])
    if type(options.indicatorPos) ~= 'table' or type(options.indicatorPos[1]) ~= 'number' or type(options.indicatorPos[2]) ~= 'number' then
        options.indicatorPos = T{ defaults.indicatorPos[1], defaults.indicatorPos[2] }
    end
    local grows = false
    for _, grow in ipairs(indicator.Grows) do
        grows = grows or options.indicatorGrow == grow
    end
    if not grows then options.indicatorGrow = indicator.DefaultGrow end
    indicator.Reset()

    triggers.Complete(options)
end

-- The sounds of every event in turn, a second apart, whether switched on or not
local function TestAll()
    for index, event in ipairs(events) do
        local file = shared.app.options.events[event.key].sound
        ashita.tasks.once((index - 1) * 1.0, function()
            shared.app:Say(('%s: %s'):format(event.label, file))
            PlayFile(file)
        end)
    end
end

shared.app = shell.New({
    defaults = defaults,
    configTitle = 'Trigger Settings',
    command = '/trigger',
    help = '/trigger opens or closes the settings; /trigger test plays every event\'s sound in turn.',
    settingsLabel = 'Notifications',
    drawSettings = DrawSettings,
    hideAppearance = true,
    tabs = {
        { label = 'Triggers', draw = triggertab.Draw },
        { label = 'Toast', draw = triggertab.DrawToast },
    },
    onSettings = function(options)
        Complete(options)
        -- another character's numbers are not this one's
        vitals.Forget()
    end,
    commands = { test = TestAll },
})

---------------------------------------------------------------------------------------------------
-- What sets it all going
---------------------------------------------------------------------------------------------------

-- Every packet the game is sent
ashita.events.register('packet_in', 'trigger_packet_in', readers.Read)
ashita.events.register('unload', 'trigger_unload', playing.Stop)

ashita.events.register('d3d_present', 'trigger_present', function()
    local app = shared.app
    app:BeginFrame()
    local now = os.clock()
    vitals.Frame(now)
    -- what is known of the mobs is not kept: let go of once the settings are closed, and the frame after
    -- it was read to find out an area's mobs
    if mobdata.IsRead() and not app.showConfig[1] then
        mobdata.Forget()
    end
    playing.PlayWaiting(now)
    indicator.Frame(now)
end)
