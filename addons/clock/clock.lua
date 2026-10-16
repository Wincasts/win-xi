addon.name = 'clock'
addon.author = 'win'
addon.version = '0.10.0'
addon.desc = 'Vana\'diel clock on one line in place of the game\'s, its icons kept, the compass hidden (uihook).'
local winxiNeeded = 5
do
    local ok, found = pcall(require, 'winxi.version')
    local number = ok and type(found) == 'table' and found.Number or 0
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number)
        print('[clock] ' .. text)
        error(text, 0)
    end
end
require('common')
local imgui = require('imgui')
local bit = require('bit')
local shell = require('winxi.shell')
local widgets = require('winxi.widgets')
local fonts = require('winxi.fonts')
local outlined = require('winxi.text')
local native = require('winxi.nativehud')
local fields = require('fields')
local icons = require('icons')
local exp = require('exp')

local hook = native.new(native.Clock)
local compass = native.new(native.Compass)
local time, timeError
local nextSample, segments = 0, nil -- the line, as fields.Segments last gave it
local preview = ''                  -- and in words, for the settings
local weekday = nil                 -- as the line was last read, for the day's icon
local sets, setsOpen = {}, false    -- the icon sets, listed as the list is opened
local screenMin, screenMax, iconMin, iconMax = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
-- Where the game puts its weather icon, from its day icon's top left, and the weather icon's size:
-- learnt whenever it draws both, less Weather Offset's move. Until then, from Clock::Draw: the
-- weather's at (x-68, y-42) and the day's at (x-68, y+26), both sixteen of its units across, so 68
-- units above, as large.
local weatherSlot = nil
local function SkySlot(dayAt)
    if not dayAt or not dayAt[1] then return nil end
    if weatherSlot then
        local x, y = dayAt[1] + weatherSlot[1], dayAt[2] + weatherSlot[2]
        return { x, y, x + weatherSlot[3], y + weatherSlot[4] }
    end
    local up = 68 * (dayAt[3] - dayAt[1]) / 16
    return { dayAt[1], dayAt[2] - up, dayAt[3], dayAt[4] - up }
end
local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoMove,
    ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoInputs,
    ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoBringToFrontOnFocus, ImGuiWindowFlags_NoBackground)
local SCALE_MIN, SCALE_MAX = 0.5, 3
local FONT_MOST = 48    -- pixels the line's font can be
local OUTLINE_MOST = 3  -- pixels its dark edge can be
local OFFSET_MOST = 10  -- pixels the set's icons can be moved up or down
local ICON_GAP = 4      -- pixels between the day icon and the line
local WEATHER_MOST = 40 -- pixels the weather icon can be moved up or down
-- Show All Weather Icons, for this session alone: each element's in its place in a row from the
-- weather icon's, in the order of the game's weather sprites, and the set's clear sky after them
local showAll = { false }
local ALL_WEATHER = { 4, 12, 10, 8, 14, 6, 16, 18, 0 } -- fire, ice, wind, earth, thunder, water, light, dark, clear
local RATE_OVER = 3600  -- EXP Per Hour is the last hour's
local noPadding = { 0, 0 }
local place, pivot, room = { 0, 0 }, { 0, 0.5 }, { 0, 0 }
local widths = {}
local format = { '' } -- the line being written in the settings
local scaleWas = nil  -- a Text Scale of 0.8 or before, to be made a Font Size
-- What can be put between fields from the settings, as it is put
local DIVIDERS = { { label = '|', text = ' | ' }, { label = '·', text = ' · ' }, { label = '-', text = ' - ' },
    { label = '/', text = ' / ' }, { label = 'Space', text = '  ' } }

-- An icon's place grown or shrunk about its middle, and moved down by offset
local function Placed(at, scale, offset)
    if not at or not at[1] then return nil end
    local cx, cy = (at[1] + at[3]) / 2, (at[2] + at[4]) / 2 + offset
    local w, h = (at[3] - at[1]) * scale / 2, (at[4] - at[2]) * scale / 2
    return { cx - w, cy - h, cx + w, cy + h }
end

-- The weather by name, for the Weather field: nil for a clear sky, or while uihook has none to give.
local function WeatherName()
    local id = hook.Weather()
    if not id or id == 0 then return nil end
    local ok, name = pcall(function() return AshitaCore:GetResourceManager():GetString('weather', id) end)
    return ok and type(name) == 'string' and #name > 0 and name or ('Weather ' .. id)
