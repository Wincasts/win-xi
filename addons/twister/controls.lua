-- What both of the settings' tabs are drawn with: the list of sounds to choose from, and the mark
-- at the end of a line that says what the line is for.
local imgui = require('imgui')
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
local function SoundCombo(id, chosen, key)
    imgui.SetNextItemWidth(170)
    if imgui.BeginCombo(id, chosen.sound) then
        local lists = Sorted(key)
        for _, list in ipairs({ lists.own, lists.rest }) do
            for _, file in ipairs(list) do
                if imgui.Selectable(file, file == chosen.sound) then
                    chosen.sound = file
                    shared.app:Save()
                    PlayFile(file)
                end
            end
            if list == lists.own and #list > 0 and #lists.rest > 0 then
                imgui.Separator()
            end
        end
        imgui.EndCombo()
    end
end

-- A mark at the end of a line that tells, when hovered, what the line is for. Every line's is at the
-- same place: a little past where an event's own line ends, at its Test button, which is the longest.
local lineEnd = 0  -- where the event's line ends, measured as it is drawn
local markGap = 8  -- between that and the mark

-- What a mark says is no wider than this sentence, and goes on to another line where it is longer
local widestSaid = 'A spell or weaponskill sounds as it begins, an ability as it is used.'
local saidWidth = nil -- how wide that is: measured once

-- beside: true for a mark straight after what is before it, where the lines are not events'
local function Mark(text, beside)
    imgui.SameLine(beside and 0 or lineEnd + markGap)
    imgui.TextDisabled('(?)')
    if imgui.IsItemHovered() then
        saidWidth = saidWidth or imgui.CalcTextSize(widestSaid)
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(saidWidth)
        imgui.Text(text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

-- The width of a control under an event's line that ends where that line does
local function ToLineEnd()
    return math.max(lineEnd - imgui.GetCursorPosX(), 100)
end

-- An event's line ends here: where the marks go, and the controls under the line end
local function EndLine()
    imgui.SameLine(0, 0)
    lineEnd = imgui.GetCursorPosX()
end

return { SoundCombo = SoundCombo, Mark = Mark, ToLineEnd = ToLineEnd, EndLine = EndLine }
