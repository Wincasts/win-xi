-- config: the settings window. Its first tab is the addon's behaviour and its last is when the windows
-- hide and how they fade (winxi's rows for both); those between are drawn from the lists of entries in
-- options.lua, one tab a list.
--
--     config.Draw(saved)         the window, if it is open; saves the settings when it is closed
--     config.Toggle(saved)       opens or closes it
--     config.Tabs                every tab, in order: { name, draw }, draw taking the settings
--
-- Every setting is a described row (winxi 65): its name, a sentence under the name saying what it
-- does, and its control at the right (winxi.widgets). An entry's sentence is its own; a setting that
-- means nothing while another is off (entry.under, or Show Statuses for the status settings) is greyed
-- under it.
require('common')
local imgui = require('imgui')
local settings = require('settings')
local widgets = require('winxi.widgets')
local window = require('winxi.window')
local organize = require('winxi.organize')
local options = require('options')
local windows = require('windows')
local nativePlacement = require('nativeposition')
local statuspicker = require('statuspicker')

local config = { }

local function Save()
    settings.save()
end

-- The controls of the kinds of entry. Each control's hidden label is made once, and kept on the entry.
local box = { 0 }             -- a number on its way in and out of a slider

local function Id(entry, suffix)
    local ids = entry.ids
    if ids == nil then
        ids = { }
        entry.ids = ids
    end
    local id = ids[suffix or 1]
    if id == nil then
        id = ('##xiframes.%s.%s%s'):format(entry.section, entry.key, suffix or '')
        ids[suffix or 1] = id
    end
    return id
end

-- An entry's row spec, made once and kept on the entry: its format, and whether it is greyed (parent, a
-- box set each draw from entry.under, and from Show Statuses for a status setting)
local function Spec(entry, saved)
    local spec = entry.spec
    if spec == nil then
        spec = { format = entry.format, experimental = entry.experimental }
        if entry.displayDivisor then
            spec.float, spec.format = true, '%.2f m'
        elseif entry.kind == 'font' then
            spec.label, spec.description = entry.label, entry.sentence
        elseif entry.kind == 'place' then
            spec.indent = false -- held by Automatic Positioning, on another tab: greyed, not indented
        end
        entry.spec = spec
    end
    if entry.under ~= nil or entry.statuses then
        local gate = entry.gate
        if gate == nil then
            gate = { true }
            entry.gate = gate
        end
        gate[1] = (entry.under == nil or entry.under(saved)) and (not entry.statuses or saved.style.showStatuses[1]) and true or false
        spec.parent = gate
    end
    return spec
end

-- Puts a control of the given width against the right edge of the row's control column, as the
-- library's own rows do
local function AtRight(width)
    local column = imgui.CalcItemWidth ~= nil and imgui.CalcItemWidth() or nil
    if type(column) == 'number' and type(width) == 'number' and column > width then
        imgui.SetCursorPosX((imgui.GetCursorPosX() or 0) + column - width)
    end
end

local function FrameHeight()
    if imgui.GetFrameHeight ~= nil then
        local height = imgui.GetFrameHeight()
        if type(height) == 'number' then return height end
    end
    local style = imgui.GetStyle()
    local _, text = imgui.CalcTextSize('A')
    return (text or 14) + 2 * ((style and style.FramePadding and style.FramePadding.y) or 2)
end

local controls = { }

function controls.text(entry, value, section, saved, spec)
    widgets.BeginRow(entry.label, entry.sentence, spec)
    imgui.InputText(Id(entry), value, 8192)
    widgets.EndRow()
end

function controls.statuslist(entry, value, section, saved, spec)
    widgets.BeginRow(entry.label, entry.sentence, spec)
    statuspicker.Draw(entry.key, value, entry.ordered)
    widgets.EndRow()
end

function controls.check(entry, value, section, saved, spec)
    widgets.Check(entry.label, entry.sentence, value, Id(entry), spec)
end

function controls.slider(entry, value, section, saved, spec)
    if entry.displayDivisor then
        -- Preserve centimeter storage while exposing meters, including the existing 20.79m default.
        local divisor = entry.displayDivisor
        box[1] = value[1] / divisor
        if widgets.Slider(entry.label, entry.sentence, box, entry.min / divisor, entry.max / divisor, Id(entry), spec) then
            value[1] = math.max(entry.min, math.min(entry.max, math.floor(box[1] * divisor + 0.5)))
        end
    else
        widgets.Slider(entry.label, entry.sentence, value, entry.min, entry.max, Id(entry), spec)
    end
end

-- two sliders, across and down, a row each
local axisNames = { 'X', 'Y' }
function controls.offset(entry, value, section, saved, spec)
    local names = entry.axisLabels
    if names == nil then
        names = { entry.label .. ' X', entry.label .. ' Y' }
        entry.axisLabels = names
    end
    for axis = 1, 2 do
        box[1] = tonumber(value[axis]) or 0
        -- reach: how far either way, or { across, down } where the two differ
        local reach = type(entry.reach) == 'table' and entry.reach[axis] or entry.reach
        if widgets.Slider(names[axis], entry.sentences[axis], box, -reach, reach, Id(entry, axisNames[axis]), spec) then
            value[axis] = box[1]
        end
    end
