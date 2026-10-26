-- Chatbox's own auto-translate picker. The game's Tab menu would become the game's active menu and take the
-- input bar back from chatbox, so chatbox keeps Tab from the game and offers the dictionary itself: a list
-- drawn above the input bar, narrowed to the word at the caret, whose choice is written into the game's own
-- buffer as the phrase's six-byte token. Typing, history and sending stay the game's. chatbox keeps the picker's
-- keys from the game (Ashita's key events, and DirectInput's polled state, from which the game reads Enter).
local bit = require('bit')
local M = {}
M.Rows = 10
M.Limit = 200
-- Ashita's native input setters clamp to 120 bytes. Never silently truncate a
-- message (or cut a six-byte token / CP932 character) to make a phrase fit.
M.MaxInputBytes = 120

local SPACE, TOKEN = 0x20, 0xFD
local function Lead(b) return (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC) end

-- The word is found walking forward from the start of the buffer, not back from the caret: only from the
-- start can a byte be told for what it is, a token's inside, a two-byte character's second half or a letter.
-- A caret inside a token or between a character's two bytes has no word, rather than half of one.
function M.Word(raw, caret)
    if type(raw) ~= 'string' or type(caret) ~= 'number' or caret ~= caret then return nil end
    caret = math.max(0, math.min(#raw, math.floor(caret)))
    local i, start = 1, 1
    while i <= caret do
        local b = raw:byte(i)
        if b == TOKEN then
            -- a phrase token is FD xx xx xx xx FD; the word starts after it
            if i + 5 > caret then return nil end
            i = i + 6
            start = i
        elseif b == SPACE then
            i = i + 1
            start = i
        elseif Lead(b) then
            if i + 1 > caret then return nil end
            i = i + 2
        else
            i = i + 1
        end
    end
    if start > caret then return nil end
    return start, caret, raw:sub(start, caret):lower()
end

-- What the title shows of the word as typed: its ASCII as it is, each two-byte character as '?', since the
-- raw buffer is CP932 and the picker's labels are UTF-8.
local function Printable(text)
    local out, i = {}, 1
    while i <= #text do
        local b = text:byte(i)
        if b >= 0x20 and b < 0x7F then out[#out + 1] = string.char(b); i = i + 1
        else out[#out + 1] = '?'; i = i + (Lead(b) and 2 or 1) end
    end
    return table.concat(out)
end

function M.New(auto)
    local picker = { open = false }
    local mode, items, selected, first = nil, {}, 1, 1
    local query, typed, category = nil, nil, nil
    local raw, caret = '', 0
    local last, problem = nil, nil

    local function Phrase(record)
        return { kind = 'phrase', id = record.Id, label = '❮' .. record.Text.en .. '❯', text = record.Text.en }
    end
    -- Text that starts with the word first, then the rest; alphabetical within each, by id where the
    -- dictionary holds the same text twice. The whole dictionary is searched before the cap, so a prefix
    -- match is never lost behind earlier substring matches.
    local function Search(q)
        local found = {}
        for _, record in ipairs(auto.Search(q, 'en', nil, nil) or {}) do
            if record.Text and record.Text.en then
                local lower = record.Text.en:lower()
                found[#found + 1] = { record = record, lower = lower, prefix = lower:sub(1, #q) == q }
            end
        end
        table.sort(found, function(a, b)
            if a.prefix ~= b.prefix then return a.prefix end
            if a.lower ~= b.lower then return a.lower < b.lower end
            return a.record.Id < b.record.Id
        end)
        local list = {}
        for i = 1, math.min(#found, M.Limit) do list[i] = Phrase(found[i].record) end
        return list
    end
    local function Categories()
        local list = {}
        for _, c in ipairs(auto.Categories() or {}) do
            list[#list + 1] = { kind = 'category', id = c.Id, label = (c.DisplayNames and c.DisplayNames.en) or c.Names.en,
                name = c.Names.en }
        end
        table.sort(list, function(a, b) return a.id < b.id end)
        return list
    end
    local function Category(id)
        local found = {}
        for _, record in ipairs(auto.Search('', 'en', id, nil) or {}) do
            if record.Text and record.Text.en then found[#found + 1] = record end
        end
        table.sort(found, function(a, b) return a.Entry < b.Entry end)
        local list = {}
        for i, record in ipairs(found) do list[i] = Phrase(record) end
        return list
    end
    -- Keep the selection in the list and on screen.
    local function Show()
        selected = math.max(1, math.min(selected, #items))
        if selected < first then first = selected end
        if selected > first + M.Rows - 1 then first = selected - M.Rows + 1 end
        first = math.max(1, math.min(first, #items - M.Rows + 1))
    end
    local function See(r, c)
        raw = type(r) == 'string' and r or ''
        caret = type(c) == 'number' and c == c and math.max(0, math.min(#raw, math.floor(c))) or #raw
    end

    function picker.Open(r, c)
        picker.pending = nil
        See(r, c)
        local wordFirst, wordLast, q = M.Word(raw, caret)
        if q then
            mode, query, typed = 'phrases', q, raw:sub(wordFirst, wordLast)
            items = Search(q)
        else
            mode, query, typed = 'categories', nil, nil
            items = Categories()
        end
        category, selected, first, problem = nil, 1, 1, nil
        picker.open = true
        return true
    end

    function picker.Refresh(r, c)
        if not picker.open then return end
        See(r, c)
        if mode ~= 'phrases' then return end
        local wordFirst, wordLast, q = M.Word(raw, caret)
        if not q then picker.Close(); return end
        typed = raw:sub(wordFirst, wordLast)
        if q == query then return end
        local id = items[selected] and items[selected].id
        query, items, selected = q, Search(q), 1
        for i, item in ipairs(items) do
            if item.id == id then selected = i; break end
        end
        first = 1
        Show()
    end

    function picker.Move(delta)
        if not picker.open or #items == 0 then return end
        selected = selected + (tonumber(delta) or 0)
        Show()
    end
    function picker.Page(delta)
        picker.Move((tonumber(delta) or 0) * M.Rows)
    end

    function picker.Close()
        picker.open = false
        mode, items, selected, first, query, typed, category = nil, {}, 1, 1, nil, nil, nil
    end
    -- A chosen phrase not yet written is dropped too (chatbox off, zoning, reset); closing alone keeps it for Flush.
    function picker.Cancel()
        picker.Close()
        picker.pending = nil
    end

    -- Read the buffer back through pcall: the chat manager is the game's, and a stand-in or an older
    -- Ashita may lack a method.
    local function Read(chat)
        local ok, text = pcall(function() return chat:GetInputTextRaw() end)
        return ok and text or nil
    end
    -- The game's parsed buffer, where it differs from the raw one written: noted in Status, not refused, as what
    -- the game keeps there for a line with a token in it has not been seen.
    local function Parsed(chat, value)
        local ok, parsed = pcall(function() return chat:GetInputTextParsed() end)
        if ok and type(parsed) == 'string' and parsed ~= value then return '; parsed buffer differs (' .. #parsed .. ' bytes)' end
        return ''
    end

    -- Written on the frame after the choice, outside the key callback. A stale choice never overwrites newer typing.
    function picker.Flush(chat)
        local pending = picker.pending
        if not pending then return false end
        picker.pending = nil
        if Read(chat) ~= pending.before then
            last = pending.text .. ' not written: input changed'
            return false
        end
        local value = pending.raw
        local ok, err = pcall(function() chat:SetInputText(value) end)
        if ok and Read(chat) == value then
            last = pending.text .. ' written' .. Parsed(chat, value)
            return true
        end
        -- Where the combined setter did not keep it, each buffer set on its own
        local repaired, failure = pcall(function()
            assert(chat.SetInputTextRaw, 'native input setters unavailable')
            chat:SetInputTextRaw(value, #value)
            if chat.SetInputTextParsed then chat:SetInputTextParsed(value) end
            if chat.SetInputTextDisplay then chat:SetInputTextDisplay(value) end
        end)
        if repaired and Read(chat) == value then
            last = pending.text .. ' written raw' .. Parsed(chat, value)
            return true
        end
        -- Nothing half written left behind: each buffer set back
        local before = pending.before
        pcall(function() chat:SetInputText(before) end)
        pcall(function() chat:SetInputTextRaw(before, #before) end)
        pcall(function() chat:SetInputTextParsed(before) end)
        pcall(function() chat:SetInputTextDisplay(before) end)
        last = pending.text .. ' not written: ' .. tostring(failure or err or 'the game kept its own text')
        return false
    end

    function picker.Enter(chat)
        if not picker.open then return false end
        local item = items[selected]
        if not item then picker.Close(); return false end
        if item.kind == 'category' then
            mode, category, query, typed = 'category', item, nil, nil
            items, selected, first = Category(item.id), 1, 1
            return false
        end
        local token = auto.Token(item.id, 'en')
        if not token then
            last = item.text .. ' not written: no token'
            picker.Close()
            return false
        end
        -- From a word, the word is replaced; in a category's list, opened with no word, the phrase goes in
        -- at the caret. Nothing is added around it, as the game's own menu adds nothing.
        local wordFirst, wordLast
        if mode == 'phrases' then wordFirst, wordLast = M.Word(raw, caret) end
        if not wordFirst then wordFirst, wordLast = caret + 1, caret end
        local newRaw = raw:sub(1, wordFirst - 1) .. token .. raw:sub(wordLast + 1)
        if #newRaw > M.MaxInputBytes then
            last = item.text .. ' not written: message exceeds ' .. M.MaxInputBytes .. ' bytes'
            return false -- keep the picker and the original text so the user can shorten it
        end
        local pending = { before = raw, raw = newRaw, text = item.text }
        picker.Close()
        picker.pending = pending
        last = item.text .. ' queued'
        return true
    end

    function picker.Back()
        if picker.open and mode == 'category' then
            local from = category and category.id
            mode, category, items, selected, first = 'categories', nil, Categories(), 1, 1
            for i, item in ipairs(items) do
                if item.id == from then selected = i; break end
            end
            Show()
            return true
        end
        picker.Close()
        return false
    end

    function picker.Title()
        local count = #items == 0 and 'no match' or (selected .. ' of ' .. #items)
        if mode == 'phrases' then return 'Auto-Translate: ' .. Printable(typed or query or '') .. '  ' .. count end
        if mode == 'category' then return 'Auto-Translate: ' .. (category.name or category.label) .. '  ' .. count end
        return 'Auto-Translate  ' .. count
    end

    function picker.View()
        return { items = items, selected = selected, first = first, rows = M.Rows }
    end

    function picker.Status()
        local line
        if not picker.open then line = 'closed'
        elseif mode == 'phrases' then line = 'open: ' .. #items .. ' phrases for ' .. Printable(typed or query or '')
        elseif mode == 'category' then line = 'open: ' .. #items .. ' phrases in ' .. (category.name or category.label)
        else line = 'open: ' .. #items .. ' categories' end
        if last then line = line .. '; last insert: ' .. last end
        if problem then line = line .. '; draw failed: ' .. problem end
        return line
    end

    -- M.Draw's report of a failed draw: the picker closes, the error is kept for Status.
    function picker.Fail(message)
        problem = tostring(message)
        picker.Close()
    end

    return picker
end

-- Above the input bar, in its font and colours, never taking focus or the mouse: the game's editor keeps
-- the keyboard while the picker shows.
function M.Draw(picker, layout, flags)
    if not picker or not picker.open or type(layout) ~= 'table' then return false end
    local imgui = require('imgui')
    local minSizePushed = false
    local drawn, err = pcall(function()
        local window = require('winxi.window')
        local render = require('render')
        local theme = require('winxi.theme').Get()
        local view = picker.View()
        local fontSize, padding = layout.fontSize or 14, layout.padding or 6
        local rows = math.min(view.rows, math.max(1, #view.items))
        local rowHeight = fontSize + 4
        local title = picker.Title()
        -- Measured in the font the rows are drawn in.
        if layout.font then imgui.PushFont(layout.font, fontSize) end
        local measured, widest = pcall(function()
            local w = render.Measure(title)
            for i = view.first, math.min(#view.items, view.first + rows - 1) do
                w = math.max(w, render.Measure(view.items[i].label))
            end
            return w
        end)
        if layout.font then imgui.PopFont() end
        if not measured then error(widest, 0) end
        local width = math.min(layout.width or 200, math.max(200, widest + padding * 2 + 8))
        local height = (rows + 1) * rowHeight + padding * 2
        local bottom = layout.bottom - layout.height - 2
        local left, top = layout.x, bottom - height
        imgui.PushStyleVar(ImGuiStyleVar_WindowMinSize, { 1, 1 })
        minSizePushed = true
        imgui.SetNextWindowPos({ left, bottom }, ImGuiCond_Always, { 0, 1 })
        imgui.SetNextWindowSize({ width, height }, ImGuiCond_Always)
        local windowFlags = bit.bor(flags or 0, ImGuiWindowFlags_NoFocusOnAppearing or 0,
            ImGuiWindowFlags_NoBringToFrontOnFocus or 0)
        window.Plain('winxi.chatbox.translate', { true }, windowFlags, function()
            if layout.font then imgui.PushFont(layout.font, fontSize) end
            local ok, failure = pcall(function()
                local list = imgui.GetWindowDrawList()
                local textColor = imgui.GetColorU32(layout.textColor or theme.TextColor)
                local chosenColor = imgui.GetColorU32(theme.TextColor)
                local h = theme.HighlightColor
                local highlight = imgui.GetColorU32({ h[1], h[2], h[3], 0.35 })
                local x, y = left + padding, top + padding
                list:PushClipRect({ left, top }, { left + width, top + height }, true)
                list:AddText({ x, y }, textColor, title)
                y = y + rowHeight
                if #view.items == 0 then
                    list:AddText({ x, y }, textColor, 'no match')
                end
                for i = view.first, math.min(#view.items, view.first + rows - 1) do
                    local color = textColor
                    if i == view.selected then
                        list:AddRectFilled({ left + padding / 2, y - 2 }, { left + width - padding / 2, y + rowHeight - 2 }, highlight)
                        color = chosenColor
                    end
                    render.Text(list, { x, y }, color, view.items[i].label)
                    y = y + rowHeight
                end
                list:PopClipRect()
                imgui.Dummy({ width - padding * 2, height - padding * 2 })
            end)
            if layout.font then imgui.PopFont() end
            if not ok then error(failure, 0) end
        end, { padding = padding, fontSize = fontSize, clickThrough = true,
            background = layout.background, border = layout.border, textColor = layout.textColor })
    end)
    if minSizePushed then imgui.PopStyleVar() end
    if not drawn then picker.Fail(err); return false end
    return true
end

return M
