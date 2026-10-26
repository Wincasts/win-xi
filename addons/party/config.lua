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
local organize = require('winxi.organize')
local options = require('options')
local windows = require('windows')
local nativePlacement = require('nativeposition')
local statuspicker = require('statuspicker')

local config = { }

local function Save()
    settings.save()
end

local Tooltip = require('winxi.tooltip').Hover

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

function controls.text(entry, value)
    imgui.InputText(Id(entry), value, 8192)
    Tooltip(entry.tooltip)
end

function controls.statuslist(entry, value)
    statuspicker.Draw(entry.key, value, entry.ordered)
    Tooltip(entry.tooltip)
end

function controls.check(entry, value)
    imgui.Checkbox(Id(entry), value)
    Tooltip(entry.tooltip)
end

function controls.slider(entry, value)
    if entry.displayDivisor then
        -- Preserve centimeter storage while exposing meters, including the existing 20.79m default.
        box[1] = value[1] / entry.displayDivisor
        if imgui.SliderFloat(Id(entry), box, entry.min / entry.displayDivisor, entry.max / entry.displayDivisor, '%.2f m') then
            value[1] = math.max(entry.min, math.min(entry.max, math.floor(box[1] * entry.displayDivisor + 0.5)))
        end
    elseif entry.format ~= nil then
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
    widgets.FontFile(section, entry.key, Id(entry), { label = false, tooltip = entry.tooltip })
end

-- where a window is: typed in, the window goes there, and stays there if it was held by a corner
local disabledPosition = { 0, 0 }
function controls.place(entry, value, section, saved)
    local defaultManaged=nativePlacement.Enabled(saved,entry.window)
    local managed=defaultManaged or (saved.automaticPositioning[1] and not nativePlacement.ManualOverride(saved,entry.window)
        and entry.window ~= 'sub' and entry.window ~= 'tot')
    if managed then
        disabledPosition[1], disabledPosition[2] = value[1], value[2]
        if imgui.BeginDisabled then
            imgui.BeginDisabled(true)
            imgui.InputInt2(Id(entry), disabledPosition)
            imgui.EndDisabled()
        else
            imgui.TextDisabled(('%d, %d'):format(value[1], value[2]))
        end
        imgui.SameLine()
        imgui.TextDisabled(defaultManaged and 'Default UI location' or 'Managed automatically')
    elseif imgui.InputInt2(Id(entry), value) then
        local which = windows.List[entry.window]
        imgui.SetWindowPos(which.name, value)
        windows.ForgetCorner(which)
    end
    Tooltip(entry.tooltip)
end

local disabledCheck = { false }
local function Checkbox(label, value, disabled)
    if not disabled then return imgui.Checkbox(label, value) end
    -- Use a copy as well as native disabling, so neither missing bindings nor test stubs can edit it.
    disabledCheck[1] = value[1]
    if imgui.BeginDisabled then
        imgui.BeginDisabled(true)
        imgui.Checkbox(label, disabledCheck)
        imgui.EndDisabled()
    else
        imgui.TextDisabled((value[1] and '[x] ' or '[ ] ') .. label:gsub('##.*', ''))
    end
    return false
end

local targetRows = {
    { 'Target', 'showMain', 'mainDebuffs' },
    { 'Sub-target', 'showSub', 'subDebuffs' },
    { 'Target of target', 'showTot', 'totDebuffs' },
}
local function DrawTargetRows(saved)
    if imgui.BeginTable('##party.targetFrames', 3, ImGuiTableFlags_SizingFixedFit) then
        imgui.TableSetupColumn('Frame')
        imgui.TableSetupColumn('Show')
        imgui.TableSetupColumn('Show debuffs')
        imgui.TableHeadersRow()
        for _, row in ipairs(targetRows) do
            imgui.TableNextRow()
            imgui.TableSetColumnIndex(0)
            imgui.Text(row[1])
            imgui.TableSetColumnIndex(1)
            Checkbox('##xiframes.target.' .. row[2], saved.target[row[2]], not saved.target.enabled[1])
            imgui.TableSetColumnIndex(2)
            Checkbox('##xiframes.target.' .. row[3], saved.target[row[3]],
                not saved.target.enabled[1] or not saved.target[row[2]][1])
        end
        imgui.EndTable()
    end
    imgui.TextDisabled('Enable a frame to configure its debuffs. Hidden frames retain their settings.')
end

local function DrawEntries(tab, saved)
    widgets.BeginLabels(tab.labels)
    local open, first = true, true
    for _, entry in ipairs(tab.entries) do
        -- with Show Statuses off, every status setting is drawn greyed and cannot be changed
        local greyed = entry.statuses and not saved.style.showStatuses[1] and imgui.BeginDisabled ~= nil
        if entry.kind == 'header' then
            open = widgets.Header(entry.label, first, entry.defaultCollapsed)
            first = false
            if greyed and open then imgui.BeginDisabled(true) end
            if open and tab.name == 'Style' and entry.label == 'Appearance' then
                imgui.TextWrapped('Shared colors, borders, backgrounds, bar textures and status icon artwork are configured in winxisettings (/wxi).')
            elseif open and tab.name == 'Style' and entry.label == 'Advanced: Status IDs' then
                widgets.Label('Priority Status IDs')
                imgui.InputText('##party.priorityStatusIds', saved.style.priorityStatuses, 8192)
                widgets.Label('Hidden Status IDs')
                imgui.InputText('##party.hiddenStatusIds', saved.style.hiddenStatuses, 8192)
                imgui.TextDisabled('Comma-separated IDs. Priority order follows the list; hidden IDs take precedence.')
            end
            if greyed and open then imgui.EndDisabled() end
        elseif entry.kind == 'gap' then
            if open then widgets.Gap() end
        elseif open and not entry.targetRow and (entry.when == nil or entry.when(saved)) then
            local section = saved[entry.section]
            if greyed then imgui.BeginDisabled(true) end
            widgets.Label(entry.label, entry.experimental)
            controls[entry.kind](entry, section[entry.key], section, saved)
            if greyed then imgui.EndDisabled() end
            if tab.name == 'Target' and entry.key == 'enabled' then DrawTargetRows(saved) end
        end
    end