end

local function Release()
    hook.Stop()
    compass.Stop()
    nextSample, segments = 0, nil
end

local app
local function Tip(text)
    if imgui.IsItemHovered() then imgui.SetTooltip(text) end
end

-- Something added to the end of the line from the settings: a field two spaces after what is there,
-- or a divider in place of the spaces at the end
local function Append(options, text, divider)
    local line = options.format
    if divider then
        line = line:gsub('%s+$', '')
    elseif line ~= '' and not line:find('%s$') then
        line = line .. '  '
    end
    options.format = line .. text
    format[1] = options.format
    nextSample = 0
    app.save()
end

local fieldsOpen = false -- the Add Field list, as last drawn

-- The clock's own font: a file of C:\Windows\Fonts or the theme's (''), at a size or the theme's (0)
local function FontChoice(options)
    widgets.Label('Font')
    local file = options.fontFile
    if imgui.BeginCombo('##clock.fontFile', file ~= '' and file or 'Theme\'s Font') then
        if imgui.Selectable('Theme\'s Font##clock.font.theme', file == '') and file ~= '' then
            options.fontFile = ''
            app.save()
        end
        for _, choice in ipairs(fonts.Files()) do
            if imgui.Selectable(choice .. '##clock.font', file == choice) and file ~= choice then
                options.fontFile = choice
                app.save()
            end
        end
        imgui.EndCombo()
    end
    Tip('The line\'s font: one of C:\\Windows\\Fonts, or the theme\'s.')
    widgets.Label('Font Size')
    imgui.SliderInt('##clock.fontSize', options.fontSize, 0, FONT_MOST, options.fontSize[1] > 0 and '%d px' or 'Theme\'s')
    if imgui.IsItemDeactivatedAfterEdit() then app.save() end
    Tip('How large the line is, in pixels; 0 for the theme\'s size.')
end

