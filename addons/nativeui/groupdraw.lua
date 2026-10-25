-- The windows the game stacks over its chat log drawn in the winxi look, from uihook's mirror of them (groupmirror):
-- the game's own stay open and do everything they do, unseen underneath (the controller moves their cursor, the mouse
-- clicks them where they are drawn, Confirm and Cancel are theirs), and each is drawn again here as a winxi panel only
-- as large as what it holds, its button bars square winxi buttons (the one the cursor is on in the Highlight Color),
-- its words in the theme's font, its icons from the game's own textures, the game's hand hanging over the box's left
-- edge at the row the cursor is on, and the scrollbar. The menus whose words are pictures (the command
-- menu) spell them a letter at a time from the game's menu font; those are read back as words. Drawn from the
-- archived menus addon (0.13), for this group alone.
--
--   local view = require('groupdraw')
--   view.Frame(on)    each frame: on, the group asked for and drawn; off, given back to the game
--   view.Stop()       unloaded: given back to the game
--   view.Status()     a line for the settings
local imgui = require('imgui')
local bit = require('bit')
local theme = require('winxi.theme')
local frame = require('winxi.frame')
local fonts = require('winxi.fonts')
local text = require('winxi.text')
local cursorArt = require('winxi.cursor')
local tabs = require('winxi.tabs')
local groupmirror = require('groupmirror')

local view = {}
local mirror = groupmirror.new()

-- A window whose place, or whose text's, could not be measured is left to the game for a while, so it is never
-- unseen or half drawn: its name -> the time until which it is the game's, and why. One left to it is taken again
-- once it has been measured whole for MEASURED_SECONDS.
local nativeUntil, nativeWhy, measuredSince = {}, {}, {}
local FALLBACK_SECONDS = 2
local MEASURED_SECONDS = 0.25

local function GiveBack(name, why, now)
    nativeUntil[name] = now + FALLBACK_SECONDS
    nativeWhy[name] = why
end
-- How much of a window's text has no measured place: printed, but not with the draws uihook measures
local function Unplaced(window)
    local missing = 0
    for _, run in ipairs(window.runs) do
        if not run.rect and run.text ~= '' then missing = missing + 1 end
    end
    return missing
end
-- How much of its text was printed off the screen (into a picture of the game's), where drawn it would not be seen
local function OffScreen(window, width, height)
    local off = 0
    for _, run in ipairs(window.runs) do
        local r = run.rect
        if r and run.text ~= '' and (r[3] <= 0 or r[4] <= 0 or r[1] >= width or r[2] >= height) then off = off + 1 end
    end
    return off
end

local white = { 1, 1, 1, 1 }
-- The game's plain text colour (0x80808080) is the theme's; any other, the game's own (an item's rarity)
local function TextColor(color)
    if color[1] == 1 and color[2] == 1 and color[3] == 1 then
        local themed = theme.Get().TextColor
        return { themed[1], themed[2], themed[3], themed[4] * color[4] }
    end
    return color
end

local function Width(r) return r[3] - r[1] end
local function Height(r) return r[4] - r[2] end

-- The row the game's cursor is on: the run or word whose middle is nearest the cursor's
local function CursorRow(window, words)
    local c = window.cursor
    if not c then return nil end
    local middle, best, row = (c[2] + c[4]) / 2, math.huge, nil
    local function Near(r)
        local distance = math.abs((r[2] + r[4]) / 2 - middle)
        if distance < best then best, row = distance, r end
    end
    for _, run in ipairs(window.runs) do if run.rect then Near(run.rect) end end
    for _, word in ipairs(words) do Near(word.rect) end
    return best < 12 and row or nil
end

