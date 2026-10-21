addon.name    = 'winxisettings'
addon.author  = 'win'
addon.version = '1.0'
addon.desc    = 'The look shared by every winxi addon, in one settings window of its own.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- winxi's appearance options and its layouts, in a window drawn with winxi itself. Five tabs:
--   Game Windows       the windows on the game screen: their colours, padding, drop shadow, font, and
--                      the styles (borders, backgrounds, frame titles, bars, bookends)
--   Icons              whether statuses have FFXIV's icons
--   Tooltips           every tooltip's colours, padding, size, width and delay, and whether they show
--   Settings Windows   the settings windows' own colours, padding and font, every addon's
--   Layouts            every addon's settings kept for each screen resolution (winxi.layouts)
-- Every change is to the shared theme, and so to every addon that follows it.
--
--   /winxi or /wxi   opens or closes the window

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
local shell = require('winxi.shell')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local layouts = require('winxi.layouts')

local function Say(text)
    print(('\30\68[%s]\30\01 %s'):format(addon.name, text))
end

-- The Layouts tab. The layouts kept are looked for again after one is saved or removed.
local kept = nil
local automatic = { true }
local removing = nil

local function DrawLayouts()
    kept = kept or layouts.List()
    local resolution = layouts.Resolution() or '?'
    widgets.BeginLabels('winxisettings.layouts')

    if widgets.Header('Layouts', true) then
        widgets.Label('Resolution')
        imgui.Text(resolution)
        tooltip.Hover('The size of the game\'s window now. A layout is kept under the resolution it is for.')

        widgets.Label('Switch With Resolution')
        automatic[1] = layouts.IsAutomatic()
        if imgui.Checkbox('##winxisettings.automatic', automatic) then
            layouts.SetAutomatic(automatic[1])
        end
        tooltip.Hover('On, starting the game at another resolution than last time keeps every addon\'s settings as the layout for the old one, then uses the layout kept for the new one, if there is one. winxisettings has to be loaded as the game starts (in scripts\\default.txt) for this.')

        local pending = layouts.Pending()
        if pending ~= nil then
            widgets.Label('Next Start')
            imgui.Text(pending)
            imgui.SameLine()
            if imgui.Button('Cancel##winxisettings.cancelPending') then
                layouts.CancelPending()
            end
            tooltip.Hover('This layout is used the next time the game starts, before a character logs in.')
        end

        widgets.Gap()
        if imgui.Button(('Save Layout for %s'):format(resolution)) and resolution ~= '?' then
            Say(('Kept %d settings files as the layout for %s.'):format(layouts.Save(resolution), resolution))
            kept = nil
        end
        tooltip.Hover('Keeps every addon\'s settings and the shared Winxi Theme as they are now as the layout for this resolution, in place of any kept before.')
    end

    if widgets.Header('Saved Layouts') then
        if #(kept or {}) == 0 then
            imgui.TextDisabled('None yet.')
        end
        for _, name in ipairs(kept or {}) do
            imgui.AlignTextToFramePadding()
            imgui.Text(name == resolution and (name .. ' (this resolution)') or name)
            imgui.SameLine()
            if imgui.Button('Use##winxisettings.use.' .. name) then
                if layouts.Use(name) == 'now' then
                    Say(('Using the layout for %s.'):format(name))
                else
                    Say(('The layout for %s is used the next time the game starts.'):format(name))
                end
            end
            tooltip.Hover('Puts this layout in place of every addon\'s settings. At the title screen or character select that is at once; with a character logged in, the next time the game starts, since each addon writes its settings back as it closes.')
            imgui.SameLine()
            if imgui.Button('Remove##winxisettings.remove.' .. name) then
                removing = name
                imgui.OpenPopup('Remove Layout?##winxisettings.remove')
            end
        end

        if imgui.BeginPopup('Remove Layout?##winxisettings.remove') then
            imgui.Text(('Remove the layout kept for %s?'):format(removing or '?'))
            imgui.Separator()
            if imgui.Button('Remove##winxisettings.remove.confirm') then
                if removing then layouts.Delete(removing) end
                removing, kept = nil, nil
                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button('Cancel##winxisettings.remove.cancel') then
                removing = nil
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end
    end
end

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
        { label = 'Layouts', draw = DrawLayouts },
    },
    hideAppearance = true,
})

-- loaded to be used: the window is open from the start
app.showConfig[1] = true

ashita.events.register('d3d_present', 'winxisettings_present', function()
    local said = layouts.Start()
    if said then
        Say(said)
    end
    app:BeginFrame()
end)