local function DrawSettings(options)
    if widgets.Header('Clock', true) then
        widgets.Label('Replace Game\'s Clock')
        if imgui.Checkbox('##clock.replace', options.replace) then
            if not options.replace[1] then hook.Stop() end
            app.save()
        end
        Tip('Writes the line below where the game writes its clock.\nThe game\'s day and weather icons stay where it puts them.\nOff, the game\'s own clock comes back.')
        widgets.Label('Hide Compass')
        if imgui.Checkbox('##clock.hideCompass', options.hideCompass) then
            if not options.hideCompass[1] then compass.Stop() end
            app.save()
        end
        Tip('Stops the game drawing its compass and radar. The clock and its icons stay.')
        imgui.TextDisabled(timeError and ('Time unavailable: ' .. timeError) or hook.Status())
    end

    if widgets.Header('Line') then
        if format[1] ~= options.format and not imgui.IsAnyItemActive() then format[1] = options.format end
        widgets.Label('Line')
        -- a width of its own, wider as the line grows: the settings window fits itself to what is
        -- in it, so a box as wide as the window (-1) and the window shrank each other every frame
        local _, textHeight = imgui.CalcTextSize('A')
        textHeight = textHeight or 14
        imgui.SetNextItemWidth(math.max(textHeight * 24, (imgui.CalcTextSize(format[1]) or 0) + textHeight * 2))
        if imgui.InputText('##clock.format', format, 256) then
            options.format = format[1]
            nextSample = 0
        end
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('Each {field} is written in its place, and anything else as it is: the dividers.\nA field with nothing to write takes the divider before it with it.')
        widgets.Label('Shows')
        imgui.TextDisabled(preview ~= '' and preview or '(nothing)')
        widgets.Label('Add Field')
        local opened = imgui.BeginCombo('##clock.addField', 'Choose a field')
        Tip('Puts a field at the end of the line, two spaces on.')
        if opened then
            for _, field in ipairs(fields.All) do
                if imgui.Selectable(('%s  {%s}##clock.add.%s'):format(field.label, field.token, field.token), false) then
                    Append(options, '{' .. field.token .. '}')
                end
                Tip(field.tip)
            end
            imgui.EndCombo()
        end
        widgets.Label('Add Divider')
        for i, divider in ipairs(DIVIDERS) do
            if i > 1 then imgui.SameLine() end
            if imgui.SmallButton(divider.label .. '##clock.divider.' .. i) then Append(options, divider.text, true) end
            Tip(('Puts \'%s\' at the end of the line. Type any other between the fields.'):format(divider.text))
        end
        widgets.Label('')
        if imgui.SmallButton('Default##clock.formatDefault') then
            options.format = fields.Default
            format[1] = options.format
            nextSample = 0
            app.save()
        end
        Tip(('Back to the line a new character has: %s'):format(fields.Default))
        if fields.Uses(options.format, 'exp') then
            widgets.Label('EXP Per Hour')
            if imgui.SmallButton('Begin Again##clock.expReset') then
                exp.Reset()
                nextSample = 0
            end
            Tip('Forgets the experience counted so far, for EXP Per Hour to begin again from now. /clock exp reset does the same.')
            local since, counted = exp.Since()
            imgui.SameLine()
            imgui.TextDisabled(since and ('%d gains over %d min'):format(counted, math.floor((os.clock() - since) / 60))
                or 'None gained yet')
        end
    end

    if widgets.Header('Text') then
        FontChoice(options)
        widgets.Label('Text Color')
        if imgui.ColorEdit4('##clock.textColor', options.textColor, ImGuiColorEditFlags_NoInputs) then nextSample = 0 end
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('The line\'s colour, and how solid it is.')
        widgets.Label('Outline')
        imgui.SliderInt('##clock.outline', options.outline, 0, OUTLINE_MOST, options.outline[1] > 0 and '%d px' or 'None')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('How thick the dark edge round the letters is, in pixels, so the line reads over anything.')
    end

    if widgets.Header('Icons') then
        widgets.Label('Icon Set')
        local chosen = options.iconSet
        if imgui.BeginCombo('##clock.iconSet', chosen == icons.None and 'Game\'s Icons' or chosen) then
            if not setsOpen then sets, setsOpen = icons.Sets(), true end
            local function Choose(key)
                options.iconSet = key
                icons.Forget()
                app.save()
            end
            if imgui.Selectable('Game\'s Icons##clock.set.none', chosen == icons.None) then Choose(icons.None) end
            for _, set in ipairs(sets) do
                if imgui.Selectable(set.label .. '##clock.set.' .. set.key, chosen == set.key) then Choose(set.key) end
            end
            imgui.EndCombo()
        else
            setsOpen = false
        end
        Tip('Pictures of your own for the day and weather icons: a folder of addons\\clock\\icons.\nWhere the set has no picture for the day or the weather, the game\'s own icon is drawn.')
        widgets.Label('Icon Scale')
        imgui.SliderFloat('##clock.iconScale', options.iconScale, SCALE_MIN, SCALE_MAX, '%.2fx')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('How large the Icon Set\'s icons are: where the game draws its own, against the game\'s icon,\nand in the line ({weathericon}), against the text. The game\'s own icons keep their size.')
        widgets.Label('Icon Offset')
        imgui.SliderInt('##clock.iconOffset', options.iconOffset, -OFFSET_MOST, OFFSET_MOST, '%d px')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('Moves the Icon Set\'s icons up (less than 0) or down (more than 0), in pixels, where the game\ndraws its own and in the line. The game\'s own icons stay where they are.')
        widgets.Label('Weather Offset')
        imgui.SliderInt('##clock.weatherOffset', options.weatherOffset, -WEATHER_MOST, WEATHER_MOST, '%d px')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('Moves the weather icon above the clock up (less than 0) or down (more than 0), in pixels:\nthe game\'s own and the Icon Set\'s alike.')
        widgets.Label('Weather Scale')
        imgui.SliderFloat('##clock.weatherScale', options.weatherScale, SCALE_MIN, SCALE_MAX, '%.2fx')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('How large the weather icon is, about its middle: the game\'s own, which uihook draws that large,\nand the Icon Set\'s, on top of Icon Scale.')
        widgets.Label('Show All Weather')
        imgui.Checkbox('##clock.showAll', showAll)
        Tip('Draws every weather icon in a row from the weather icon\'s place, to see them and where they sit:\nfire, ice, wind, earth, thunder, water, light and dark, then the clear sky.\nThe Icon Set\'s where it has them, the game\'s own where not. Until it is turned off, or the game is restarted.')
    end