-- A line of the window's text, as tall as the game's letters mostly are: the middle of its runs' heights, so neither
-- text nor the hand is drawn larger than a line where the game measures something taller
local function LineHeight(window, words)
    local heights = {}
    for _, run in ipairs(window.runs) do
        if run.rect and run.text ~= '' then heights[#heights + 1] = Height(run.rect) end
    end
    for _, word in ipairs(words) do heights[#heights + 1] = word.tall end
    if #heights == 0 then return nil end
    table.sort(heights)
    return heights[math.floor((#heights + 1) / 2)]
end
local LINE_SLACK = 1.5 -- how much taller than the window's line a run of its text may be drawn

-- How far the box reaches past what it holds, in pixels: only enough to frame its buttons, the hand hanging over its
-- left edge
local BOX_PAD = 4
-- The game's button bars: a window's elements that are no letter, at least twice as wide as they are tall and as tall
-- as a small letter; each { rect, lit } (lit: tinted by the game, the cursor's). The rest of its art (a submenu's
-- arrow, an icon) is drawn as the game's.
local BUTTON_LEAST = 8
local function Buttons(window, spelled)
    local buttons, used = {}, {}
    for i, quad in ipairs(window.quads) do
        local q = quad.rect
        if not spelled[i] and quad.phase == groupmirror.Element and Height(q) >= BUTTON_LEAST and Width(q) >= Height(q) * 2 then
            local c = quad.color
            -- lit: warm, as the game tints the one the cursor is on (613C20, against the blue-grey 616180 of the rest)
            buttons[#buttons + 1] = { rect = q, lit = c[1] > c[3] + 0.05, faint = c[4] < 0.5 }
            used[i] = true
        end
    end
    return buttons, used
end
-- What the window holds: its buttons, words, text, art and scrollbar, as one rectangle; nil where it holds nothing
local function Holds(window, buttons, words, spelled, used)
    local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
    local function Take(q) if q then l, t, r, b = math.min(l, q[1]), math.min(t, q[2]), math.max(r, q[3]), math.max(b, q[4]) end end
    for _, button in ipairs(buttons) do Take(button.rect) end
    for _, word in ipairs(words) do Take(word.rect) end
    for _, run in ipairs(window.runs) do if run.text ~= '' then Take(run.rect) end end
    for i, quad in ipairs(window.quads) do if not spelled[i] and not used[i] then Take(quad.rect) end end
    if window.scroll and window.scrollCount > window.scrollPage then Take(window.scroll) end
    if l > r or t > b then return nil end
    return { l, t, r, b }
end
-- The button a place is on (its middle, upright), or nil
local function ButtonAt(buttons, r)
    local y = (r[2] + r[4]) / 2
    for _, button in ipairs(buttons) do
        local q = button.rect
        if y >= q[2] and y <= q[4] and r[1] < q[3] and r[3] > q[1] then return button end
    end
end

-- A square button in winxi's look: the theme's button colour (its border colour, faint), the Highlight Color where
-- the cursor is on it, the theme's tab style over it
local function DrawButton(list, button)
    local q = button.rect
    local themed = theme.Get()
    local color
    if button.lit then
        color = themed.HighlightColor
    else
        local border = themed.BorderColor
        color = { border[1], border[2], border[3], border[4] * (button.faint and 0.12 or 0.25) }
    end
    list:AddRectFilled({ q[1], q[2] }, { q[3], q[4] }, imgui.GetColorU32(color), 0)
    tabs.Over(list, q[1], q[2], q[3], q[4], 0)
end

local function DrawContents(list, window, box, layout)
    local words, spelled, buttons, used = layout.words, layout.spelled, layout.buttons, layout.used
    local line = LineHeight(window, words)
    local most = math.min(Height(box), line and line * LINE_SLACK or math.huge)
    -- the row the cursor is on, where it is no button: lit across the box, under everything else
    local row = layout.row
    if row and not layout.button then
        list:AddRectFilled({ box[1] + 2, row[2] - 1 }, { box[3] - 2, row[4] + 1 }, imgui.GetColorU32(theme.Get().HighlightColor), 0)
    end
    for _, button in ipairs(buttons) do DrawButton(list, button) end
    -- the game's art: the contents' icons as the game drew them, the other elements (a submenu's arrow) in their own
    -- colours, faint where the game greys one
    for i, quad in ipairs(window.quads) do
        if not spelled[i] and not used[i] and quad.texture then
            local q, uv = quad.rect, quad.uv
            local color = quad.phase == groupmirror.Element and { 1, 1, 1, quad.color[4] } or quad.color
            list:AddImage(quad.texture, { q[1], q[2] }, { q[3], q[4] }, { uv[1], uv[2] }, { uv[3], uv[4] }, imgui.GetColorU32(color))
        end
    end
    -- the words spelled from the game's fonts, in the theme's: on a button, upright in its middle
    for _, word in ipairs(words) do
        local t = word.rect
        local size = math.max(8, math.floor(math.min(word.tall, most) + 0.5))
        local on = ButtonAt(buttons, t)
        local top = on and (on.rect[2] + on.rect[4] - size) / 2 or t[2] + (Height(t) - size) / 2
        imgui.PushFont(nil, size)
        text.Draw(list, t[1], top, TextColor({ 1, 1, 1, word.color[4] }), word.text)
        imgui.PopFont()
    end
    -- the text, each run where the game printed it, in the theme's font at the height of the game's letters
    for _, run in ipairs(window.runs) do
        local t = run.rect
        if t and run.text ~= '' then
            local size = math.max(8, math.floor(math.min(Height(t), most) + 0.5))
            imgui.PushFont(nil, size)
            text.Draw(list, t[1], t[2] + (Height(t) - size) / 2, TextColor(run.color), run.text)
            imgui.PopFont()
        end
    end
    -- the scrollbar: the rows shown against them all, where there are more than fit
    local s = window.scroll
    if s and window.scrollCount > window.scrollPage and window.scrollCount > 0 then
        local track = theme.Get().BorderColor or white
        local thumb = theme.Get().HighlightColor
        local width = math.max(3, math.min(6, Width(s)))
        local left = s[3] - width
        list:AddRectFilled({ left, s[2] }, { s[3], s[4] }, imgui.GetColorU32({ track[1], track[2], track[3], 0.25 }), 0)
        local top = s[2] + Height(s) * window.scrollTop / window.scrollCount
        local bottom = s[2] + Height(s) * math.min(1, (window.scrollTop + window.scrollPage) / window.scrollCount)
        list:AddRectFilled({ left, top }, { s[3], bottom }, imgui.GetColorU32({ thumb[1], thumb[2], thumb[3], 1 }), 0)
    end
end

-- The game's hand at the row the cursor is on, its fingertip (the art's pivot) at the row's left edge, so that it
-- hangs out over the box's left edge; as tall as the row, upright in its middle. Where no row is found, its fingertip
-- where the game's hand pointed.
local function DrawHand(list, window, layout)
    local c = window.cursor
    if not c then return end
    local handle, art = cursorArt.Get()
    if not handle or not art.corners then return end
    local row = layout.button and layout.button.rect or layout.row
    local tall = row and Height(row) or math.min(Height(c), 18)
    local line = LineHeight(window, layout.words)
    if line and not layout.button then tall = math.min(tall, line + 2) end
    local x = row and row[1] - 1 or c[3]
    local middle = row and (row[2] + row[4]) / 2 or (c[2] + c[4]) / 2
    local corners, scale = art.corners, tall / art[6]
    local pivotY = middle - (corners[8] + corners[2]) * scale / 2
    list:AddImage(handle, { x + corners[1] * scale, pivotY + corners[2] * scale }, { x + corners[7] * scale, pivotY + corners[8] * scale },
        { art[1], art[2] }, { art[3], art[4] }, imgui.GetColorU32(white))
end

-- A window's letters read back as words: its title (the game's serif letters), joined, for the frame's edge; the
-- rest, its labels; and the quads read, not to be drawn as art
local function Spelled(window)
    local words, spelled = groupmirror.Words(window.quads)
    local title, labels = {}, {}
    for _, word in ipairs(words) do
        if word.font == 'title' then title[#title + 1] = word.text else labels[#labels + 1] = word end
    end
    return #title > 0 and table.concat(title, ' ') or nil, labels, spelled
end

-- The window laid out: its words, buttons, the row the cursor is on (the button lit, else the run or word nearest the
-- game's hand, else the game's own highlight where it is the shape of a row), and its box, only as large as what it
-- holds and BOX_PAD round it (the game's frame where it holds nothing measured)
local function Layout(window)
    local title, words, spelled = Spelled(window)
    local buttons, used = Buttons(window, spelled)
    local layout = { title = title, words = words, spelled = spelled, buttons = buttons, used = used }
    for _, button in ipairs(buttons) do if button.lit then layout.button = button end end
    if not layout.button and window.cursor then layout.button = ButtonAt(buttons, window.cursor) end
    if not layout.button then
        layout.row = CursorRow(window, words)
        local lit = window.selection
        if not layout.row and lit and Height(lit) < Height(window.rect) / 2 then layout.row = lit end
    end
    local holds = Holds(window, buttons, words, spelled, used)
    layout.box = holds and { holds[1] - BOX_PAD, holds[2] - BOX_PAD, holds[3] + BOX_PAD, holds[4] + BOX_PAD } or window.rect
    return layout
end

local function DrawWindow(list, window)
    local layout = Layout(window)
    local box = layout.box
    frame.Draw({ left = box[1], top = box[2], width = Width(box), height = Height(box) }, function()
        list:PushClipRect({ box[1] - 24, box[2] - 24 }, { box[3] + 24, box[4] + 24 }, true)
        local ok, err = pcall(DrawContents, list, window, box, layout)
        list:PopClipRect()
        if not ok then error(err, 0) end
    end, { title = layout.title })
    -- over the frame's border, which it hangs across
    DrawHand(list, window, layout)
end

local hostFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoBackground,
    ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoBringToFrontOnFocus,
    ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoMove)

local function Draw()
    local now = os.clock()
    local kept = {}
    for name, untilTime in pairs(nativeUntil) do
        if now < untilTime then kept[#kept + 1] = name end
    end
    if not mirror.Request(kept) then return end
    local display = imgui.GetIO().DisplaySize
    local width, height = display.x or display[1], display.y or display[2]
    local windows = mirror.Windows(width, height)
    if not windows or #windows == 0 then return end
    imgui.SetNextWindowPos({ 0, 0 })
    imgui.SetNextWindowSize({ width, height })
    local pushed = fonts.Push()
    -- under every other window of imgui's, as the game's menus are
    if imgui.Begin('##nativeui.group', true, hostFlags) then
        local list = imgui.GetWindowDrawList()
        for _, window in ipairs(windows) do
            local name = window.name
            if window.kept then
                -- the game's for now: taken again once measured whole for a while
                if window.rect and Unplaced(window) == 0 and OffScreen(window, width, height) == 0 then
                    measuredSince[name] = measuredSince[name] or now
                    if now - measuredSince[name] >= MEASURED_SECONDS then nativeUntil[name], measuredSince[name] = now, nil end
                else
                    measuredSince[name] = nil
                end
            elseif not window.rect then
                GiveBack(name, 'its place could not be measured', now)
            elseif Unplaced(window) > 0 then
                GiveBack(name, ('%d of its %d pieces of text could not be placed'):format(Unplaced(window), #window.runs), now)
            elseif OffScreen(window, width, height) > 0 then
                GiveBack(name, 'some of its text was printed off the screen', now)
            else
                DrawWindow(list, window)
            end
        end
    end
    imgui.End()
    fonts.Pop(pushed)
end

-- After an error the game draws the group for a while, the error said once
local failedUntil = 0
function view.Frame(on)
    if not on or os.clock() < failedUntil then
        mirror.Stop()
        return
    end
    local ok, err = pcall(Draw)
    if not ok then
        mirror.Stop()
        failedUntil = os.clock() + 10
        print(('\30\68[nativeui]\30\01 %s; the game draws the menus over the chat log for ten seconds.'):format(tostring(err)))
    end
end

function view.Stop() mirror.Stop() end

-- A line for the settings: what the mirror is doing, and which windows were left to the game lately, and why
function view.Status()
    local lines = { mirror.Status() }
    local now = os.clock()
    for name, untilTime in pairs(nativeUntil) do
        if now < untilTime + 10 then lines[#lines + 1] = ('%s was left to the game: %s.'):format(name, nativeWhy[name] or 'not measured') end
    end
    return table.concat(lines, ' ')
end

return view
