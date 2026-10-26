-- Chatbox's auto-translate picker against the installed client's dictionary: the word at the caret, the
-- lists, the keys, the bytes written into the game's buffer and the window drawn above the input bar.
package.path = 'addons/libs/?.lua;addons/chatbox/?.lua;' .. package.path
require('winxi.gamedata').Root('addons/libs/winxi/data/')
local auto = require('winxi.autotranslate')
local translate = dofile('addons/chatbox/translate.lua')
local function check(label, ok) assert(ok, label) end
local HELLO = string.char(0xFD, 2, 2, 1, 11, 0xFD)

-- The word at the caret
local function word(raw, caret) return { translate.Word(raw, caret) } end
local w = word('hel', 3)
check('plain word', w[1] == 1 and w[2] == 3 and w[3] == 'hel')
w = word('say HeL', 7)
check('word after a space, lowered', w[1] == 5 and w[2] == 7 and w[3] == 'hel')
check('caret 0 has no word', translate.Word('hel', 0) == nil)
check('after a space no word', translate.Word('say ', 4) == nil)
check('empty buffer no word', translate.Word('', 0) == nil)
check('right after a token no word', translate.Word(HELLO, 6) == nil)
w = word(HELLO .. 'abc', 9)
check('word after a token stops at its FD', w[1] == 7 and w[2] == 9 and w[3] == 'abc')
for caret = 1, 5 do check('caret inside a token no word', translate.Word(HELLO .. 'x', caret) == nil) end
w = word('say hello world', 9)
check('word in the middle of a line ends at the caret', w[1] == 5 and w[2] == 9 and w[3] == 'hello')
w = word('say hello world', 7)
check('word ends at the caret, not the word end', w[2] == 7 and w[3] == 'hel')
local kana = '\130\160' -- あ in CP932
w = word('x ' .. kana .. 'ab', 6)
check('a two-byte character is part of the word', w[1] == 3 and w[2] == 6 and w[3] == kana .. 'ab')
check('caret between a character\'s two bytes no word', translate.Word('x ' .. kana, 3) == nil)
-- a trail byte of 0x40..0xFC is never taken for a lead or a token
local soTrail = '\131\92' -- ソ: second byte is a backslash
w = word(soTrail .. 'a', 3)
check('trail byte not misread', w[1] == 1 and w[3] == soTrail .. 'a')
w = word('ab', 99)
check('caret clamped', w[2] == 2)
check('bad input', translate.Word(nil, 1) == nil and translate.Word('a', 0 / 0) == nil)

-- The picker over the real dictionary
local picker = translate.New(auto)
check('closed at first', picker.open == false and picker.Status() == 'closed')
check('Open with hel', picker.Open('say hel', 7) and picker.open)
local view = picker.View()
check('Hello! first', view.items[1].kind == 'phrase' and view.items[1].label == '❮Hello!❯' and view.selected == 1 and view.first == 1)
check('rows', view.rows == translate.Rows and translate.Rows == 10)
local prefixDone = false
for i, item in ipairs(view.items) do
    local starts = auto.Text(item.id, 'en'):lower():sub(1, 3) == 'hel'
    if not starts then prefixDone = true end
    check('prefix matches before the rest', not (prefixDone and starts))
    if i > 1 then
        local a, b = auto.Text(view.items[i - 1].id, 'en'):lower(), auto.Text(item.id, 'en'):lower()
        local sa, sb = a:sub(1, 3) == 'hel', b:sub(1, 3) == 'hel'
        check('alphabetical within each group', sa ~= sb or a <= b)
    end
