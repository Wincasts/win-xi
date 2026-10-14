-- config: the settings window. Its first tab and its last are winxi's doing (when the windows hide;
-- the Winxi Theme tab, with fading under it); those between are drawn from the lists of entries in
-- options.lua, one tab a list.
--
--     config.Draw(saved)         the window, if it is open; saves the settings when it is closed
--     config.Toggle(saved)       opens or closes it
--     config.Tabs                every tab, in order: { name, draw, theme }, draw taking the settings, and
--                                theme true for the Winxi Theme tab
--
-- Each setting's name is to the left of its control and followed by a colon, with every word
-- capitalised, and one family of settings is set a little apart from the next (see winxi.widgets).
require('common')
local imgui = require('imgui')
local settings = require('settings')
local widgets = require('winxi.widgets')
local window = require('winxi.window')
local fonts = require('winxi.fonts')
local organize = require('winxi.organize')
local options = require('options')
local windows = require('windows')

local config = { }

local function Save()
    settings.save()
end

local function Tooltip(text)
    if text ~= nil and imgui.IsItemHovered() then
        imgui.SetTooltip(text)
    end
end

-- The controls of the kinds of entry. Each control's hidden label is made once, and kept on the entry.
local box = { 0 }             -- a number on its way in and out of a slider
local offsetSliderWidth = 130

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

local controls = { }

function controls.check(entry, value)
    imgui.Checkbox(Id(entry), value)
    Tooltip(entry.tooltip)
end

function controls.slider(entry, value)
    if entry.format ~= nil then
        imgui.SliderInt(Id(entry), value, entry.min, entry.max, entry.format)
    else
        imgui.SliderInt(Id(entry), value, entry.min, entry.max)
    end
    Tooltip(entry.tooltip)
end

-- two sliders side by side, across and down
function controls.offset(entry, value)
    for axis = 1, 2 do
        if axis == 2 then
            imgui.SameLine()
        end
        box[1] = tonumber(value[axis]) or 0
        imgui.PushItemWidth(offsetSliderWidth)
        if imgui.SliderInt(Id(entry, axis == 1 and 'X' or 'Y'), box, -entry.reach, entry.reach, axis == 1 and 'X %d' or 'Y %d') then
            value[axis] = box[1]
        end
        imgui.PopItemWidth()
        Tooltip(entry.tooltip)
    end
end

-- radio buttons, two to a line; the first is the one chosen when none is
function controls.choice(entry, value, section)
    local column = imgui.GetCursorPosX()
    for index, choice in ipairs(entry.choices) do
        if index % 2 == 0 then
            imgui.SameLine()
        elseif index > 1 then
            imgui.SetCursorPosX(column)
        end
        local labels = entry.choiceLabels
        if labels == nil then
            labels = { }
            entry.choiceLabels = labels
        end
        labels[index] = labels[index] or ('%s%s'):format(choice.label, Id(entry))
        if imgui.RadioButton(labels[index], value == choice.key or (index == 1 and value == nil)) then
            section[entry.key] = choice.key
        end
        Tooltip(entry.tooltip)
    end
end

-- Style selectors: display labels, but keep the existing string keys in saved settings.
function controls.dropdown(entry, value, section)
    local chosen = entry.choices[1]
    for _, choice in ipairs(entry.choices) do
        if choice.key == value then chosen = choice; break end
    end
    local opened = imgui.BeginCombo(Id(entry), chosen.label)
    Tooltip(entry.tooltip)
    if opened then
        local labels = entry.dropdownLabels
        if labels == nil then
            labels = { }
            entry.dropdownLabels = labels
        end
        for index, choice in ipairs(entry.choices) do
            labels[index] = labels[index] or (choice.label .. Id(entry, index))
            local selected = choice.key == chosen.key
            if imgui.Selectable(labels[index], selected) then
                section[entry.key] = choice.key
            end
            if selected then imgui.SetItemDefaultFocus() end
        end
        imgui.EndCombo()
    end
end

-- a font of C:\Windows\Fonts, or '' for the theme's
function controls.font(entry, value, section)
    local opened = imgui.BeginCombo(Id(entry), value ~= '' and value or 'Theme Font')
    Tooltip(entry.tooltip)
    if opened then
        if imgui.Selectable('Theme Font' .. Id(entry, 'theme'), value == '') then
            section[entry.key] = ''
        end
        for _, file in ipairs(fonts.Files()) do
            if imgui.Selectable(file .. Id(entry, file), value == file) then
                section[entry.key] = file
            end
        end
        imgui.EndCombo()
    end
