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
check('Helldive then Hello!', view.items[1].kind == 'phrase' and view.items[1].label == '❮Helldive❯'
    and view.items[2].label == '❮Hello!❯' and view.selected == 1 and view.first == 1)
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
local function distinct(q)
    local seen, n = {}, 0
    for _, record in ipairs(auto.Search(q, 'en')) do
        local key = record.Text.en:lower()
        if not seen[key] then seen[key], n = true, n + 1 end
    end
    return n
end
check('every match listed', #view.items == distinct('hel'))
check('title', picker.Title() == 'Auto-Translate: hel  1 of ' .. #view.items)
check('status open', picker.Status() == 'open: ' .. #view.items .. ' matches for hel')
check('capped', (function() picker.Open('e', 1) local n = #picker.View().items picker.Close() return n == translate.Limit end)())

-- The dictionary's references (spells, areas, abilities, jobs) are found by their names, each name once
local function labels(raw)
    picker.Open(raw, #raw)
    local found = {}
    for _, item in ipairs(picker.View().items) do found[item.label] = (found[item.label] or 0) + 1 end
    picker.Close()
    return found
end
local tele = labels('tele')
for _, name in ipairs({ 'Teleport-Dem', 'Teleport-Holla', 'Teleport-Mea', 'Teleport-Vahzl', 'Teleport-Altep', 'Teleport-Yhoat' }) do
    check('spell ' .. name, tele['❮' .. name .. '❯'] == 1)
end
local bastok = labels('bastok')
for _, name in ipairs({ 'Bastok Mines', 'Bastok Markets', 'Port Bastok', 'Bastok' }) do
    check('area ' .. name, bastok['❮' .. name .. '❯'] == 1)
end
check('ability', labels('provo')['❮Provoke❯'] == 1)
check('weapon skill', labels('savage')['❮Savage Blade❯'] == 1)
check('job', labels('thie')['❮Thief❯'] == 1)
check('area named by several zones once', labels('vahzl')['❮Promyvion - Vahzl❯'] == 1)
for _, id in ipairs(auto.Ids()) do
    local text = auto.Text(id, 'en')
    check('no unresolved reference ' .. id, not (text and text:find('^@')))
end
picker.Open('', 0)
picker.Close()

picker.Open('', 0)
view = picker.View()
check('categories with no word', #view.items == 44 and view.items[1].kind == 'category' and view.items[1].label == '[Greetings]')
for i = 2, 42 do check('categories in id order', view.items[i - 1].id < view.items[i].id) end
check('the character\'s two last', view.items[43].id == 'item' and view.items[43].label == '[Items]'
    and view.items[44].id == 'keyitem' and view.items[44].label == '[Key Items]')
check('categories title and status', picker.Title() == 'Auto-Translate  1 of 44' and picker.Status() == 'open: 44 categories')
picker.Refresh('', 0)
check('categories stay with no word', picker.open and #picker.View().items == 44)

-- Move and Page clamp
picker.Move(-1); check('Move clamps at the top', picker.View().selected == 1)
picker.Move(1); check('Move down', picker.View().selected == 2)
picker.Page(1); check('Page down', picker.View().selected == 12 and picker.View().first == 3)
picker.Page(10); check('Page clamps at the end', picker.View().selected == 44 and picker.View().first == 35)
picker.Page(-1); check('Page up keeps the row shown', picker.View().selected == 34 and picker.View().first == 34)
picker.Page(-10); check('Page clamps at the top', picker.View().selected == 1 and picker.View().first == 1)

-- Separate native edit, send and display buffers: a raw-only write is not success.
local function Chat(keeps, withRaw, initial)
    local chat = { buffer = initial or 'say hello', parsed = initial or 'say hello', display = initial or 'say hello' }
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
check('category status', picker.Status():find('^open: %d+ entries in Greetings$'))
check('Back to the categories', picker.Back() == true and #picker.View().items == 44 and picker.View().selected == 1)
picker.Move(2); Enter(chat)
check('Back selects the category it came from', picker.Back() and picker.View().selected == 3)
check('Back from the categories closes', picker.Back() == false and not picker.open)
chat = Chat(false, false, 'say ')
picker.Open('say ', 4); Enter(chat)
for i, item in ipairs(picker.View().items) do if item.id == 256 + 11 then picker.Move(i - 1) end end
check('category phrase inserted at the caret', Enter(chat) and chat.set == 'say ' .. HELLO and not picker.open)
check('status after insert', picker.Status() == 'closed; last insert: Hello! written')

-- The bytes for 'say hello' with the caret at 9
chat = Chat()
picker.Open('say hello', 9)
check('selection queued, not written in key callback', picker.Enter(chat) and picker.pending and chat.set == nil)
check('phrase written on the next frame', picker.Flush(chat) == true)
check('exact bytes', chat.set == 'say ' .. string.char(0xFD, 0x02, 0x02, 0x01, 0x0B, 0xFD))
check('closed after Enter', not picker.open)
-- the word replaced in the middle of a line, the rest kept
chat = Chat(false, false, 'say hello there')
picker.Open('say hello there', 9)
Enter(chat)
check('rest of the line kept', chat.set == 'say ' .. HELLO .. ' there')

-- The SetInputTextRaw fallback, and a game that keeps its text
chat = Chat(true, true, 'hello')
picker.Open('hello', 5)
check('raw fallback written', Enter(chat) == true and chat.set == HELLO and chat.rawSet[1] == HELLO and chat.rawSet[2] == 6)
check('raw fallback status', picker.Status() == 'closed; last insert: Hello! written raw')
check('raw fallback synchronises send/display buffers', chat.parsed == HELLO and chat.display == HELLO)
chat = Chat(true, false, 'hello')
picker.Open('hello', 5)
check('game kept its text', Enter(chat) == false and picker.Status():find('not written') and chat.buffer == 'hello')
chat = { SetInputText = function() error('no binding') end, GetInputTextRaw = function() return 'hello' end }
picker.Open('hello', 5)
check('a failing SetInputText is caught', Enter(chat) == false and picker.Status():find('not written'))
picker.Open('zzzzqqq', 7)
check('no match still opens', picker.open and #picker.View().items == 0 and picker.Title() == 'Auto-Translate: zzzzqqq  no match')
check('Enter on no match closes', Enter(Chat()) == false and not picker.open)

-- A throwing combined setter must still try the native raw/parsed/display path.
chat = Chat(true, true, 'hello')
chat.SetInputText = function() error('combined setter unavailable') end
picker.Open('hello', 5)
check('fallback after a throwing combined setter', Enter(chat) and chat.buffer == HELLO and chat.parsed == HELLO)
-- The raw buffer kept is success; a parsed buffer that differs is noted for /chatbox status, not undone
chat = Chat(true, true, 'hello')
chat.SetInputText = function(self, value) self.buffer = value end
picker.Open('hello', 5)
check('raw buffer kept: written', Enter(chat) and chat.buffer == HELLO)
check('a differing parsed buffer noted', picker.Status():find('written; parsed buffer differs', 1, true))
-- Never overwrite text typed between selection and the frame's commit.
chat = Chat(false, false, 'hello')
picker.Open('hello', 5); picker.Enter(chat); chat.buffer = 'hello later'
check('stale pending write cancelled', not picker.Flush(chat) and chat.buffer == 'hello later' and chat.set == nil)
chat = Chat(false, false, 'hello')
picker.Open('hello', 5); picker.Enter(chat); picker.Close()
check('closing the list keeps the chosen phrase for the next frame', picker.pending ~= nil)
picker.Cancel()
check('cancelling drops it', not picker.Flush(chat) and chat.set == nil)
-- Exact-fit messages are legal; overflowing messages remain editable, never truncated.
local prefix = string.rep('x', 113) .. ' '
chat = Chat(false, false, prefix .. 'hello')
picker.Open(chat.buffer, #chat.buffer)
check('120-byte message with complete token', Enter(chat) and #chat.buffer == 120 and chat.buffer:sub(-6) == HELLO)
prefix = prefix .. 'x '
chat = Chat(false, false, prefix .. 'hello')
picker.Open(chat.buffer, #chat.buffer)
check('oversize selection rejected without losing text', not picker.Enter(chat) and picker.open and chat.set == nil
    and picker.Status():find('exceeds 120 bytes'))
picker.Close()
-- The normal native send sees the encoded token, not the translated display label.
chat = Chat(false, false, '/p hello there')
picker.Open(chat.buffer, 8)
check('native outbound bytes', Enter(chat) and chat.parsed == '/p ' .. HELLO .. ' there')
check('outbound phrase decodes for other clients', auto.Decode(chat.parsed:sub(4, 9)).Id == 267)
local before = '/p ' .. HELLO .. ' ' .. kana .. ' '
chat = Chat(false, false, before .. 'hello suffix')
picker.Open(chat.buffer, #before + 5)
check('existing tokens, CP932 and suffix survive insertion', Enter(chat) and chat.parsed == before .. HELLO .. ' suffix')
-- Failed partial writes restore the draft instead of leaving only the raw buffer changed.
chat = Chat(true, true, 'hello')
chat.SetInputTextParsed = function() error('send buffer unavailable') end
picker.Open('hello', 5)
check('partial fallback rolls back', not Enter(chat) and chat.buffer == 'hello' and chat.parsed == 'hello')

-- Refresh narrows and closes
picker.Open('say he', 6)
local wide = #picker.View().items
picker.Move(1)
local keep = picker.View().items[2].id
picker.Refresh('say hel', 7)
view = picker.View()
check('Refresh narrows', #view.items < wide and #view.items == distinct('hel'))
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
    for _, t in ipairs(texts) do if t.text == 'Helldive' then return t.color == theme.TextColor end end end)())
check('others in the layout colour', (function()
    for _, t in ipairs(texts) do if t.text ~= 'Helldive' and t.text ~= picker.Title() then return t.color == layout.textColor end end end)())
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
theme.HighlightColor = { 0.2, 0.4, 0.8, 0.6 }

-- Items and key items, from a stand-in for the client's names
check('names kept plain', translate.Name(' Fire Crystal ') == 'Fire Crystal' and translate.Name('.') == nil
    and translate.Name('') == nil and translate.Name('Caf\130\160') == nil and translate.Name(nil) == nil)
check('no names without Ashita', #translate.CharacterNames() == 0)
-- The character's bags and key items, read through a stand-in for Ashita
do
    local bags = { [0] = { 65535, 4096, 4096, 0 }, [5] = { 4104 }, [17] = { 300, 77 } }
    local keys = { [5] = true, [513] = true, [4095] = true, [600] = true }
    local itemReads = 0
    local names = { [4096] = 'Fire Crystal', [4104] = 'Fire Cluster', [300] = 'Hello!', [77] = '.' }
    local keyNames = { [5] = 'Hellfire Map', [513] = 'Ancient Fire Seal', [4095] = 'Last Key', [600] = '' }
    AshitaCore = {
        GetResourceManager = function() return {
            GetItemById = function(_, id) itemReads = itemReads + 1; return { Name = { names[id] } } end,
            GetString = function(_, table_, id) assert(table_ == 'keyitems.names'); return keyNames[id] end } end,
        GetMemoryManager = function() return {
            GetInventory = function() return {
                GetContainerCountMax = function(_, bag) return bags[bag] and #bags[bag] or 0 end,
                GetContainerItem = function(_, bag, slot)
                    local id = bags[bag][slot]
                    return { Id = id, Count = id == 0 and 0 or 1 }
                end } end,
            GetPlayer = function() return { HasKeyItem = function(_, id) return keys[id] == true end } end } end }
    local got = translate.CharacterNames()
    local by = {}
    for _, entry in ipairs(got) do by[entry.kind .. entry.id] = entry.text end
    check('items from every bag, once, gil and blank names left out', by.item4096 == 'Fire Crystal' and by.item4104 == 'Fire Cluster'
        and by.item300 == 'Hello!' and by.item77 == nil and by.item65535 == nil)
    check('owned key items only, to the last id', by.keyitem5 == 'Hellfire Map' and by.keyitem513 == 'Ancient Fire Seal'
        and by.keyitem4095 == 'Last Key' and by.keyitem600 == nil and by.keyitem6 == nil)
    local count = 0
    for _ in pairs(by) do count = count + 1 end
    check('nothing else', count == #got and count == 6)
    local before = itemReads
    bags[0] = { 4096 }
    got = translate.CharacterNames()
    check('bags read again, names kept once read', itemReads == before and #got == 6)
    -- With a store: who is playing, what they held before and what was heard
    local known = dofile('addons/chatbox/known.lua')
    local files = { Win_77 = 'return { item = { 9000 }, keyitem = { 700 } }' }
    local store = known.New({ Read = function(c) return files[c] end, Write = function(c, t) files[c] = t; return true end })
    names[9000], keyNames[700], names[12] = 'Old Sword', 'Old Map', 'Heard Ring'
    check('no store without a character', #translate.CharacterNames(store) == 6 and store.character == nil)
    local member = { 'Win', 77 }
    local memory = AshitaCore.GetMemoryManager
    AshitaCore.GetMemoryManager = function()
        local m = memory()
        m.GetParty = function() return { GetMemberName = function() return member[1] end,
            GetMemberServerId = function() return member[2] end } end
        return m
    end
    store.Hear('item', 12)
    got = translate.CharacterNames(store)
    by = {}
    for _, entry in ipairs(got) do by[entry.kind .. entry.id] = entry.text end
    check('the character named', store.character == 'Win_77')
    check('held before, held now and heard', by.item9000 == 'Old Sword' and by.keyitem700 == 'Old Map' and by.item4096 == 'Fire Crystal'
        and by.item12 == 'Heard Ring' and by.keyitem5 == 'Hellfire Map' and #got == 9)
    check('what they hold saved', known.Parse(files.Win_77).item[4096] and known.Parse(files.Win_77).keyitem[5]
        and not known.Parse(files.Win_77).item[12])
    bags[0] = {}
    got = translate.CharacterNames(store)
    by = {}
    for _, entry in ipairs(got) do by[entry.kind .. entry.id] = entry.text end
    check('an item sold stays in the list', by.item4096 == 'Fire Crystal')
    member = { '', 0 }
    check('the title screen: only what is held now', #translate.CharacterNames(store) == 5)
    AshitaCore = nil
end
local reads, sold = 0, false
local named = translate.New(auto, function()
    reads = reads + 1
    if sold then return { { kind = 'item', id = 4104, text = 'Fire Cluster' } } end
    return { { kind = 'item', id = 4096, text = 'Fire Crystal' }, { kind = 'item', id = 4104, text = 'Fire Cluster' },
        { kind = 'item', id = 9000, text = 'Fire Crystal' }, { kind = 'item', id = 300, text = 'Hello!' },
        { kind = 'keyitem', id = 5, text = 'Hellfire Map' }, { kind = 'keyitem', id = 513, text = 'Ancient Fire Seal' },
        { kind = 'weird', id = 1, text = 'Fireproof' } }
end)
local function find(list, label, kind)
    for i, item in ipairs(list) do if item.label == label and item.kind == kind then return i, item end end
end
named.Open('fire', 4)
local found = named.View().items
check('items found', find(found, '❮Fire Crystal❯', 'item') and find(found, '❮Fire Cluster❯', 'item'))
local count = 0
for _, item in ipairs(found) do if item.label == '❮Fire Crystal❯' then count = count + 1 end end
local _, crystal = find(found, '❮Fire Crystal❯', 'item')
check('an item named twice listed once, the lowest id', count == 1 and crystal.id == 4096 and crystal.note == 'item')
named.Open('fire', 4)
found = named.View().items
check('names read each time the list opens', reads == 2)
check('an unknown kind left out', not find(found, '❮Fireproof❯', 'weird'))
local _, seal = find(found, '❮Ancient Fire Seal❯', 'keyitem')
check('key item by substring, after the prefixes', seal and seal.note == 'key item' and find(found, '❮Ancient Fire Seal❯', 'keyitem') > find(found, '❮Fire Crystal❯', 'item'))
named.Open('hello', 5)
found = named.View().items
local p, i = find(found, '❮Hello!❯', 'phrase'), find(found, '❮Hello!❯', 'item')
check('a phrase and an item of one name both listed, the phrase first', p and i and p < i)
check('status counts matches', named.Status() == 'open: ' .. #found .. ' matches for hello')
-- Written as the item and key item tokens, a zero byte escaped
chat = Chat(false, false, 'say crystal')
named.Open(chat.buffer, #chat.buffer)
named.Move(select(1, find(named.View().items, '❮Fire Crystal❯', 'item')) - 1)
check('item token, low byte escaped', named.Enter(chat) and named.Flush(chat) and chat.set == 'say ' .. string.char(0xFD, 0x0A, 2, 0x10, 0xFF, 0xFD))
check('item token decodes', auto.Decode(chat.set:sub(5)).Kind == 'item' and auto.Decode(chat.set:sub(5)).Id == 4096)
chat = Chat(false, false, 'hellf')
named.Open(chat.buffer, 5)
check('key item token, high byte escaped', named.Enter(chat) and named.Flush(chat) and chat.set == string.char(0xFD, 0x15, 2, 0xFF, 5, 0xFD)
    and named.Status() == 'closed; last insert: Hellfire Map written')
-- Refresh keeps an item chosen by its kind as well as its id
named.Open('fir', 3)
local at = find(named.View().items, '❮Fire Cluster❯', 'item')
named.Move(at - 1)
named.Refresh('fire', 4)
check('selection kept by kind and id', named.View().items[named.View().selected].label == '❮Fire Cluster❯')
local opened = reads
named.Refresh('fir', 3)
check('typing does not read the bags again', reads == opened)
-- The Items and Key Items categories: the character's own, alphabetical, each name once
named.Open('', 0)
named.Move(42)
check('Items category', named.Enter(Chat()) == false and named.Title():find('^Auto%-Translate: Items  1 of 3$'))
found = named.View().items
check('items alphabetical', found[1].label == '❮Fire Cluster❯' and found[2].label == '❮Fire Crystal❯' and found[3].label == '❮Hello!❯'
    and found[2].id == 4096 and found[1].note == 'item')
check('Items status', named.Status():find('^open: 3 entries in Items'))
check('Back selects Items', named.Back() and named.View().selected == 43)
named.Move(1); named.Enter(Chat())
found = named.View().items
check('Key Items category', #found == 2 and found[1].label == '❮Ancient Fire Seal❯' and found[2].label == '❮Hellfire Map❯'
    and found[1].kind == 'keyitem')
named.Close()
-- An item no longer held is gone the next time the list opens
sold = true
named.Open('crystal', 7)
check('an item sold is gone', not find(named.View().items, '❮Fire Crystal❯', 'item'))
named.Open('cluster', 7)
check('an item still held stays', find(named.View().items, '❮Fire Cluster❯', 'item'))
sold = false
-- The note drawn at the right, dimmed
named.Open('fire', 4); texts = {}; calls = {}
check('drawn with notes', translate.Draw(named, layout, 0) == true)
local note
for _, t in ipairs(texts) do if t.text == 'item' then note = t end end
check('note dimmed', note and note.color[4] == 0.6)
named.Close()
-- A names list that fails leaves the dictionary
local failing = translate.New(auto, function() error('no resources') end)
failing.Open('hel', 3)
check('failing names: phrases still found', #failing.View().items == distinct('hel'))
auto.Clear()
print('Chatbox translate: word at the caret, CP932 and tokens, search, categories, deferred insertion, send bytes, rollback, limits, refresh, items, key items and draw passed')
