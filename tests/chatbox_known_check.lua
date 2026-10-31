-- Chatbox's Auto-Translate item and key item list (known.lua): held between sessions per character, heard until
-- the game closes for every character played, and the file it keeps.
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
store.Hear('item', 300)
store.Hear('item', 17); store.Hear('keyitem', 9)
store.Hear('phrase', 1); store.Hear('item', -3)
local counts = store.Counts()
check('counts', counts.held == 3 and counts.heard == 2)
check('saved', store.Save() and writes == 1 and known.Parse(files.Win_1).item[300] and not known.Parse(files.Win_1).item[17])
check('nothing to save twice', store.Save() and writes == 1)
store.Hold('item', 4096)
check('holding again changes nothing', store.Save() and writes == 1)
-- another character: their own file, the first saved before, and what was heard shared
store.Hear('item', 18)
store.Hold('item', 5000)
store.Use('Alt_2')
check('first saved on the switch', known.Parse(files.Win_1).item[5000])
local alt = list()
check('the other: nothing held, everything heard', alt.item5000 == nil and alt.item4096 == nil and alt.item17 == 'heard'
    and alt.keyitem9 == 'heard' and alt.item18 == 'heard' and alt.item300 == 'heard')
store.Hold('item', 17)
check('held by the other', list().item17 == 'held')
store.Use('Win_1')
check('the other saved on the switch back', known.Parse(files.Alt_2).item[17])
local back = list()
check('back to the first: held kept, heard still there', back.item5000 == 'held' and back.item18 == 'heard' and back.item17 == 'heard')
store.Use(nil)
check('no character changes nothing', store.character == 'Win_1')
-- a failed write keeps the change for the next save and says why
failing = true
store.Hold('item', 6)
check('a failed write', not store.Save() and store.problem == 'disk full')
failing = false
check('written next time', store.Save() and store.problem == nil and known.Parse(files.Win_1).item[6])

print('Chatbox known: the file, held and heard, heard shared by the characters, failed writes passed')
