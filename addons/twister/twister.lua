addon.name    = 'twister'
addon.author  = 'win (and claude)'
addon.version = '1.0'
addon.desc    = 'Plays a sound when something happens: a tell, an invite, a trade, being examined, an item you are after dropping, low HP and the like.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A sound for each of a few things worth hearing about. Each event has its own switch and its own
-- sound, any wav in the addon's sounds folder. It needs only winxi.
--
--   /twister           opens or closes the settings
--   /twister test      plays every event's sound in turn, to hear them
--
-- Beside the events there are triggers, which are experimental: a sound of your choosing when a mob
-- of a kind of your choosing begins a spell or a weaponskill of your choosing, or uses an ability,
-- in any area. They are made in the settings' Triggers tab, from what mobs.lua says each kind can do.
-- A trigger can be seen as well as heard: the indicator, a small window in the theme that says for a
-- few seconds what the mob does, as the chat log does.
--
-- What sets a sound off is read from packets (chat, invitations, trades, being examined, messages,
-- treasure, actions) and from the party's numbers as the game keeps them (TP, HP and MP), looked at
-- a few times a second.
--
-- Ashita plays one sound at a time, at the volume of the file: a sound cuts short the one before it.
-- So that one event's sound is not lost to another's, a sound asked for while one is playing waits
-- for it to finish.
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
local SoundCombo, Mark, ToLineEnd = controls.SoundCombo, controls.Mark, controls.ToLineEnd

local defaults = T{
    events = T{ },
    lowHpPercent = T{ 25 },
    lowMpPercent = T{ 20 },
    dropItems = T{ '' },
    triggers = T{ },
    showIndicator = T{ false },
    indicatorSeconds = T{ 5 },
    indicatorPos = T{ 100, 300 },
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
        enabled = ('##twister.%s.enabled'):format(event.key),
        sound = ('##twister.%s.sound'):format(event.key),
        test = ('Test##twister.%s.test'):format(event.key),
        threshold = ('##twister.%s.threshold'):format(event.key),
        items = ('##twister.%s.items'):format(event.key),
    }
end

local function DrawEvent(options, event)
    local chosen = options.events[event.key]
    local id = ids[event.key]

    widgets.Label(event.label)
    imgui.Checkbox(id.enabled, chosen.enabled)

    imgui.SameLine()
    SoundCombo(id.sound, chosen, event.key)

    imgui.SameLine()
    if imgui.Button(id.test) then
        Try(chosen.sound)
    end
    controls.EndLine()

    -- what sets the event off
    Mark(event.tooltip)

    -- the threshold only while the event is switched on: off, there is nothing for it to set
    if event.threshold ~= nil and chosen.enabled[1] then
        widgets.Label(event.thresholdLabel)
        imgui.SetNextItemWidth(ToLineEnd())
        imgui.SliderInt(id.threshold, options[event.threshold], 5, 90, '%d%%')
    end

    -- and so the names of the items listened for
    if event.items ~= nil and chosen.enabled[1] then
        widgets.Label('Items')
        imgui.SetNextItemWidth(ToLineEnd())
        imgui.InputText(id.items, options[event.items], 1024)
        if imgui.IsItemDeactivatedAfterEdit() then
            shared.app:Save()
        end
        Mark('Item names, separated by commas.\nex: Kindred\'s Seal, Beastmen\'s Seal')
    end
end

local function DrawSettings(options)
    local group = nil
    for _, event in ipairs(events) do
        if event.group ~= group then
            -- the first heads the tab: no blank line over it
            widgets.Header(event.group, group == nil)
            group = event.group
        end
        DrawEvent(options, event)
    end
end

-- Whatever saved settings lack, or have as the wrong kind of thing
local function Complete(options)
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

    Boxed(options, 'showIndicator', 'boolean', false)
    Boxed(options, 'indicatorSeconds', 'number', defaults.indicatorSeconds[1])
    if type(options.indicatorPos) ~= 'table' or type(options.indicatorPos[1]) ~= 'number' or type(options.indicatorPos[2]) ~= 'number' then
        options.indicatorPos = T{ defaults.indicatorPos[1], defaults.indicatorPos[2] }
    end

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
    configTitle = 'Twister Settings',
    command = '/twister',
    help = '/twister opens or closes the settings; /twister test plays every event\'s sound in turn.',
    drawSettings = DrawSettings,
    tabs = { { label = 'Triggers', draw = triggertab.Draw } },
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
ashita.events.register('packet_in', 'twister_packet_in', readers.Read)

ashita.events.register('d3d_present', 'twister_present', function()
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