end

-- A setting's explanation, as winxi gives one: a greyed (?) after its control, the text in its tooltip
local function Help(text)
    imgui.SameLine()
    imgui.TextDisabled('(?)')
    Tooltip(text)
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

-- Whether the mouse goes through the windows, where they are placed, and uihook
local function DrawGlobal(saved)
    widgets.BeginLabels('xiframes.global')
    if widgets.Header('Mouse Interaction', true) then
        widgets.Lock(saved.clickThrough, '##xiframes.clickThrough', { label = 'Clickthrough', tooltip = 'The windows let the mouse through to the game. Off, a window is moved by holding Shift and dragging it. Ignored while organizing, so they can be dragged.' })
        widgets.Label('Hover Details')
        Checkbox('##party.hoverDetails', saved.style.hoverDetails, saved.clickThrough[1])
        Tooltip('Full names, jobs and pet owners.')
        if saved.clickThrough[1] then imgui.TextDisabled('Turn off Clickthrough to enable hover details.') end
    end

    if widgets.Header('Positioning') then
        widgets.Label('Automatic Positioning')
        if imgui.Checkbox('##party.automaticPositioning', saved.automaticPositioning) then Save() end
        Tooltip('Main party: 15px from the right and bottom. Target: 5px above the main party.\nAlliance 2: right edge, with room reserved for full parties and a 35px gap above the fully expanded Target. Alliance 3 stays linked 5px below Alliance 2.\nSub-target and target of target are unchanged. Manual positions are preserved; disable to use them.\nDoes not resize frames. If the full layout cannot fit, windows are clamped to the screen and gaps may be smaller.')
    end

    -- Only with uihook (or the older partyhook) loaded: the windows can be drawn in the game's own place
    -- among its menus. Its choices are kept while it is not loaded, and come back with it.
    local manager = AshitaCore:GetPluginManager()
    local plugin = manager:IsLoaded('uihook') and 'uihook' or (manager:IsLoaded('partyhook') and 'partyhook')
    if plugin then
        local open = widgets.Header('uihook')
        imgui.SameLine()
        imgui.TextColored(foundColor, Found(manager, plugin))
        if open then
            widgets.Label('Use uihook')
            if imgui.Checkbox('##party.nativeHook', saved.nativeHook) then Save() end
            Help('The chosen windows take the place of the game\'s own, drawn among its menus. Unload hideparty first. Organize mode uses ordinary windows. /pt native status shows diagnostics.')
            if saved.nativeHook[1] then
                widgets.Label('Party')
                if imgui.Checkbox('##party.nativeParty', saved.nativeParty) then Save() end
                Help('The three Party lists replace the game\'s, keeping its selection. Pets are drawn in the Party windows and go with them.')
                widgets.Label('Target')
                if imgui.Checkbox('##party.nativeTarget', saved.nativeTarget) then Save() end
                Help('Main, sub-target and target-of-target windows replace the stock target box together. The client still draws its own overhead target/subtarget arrows, with native positions and range colours. /pt native target on|off.')
                widgets.Label('Follow Default UI Behavior')
                if imgui.Checkbox('##party.nativeBehavior', saved.nativeBehavior) then Save() end
                Help('For hooked windows only: follow whether the client draws the HUD instead of Party hide rules, use native party order, show the solo member when the client does, and skip addon idle/presence fading. Native menus still cover the frames and the original target arrows are preserved. Zoning, interface hiding and cutscenes are always guarded. Other windows keep their normal options. Styles, pet/buff choices and frame sizes are unchanged.')
            end
        end
    end
end

-- When the windows are hidden, and how they fade while idle
local function DrawVisibility(saved)
    widgets.BeginLabels('xiframes.visibility')
    if widgets.Header('Hide Windows', true) then
        widgets.Hide(saved.hide, Save)
    end

    if widgets.Header('Fading') then
        imgui.Indent()
        widgets.PushControlWidth()
        local fade = saved.fade
        widgets.Fade(fade, Save, true)

        -- A chosen window fades out while idle, and fades in and out as it appears and goes (the target
        -- window as a target is taken and dropped)
        if fade.Enabled and widgets.Header('Affected Windows') then
            for _, group in ipairs(windows.Groups) do
                widgets.Label(group.label)
                group.id = group.id or ('##xiframes.fade.%s'):format(group.key)
                if imgui.Checkbox(group.id, fade.windows[group.key]) then Save() end
                Tooltip('Fades out while you are idle, and fades in and out as it appears and goes.')
            end
        end
        widgets.PopControlWidth()
        imgui.Unindent()
    end
end

config.Tabs = {
    { name = 'Behavior', draw = DrawGlobal },
    { name = 'Visibility', draw = DrawVisibility },
}
for _, tab in ipairs(options.Tabs) do
    tab.labels = ('xiframes.%s'):format(tab.name:lower())
    table.insert(config.Tabs, { name = tab.name, draw = function(saved) DrawEntries(tab, saved) end })
end

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