end

-- a colour, its swatch opening the picker, with no alpha to set
local colorFlags = nil
function controls.color(entry, value, section, saved, spec)
    colorFlags = colorFlags or (ImGuiColorEditFlags_NoInputs + ImGuiColorEditFlags_NoAlpha)
    widgets.BeginRow(entry.label, entry.sentence, spec)
    AtRight(FrameHeight())
    imgui.ColorEdit4(Id(entry), value, colorFlags)
    widgets.EndRow()
end

-- one of several: a dropdown, the first chosen when none is. Display labels, but keep the existing
-- string keys in saved settings.
function controls.choice(entry, value, section, saved, spec)
    local chosen = widgets.Dropdown(entry.label, entry.sentence, entry.choices, value, Id(entry), spec)
    if chosen ~= nil then
        section[entry.key] = chosen
    end
end
controls.dropdown = controls.choice

-- a font of C:\Windows\Fonts, or '' for the theme's
function controls.font(entry, value, section, saved, spec)
    widgets.FontFile(section, entry.key, Id(entry), spec)
end

-- where a window is: typed in, the window goes there, and stays there if it was held by a corner.
-- A window placed for it (Automatic Positioning) has its place shown greyed.
local disabledPosition = { 0, 0 }
local placeHeld = { false }
local placeSentences = { default = 'Where the game default puts it.', managed = 'Placed by Automatic Positioning, on the Behavior tab.' }
function controls.place(entry, value, section, saved, spec)
    local defaultManaged = nativePlacement.Enabled(saved, entry.window)
    local managed = defaultManaged or (saved.automaticPositioning[1] and not nativePlacement.ManualOverride(saved, entry.window)
        and entry.window ~= 'sub' and entry.window ~= 'tot')
    -- greyed while it is placed for it, a plain row otherwise
    spec.parent = managed and placeHeld or nil
    if managed then
        -- a copy as well as the greying, so neither missing bindings nor test stubs can edit it
        disabledPosition[1], disabledPosition[2] = value[1], value[2]
        widgets.Numbers(entry.label, defaultManaged and placeSentences.default or placeSentences.managed, disabledPosition, Id(entry), spec)
    elseif widgets.Numbers(entry.label, entry.sentence, value, Id(entry), spec) then
        local which = windows.List[entry.window]
        imgui.SetWindowPos(which.name, value)
        windows.ForgetCorner(which)
    end
end

-- The status numbers typed in by hand, under Advanced: Status IDs
local statusIdsSpec = { parent = { true } }
local function DrawStatusIds(saved)
    statusIdsSpec.parent[1] = saved.style.showStatuses[1] and true or false
    widgets.BeginRow('Priority Status IDs', 'The numbers of the statuses shown first, in this order, separated by commas.', statusIdsSpec)
    imgui.InputText('##party.priorityStatusIds', saved.style.priorityStatuses, 8192)
    widgets.EndRow()
    widgets.BeginRow('Hidden Status IDs', 'The numbers of the statuses never shown, separated by commas. These win over the priority list.', statusIdsSpec)
    imgui.InputText('##party.hiddenStatusIds', saved.style.hiddenStatuses, 8192)
    widgets.EndRow()
end

local function DrawEntries(tab, saved)
    widgets.BeginLabels(tab.labels)
    local open, first = true, true
    for _, entry in ipairs(tab.entries) do
        if entry.kind == 'header' then
            open = widgets.Header(entry.label, first, entry.defaultCollapsed)
            first = false
            if open and tab.name == 'Style' and entry.label == 'Advanced: Status IDs' then
                DrawStatusIds(saved)
            end
        elseif entry.kind == 'gap' then
            if open then widgets.Gap() end
        elseif open and (entry.when == nil or entry.when(saved)) then
            local section = saved[entry.section]
            controls[entry.kind](entry, section[entry.key], section, saved, Spec(entry, saved))
        end
    end
end

-- [uihook 1.60 found], in green after the uihook section's title: the plugin's name and version,
-- remade only when either changes
local foundColor = { 0.4, 0.9, 0.4, 1.0 }
local foundName, foundVersion, foundText = nil, nil, nil
local function Found(manager, name)
    local version = nil
    local ok, plugin = pcall(manager.Get, manager, name)
    if ok and plugin ~= nil then
        local got, number = pcall(plugin.GetVersion, plugin)
        version = got and tonumber(number) or nil
    end
    if name ~= foundName or version ~= foundVersion then
        foundName, foundVersion = name, version
        foundText = version and ('[%s %.2f found]'):format(name, version) or ('[%s found]'):format(name)
    end
    return foundText
end

-- Where the windows are placed, uihook, and whether the mouse goes through them
local nativeSpec = { }
local lockSpec = { label = 'Lock Windows',
    description = 'Clicks go through the windows to the game. Off, a window is moved by holding Shift and dragging it.' }
