-- What both of the settings' tabs are drawn with: the list of sounds to choose from, and the described
-- row that holds it with a Test button beside it (winxi.widgets).
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local shared = require('shared')
local playing = require('playing')

local soundFolder, PlayFile = playing.folder, playing.PlayFile

-- The wav files in the sounds folder, looked for again every few seconds while the settings are open
local files, filesRead = { }, -10

local function Files()
    local now = os.clock()
    if now - filesRead > 3 then
        filesRead = now
        files = { }
        local found = ashita.fs.get_directory(soundFolder, '.*\\.wav')
        if type(found) == 'table' then
            for _, name in pairs(found) do
                files[#files + 1] = name
            end
            table.sort(files)
        end
    end
    return files
end

-- The sounds in two lists for whatever key names (an event, or 'trigger'): its own, which are the
-- ones made for it (its two voices and its two tones), and the rest. Put together once for
-- each key, and again when the files have been looked for again.
local sorted = { files = nil }

local function Sorted(key)
    local all = Files()
    if sorted.files ~= all then
        sorted = { files = all }
    end
    local lists = sorted[key]
    if lists == nil then
        lists = { own = { }, rest = { } }
        local own = { ['voicef-' .. key .. '.wav'] = 1, ['voicem-' .. key .. '.wav'] = 2, ['tone-' .. key .. '1.wav'] = 3, ['tone-' .. key .. '2.wav'] = 4 }
        for _, file in ipairs(all) do
            local list = own[file] and lists.own or lists.rest
            list[#list + 1] = file
        end
        table.sort(lists.own, function(a, b) return own[a] < own[b] end)
        sorted[key] = lists
    end
    return lists
end

-- A list of sounds to choose from, those made for key first and the rest under a line. The one
-- chosen is played, and kept as the sound of chosen: an event's settings, or a trigger.
local function SoundChoices(files, chosen)
    for _, file in ipairs(files) do
        if imgui.Selectable(file, file == chosen.sound) then
            if chosen.sound ~= file then
                chosen.sound = file
                shared.app:Save()
            end
            PlayFile(file)
        end
    end
end

-- The list itself: width wide where one is given (a table's cell), else as wide as the row has set
local function SoundCombo(id, chosen, key, width)
    if width ~= nil then
        imgui.SetNextItemWidth(width)
    end
    if imgui.BeginCombo(id, chosen.sound) then
        local lists = Sorted(key)
        SoundChoices(lists.own, chosen)
        if #lists.own > 0 and #lists.rest > 0 then
            imgui.Separator()
        end
        SoundChoices(lists.rest, chosen)
        imgui.EndCombo()
    end
end

-- A described row holding a sound: the list takes the row's control column but for the Test button
-- at its right end, which reads testId. Returns whether Test was pressed.
local testWord = 'Test'

local function SoundRow(name, sentence, id, chosen, key, testId, spec)
    widgets.BeginRow(name, sentence, spec)
    local style = imgui.GetStyle()
    local padding = (style and style.FramePadding and style.FramePadding.x) or 4
    local spacing = (style and style.ItemSpacing and style.ItemSpacing.x) or 8
    local button = (imgui.CalcTextSize(testWord) or 0) + 2 * padding
    -- the column's width, as the row pushed it; where imgui does not say, the rows' own measure
    local column = imgui.CalcItemWidth ~= nil and imgui.CalcItemWidth() or nil
    if type(column) ~= 'number' then
        local _, textHeight = imgui.CalcTextSize('A')
        column = (textHeight or 14) * widgets.RowControlWidth
    end
    SoundCombo(id, chosen, key, math.max(column - button - spacing, button))
    imgui.SameLine()
    local pressed = imgui.Button(testId)
    widgets.EndRow()
    return pressed
end

return { SoundCombo = SoundCombo, SoundRow = SoundRow }
