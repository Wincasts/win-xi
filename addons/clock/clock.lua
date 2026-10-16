addon.name = 'clock'
addon.author = 'win'
addon.version = '0.5.0'
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
local theme = require('winxi.theme')
local native = require('winxi.nativehud')
local fields = require('fields')
local icons = require('icons')

local hook = native.new(native.Clock)
local compass = native.new(native.Compass)
local time, timeError
local nextSample, line = 0, nil
local weekday = nil -- as the line was last read, for the day's icon
local sets, setsOpen = {}, false -- the icon sets, listed as the list is opened
local screenMin, screenMax, iconMin, iconMax = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
-- Where the game puts its weather icon, from its day icon's top left, and the weather icon's size:
-- learnt whenever it draws both. Until then, from Clock::Draw: the weather's at (x-68, y-42) and the
-- day's at (x-68, y+26), both sixteen of its units across, so 68 units above, as large.
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
local noPadding = { 0, 0 }
local place, pivot, room = { 0, 0 }, { 0, 0.5 }, { 0, 0 }

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
    nextSample, line = 0, nil
end

local app
local tick = { false }
local function Tip(text)
    if imgui.IsItemHovered() then imgui.SetTooltip(text) end
end
local function DrawSettings(options)
    if widgets.Header('Clock', true) then
        widgets.Label('Replace Game\'s Clock')
        if imgui.Checkbox('##clock.replace', options.replace) then
            if not options.replace[1] then hook.Stop() end
            app.save()
        end
        Tip('Writes the time, map grid, day, date and moon on one line where the game writes its clock.\nThe game\'s day and weather icons stay where it puts them.\nOff, the game\'s own clock comes back.')
        widgets.Label('Text Scale')
        imgui.SliderFloat('##clock.textScale', options.textScale, SCALE_MIN, SCALE_MAX, '%.2fx')
        if imgui.IsItemDeactivatedAfterEdit() then app.save() end
        Tip('How large the line is, against the theme\'s font size.')
        widgets.Label('Hide Compass')
        if imgui.Checkbox('##clock.hideCompass', options.hideCompass) then
            if not options.hideCompass[1] then compass.Stop() end
            app.save()
        end
        Tip('Stops the game drawing its compass and radar. The clock and its icons stay.')
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
        imgui.TextDisabled(timeError and ('Time unavailable: ' .. timeError) or hook.Status())
    end
    if widgets.Header('Line') then
        imgui.TextDisabled('Ticked fields are shown, in this order, from left to right.')
        local order, shown = options.order, options.shown
        for at, key in ipairs(order) do
            local field = fields.ByKey[key]
            local id = '##clock.field.' .. key
            tick[1] = shown[key] == true
            if imgui.Checkbox(field.label .. id, tick) then
                shown[key] = tick[1]
                nextSample = 0
                app.save()
            end
            Tip(field.tip)
            imgui.SameLine()
            imgui.BeginDisabled(at == 1)
            local up = imgui.SmallButton('Up' .. id)
            imgui.EndDisabled()
            imgui.SameLine()
            imgui.BeginDisabled(at == #order)
            local down = imgui.SmallButton('Down' .. id)
            imgui.EndDisabled()
            -- the list has changed under the loop: drawn as it is next frame
            if (up and fields.Move(order, at, -1)) or (down and fields.Move(order, at, 1)) then
                nextSample = 0
                app.save()
                break
            end
        end
    end
end

local function SayStatus()
    local options = app.options
    app:Say(not options.replace[1] and 'Off: the game\'s own clock is shown.' or
        timeError and ('Time unavailable: ' .. timeError) or hook.Status())
    app:Say(options.hideCompass[1] and ('Compass: ' .. compass.Status()) or 'Compass: shown.')
end

app = shell.New({
    defaults = (function()
        local order, shown = fields.Defaults()
        return T{ replace = T{ true }, hideCompass = T{ true }, textScale = T{ 1 }, iconSet = icons.None, order = order, shown = shown }
    end)(),
    configTitle = 'Clock Settings',
    command = '/clock',
    help = '/clock opens or closes the settings; /clock on, /clock off, /clock status.',
    drawSettings = DrawSettings,
    commands = {
        on = function(options) options.replace[1] = true; app.save() end,
        off = function(options) options.replace[1] = false; hook.Stop(); app.save() end,
        status = SayStatus,
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
        fields.Normalize(options.order, options.shown)
        if type(options.iconSet) ~= 'string' then options.iconSet = icons.None end
        icons.Forget()
        local scale = tonumber(options.textScale[1]) or 1
        options.textScale[1] = math.min(SCALE_MAX, math.max(SCALE_MIN, scale))
        Release()
    end,
})

ashita.events.register('load', 'clock_load', function()
    local ok, value = pcall(require, 'ffxi.time')
    if ok then time = value else timeError = tostring(value) end
    if timeError then print('[clock] Ashita ffxi.time unavailable: ' .. timeError) end
end)
ashita.events.register('unload', 'clock_unload', Release)

ashita.events.register('d3d_present', 'clock_present', function()
    app:BeginFrame()
    local options = app.options
    -- an empty compass, renewed each frame; the clock inside it is drawn all the same
    if options.hideCompass[1] then compass.Begin() else compass.Stop() end
    if not options.replace[1] or not time then hook.Stop(); return end

    local now = os.clock()
    if now >= nextSample then
        nextSample = now + 0.25
        local ok, value = pcall(function()
            local weather = options.shown.weather and WeatherName() or nil
            local context = fields.Context(time, hook.Grid(), weather)
            weekday = time.get_game_weekday(context.raw)
            return fields.Line(context, options.order, options.shown)
        end)
        if not ok then
            timeError, line = tostring(value), nil
            hook.Stop()
            return
        end
        line, timeError = value, nil
    end
    -- where the game writes its clock: until uihook has seen it, the game's own is left alone
    local left, top, _, bottom = hook.ClockRect()
    if not line or not left then hook.Stop(); return end
    if not hook.Begin() then return end

    -- the set's icons where it has them, each where the game draws its own; the game's elsewhere
    local set = type(options.iconSet) == 'string' and options.iconSet or icons.None
    local day = icons.Day(set, weekday)
    local weather, double, gameDraws = icons.Weather(set, hook.Weather())
    local dayAt = { hook.IconRect(native.DayIcon) }
    local gameWeather = { hook.IconRect(native.WeatherIcon) }
    if dayAt[1] and gameWeather[1] then
        weatherSlot = { gameWeather[1] - dayAt[1], gameWeather[2] - dayAt[2], gameWeather[3] - gameWeather[1], gameWeather[4] - gameWeather[2] }
    end
    local weatherAt, secondAt
    if weather and gameDraws then
        -- in place of the game's icon, once uihook has seen where it goes
        weatherAt = gameWeather[1] and gameWeather or nil
        secondAt = double and { hook.IconRect(native.SecondWeatherIcon) } or nil
    elseif weather then
        -- a sky the game draws no icon for: where its weather icon would be
        weatherAt = SkySlot(dayAt)
    end
    if not dayAt[1] then day = nil end
    if not weatherAt then weather = nil end
    hook.HideIcons((day and native.HideDay or 0) + (weather and gameDraws and native.HideWeather or 0))

    -- the line's left on the game's, its middle on the game's middle, growing right
    place[1], place[2] = left, (top + bottom) / 2
    imgui.SetNextWindowPos(place, ImGuiCond_Always, pivot)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, noPadding)
    local pushed = fonts.Push()
    if imgui.Begin('clock.native', { true }, flags) then
        local scale = options.textScale[1]
        imgui.PushFont(nil, imgui.GetFontSize() * scale)
        local x, y = imgui.GetCursorScreenPos()
        room[1], room[2] = imgui.CalcTextSize(line)
        imgui.Dummy(room)
        -- the dark edge winxi writes over the game with, thicker as the text grows
        outlined.Draw(imgui.GetWindowDrawList(), x, y, theme.Get().TextColor, line, scale >= 1.75 and 2 or 1)
        imgui.PopFont()
        if day or weather then
            -- the icons are away from the line: drawn unclipped by the window
            local list = imgui.GetWindowDrawList()
            local display = imgui.GetIO().DisplaySize
            screenMax[1], screenMax[2] = display.x or display[1] or 0, display.y or display[2] or 0
            list:PushClipRect(screenMin, screenMax, false)
            local function Icon(handle, at)
                if not handle or not at or not at[1] then return end
                iconMin[1], iconMin[2], iconMax[1], iconMax[2] = at[1], at[2], at[3], at[4]
                list:AddImage(handle, iconMin, iconMax)
            end
            Icon(day, dayAt)
            Icon(weather, weatherAt)
            Icon(weather, secondAt)
            list:PopClipRect()
        end
        hook.Capture() -- current window's text, never a pointer passed from Lua
    end
    imgui.End()
    fonts.Pop(pushed)
    imgui.PopStyleVar(1)
end)