local function DrawGlobal(saved)
    widgets.BeginLabels('xiframes.global')
    if widgets.Header('Positioning', true) then
        if widgets.Check('Automatic Positioning',
            'Puts the windows in their usual places, your party at the bottom right and the target above it. Off, each window stays where you put it.',
            saved.automaticPositioning, '##party.automaticPositioning') then Save() end
    end

    -- Only with uihook loaded: the windows can be drawn in the game's own place among its menus. Its
    -- choices are kept while it is not loaded, and come back with it.
    local manager = AshitaCore:GetPluginManager()
    local plugin = manager:IsLoaded('uihook') and 'uihook'
    if plugin then
        local open = widgets.Header('uihook')
        imgui.SameLine()
        imgui.TextColored(foundColor, Found(manager, plugin))
        if open then
            if widgets.Check('Use uihook',
                'Draws the chosen windows where the game draws its own, among its menus. /pt native status says how it is going.',
                saved.nativeHook, '##party.nativeHook') then Save() end
            nativeSpec.parent = saved.nativeHook
            if widgets.Check('Party',
                'The three party lists instead of the game default ones, with its selection. Pets go with them.',
                saved.nativeParty, '##party.nativeParty', nativeSpec) then Save() end
            if widgets.Check('Target',
                'The target windows instead of the game default target box. /pt native target on|off does the same.',
                saved.nativeTarget, '##party.nativeTarget', nativeSpec) then Save() end
            if widgets.Check('Follow Default UI Behavior',
                'The windows in the game\'s place show and hide with its interface, in its order, solo too, and never fade.',
                saved.nativeBehavior, '##party.nativeBehavior', nativeSpec) then Save() end
        end
    end

    if widgets.Header('Mouse Interaction') then
        widgets.Lock(saved.clickThrough, '##xiframes.clickThrough', lockSpec)
        widgets.Check('Show Tooltips',
            'Hovering a window shows full names, jobs and pet owners, and each buff and debuff with its time left.',
            saved.style.hoverDetails, '##party.hoverDetails')
    end
end

-- When the windows are hidden, and how they fade while idle
local fadedSpec = { parent = true } -- indented under Fade When Idle, as the fade's own rows are
local fadeSentences = {
    party = 'The party and alliance lists fade while you are idle, and fade in and out as they appear and go.',
    target = 'The target windows fade while you are idle, and fade in and out as a target is taken and dropped.',
}
local function DrawVisibility(saved)
    widgets.BeginLabels('xiframes.visibility')
    if widgets.Header('Hide Windows', true) then
        widgets.Hide(saved.hide, Save)
    end

    if widgets.Header('Fading') then
        local fade = saved.fade
        widgets.Fade(fade, Save, true)

        -- A chosen window fades out while idle, and fades in and out as it appears and goes (the target
        -- window as a target is taken and dropped)
        if fade.Enabled and widgets.SubHeader('Affected Windows') then
            for _, group in ipairs(windows.Groups) do
                group.id = group.id or ('##xiframes.fade.%s'):format(group.key)
                if widgets.Check(group.label, fadeSentences[group.key] or '', fade.windows[group.key], group.id, fadedSpec) then Save() end
            end
        end
        widgets.EndSub()
    end
end

config.Tabs = {
    { name = 'Behavior', draw = DrawGlobal },
}
for _, tab in ipairs(options.Tabs) do
    tab.labels = ('xiframes.%s'):format(tab.name:lower())
    table.insert(config.Tabs, { name = tab.name, draw = function(saved) DrawEntries(tab, saved) end })
end
table.insert(config.Tabs, { name = 'Visibility', draw = DrawVisibility })

-- The window has the theme's settings window values, apart from the game windows' that are set in it;
-- winxi.window fits it to its rows, which are the same width on every tab.
local framePadding = { 4, 2 }
local style = { kind = window.Settings }
local flags = nil
local drawing = nil

local function DrawContent()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)

    if imgui.BeginTabBar('##xiframes.config', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        for _, tab in ipairs(config.Tabs) do
            if imgui.BeginTabItem(tab.name) then
                tab.draw(drawing)
                imgui.EndTabItem()
            end
        end
        imgui.EndTabBar()
    end

    -- the strip along the bottom, below whichever tab is showing: winxi's Organize button against the
    -- right edge, with its grid option to the left while it is switched on
    imgui.Separator()
    organize.Controls(framePadding[1])

    imgui.PopStyleVar()
end

function config.Toggle(saved)
    saved.showConfig[1] = not saved.showConfig[1]
end

function config.Draw(saved)
    if not saved.showConfig[1] then
        return
    end

    -- a settings window: winxi.window fits it to its content, or keeps the size it is resized to
    flags = flags or ImGuiWindowFlags_NoSavedSettings
    drawing = saved
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, windows.ItemSpacing)
    window.Full('Party Settings', saved.showConfig, flags, DrawContent, style)
    imgui.PopStyleVar()

    if not saved.showConfig[1] then
        -- closed by its own button: what was set in it is kept
        settings.save()
    end
end

return config
