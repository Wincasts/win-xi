-- Chatbox links: tokens, names under the mouse and their tooltips, against the real catalogs and a
-- stand-in for the client's resources. No FFXI needed.
package.path = 'addons/chatbox/?.lua;addons/libs/?.lua;' .. package.path
require('winxi.gamedata').Root('addons/libs/winxi/data/')

-- imgui and the tooltip record what is drawn
local drawn, begun, ended = {}, 0, 0
package.loaded.imgui = {
    Text = function(text) drawn[#drawn + 1] = text end,
    TextColored = function(colour, text) drawn[#drawn + 1] = text; drawn.titleColour = colour end,
    TextDisabled = function(text) drawn[#drawn + 1] = text; drawn.dim = drawn.dim or {}; drawn.dim[text] = true end,
    Image = function(sheet, size, uv0, uv1) drawn.image = { sheet = sheet, size = size, uv0 = uv0, uv1 = uv1 } end,
    SameLine = function() end,
    Spacing = function() end,
}
local tooltipsOn = true
package.loaded['winxi.tooltip'] = {
    Begin = function() if not tooltipsOn then return false end begun = begun + 1; return true end,
    End = function() ended = ended + 1 end,
}
local title = { 0.9, 0.8, 0.1, 1 }
package.loaded['winxi.theme'] = { Get = function() return { TitleColor = title, TextColor = { 1, 1, 1, 1 } } end }
local framed = 0
package.loaded['winxi.itemicons'] = {
    Frame = function() framed = framed + 1; return 77 end,
    Place = function(id) return id == 12306 and { 0.1, 0.2, 0.3, 0.4 } or nil end,
}

-- The client's resources, with a few names, and a count of every call
local calls = 0
local function counted(f) return function(...) calls = calls + 1; return f(...) end end
local items = {
    [12306] = { Id = 12306, Name = { 'Kite Shield' }, Description = { 'DEF:22' } },
    [4096] = { Id = 4096, Name = { 'Fire Crystal' } },
    [17440] = { Id = 17440, Name = { 'Raise II' } }, -- an item of a spell's name, for the tie
    [99] = { Id = 99, Name = { '55 PM' } },          -- what a timestamp would match if read
    [98] = { Id = 98, Name = { 'Shield' } },
}
local spellNames = { [4] = { Name = { 'Cure IV' }, Description = { 'Restores a great deal of HP.' } } }
local abilityNames = { [16 + 512] = { Name = { 'Mighty Strikes' } } }
local zones = { [100] = 'West Ronfaure', [230] = "Southern San d'Oria" }
local manager = {
    GetItemByName = counted(function(_, name, lang)
        assert(lang == 0, 'items are asked for in English')
        for _, item in pairs(items) do if item.Name[1]:lower() == name:lower() then return item end end
        return nil
    end),
    GetItemById = counted(function(_, id) return items[id] end),
    GetSpellById = counted(function(_, id) return spellNames[id] end),
    GetAbilityById = counted(function(_, id) return abilityNames[id] end),
    GetString = counted(function(_, table_, id)
        if table_ == 'zones.names' then return zones[id] end
        if table_ == 'keyitems.descriptions' and id == 1 then return 'A key for testing.' end
        if table_ == 'keyitems.names' and id == 1 then return 'Test Key' end
        return nil
    end),
}
AshitaCore = { GetResourceManager = function() return manager end }

local links = require('links')
local auto = require('winxi.autotranslate')
local spells = require('winxi.spells')
local quests = require('winxi.quests')
local function check(label, ok) assert(ok, label) end
local function find(text, word, nth)
    local at = 0
    for _ = 1, nth or 1 do at = assert(text:find(word, at + 1, true), word) end
    return at
end
local all = { items = true, actions = true, weaponskills = true, quests = true, places = true, autotranslate = true }
local function without(key) local copy = {}; for k, v in pairs(all) do copy[k] = v end; copy[key] = false; return copy end

-- The kinds, in order, for the settings
local keys = {}
for i, kind in ipairs(links.Kinds) do keys[i] = kind.key .. '=' .. kind.label end
check('kinds', table.concat(keys, ',') == 'items=Items,actions=Spells And Abilities,weaponskills=Weapon Skills,'
    .. 'quests=Quests,places=Places,autotranslate=Auto-Translate')

-- Tokens: a phrase, an item and a key item among junk and colour escapes
local phrase = auto.Search('Nice to meet you.', 'en', nil, 1)[1].Id
local raw = '\30\2Hi ' .. auto.Token(phrase, 'en') .. ' look \253\1\2 ' .. auto.ItemToken(12306, 'en')
    .. '\253\253\253\253\253\253' .. auto.KeyItemToken(1, 'en') .. '\253\2'
local tokens = links.Tokens(raw)
check('three tokens', #tokens == 3)
check('phrase token', tokens[1].kind == 'phrase' and tokens[1].id == phrase)
check('item token', tokens[2].kind == 'item' and tokens[2].id == 12306)
check('key item token', tokens[3].kind == 'keyitem' and tokens[3].id == 1)
check('no tokens', #links.Tokens('plain text') == 0 and #links.Tokens(nil) == 0 and #links.Tokens('\253') == 0)

-- Nothing is read until At is first called
check('lazy', calls == 0)

-- Bracketed links, by their tokens
local row = '[12:00:00] Win : \226\157\174Nice to meet you.\226\157\175 \226\157\174Kite Shield\226\157\175 \226\157\174Test Key\226\157\175'
local ref = links.At(row, find(row, 'meet'), tokens, all)
check('bracketed phrase', ref and ref.kind == 'phrase' and ref.id == phrase and ref.name == 'Nice to meet you.'
    and ref.first == find(row, '\226\157\174') and ref.last == find(row, '\226\157\175') + 2)
ref = links.At(row, find(row, 'Kite'), tokens, all)
check('bracketed item', ref and ref.kind == 'item' and ref.id == 12306 and ref.name == 'Kite Shield')
ref = links.At(row, find(row, '\226\157\174', 2), tokens, all)
check('the bracket itself is the link', ref and ref.kind == 'item')
ref = links.At(row, find(row, 'Test'), tokens, all)
check('bracketed key item', ref and ref.kind == 'keyitem' and ref.id == 1)
check('item links off', links.At(row, find(row, 'Kite'), tokens, without('items')) == nil
    and links.At(row, find(row, 'Test'), tokens, without('items')) == nil)
check('phrases off', links.At(row, find(row, 'meet'), tokens, without('autotranslate')) == nil)

-- Bracketed links without tokens, by their words
ref = links.At(row, find(row, 'meet'), nil, all)
check('bracketed phrase by its text', ref and ref.kind == 'phrase' and ref.id == phrase)
ref = links.At(row, find(row, 'Shield'), nil, all)
check('bracketed item by its name', ref and ref.kind == 'item' and ref.id == 12306)

-- Plain names
local cure = 4
check('catalog has cure iv', spells.Get(cure).Name == 'cure iv')
row = 'Win casts Cure IV on Tarutaru.'
ref = links.At(row, find(row, 'Cure'), nil, all)
check('plain spell, longest match', ref and ref.kind == 'spell' and ref.id == cure and ref.name == 'Cure IV'
    and ref.first == find(row, 'Cure') and ref.last == find(row, 'IV') + 1)
ref = links.At(row, find(row, 'IV') + 1, nil, all)
check('the match from its last word', ref and ref.id == cure)
check('no name under an ordinary word', links.At(row, find(row, 'casts'), nil, all) == nil)
check('spells off', links.At(row, find(row, 'Cure'), nil, without('actions')) == nil)

local fire
for _, id in ipairs(spells.Ids()) do if spells.Get(id).Name == 'fire' then fire = id; break end end
row = 'Fire is cast. The fire burns.'
ref = links.At(row, 1, nil, all)
check('one word, case-exact', ref and ref.kind == 'spell' and ref.id == fire and ref.name == 'Fire')
check('one word in another case is an ordinary word', links.At(row, find(row, 'fire'), nil, all) == nil)

row = 'Selh uses savage blade, then MIGHTY STRIKES!'
ref = links.At(row, find(row, 'blade'), nil, all)
check('weapon skill, case-insensitive', ref and ref.kind == 'weaponskill' and ref.id == 42 and ref.name == 'savage blade')
check('weapon skills off', links.At(row, find(row, 'blade'), nil, without('weaponskills')) == nil)
ref = links.At(row, find(row, 'STRIKES'), nil, all)
check('ability by its client name, punctuation not in it', ref and ref.kind == 'ability' and ref.id == 16
    and ref.name == 'MIGHTY STRIKES')

row = "Meet me in Southern San d'Oria, by the gate."
ref = links.At(row, find(row, 'San'), nil, all)
check('place', ref and ref.kind == 'place' and ref.id == 230 and ref.name == "Southern San d'Oria")
check('places off', links.At(row, find(row, 'San'), nil, without('places')) == nil)

row = "Doing A Sentry's Peril again."
ref = links.At(row, find(row, 'Peril'), nil, all)
check('quest', ref and ref.kind == 'quest' and ref.log == 0 and ref.id == 0 and ref.name == "A Sentry's Peril")
check('quests off', links.At(row, find(row, 'Peril'), nil, without('quests')) == nil)

row = 'Got a Kite Shield and a Shield and a shield.'
ref = links.At(row, find(row, 'Shield'), nil, all)
check('plain item, longest match', ref and ref.kind == 'item' and ref.id == 12306 and ref.name == 'Kite Shield')
ref = links.At(row, find(row, 'Shield', 2), nil, all)
check('one-word item', ref and ref.kind == 'item' and ref.id == 98)
check('one-word item, case-exact', links.At(row, find(row, 'shield'), nil, all) == nil)
check('items off', links.At(row, find(row, 'Kite'), nil, without('items')) == nil)

row = 'Need Raise II now'
ref = links.At(row, find(row, 'Raise'), nil, all)
check('item wins a tie with a spell', ref and ref.kind == 'item' and ref.id == 17440)
ref = links.At(row, find(row, 'Raise'), nil, without('items'))
check('the spell when items are off', ref and ref.kind == 'spell')

-- Never inside a timestamp
row = '[11:55 PM] Hello there'
check('nothing in a timestamp', links.At(row, find(row, 'PM'), nil, all) == nil
    and links.At(row, find(row, '55'), nil, all) == nil)

-- Garbage never raises
check('garbage', links.At(nil, 1) == nil and links.At('abc', 0) == nil and links.At('abc', 99) == nil
    and links.At('\226\157\174', 1, { {} }, 'x') == nil and links.At('\226\157\175 Fire', 6, 7) ~= nil)

-- The cache: the same row costs nothing the second time
row = 'Casting Cure IV soon'
links.At(row, find(row, 'Cure'), nil, all)
local before = calls
check('cached row', links.At(row, find(row, 'Cure'), nil, all).id == cure and calls == before)
check('cached word, another byte', links.At(row, find(row, 'Cure') + 2, nil, all).id == cure and calls == before)
local same = links.At(row, find(row, 'Cure'), nil, all)
same.id = -1
check('results are copies', links.At(row, find(row, 'Cure'), nil, all).id == cure)

-- Reset drops the maps: the next call builds them again
before = calls
links.Reset()
check('reset rebuilds', links.At(row, find(row, 'Cure'), nil, all).id == cure and calls > before + 800)

-- Tooltips
local function show(reference)
    for k in pairs(drawn) do drawn[k] = nil end
    local shown = links.Tooltip(reference)
    return shown, table.concat(drawn, '\n')
end
local function has(text, part) return text:find(part, 1, true) ~= nil end

local shown, text = show({ kind = 'item', id = 12306, name = 'Kite Shield' })
check('item tooltip shown', shown and begun == ended and begun == 1)
check('item tooltip title', drawn[1] == 'Kite Shield' and drawn.titleColour == title)
check('item tooltip body', has(text, 'DEF:22') and has(text, 'Stack: 1') and has(text, 'Level:'))
check('item tooltip warnings dimmed', drawn.dim and drawn.dim['Client description is presentation text, not verified server behavior.'])
check('item icon', drawn.image and drawn.image.sheet == 77 and drawn.image.size[1] == 32 and drawn.image.uv0[1] == 0.1
    and drawn.image.uv1[2] == 0.4 and framed == 1)

shown, text = show({ kind = 'keyitem', id = 1, name = 'Test Key' })
check('key item tooltip', shown and drawn[1] == 'Test Key' and has(text, 'Key item') and has(text, 'A key for testing.'))

shown, text = show({ kind = 'spell', id = cure, name = 'cure iv' })
check('spell tooltip', shown and drawn[1] == 'Cure IV' and has(text, 'Restores a great deal of HP.') and has(text, 'MP: ')
    and drawn.dim['Definition only: content restrictions, unlocks and player state are not evaluated.'])
shown, text = show({ kind = 'ability', id = 16, name = 'Mighty Strikes' })
check('ability tooltip', shown and drawn[1] == 'Mighty Strikes' and has(text, 'base recast'))
shown, text = show({ kind = 'weaponskill', id = 42, name = 'Savage Blade' })
check('weapon skill tooltip', shown and drawn[1] == 'Savage Blade' and has(text, 'Skill requirement:') and has(text, 'Skillchain:'))

shown, text = show({ kind = 'quest', log = 0, id = 0, name = "A Sentry's Peril" })
check('quest tooltip', shown and drawn[1] == "A Sentry's Peril" and has(text, 'Log: sandoria [0]; quest ID: 0'))

local zoneQuests = 0
for _, key in ipairs(quests.Index().ByZone[100] or {}) do if key:sub(1, 7) ~= 'hidden:' then zoneQuests = zoneQuests + 1 end end
check('the index count is ForZone\'s', zoneQuests == #quests.ForZone(100, { Limit = 9999 }))
shown, text = show({ kind = 'place', id = 100, name = 'West Ronfaure' })
check('place tooltip', shown and drawn[1] == 'West Ronfaure' and has(text, 'Monsters: levels ') and has(text, 'notorious')
    and has(text, ('%d quests mention this place'):format(zoneQuests)))

shown, text = show({ kind = 'phrase', id = phrase, name = 'Nice to meet you.' })
check('phrase tooltip', shown and drawn[1] == 'Nice to meet you.' and has(text, '初めまして。') and has(text, 'Category: '))

-- Without the notes: the dimmed lines left out, and no gap left for them
shown, text = show({ kind = 'item', id = 12306, name = 'Kite Shield' })
local withNotes = #drawn
for k in pairs(drawn) do drawn[k] = nil end
shown = links.Tooltip({ kind = 'item', id = 12306, name = 'Kite Shield' }, false)
check('notes off: no dimmed line', shown and drawn.dim == nil and #drawn < withNotes and drawn[1] == 'Kite Shield' and has(table.concat(drawn, '\n'), 'DEF:22'))
for k in pairs(drawn) do drawn[k] = nil end
shown = links.Tooltip({ kind = 'phrase', id = phrase, name = 'Nice to meet you.' }, false)
check('notes off: a phrase without its category and kind', shown and drawn.dim == nil and has(table.concat(drawn, '\n'), '初めまして。'))
for k in pairs(drawn) do drawn[k] = nil end
shown = links.Tooltip({ kind = 'item', id = 12306, name = 'Kite Shield' }, true)
check('notes on again', shown and drawn.dim ~= nil)

-- Made once: drawing it again asks nothing of the client
before = calls
show({ kind = 'item', id = 12306, name = 'Kite Shield' })
check('tooltip cached', calls == before)

tooltipsOn = false
check('tooltips off', not links.Tooltip({ kind = 'item', id = 12306 }) and begun == ended)
tooltipsOn = true
check('bad references', not links.Tooltip(nil) and not links.Tooltip({ kind = 'nothing', id = 1 }) and not links.Tooltip({ kind = 'item' }))

-- Offline: without the client, items and places match nothing but the catalogs still do
AshitaCore = nil
links.Reset()
row = 'Kite Shield and Cure IV in West Ronfaure'
check('offline items', links.At(row, find(row, 'Kite'), nil, all) == nil)
check('offline places', links.At(row, find(row, 'Ronfaure'), nil, all) == nil)
ref = links.At(row, find(row, 'Cure'), nil, all)
check('offline spells', ref and ref.kind == 'spell' and ref.id == cure)
shown, text = show({ kind = 'item', id = 12306, name = 'Kite Shield' })
check('offline item tooltip', shown and drawn[1] == 'Kite Shield' and has(text, 'Stack: 1'))

print('Chatbox links: tokens, bracketed links, plain names of every kind, case, longest match, timestamps, switches, caching, Reset and every tooltip passed')
