-- What both of the settings' tabs are drawn with: the list of sounds to choose from, and the mark
-- at the end of a line that says what the line is for.
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
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

local function SoundCombo(id, chosen, key)
    widgets.PushControlWidth()
    if imgui.BeginCombo(id, chosen.sound) then
        local lists = Sorted(key)
        SoundChoices(lists.own, chosen)
        if #lists.own > 0 and #lists.rest > 0 then
            imgui.Separator()
        end
        SoundChoices(lists.rest, chosen)
        imgui.EndCombo()
    end
    widgets.PopControlWidth()
end

-- A mark at the end of a line that tells, when hovered, what the line is for. Every line's is at the
-- same place: a little past where an event's own line ends, at its Test button, which is the longest.
local lineEnd = 0  -- where the event's line ends, measured as it is drawn
local markGap = 8  -- between that and the mark

-- beside: true for a mark straight after what is before it, where the lines are not events'
local function Mark(text, beside)
    imgui.SameLine(beside and 0 or lineEnd + markGap)
    imgui.TextDisabled('(?)')
    tooltip.Hover(text)
end

-- Help for a whole row, held at the content area's right edge. Never overlap its controls;
-- a narrow settings window can scroll horizontally instead.
local function RightMark(text)
    imgui.SameLine(0, markGap)
    local x = imgui.GetCursorPosX()
    local room = imgui.GetContentRegionAvail()
    local width = imgui.CalcTextSize('(?)')
    imgui.SetCursorPosX(math.max(x, x + room - width))
    imgui.TextDisabled('(?)')
    tooltip.Hover(text)
end

-- An event's line ends here: where the marks go, and the controls under the line end
local function EndLine()
    imgui.SameLine(0, 0)
    lineEnd = imgui.GetCursorPosX()
end

return { SoundCombo = SoundCombo, Mark = Mark, RightMark = RightMark, EndLine = EndLine }