end

-- where a window is: typed in, the window goes there, and stays there if it was held by a corner
function controls.place(entry, value)
    if imgui.InputInt2(Id(entry), value) then
        local which = windows.List[entry.window]
        imgui.SetWindowPos(which.name, value)
        windows.ForgetCorner(which)
    end
    Tooltip(entry.tooltip)
end

local function DrawEntries(tab, saved)
    widgets.BeginLabels(tab.labels)
    for _, entry in ipairs(tab.entries) do
        if entry.kind == 'gap' then
            widgets.Gap()
        elseif entry.when == nil or entry.when(saved) then
            local section = saved[entry.section]
            widgets.Label(entry.label, entry.experimental)
            controls[entry.kind](entry, section[entry.key], section)
        end
    end
end

-- When the windows get out of the way, and whether the mouse goes through them
local function DrawGlobal(saved)
    widgets.BeginLabels('xiframes.global')
    widgets.Hide(saved.hide, Save)

    widgets.Gap()
    widgets.Label('Clickthrough')
    imgui.Checkbox('##xiframes.clickThrough', saved.clickThrough)
    Tooltip('The windows let the mouse through to the game. Ignored while organizing, so they can be dragged.')
end

-- The Theme, Window and Styles sections are winxi's; the Addon section is what is this addon's own: fading
-- while idle, and which windows it applies to
local hookedTo = nil
local appearanceHooks = {
    onUseShared = function(useShared)
        hookedTo.useSharedTheme = useShared
        settings.save()
    end,
    onOwnChanged = Save,
}

local function DrawAppearance(saved)
    hookedTo = saved
    widgets.Appearance(appearanceHooks)

    if not widgets.Header('Addon') then return end
    widgets.PushControlWidth()
    local fade = saved.fade
    widgets.Fade(fade, Save)

    -- A chosen window fades out while idle, and fades in and out as it appears and goes (the target
    -- window as a target is taken and dropped)
    if fade.Enabled then
        widgets.Label('Windows That Fade')
        for index, group in ipairs(windows.Groups) do
            if index > 1 then
                imgui.SameLine()
            end
            group.id = group.id or ('%s##xiframes.fade'):format(group.label)
            imgui.Checkbox(group.id, fade.windows[group.key])
            Tooltip('Fades out while you are idle, and fades in and out as it appears and goes.')
        end
    end
    widgets.PopControlWidth()
end

config.Tabs = {
    { name = 'Global Settings', draw = DrawGlobal },
}
for _, tab in ipairs(options.Tabs) do
    tab.labels = ('xiframes.%s'):format(tab.name:lower())
    table.insert(config.Tabs, { name = tab.name, draw = function(saved) DrawEntries(tab, saved) end })
end
table.insert(config.Tabs, { name = widgets.ThemeTabLabel, draw = DrawAppearance, theme = true })

-- The window is never narrower than this, so it does not jump about as the tabs are switched. It has
-- the theme's settings window values, apart from the game windows' that are set in it.
local minSize, maxSize = { 780, 0 }, { 10000, 10000 }
local framePadding = { 4, 2 }
local style = { kind = window.Settings }
local flags = nil
local drawing = nil

local function DrawContent()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)

    if imgui.BeginTabBar('##xiframes.config', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        for _, tab in ipairs(config.Tabs) do
            if tab.theme then
                if widgets.BeginThemeTab() then
                    tab.draw(drawing)
                    widgets.EndThemeTab()
                end
            elseif imgui.BeginTabItem(tab.name) then
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
    -- only while the window is showing: the constraint goes to whichever window is drawn next
    if not saved.showConfig[1] then
        return
    end

    -- a settings window: winxi.window fits it to its content, or keeps the size it is resized to
    flags = flags or ImGuiWindowFlags_NoSavedSettings
    drawing = saved
    imgui.SetNextWindowSizeConstraints(minSize, maxSize)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, windows.ItemSpacing)
    window.Full('Party Settings', saved.showConfig, flags, DrawContent, style)
    imgui.PopStyleVar()

    if not saved.showConfig[1] then
        -- closed by its own button: what was set in it is kept
        settings.save()
    end
end

return config
