-- The box: a small window in the theme that says for a few seconds what the enemies about are doing,
-- a line for each. It is trigger's indicator, taken further: a line is known by whose it is and what
-- kind of thing it says, so that the end of a cast takes the place of its beginning rather than
-- joining it. It fades in as it appears and out as it goes, as winxi's windows do.
local bit = require('bit')
local imgui = require('imgui')
local window = require('winxi.window')
local text = require('winxi.text')
local fade = require('winxi.fade')
local anchor = require('winxi.anchor')
local game = require('winxi.game')
local shared = require('shared')

-- sample: switched on by the settings each frame they are drawn. The box is then shown with a line
-- of each kind to see it by, so that it can be put where it is wanted.
local box = { sample = false }

-- The side the window grows from, which stays where it is as what is said gets longer or shorter:
-- the choices there are, what winxi.anchor calls each, and how far along the window that side is.
-- The lines are set to that side too.
box.Grows = { 'Left', 'Center', 'Right' }
box.DefaultGrow = 'Left'
local growModes = { Left = 'TopLeft', Center = 'TopCenter', Right = 'TopRight' }
local growShare = { Left = 0, Center = 0.5, Right = 1 }

-- Where the newest line is: at the bottom, the lines in the order they were said, or at the top, in
-- the order the other way about, the newest always in the same place under the top edge
box.Newests = { 'Bottom', 'Top' }
box.DefaultNewest = 'Bottom'

-- The lines up, the first said at the top: { key, text, color, till }. key is whose line it is and of
-- what kind (reader.lua's), or nil for one that stands alone. A line said again while it is up stays
-- up longer, and is not said twice; a line of the same key takes the old one's place. The last lines
-- up stay in the list after their time, for the window to fade out with: they go once it has.
local lines = { }

-- key: whose line, and of what kind, or nil. color: a table of four, kept hold of (the setting's own)
function box.Say(key, words, color, seconds)
    local till = os.clock() + seconds
    for _, line in ipairs(lines) do
        if (key ~= nil and line.key == key) or line.text == words then
            line.text, line.color, line.till = words, color, till
            return
        end
    end
    lines[#lines + 1] = { key = key, text = words, color = color, till = till }
    -- no more lines than wanted: the oldest go
    local most = shared.app.options.maxLines[1]
    while #lines > most do
        table.remove(lines, 1)
    end
end

-- How many lines are up and still in their time
function box.Live()
    local now, live = os.clock(), 0
    for _, line in ipairs(lines) do
        if now < line.till then
            live = live + 1
        end
    end
    return live
end

local function ForgetLines()
    for index = #lines, 1, -1 do
        lines[index] = nil
    end
end
box.Forget = ForgetLines

-- A window as recast's is: the theme's, with nothing to it but its lines, as big as they are. It is
-- moved by dragging it, and does not take the keyboard or the controller from the game as it appears.
local windowName = 'mobcast.box'
local windowOpen = { true }
local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings,
    ImGuiWindowFlags_NoFocusOnAppearing or 0, ImGuiWindowFlags_NoNav or 0)
local windowSpacing = { 8, 4 }
local windowPadding = { 0, 0 }
local windowStyle = { alpha = 1, title = 'Mobcast' }

-- What is shown with the settings open and nothing to say: a line of each kind, in its colour
local sampleLines = {
    { text = 'Mad Sheep readies Sheep Song.', kind = 'skill' },
    { text = 'Goblin Smithy starts casting Fire on Tester.', kind = 'spell' },
    { text = 'Orcish Fighter uses Mighty Strikes.', kind = 'ability' },
}
local sampleColors = { } -- a kind -> the setting of its colour
for _, kind in ipairs(shared.kinds) do
    sampleColors[kind.key] = kind.color
end

local shown = nil -- the lines drawn this frame, and what it fades out with after

local function DrawContent()
    -- each line to the side the window grows from: as far in as it is shorter than the longest
    local options = shared.app.options
    local share = growShare[options.grow] or 0
    local left, widest = imgui.GetCursorPosX(), 0
    if share > 0 then
        for _, line in ipairs(shown) do
            widest = math.max(widest, (imgui.CalcTextSize(line.text)))
        end
    end
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, windowPadding)
    local first, last, step = 1, #shown, 1
    if options.newest == 'Top' then
        first, last, step = #shown, 1, -1
    end
    for index = first, last, step do
        local line = shown[index]
        if share > 0 then
            imgui.SetCursorPosX(left + (widest - imgui.CalcTextSize(line.text)) * share)
        end
        text.Outlined(line.text, line.color or (line.kind and options[sampleColors[line.kind]]))
    end
    imgui.PopStyleVar()
end

local function Draw(now, sample)
    -- a line whose time is up goes, unless every line's is: those stay, to fade out
    local live = 0
    for _, line in ipairs(lines) do
        if now < line.till then
            live = live + 1
        end
    end
    if live > 0 then
        for index = #lines, 1, -1 do
            if now >= lines[index].till then
                table.remove(lines, index)
            end
        end
    elseif sample then
        -- the sample is what is shown with nothing to say
        ForgetLines()
    end
    if #lines > 0 then
        shown = lines
    elseif sample then
        shown = sampleLines
    end
    -- out of the way of what recast's window is: the chat log opened out, the map, an event, the
    -- interface hidden
    local options = shared.app.options
    if shown == nil or game.IsHidden(options.hide) then
        return
    end

    -- wanted while there is something to say: after that it is drawn until it has faded out
    local wanted = live > 0 or sample
    local alpha = options.fadeInOut[1] and fade.Presence(windowName, wanted) or (wanted and 1 or 0)
    if alpha <= 0.01 then
        if not wanted then
            ForgetLines()
            shown = nil
        end
        return
    end

    -- where it is, kept in the settings, is where the side it grows from is: the left, the middle
    -- or the right of its top edge. winxi.anchor holds it there, told of it the first time.
    local pos = options.pos
    local mode = growModes[options.grow] or growModes[box.DefaultGrow]
    if anchor.Point(windowName) == nil then
        anchor.Set(windowName, mode, pos[1], pos[2])
    end

    imgui.SetNextWindowPos(pos, ImGuiCond_FirstUseEver)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, windowSpacing)
    windowOpen[1] = true
    windowStyle.alpha, windowStyle.growFrom = alpha, mode
    local size = tonumber(options.fontSize[1]) or 0
    windowStyle.fontSize = size > 0 and size or nil
    windowStyle.locked = options.locked[1] and true or nil
    windowStyle.clickThrough = windowStyle.locked
    window.Plain(windowName, windowOpen, windowFlags, DrawContent, windowStyle)
    imgui.PopStyleVar()

    -- dragged, or grown from another side now, it is somewhere else
    local x, y = anchor.Point(windowName)
    if x ~= nil then
        pos[1], pos[2] = x, y
    end
end

-- Other settings have been loaded: where the box is, is asked of them again
function box.Reset()
    anchor.Reset(windowName)
end

-- The sample lines, said as if they were real: for /mobcast test and the settings' Test button
function box.Test()
    local options = shared.app.options
    for _, line in ipairs(sampleLines) do
        box.Say(nil, line.text, options[sampleColors[line.kind]], options.seconds[1])
    end
end

-- Once a frame, after the settings have been drawn
function box.Frame(now)
    if #lines > 0 or box.sample or shown ~= nil then
        Draw(now, box.sample)
    end
    box.sample = false
end

return box