end
check('every match listed', #view.items == #auto.Search('hel', 'en'))
check('title', picker.Title() == 'Auto-Translate: hel  1 of ' .. #view.items)
check('status open', picker.Status() == 'open: ' .. #view.items .. ' phrases for hel')
check('capped', (function() picker.Open('e', 1) local n = #picker.View().items picker.Close() return n == translate.Limit end)())

picker.Open('', 0)
view = picker.View()
check('categories with no word', #view.items == 42 and view.items[1].kind == 'category' and view.items[1].label == '【Greetings】')
for i = 2, #view.items do check('categories in id order', view.items[i - 1].id < view.items[i].id) end
check('categories title and status', picker.Title() == 'Auto-Translate  1 of 42' and picker.Status() == 'open: 42 categories')
picker.Refresh('', 0)
check('categories stay with no word', picker.open and #picker.View().items == 42)

-- Move and Page clamp
picker.Move(-1); check('Move clamps at the top', picker.View().selected == 1)
picker.Move(1); check('Move down', picker.View().selected == 2)
picker.Page(1); check('Page down', picker.View().selected == 12 and picker.View().first == 3)
picker.Page(10); check('Page clamps at the end', picker.View().selected == 42 and picker.View().first == 33)
picker.Page(-1); check('Page up keeps the row shown', picker.View().selected == 32 and picker.View().first == 32)
picker.Page(-10); check('Page clamps at the top', picker.View().selected == 1 and picker.View().first == 1)

-- Separate native edit, send and display buffers: a raw-only write is not success.
local function Chat(keeps, withRaw, initial)
    local chat = { buffer = initial or 'say hel', parsed = initial or 'say hel', display = initial or 'say hel' }
    function chat:SetInputText(text)
        self.set = text
        if not keeps then self.buffer, self.parsed, self.display = text, text, text end
    end
    function chat:GetInputTextRaw() return self.buffer end
    function chat:GetInputTextParsed() return self.parsed end
    if withRaw then
        function chat:SetInputTextRaw(text, size) self.rawSet = { text, size }; self.buffer = text:sub(1, size) end
        function chat:SetInputTextParsed(text) self.parsed = text end
        function chat:SetInputTextDisplay(text) self.display = text end
    end
    return chat
end
local function Enter(chat)
    if not picker.Enter(chat) then return false end
    return picker.Flush(chat)
end

-- Enter on a category, then on a phrase
local chat = Chat(false, false, '')
check('Enter on a category writes nothing', Enter(chat) == false and chat.set == nil and picker.open)
view = picker.View()
check('category list', view.items[1].kind == 'phrase' and view.selected == 1 and picker.Title():find('^Auto%-Translate: Greetings  1 of '))
for i = 2, #view.items do check('category in entry order', auto.Get(view.items[i - 1].id).Entry < auto.Get(view.items[i].id).Entry) end
check('category status', picker.Status():find('^open: %d+ phrases in Greetings$'))
check('Back to the categories', picker.Back() == true and #picker.View().items == 42 and picker.View().selected == 1)
picker.Move(2); Enter(chat)
check('Back selects the category it came from', picker.Back() and picker.View().selected == 3)
check('Back from the categories closes', picker.Back() == false and not picker.open)
chat = Chat(false, false, 'say ')
picker.Open('say ', 4); Enter(chat)
for i, item in ipairs(picker.View().items) do if item.id == 256 + 11 then picker.Move(i - 1) end end
check('category phrase inserted at the caret', Enter(chat) and chat.set == 'say ' .. HELLO and not picker.open)
check('status after insert', picker.Status() == 'closed; last insert: Hello! written')

-- The bytes for 'say hel' with the caret at 7
chat = Chat()
picker.Open('say hel', 7)
check('selection queued, not written in key callback', picker.Enter(chat) and picker.pending and chat.set == nil)
check('phrase written on the next frame', picker.Flush(chat) == true)
check('exact bytes', chat.set == 'say ' .. string.char(0xFD, 0x02, 0x02, 0x01, 0x0B, 0xFD))
check('closed after Enter', not picker.open)
-- the word replaced in the middle of a line, the rest kept
chat = Chat(false, false, 'say hel there')
picker.Open('say hel there', 7)
Enter(chat)
check('rest of the line kept', chat.set == 'say ' .. HELLO .. ' there')

-- The SetInputTextRaw fallback, and a game that keeps its text
chat = Chat(true, true, 'hel')
picker.Open('hel', 3)
check('raw fallback written', Enter(chat) == true and chat.set == HELLO and chat.rawSet[1] == HELLO and chat.rawSet[2] == 6)
check('raw fallback status', picker.Status() == 'closed; last insert: Hello! written raw')
check('raw fallback synchronises send/display buffers', chat.parsed == HELLO and chat.display == HELLO)
chat = Chat(true, false, 'hel')
picker.Open('hel', 3)
check('game kept its text', Enter(chat) == false and picker.Status():find('not written') and chat.buffer == 'hel')
chat = { SetInputText = function() error('no binding') end, GetInputTextRaw = function() return 'hel' end }
picker.Open('hel', 3)
check('a failing SetInputText is caught', Enter(chat) == false and picker.Status():find('not written'))
picker.Open('zzzzqqq', 7)
check('no match still opens', picker.open and #picker.View().items == 0 and picker.Title() == 'Auto-Translate: zzzzqqq  no match')
check('Enter on no match closes', Enter(Chat()) == false and not picker.open)

-- A throwing combined setter must still try the native raw/parsed/display path.
chat = Chat(true, true, 'hel')
chat.SetInputText = function() error('combined setter unavailable') end
picker.Open('hel', 3)
check('fallback after a throwing combined setter', Enter(chat) and chat.buffer == HELLO and chat.parsed == HELLO)
-- The raw buffer kept is success; a parsed buffer that differs is noted for /chatbox status, not undone
chat = Chat(true, true, 'hel')
chat.SetInputText = function(self, value) self.buffer = value end
picker.Open('hel', 3)
check('raw buffer kept: written', Enter(chat) and chat.buffer == HELLO)
check('a differing parsed buffer noted', picker.Status():find('written; parsed buffer differs', 1, true))
-- Never overwrite text typed between selection and the frame's commit.
chat = Chat(false, false, 'hel')
picker.Open('hel', 3); picker.Enter(chat); chat.buffer = 'hel later'
check('stale pending write cancelled', not picker.Flush(chat) and chat.buffer == 'hel later' and chat.set == nil)
chat = Chat(false, false, 'hel')
picker.Open('hel', 3); picker.Enter(chat); picker.Close()
check('closing the list keeps the chosen phrase for the next frame', picker.pending ~= nil)
picker.Cancel()
check('cancelling drops it', not picker.Flush(chat) and chat.set == nil)
-- Exact-fit messages are legal; overflowing messages remain editable, never truncated.
local prefix = string.rep('x', 113) .. ' '
chat = Chat(false, false, prefix .. 'hel')
picker.Open(chat.buffer, #chat.buffer)
check('120-byte message with complete token', Enter(chat) and #chat.buffer == 120 and chat.buffer:sub(-6) == HELLO)
prefix = prefix .. 'x '
chat = Chat(false, false, prefix .. 'hel')
picker.Open(chat.buffer, #chat.buffer)
check('oversize selection rejected without losing text', not picker.Enter(chat) and picker.open and chat.set == nil
    and picker.Status():find('exceeds 120 bytes'))
picker.Close()
-- The normal native send sees the encoded token, not the translated display label.
chat = Chat(false, false, '/p hel there')
picker.Open(chat.buffer, 6)
check('native outbound bytes', Enter(chat) and chat.parsed == '/p ' .. HELLO .. ' there')
check('outbound phrase decodes for other clients', auto.Decode(chat.parsed:sub(4, 9)).Id == 267)
local before = '/p ' .. HELLO .. ' ' .. kana .. ' '
chat = Chat(false, false, before .. 'hel suffix')
picker.Open(chat.buffer, #before + 3)
check('existing tokens, CP932 and suffix survive insertion', Enter(chat) and chat.parsed == before .. HELLO .. ' suffix')
-- Failed partial writes restore the draft instead of leaving only the raw buffer changed.
chat = Chat(true, true, 'hel')
chat.SetInputTextParsed = function() error('send buffer unavailable') end
picker.Open('hel', 3)
check('partial fallback rolls back', not Enter(chat) and chat.buffer == 'hel' and chat.parsed == 'hel')

-- Refresh narrows and closes
picker.Open('say he', 6)
local wide = #picker.View().items
picker.Move(1)
local keep = picker.View().items[2].id
picker.Refresh('say hel', 7)
view = picker.View()
check('Refresh narrows', #view.items < wide and #view.items == #auto.Search('hel', 'en'))
check('selection kept by id', view.items[view.selected].id == keep or (function()
    for _, item in ipairs(view.items) do if item.id == keep then return false end end return view.selected == 1 end)())
picker.Refresh('say hel', 7)
check('same query keeps the list', picker.open and #picker.View().items == #view.items)
picker.Refresh('say hel ', 8)
check('Refresh closes when the word is gone', not picker.open)
picker.Open('hel', 3); picker.Refresh('', 0)
check('emptied input closes', not picker.open)
picker.Open('hel', 3); picker.Refresh('hel', 1)
check('caret moved shortens the word', picker.open and picker.Title():find('^Auto%-Translate: h  '))
picker.Close(); check('Close', not picker.open and picker.Status():find('^closed'))

-- Draw, with stand-ins for imgui, the theme and window.Plain
local calls, rects, texts, plain = {}, {}, {}, nil
local list = setmetatable({}, { __index = function(_, k) return function(_, ...)
    calls['draw.' .. k] = (calls['draw.' .. k] or 0) + 1
    if k == 'AddRectFilled' then rects[#rects + 1] = { ... } end
    if k == 'AddText' then local _, color, text = ... texts[#texts + 1] = { text = text, color = color } end
end end })
local imgui = setmetatable({}, { __index = function(_, k) return function(...)
    calls[k] = (calls[k] or 0) + 1
    if k == 'SetNextWindowPos' or k == 'SetNextWindowSize' then calls[k .. '.args'] = { ... } end
    if k == 'GetWindowDrawList' then return list end
    if k == 'CalcTextSize' then return #(...) * 7, 14 end
    if k == 'GetFontSize' then return 14 end
    if k == 'GetColorU32' then local c = ... return c end
end end })
package.preload['imgui'] = function() return imgui end
local theme = { TextColor = { 1, 1, 1, 1 }, HighlightColor = { 0.2, 0.4, 0.8, 0.6 } }
package.preload['winxi.theme'] = function() return { Get = function() return theme end } end
package.preload['winxi.window'] = function() return { Plain = function(name, open, flags, draw, options)
    plain = { name = name, flags = flags, options = options }
    draw()
    return true
end } end
setmetatable(_G, { __index = function(_, k) if type(k) == 'string' and k:match('^ImGui') then return 0 end end })
local layout = { x = 20, bottom = 1060, width = 640, height = 40, fontSize = 14, padding = 6, font = 'font',
    textColor = { 0.9, 0.9, 0.9, 1 }, background = 'bg', border = 'border' }
check('nothing drawn when closed', translate.Draw(picker, layout, 0) == false and calls.SetNextWindowPos == nil and plain == nil)
picker.Open('say hel', 7)
check('drawn when open', translate.Draw(picker, layout, 0) == true)
check('window named and click-through', plain.name == 'winxi.chatbox.translate' and plain.options.clickThrough == true
    and plain.options.background == 'bg' and plain.options.border == 'border' and plain.options.textColor == layout.textColor
    and plain.options.padding == 6 and plain.options.fontSize == 14)
local pos, size = calls['SetNextWindowPos.args'], calls['SetNextWindowSize.args']
check('placed above the bar', pos[1][1] == 20 and pos[1][2] == 1060 - 40 - 2 and pos[3][2] == 1)
check('sized for ten rows and a title', size[1][2] == 11 * 18 + 12 and size[1][1] >= 200 and size[1][1] <= 640)
check('style and font balanced', calls.PushStyleVar == 1 and calls.PopStyleVar == 1 and calls.PushFont == calls.PopFont and calls.PushFont == 2)
local rows = math.min(10, #picker.View().items)
check('title and rows drawn', texts[1].text == picker.Title() and calls['draw.AddText'] >= 1 + rows)
check('one highlight in the theme colour', #rects == 1 and rects[1][3][1] == 0.2 and rects[1][3][4] == 0.35)
check('brackets drawn as geometry', (calls['draw.AddLine'] or 0) == rows * 4)
check('selected text in TextColor', (function()
    for _, t in ipairs(texts) do if t.text == 'Hello!' then return t.color == theme.TextColor end end end)())
check('others in the layout colour', (function()
    for _, t in ipairs(texts) do if t.text ~= 'Hello!' and t.text ~= picker.Title() then return t.color == layout.textColor end end end)())
layout.width = 150; calls = {}
translate.Draw(picker, layout, 0)
check('never wider than the bar', calls['SetNextWindowSize.args'][1][1] == 150)
picker.Open('zzzzqqq', 7); texts = {}; calls = {}
translate.Draw(picker, layout, 0)
check('no match drawn as one row', texts[2].text == 'no match' and calls['SetNextWindowSize.args'][1][2] == 2 * 18 + 12)
picker.Open('say hel', 7)
-- a broken draw closes the picker and says why
theme.HighlightColor = nil
calls = {}
check('failed draw', translate.Draw(picker, layout, 0) == false and not picker.open and picker.Status():find('draw failed'))
check('stacks balanced after a failure', calls.PushStyleVar == calls.PopStyleVar and calls.PushFont == calls.PopFont)
auto.Clear()
print('Chatbox translate: word at the caret, CP932 and tokens, search, categories, deferred insertion, send bytes, rollback, limits, refresh and draw passed')
