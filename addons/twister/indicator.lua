-- The indicator: a small window in the theme that says for a few seconds what a trigger was for.
local bit = require('bit')
local imgui = require('imgui')
local window = require('winxi.window')
local game = require('winxi.game')
local shared = require('shared')

-- sample: switched on by the Triggers tab each frame it is drawn. The indicator is then shown with a
-- line to see it by, so that it can be put where it is wanted.
local indicator = { sample = false }

-- The indicator: what a trigger was for, in words on the screen for a few seconds, as the chat log
-- says it. A line for each thing said, the first said at the top; what is said again while it is
-- still up stays up longer, and is not said twice.
local indicatorLines = { } -- { text, till }: what is up, and until when
local indicatorVerbs = { skill = 'readies', spell = 'starts casting', ability = 'uses' }

-- who: the mob by its own name, or nil for the trigger's kind of mob
local function Indicate(trigger, who)
    local options = shared.app.options
    if not options.showIndicator[1] then
        return
    end
    local text = ('%s %s %s.'):format(who or trigger.mob, indicatorVerbs[trigger.kind], trigger.name)
    local till = os.clock() + options.indicatorSeconds[1]
    for _, line in ipairs(indicatorLines) do
        if line.text == text then
            line.till = till
            return
        end
    end
    indicatorLines[#indicatorLines + 1] = { text = text, till = till }
end

-- A window as recast's is: the theme's, with nothing to it but its lines, as big as they are. It is
-- moved by dragging it, and does not take the keyboard or the controller from the game as it appears.
local indicatorName = 'twister.indicator'
local indicatorOpen = { true }
local indicatorFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings,
    ImGuiWindowFlags_NoFocusOnAppearing or 0, ImGuiWindowFlags_NoNav or 0)
local indicatorSpacing = { 8, 4 }
local indicatorPadding = { 0, 0 }
local indicatorSample = { { text = 'Mad Sheep readies Sheep Song.' } } -- what is shown with the Triggers tab open and nothing to say

local indicatorShown = nil -- the lines drawn this frame

local function DrawIndicatorContent()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, indicatorPadding)
    for _, line in ipairs(indicatorShown) do
        imgui.Text(line.text)
    end
    imgui.PopStyleVar()
    -- where the window is, kept in the settings
    local pos = shared.app.options.indicatorPos
    pos[1], pos[2] = imgui.GetWindowPos()
end

local function DrawIndicator(now, sample)
    for index = #indicatorLines, 1, -1 do
        if now >= indicatorLines[index].till then
            table.remove(indicatorLines, index)
        end
    end
    if not shared.app.options.showIndicator[1] then
        return
    end
    indicatorShown = #indicatorLines > 0 and indicatorLines or sample and indicatorSample or nil
    -- out of the way of what recast's window is: the chat log opened out, the map, an event, the
    -- interface hidden
    if indicatorShown == nil or game.IsChatExpanded() or game.IsMapOpen() or game.IsEventHappening() or game.IsInterfaceHidden() then
        return
    end

    imgui.SetNextWindowPos(shared.app.options.indicatorPos, ImGuiCond_FirstUseEver)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, indicatorSpacing)
    indicatorOpen[1] = true
    window.Plain(indicatorName, indicatorOpen, indicatorFlags, DrawIndicatorContent)
    imgui.PopStyleVar()
end

-- Once a frame, after the settings have been drawn
function indicator.Frame(now)
    if #indicatorLines > 0 or indicator.sample then
        DrawIndicator(now, indicator.sample)
    end
    indicator.sample = false
end

indicator.Indicate = Indicate

return indicator
