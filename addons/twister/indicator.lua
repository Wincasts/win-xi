-- The indicator: a small window in the theme that says for a few seconds what a trigger was for. It
-- fades in as it appears and out as it goes, as winxi's windows do.
local bit = require('bit')
local imgui = require('imgui')
local window = require('winxi.window')
local fade = require('winxi.fade')
local anchor = require('winxi.anchor')
local game = require('winxi.game')
local shared = require('shared')

-- sample: switched on by the Triggers tab each frame it is drawn. The indicator is then shown with a
-- line to see it by, so that it can be put where it is wanted.
local indicator = { sample = false }

-- The side the window grows from, which stays where it is as what is said gets longer or shorter:
-- the choices there are, what winxi.anchor calls each, and how far along the window that side is.
-- The lines are set to that side too.
indicator.Grows = { 'Left', 'Center', 'Right' }
indicator.DefaultGrow = 'Left'
local growModes = { Left = 'TopLeft', Center = 'TopCenter', Right = 'TopRight' }
local growShare = { Left = 0, Center = 0.5, Right = 1 }

-- The indicator: what a trigger was for, in words on the screen for a few seconds, as the chat log
-- says it. A line for each thing said, the first said at the top; what is said again while it is
-- still up stays up longer, and is not said twice. The last lines up stay in the list after their
-- time, for the window to fade out with: they go once it has.
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

local indicatorShown = nil -- the lines drawn this frame, and what it fades out with after
local indicatorStyle = { alpha = 1 }

local function ForgetLines()
    for index = #indicatorLines, 1, -1 do
        indicatorLines[index] = nil
    end
end

local function DrawIndicatorContent()
    -- each line to the side the window grows from: as far in as it is shorter than the longest
    local share = growShare[shared.app.options.indicatorGrow] or 0
    local left, widest = imgui.GetCursorPosX(), 0
    if share > 0 then
        for _, line in ipairs(indicatorShown) do
            widest = math.max(widest, (imgui.CalcTextSize(line.text)))
        end
    end
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, indicatorPadding)
    for _, line in ipairs(indicatorShown) do
        if share > 0 then
            imgui.SetCursorPosX(left + (widest - imgui.CalcTextSize(line.text)) * share)
        end
        imgui.Text(line.text)
    end
    imgui.PopStyleVar()
end

local function DrawIndicator(now, sample)
    -- a line whose time is up goes, unless every line's is: those stay, to fade out
    local live = 0
    for _, line in ipairs(indicatorLines) do
        if now < line.till then
            live = live + 1
        end
    end
    if live > 0 then
        for index = #indicatorLines, 1, -1 do
            if now >= indicatorLines[index].till then
                table.remove(indicatorLines, index)
            end
        end
    elseif sample then
        -- the sample is what is shown with nothing to say
        ForgetLines()
    end
    if not shared.app.options.showIndicator[1] then
        ForgetLines()
        indicatorShown = nil
        return
    end
    if #indicatorLines > 0 then
        indicatorShown = indicatorLines
    elseif sample then
        indicatorShown = indicatorSample
    end
    -- out of the way of what recast's window is: the chat log opened out, the map, an event, the
    -- interface hidden
    if indicatorShown == nil or game.IsChatExpanded() or game.IsMapOpen() or game.IsEventHappening() or game.IsInterfaceHidden() then
        return
    end

    -- wanted while there is something to say: after that it is drawn until it has faded out
    local wanted = live > 0 or sample
    local alpha = fade.Presence(indicatorName, wanted)
    if alpha <= 0.01 then
        if not wanted then
            ForgetLines()
            indicatorShown = nil
        end
        return
    end

    -- where it is, kept in the settings, is where the side it grows from is: the left, the middle
    -- or the right of its top edge. winxi.anchor holds it there, told of it the first time.
    local options = shared.app.options
    local pos = options.indicatorPos
    local mode = growModes[options.indicatorGrow] or growModes[indicator.DefaultGrow]
    if anchor.Point(indicatorName) == nil then
        anchor.Set(indicatorName, mode, pos[1], pos[2])
    end

    imgui.SetNextWindowPos(pos, ImGuiCond_FirstUseEver)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, indicatorSpacing)
    indicatorOpen[1] = true
    indicatorStyle.alpha, indicatorStyle.growFrom = alpha, mode
    window.Plain(indicatorName, indicatorOpen, indicatorFlags, DrawIndicatorContent, indicatorStyle)
    imgui.PopStyleVar()

    -- dragged, or grown from another side now, it is somewhere else
    local x, y = anchor.Point(indicatorName)
    if x ~= nil then
        pos[1], pos[2] = x, y
    end
end

-- Other settings have been loaded: where the indicator is, is asked of them again
function indicator.Reset()
    anchor.Reset(indicatorName)
end

-- Once a frame, after the settings have been drawn
function indicator.Frame(now)
    if #indicatorLines > 0 or indicator.sample or indicatorShown ~= nil then
        DrawIndicator(now, indicator.sample)
    end
    indicator.sample = false
end

indicator.Indicate = Indicate

return indicator
