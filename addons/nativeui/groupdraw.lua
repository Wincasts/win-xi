-- The windows the game stacks over its chat log drawn in the winxi look, from uihook's mirror of them (groupmirror):
-- the game's own stay open and do everything they do, unseen underneath (the controller moves their cursor, the mouse
-- clicks them where they are drawn, Confirm and Cancel are theirs), and each is drawn again here as a winxi panel with
-- its words in the theme's font, its icons from the game's own textures, the row the cursor is on lit in the Highlight
-- Color, the game's hand where the game put it, and the scrollbar. The menus whose words are pictures (the command
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

local function DrawContents(list, window, words, spelled)
    local r = window.rect
    local pad = 4
    local line = LineHeight(window, words)
    local most = math.min(Height(r), line and line * LINE_SLACK or math.huge)
    -- the row the cursor is on, lit across the window, under everything else: found from the cursor, or the game's
    -- own highlight where that is the shape of a row
    local row = CursorRow(window, words)
    local lit = window.selection
    if not row and lit and Height(lit) < Height(r) / 2 then row = lit end
    if row then
        local left, right = r[1] + pad, r[3] - pad
        if row == lit then left, right = math.max(left, lit[1]), math.min(right, lit[3]) end
        list:AddRectFilled({ left, row[2] - 1 }, { right, row[4] + 1 }, imgui.GetColorU32(theme.Get().HighlightColor), 3)
    end
    -- the game's art: the contents' icons as the game drew them, and the elements that are no letter (a button) in
    -- their own colours, faint where the game greys one; the cursor's tint left to the row lit under it
    for i, quad in ipairs(window.quads) do
        if not spelled[i] and quad.texture then
            local q, uv = quad.rect, quad.uv
            local color = quad.phase == groupmirror.Element and { 1, 1, 1, quad.color[4] } or quad.color
            list:AddImage(quad.texture, { q[1], q[2] }, { q[3], q[4] }, { uv[1], uv[2] }, { uv[3], uv[4] }, imgui.GetColorU32(color))
        end
    end
    -- the words spelled from the game's fonts, in the theme's
    for _, word in ipairs(words) do
        local t = word.rect
        local size = math.max(8, math.floor(math.min(word.tall, most) + 0.5))
        imgui.PushFont(nil, size)
        text.Draw(list, t[1], t[2] + (Height(t) - size) / 2, TextColor({ 1, 1, 1, word.color[4] }), word.text)
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
        list:AddRectFilled({ left, s[2] }, { s[3], s[4] }, imgui.GetColorU32({ track[1], track[2], track[3], 0.25 }), 2)
        local top = s[2] + Height(s) * window.scrollTop / window.scrollCount
        local bottom = s[2] + Height(s) * math.min(1, (window.scrollTop + window.scrollPage) / window.scrollCount)
        list:AddRectFilled({ left, top }, { s[3], bottom }, imgui.GetColorU32({ thumb[1], thumb[2], thumb[3], 1 }), 2)
    end
    -- the hand where the game drew its own: as tall as the row it points at, from the left of where the game drew it,
    -- on its middle
    local c = window.cursor
    if c then
        local handle, art = cursorArt.Get()
        if handle then
            local tall = row and Height(row) + 2 or math.min(Height(c), 18)
            if line then tall = math.min(tall, line + 2) end
            local wide = tall * art[5] / art[6]
            local middle = (c[2] + c[4]) / 2
            list:AddImage(handle, { c[1], middle - tall / 2 }, { c[1] + wide, middle + tall / 2 },
                { art[1], art[2] }, { art[3], art[4] }, imgui.GetColorU32(white))
        end
    end
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

local function DrawWindow(list, window)
    local r = window.rect
    local title, words, spelled = Spelled(window)
    frame.Draw({ left = r[1], top = r[2], width = Width(r), height = Height(r) }, function()
        list:PushClipRect({ r[1] - 24, r[2] - 24 }, { r[3] + 24, r[4] + 24 }, true)
        local ok, err = pcall(DrawContents, list, window, words, spelled)
        list:PopClipRect()
        if not ok then error(err, 0) end
    end, { title = title })
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