end

local function SayStatus()
    local options = app.options
    app:Say(not options.replace[1] and 'Off: the game\'s own clock is shown.' or
        timeError and ('Time unavailable: ' .. timeError) or hook.Status())
    app:Say(options.hideCompass[1] and ('Compass: ' .. compass.Status()) or 'Compass: shown.')
end

app = shell.New({
    defaults = T{ replace = T{ true }, hideCompass = T{ true }, fontFile = '', fontSize = T{ 0 }, textColor = T{ 1, 1, 1, 1 },
        outline = T{ 1 }, iconScale = T{ 1 }, iconOffset = T{ 0 }, weatherOffset = T{ 0 }, weatherScale = T{ 1 }, iconSet = icons.None,
        format = fields.Default },
    hideAppearance = true, -- the clock has its own font and colour: no Winxi Theme tab
    configTitle = 'Clock Settings',
    command = '/clock',
    help = '/clock opens or closes the settings; /clock on, /clock off, /clock status, /clock exp reset.',
    drawSettings = DrawSettings,
    commands = {
        on = function(options) options.replace[1] = true; app.save() end,
        off = function(options) options.replace[1] = false; hook.Stop(); app.save() end,
        status = SayStatus,
        exp = function(_, args)
            if args[3] and args[3]:lower() == 'reset' then
                exp.Reset()
                nextSample = 0
                app:Say('EXP Per Hour begins again from now.')
            else
                app:Say('/clock exp reset begins EXP Per Hour again from now.')
            end
        end,
    },
    onSettings = function(options)
        -- 0.1 kept enabled as true or false, and a place of its own, now the game's clock's. Under a
        -- new name: Ashita merges the saved file with these defaults, and a default table over a
        -- saved true or false stops the addon loading (table.merge's rawget)
        if options.enabled ~= nil then
            options.replace[1] = options.enabled ~= false
            options.enabled = nil
        end
        options.x, options.y = nil, nil
        -- 0.3 to 0.6 kept the fields as a list to tick and move, and 0.6 experience as a switch
        if type(options.order) == 'table' then
            local experience = type(options.experience) == 'table' and options.experience[1] == true
            options.format = fields.FromList(options.order, options.shown, { exp = experience })
        end
        options.order, options.shown, options.experience, options.expWindow = nil, nil, nil, nil
        if type(options.format) ~= 'string' then options.format = fields.Default end
        format[1] = options.format
        if type(options.iconSet) ~= 'string' then options.iconSet = icons.None end
        icons.Forget()
        local function Clamp(value, low, high, default) return math.min(high, math.max(low, tonumber(value) or default)) end
        -- 0.1 to 0.8 had a Text Scale against the theme's size: made a Font Size the first time the
        -- line is drawn, when the theme's size is known
        if type(options.textScale) == 'table' then
            scaleWas = Clamp(options.textScale[1], SCALE_MIN, SCALE_MAX, 1)
            options.textScale = nil
        end
        if type(options.fontFile) ~= 'string' then options.fontFile = '' end
        options.fontSize[1] = math.floor(Clamp(options.fontSize[1], 0, FONT_MOST, 0))
        options.outline[1] = math.floor(Clamp(options.outline[1], 0, OUTLINE_MOST, 1))
        for i = 1, 4 do options.textColor[i] = Clamp(options.textColor[i], 0, 1, 1) end
        options.iconScale[1] = Clamp(options.iconScale[1], SCALE_MIN, SCALE_MAX, 1)
        options.iconOffset[1] = math.floor(Clamp(options.iconOffset[1], -OFFSET_MOST, OFFSET_MOST, 0))
        options.weatherOffset[1] = math.floor(Clamp(options.weatherOffset[1], -WEATHER_MOST, WEATHER_MOST, 0))
        options.weatherScale[1] = Clamp(options.weatherScale[1], SCALE_MIN, SCALE_MAX, 1)
        Release()
    end,
})

ashita.events.register('load', 'clock_load', function()
    local ok, value = pcall(require, 'ffxi.time')
    if ok then time = value else timeError = tostring(value) end
    if timeError then print('[clock] Ashita ffxi.time unavailable: ' .. timeError) end
end)
ashita.events.register('unload', 'clock_unload', Release)
-- experience gained, counted only while an experience field is in the line
ashita.events.register('packet_in', 'clock_packet', function(e)
    if fields.Uses(app.options.format, 'exp') then exp.Packet(e.id, e.data) end
end)

ashita.events.register('d3d_present', 'clock_present', function()
    app:BeginFrame()
    local options = app.options
    -- an empty compass, renewed each frame; the clock inside it is drawn all the same
    if options.hideCompass[1] then compass.Begin() else compass.Stop() end
    if not options.replace[1] or not time then hook.Stop(); return end

    local now = os.clock()
    local set = type(options.iconSet) == 'string' and options.iconSet or icons.None
    local day = icons.Day(set, weekday)
    local weather, double, gameDraws = icons.Weather(set, hook.Weather())
    -- the weather's icon in the line ({weathericon}), where the set has a picture for it
    local inline = weather ~= nil and fields.Has(options.format, 'weathericon')
    if now >= nextSample then
        nextSample = now + 0.25
        local ok, value = pcall(function()
            local context = fields.Context(time, hook.Grid(), fields.Has(options.format, 'weather') and WeatherName() or nil)
            context.weatherIcon = inline and weather or nil
            context.exp = fields.Uses(options.format, 'exp') and exp.Snapshot(now, RATE_OVER) or nil
            weekday = time.get_game_weekday(context.raw)
            return fields.Segments(context, options.format)
        end)
        if not ok then
            timeError, segments = tostring(value), nil
            hook.Stop()
            return
        end
        segments, timeError = value, nil
        local words = {}
        for _, segment in ipairs(segments) do words[#words + 1] = type(segment) == 'string' and segment or '[icon]' end
        preview = table.concat(words)
    end
    -- where the game writes its clock: until uihook has seen it, the game's own is left alone
    local left, top, _, bottom = hook.ClockRect()
    if not segments or not left then hook.Stop(); return end
    if not hook.Begin() then return end

    -- the set's icons where it has them, each where the game draws its own; the game's elsewhere
    local iconScale, iconOffset = options.iconScale[1], options.iconOffset[1]
    local dayAt = { hook.IconRect(native.DayIcon) }
    local gameWeather = { hook.IconRect(native.WeatherIcon) }
    -- Weather Offset in the game's units (its day icon sixteen across), and back in pixels
    local unit = dayAt[1] and (dayAt[3] - dayAt[1]) / 16 or 1
    local shiftUnits = unit > 0 and math.floor(options.weatherOffset[1] / unit + 0.5) or 0
    local shift = shiftUnits * unit
    hook.ShiftWeather(shiftUnits)
    local weatherScale = options.weatherScale[1]
    hook.ScaleWeather(weatherScale)
    if dayAt[1] and gameWeather[1] then
        weatherSlot = { gameWeather[1] - dayAt[1], gameWeather[2] - dayAt[2] - shift, gameWeather[3] - gameWeather[1], gameWeather[4] - gameWeather[2] }
    end
    local function Sky()
        local at = SkySlot(dayAt)
        if at then at[2], at[4] = at[2] + shift, at[4] + shift end
        return at
    end
    -- every weather icon in a row: the set's drawn here, the game's by uihook
    local all, gameAll = nil, 0
    if showAll[1] then
        local first = Sky()
        if first then
            all = {}
            -- as far apart as the grown icons and two of the game's units, as uihook spaces the game's
            local step = (first[3] - first[1]) * weatherScale + 2 * unit
            for i, id in ipairs(ALL_WEATHER) do
                local handle = icons.Weather(set, id)
                local at = { first[1] + (i - 1) * step, first[2], first[3] + (i - 1) * step, first[4] }
                if handle then all[#all + 1] = { handle, at, true }
                elseif i <= 8 then gameAll = gameAll + 2 ^ (i - 1) end
            end
        end
    end
    hook.PreviewWeather(gameAll)
    local weatherAt, secondAt
    if all then
        -- the row in place of the weather icon: nothing of its own above, the game's hidden
    elseif inline then
        -- in the line instead: nothing of its own above
    elseif weather and gameDraws then
        -- in place of the game's icon, once uihook has seen where it goes
        weatherAt = gameWeather[1] and gameWeather or nil
        secondAt = double and { hook.IconRect(native.SecondWeatherIcon) } or nil
    elseif weather then
        -- a sky the game draws no icon for: where its weather icon would be
        weatherAt = Sky()
    end
    if not dayAt[1] then day = nil end
    local hideWeather = all ~= nil or (weather and gameDraws and (inline or weatherAt ~= nil))
    if not weatherAt then weather = nil end
    hook.HideIcons((day and native.HideDay or 0) + (hideWeather and native.HideWeather or 0))

    -- the line's left on the game's, clear of the day icon as it is drawn (the set's, scaled and
    -- moved, or the game's), its middle on the game's middle, growing right
    local dayDrawn = day and Placed(dayAt, iconScale, iconOffset) or (dayAt[1] and dayAt)
    if dayDrawn then left = math.max(left, dayDrawn[3] + ICON_GAP) end
    place[1], place[2] = left, (top + bottom) / 2
    imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, noPadding)
    local pushed = fonts.Push()
    if imgui.Begin('clock.native', { true }, flags) then
        if scaleWas then
            -- the old Text Scale, against the theme's size, as a size of its own
            if scaleWas ~= 1 then options.fontSize[1] = math.min(FONT_MOST, math.floor(imgui.GetFontSize() * scaleWas + 0.5)) end
            scaleWas = nil
            app.save()
        end
        local size = options.fontSize[1] > 0 and options.fontSize[1] or imgui.GetFontSize()
        imgui.PushFont(fonts.Get(options.fontFile), size)
        local list = imgui.GetWindowDrawList()
        local fontSize = imgui.GetFontSize()
        local iconSize = fontSize * iconScale * weatherScale -- the line's only icon is the weather's
        -- the pieces side by side, their middles on the line's
        local width, height = 0, fontSize
        for i, segment in ipairs(segments) do
            if type(segment) == 'string' then
                widths[i] = imgui.CalcTextSize(segment)
            else
                widths[i] = iconSize
                height = math.max(height, iconSize)
            end
            width = width + widths[i]
        end
        local x, y = imgui.GetCursorScreenPos()
        room[1], room[2] = width, height
        imgui.Dummy(room)
        local color, edge = options.textColor, options.outline[1]
        for i, segment in ipairs(segments) do
            if type(segment) == 'string' then
                -- the dark edge winxi writes over the game with, as thick as Outline; none at 0
                if edge > 0 then
                    outlined.Draw(list, x, y + (height - fontSize) / 2, color, segment, edge)
                else
                    iconMin[1], iconMin[2] = x, y + (height - fontSize) / 2
                    list:AddText(iconMin, imgui.GetColorU32(color), segment)
                end
            else
                iconMin[1], iconMin[2] = x, y + (height - iconSize) / 2 + iconOffset
                iconMax[1], iconMax[2] = x + iconSize, iconMin[2] + iconSize
                list:AddImage(segment.icon, iconMin, iconMax)
            end
            x = x + widths[i]
        end
        imgui.PopFont()
        if day or weather or all then
            -- the icons are away from the line: drawn unclipped by the window
            local display = imgui.GetIO().DisplaySize
            screenMax[1], screenMax[2] = display.x or display[1] or 0, display.y or display[2] or 0
            list:PushClipRect(screenMin, screenMax, false)
            local function Icon(handle, at, isWeather)
                at = Placed(at, iconScale * (isWeather and weatherScale or 1), iconOffset)
                if not handle or not at then return end
                iconMin[1], iconMin[2], iconMax[1], iconMax[2] = at[1], at[2], at[3], at[4]
                list:AddImage(handle, iconMin, iconMax)
            end
            Icon(day, dayAt)
            Icon(weather, weatherAt, true)
            -- a double weather's second grows about the first's middle, out beside it
            if secondAt and secondAt[1] and weatherAt then
                local grow = iconScale * weatherScale - 1
                local dx = ((secondAt[1] + secondAt[3]) - (weatherAt[1] + weatherAt[3])) / 2 * grow
                secondAt = { secondAt[1] + dx, secondAt[2], secondAt[3] + dx, secondAt[4] }
            end
            Icon(weather, secondAt, true)
            for _, entry in ipairs(all or {}) do Icon(entry[1], entry[2], true) end
            list:PopClipRect()
        end
        hook.Capture() -- current window's text and icons, never a pointer passed from Lua
    end
    imgui.End()
    fonts.Pop(pushed)
    imgui.PopStyleVar(1)
end)
