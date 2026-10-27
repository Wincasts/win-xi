addon.name    = 'winxisettings'
addon.author  = 'win'
addon.version = '1.2'
addon.desc    = 'The look shared by every winxi addon, in one settings window of its own.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- winxi's appearance options, its layouts and whose game data it reads, in a window drawn with winxi
-- itself. Six tabs:
--   Game Windows       the windows on the game screen: their colours, padding, drop shadow, font, and
--                      the styles (borders, backgrounds, frame titles, bars, bookends)
--   Icons              whether statuses have FFXIV's icons
--   Tooltips           every tooltip's colours, padding, size, width and delay, and whether they show
--   Settings Windows   the settings windows' own colours, padding and font, every addon's
--   Layouts            every addon's settings kept for each screen resolution (winxi.layouts)
--   Server Data        which server's data every winxi addon reads (winxi.gamedata's datasets), and what
--                      it was made from
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
local layouts = require('winxi.layouts')
local gamedata = require('winxi.gamedata')

local function Say(text)
    print(('\30\68[%s]\30\01 %s'):format(addon.name, text))
end

-- The Layouts tab. The layouts kept are looked for again after one is saved or removed.
local kept = nil
local automatic = { true }
local removing = nil

local saveSentences = {} -- resolution -> the Save Layout row's sentence
local rowIds = {} -- a layout's name -> its buttons' labels

local function DrawLayouts()
    kept = kept or layouts.List()
    local resolution = layouts.Resolution() or '?'
    widgets.BeginLabels('winxisettings.layouts')

    if widgets.Header('Layouts', true) then
        widgets.BeginRow('Resolution', 'The size of the game window now. Each layout is kept for one resolution.')
        imgui.AlignTextToFramePadding()
        imgui.Text(resolution)
        widgets.EndRow()

        automatic[1] = layouts.IsAutomatic()
        if widgets.Check('Switch With Resolution', 'Starting the game at another resolution loads the layout kept for it, if there is one.', automatic, '##winxisettings.automatic') then
            layouts.SetAutomatic(automatic[1])
        end

        local pending = layouts.Pending()
        if pending ~= nil then
            widgets.BeginRow('Next Start', 'Uses this layout the next time the game starts, before a character logs in.')
            imgui.AlignTextToFramePadding()
            imgui.Text(pending)
            imgui.SameLine()
            if imgui.Button('Cancel##winxisettings.cancelPending') then
                layouts.CancelPending()
            end
            widgets.EndRow()
        end

        widgets.Gap()
        local sentence = saveSentences[resolution]
        if sentence == nil then
            sentence = ('Saves every addon\'s settings and the Winxi Theme as they are now, as the layout for %s.'):format(resolution)
            saveSentences[resolution] = sentence
        end
        if widgets.Action('Save Layout', sentence, 'Save Layout##winxisettings.save') and resolution ~= '?' then
            Say(('Kept %d settings files as the layout for %s.'):format(layouts.Save(resolution), resolution))
            kept = nil
        end
    end

    if widgets.Header('Saved Layouts') then
        if #(kept or {}) == 0 then
            widgets.Note('None yet.')
        end
        for _, name in ipairs(kept or {}) do
            local ids = rowIds[name]
            if ids == nil then
                ids = { name .. ' (this resolution)', 'Use##winxisettings.use.' .. name, 'Remove##winxisettings.remove.' .. name }
                rowIds[name] = ids
            end
            widgets.BeginRow(name == resolution and ids[1] or name, nil)
            if imgui.Button(ids[2]) then
                if layouts.Use(name) == 'now' then
                    Say(('Using the layout for %s.'):format(name))
                else
                    Say(('The layout for %s is used the next time the game starts.'):format(name))
                end
            end
            imgui.SameLine()
            if imgui.Button(ids[3]) then
                removing = name
                imgui.OpenPopup('Remove Layout?##winxisettings.remove')
            end
            widgets.EndRow()
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

-- The Server Data tab: the servers there is data for, the one every addon reads, and what it was made from
local function DrawServerData()
    widgets.BeginLabels('winxisettings.server')
    if widgets.Header('Server Data', true) then
        local choices = {}
        for _, dataset in ipairs(gamedata.Datasets()) do
            choices[#choices + 1] = { key = dataset.Key, label = dataset.Name or dataset.Key }
        end
        if #choices == 0 then
            widgets.BeginRow('Server', 'There is no server data installed: install winxi with an addon that comes with it.')
            imgui.TextDisabled('None')
            widgets.EndRow()
        else
            local chosen = widgets.Dropdown('Server', 'Whose data every winxi addon reads: its monsters, spells, statuses and rules, as that server has them.',
                choices, gamedata.Dataset(), '##winxisettings.dataset')
            if chosen ~= nil and chosen ~= gamedata.Dataset() and gamedata.UseDataset(chosen) then
                Say(('Every winxi addon now reads %s\'s data.'):format(chosen))
            end
            local made = gamedata.Manifest().Source or {}
            widgets.BeginRow('Made From', 'The server\'s source the data was made from, and when.')
            imgui.AlignTextToFramePadding()
            imgui.Text(('%s %s %s'):format(made.Branch or '?', (made.Commit or '?'):sub(1, 9), (made.Committed or ''):sub(1, 10)))
            widgets.EndRow()
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
        { label = 'Server Data', draw = DrawServerData },
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
