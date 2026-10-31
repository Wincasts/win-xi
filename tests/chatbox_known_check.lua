-- Chatbox's Auto-Translate item and key item list (known.lua): held between sessions per character, heard until
-- logging out, the file it keeps and the logout packet.
package.path = 'addons/chatbox/?.lua;' .. package.path
local known = dofile('addons/chatbox/known.lua')
local function check(label, ok) assert(ok, label) end

-- The file
local text = known.Format({ item = { [4104] = true, [4096] = true }, keyitem = { [0] = true, [5] = true } })
check('format sorted', text:find('item = { 4096, 4104 },', 1, true) and text:find('keyitem = { 0, 5 },', 1, true))
local back = known.Parse(text)
check('read back', back.item[4096] and back.item[4104] and back.keyitem[0] and back.keyitem[5])
check('nothing for no file', next(known.Parse(nil).item) == nil)
check('nothing for a broken file', next(known.Parse('return {').item) == nil)
check('no globals while read', next(known.Parse('return { item = { os.time() } }').item) == nil)
local odd = known.Parse('return { item = { 1.5, -1, 70000, "x", 7 }, keyitem = "no", other = { 1 } }')
check('only whole ids in range', odd.item[7] and not odd.item[1.5] and not odd.item[-1] and not odd.item[70000]
    and next(odd.keyitem) == nil)

-- The store
local files, writes, failing = {}, 0, false
local store = known.New({
    Read = function(character) return files[character] end,
    Write = function(character, value)
        if failing then return nil, 'disk full' end
        writes = writes + 1
        files[character] = value
        return true
    end,
})
local function list()
    local found = {}
    store.Each(function(kind, id, heard) found[kind .. id] = heard and 'heard' or 'held' end)
    return found
end
store.Hear('item', 300)
check('heard before the character is known', list().item300 == 'heard')
store.Use('Win_1')
check('the first character keeps it', list().item300 == 'heard')
store.Hold('item', 4096); store.Hold('keyitem', 5)
check('held', list().item4096 == 'held' and list().keyitem5 == 'held')
store.Hear('item', 4096)
check('heard what is held stays held', list().item4096 == 'held')
store.Hold('item', 300)
check('held what was heard is held', list().item300 == 'held')
store.Hear('item', 17); store.Hear('keyitem', 9)
store.Hear('phrase', 1); store.Hear('item', -3)
local counts = store.Counts()
check('counts', counts.held == 3 and counts.heard == 2)
check('saved', store.Save() and writes == 1 and known.Parse(files.Win_1).item[300] and not known.Parse(files.Win_1).item[17])
check('nothing to save twice', store.Save() and writes == 1)
store.Hold('item', 4096)
check('holding again changes nothing', store.Save() and writes == 1)
-- logging out drops what was heard, never what was held
store.Forget()
counts = store.Counts()
check('logged out', counts.held == 3 and counts.heard == 0 and list().item17 == nil)
-- another character: their own file, nothing heard carried over, the first saved before
store.Hear('item', 18)
store.Hold('item', 5000)
store.Use('Alt_2')
check('first saved on the switch', known.Parse(files.Win_1).item[5000])
check('the other starts empty', next(list()) == nil)
store.Hold('item', 1)
store.Use('Win_1')
check('the other saved on the switch back', known.Parse(files.Alt_2).item[1])
check('back to the first: held kept, heard gone', list().item5000 == 'held' and list().item18 == nil and list().item17 == nil)
store.Use(nil)
check('no character changes nothing', store.character == 'Win_1')
-- a failed write keeps the change for the next save and says why
failing = true
store.Hold('item', 6)
check('a failed write', not store.Save() and store.problem == 'disk full')
failing = false
check('written next time', store.Save() and store.problem == nil and known.Parse(files.Win_1).item[6])

-- The logout packet: 0x00B with a LogoutState that ends the session, at its fifth byte
local function packet(state) return '\11\14\0\0' .. string.char(state) .. string.rep('\0', 23) end
for _, state in ipairs({ 1, 5, 6, 7, 8, 9 }) do check('logout state ' .. state, known.LoggedOut(0x00B, packet(state))) end
for _, state in ipairs({ 0, 2, 3, 4, 10 }) do check('not a logout ' .. state, not known.LoggedOut(0x00B, packet(state))) end
check('another packet', not known.LoggedOut(0x00A, packet(1)) and not known.LoggedOut(0x00B, '\11\14') and not known.LoggedOut(0x00B, nil))

print('Chatbox known: the file, held and heard, logout, characters, failed writes and the logout packet passed')
