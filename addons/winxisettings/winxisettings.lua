addon.name    = 'winxisettings'
addon.author  = 'win (and claude)'
addon.version = '1.0'
addon.desc    = 'The look shared by every winxi addon, in one settings window of its own.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- winxi's appearance options and nothing else, in a window drawn with winxi itself. Four tabs:
--   Game Windows       the windows on the game screen: their colours, padding, drop shadow, font, and
--                      the styles (borders, backgrounds, frame titles, bars, bookends)
--   Icons              whether statuses have FFXIV's icons
--   Tooltips           every tooltip's colours, padding, size, width and delay, and whether they show
--   Settings Windows   the settings windows' own colours, padding and font, every addon's
-- Every change is to the shared theme, and so to every addon that follows it.
--
--   /winxi or /wxi   opens or closes the window

require('common')
local shell = require('winxi.shell')
local widgets = require('winxi.widgets')

local app = shell.New({
    defaults = T{ },
    configTitle = 'winxi Appearance',
    command = '/winxi',
    aliases = { '/wxi' },
    help = '/winxi or /wxi opens or closes the window.',
    settingsLabel = 'Game Windows',
    -- no hooks: no Use Shared Theme checkbox, the shared theme is what this addon is for
    drawSettings = function() widgets.Appearance(nil, { icons = false }) end,
    tabs = {
        { label = 'Icons', draw = function() widgets.IconAppearance() end },
        { label = 'Tooltips', draw = function() widgets.TooltipAppearance() end },
        { label = 'Settings Windows', draw = function() widgets.SettingsAppearance() end },
    },
    hideAppearance = true,
})

-- loaded to be used: the window is open from the start
app.showConfig[1] = true

ashita.events.register('d3d_present', 'winxisettings_present', function()
    app:BeginFrame()
end)
