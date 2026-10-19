-- links: what a word in the log names, and a tooltip of what is known of it.
--
--   links.Kinds                     the kinds the settings can switch, in order, { key, label }
--   links.Tokens(raw)               the auto-translate and link tokens of a line as the game gave it
--   links.At(text, offset, tokens, enabled)
--                                   the item, key item, spell, ability, weapon skill, quest, place or
--                                   phrase under one byte of a drawn row, or nil
--   links.Tooltip(reference, notes) that reference's tooltip, now, through winxi.tooltip; notes false leaves
--                                   out the dimmed lines (the catalogs' caveats, a phrase's category and kind)
--   links.Reset()                   drops every name map and every row's results
--
-- A bracketed phrase or link is known by its token where chatbox gives the row's tokens; anything else is
-- known by its name, the longest name of one to six words round the mouse. Names of one word must be
-- written as the game writes them (Fire and Shield are ordinary words too); longer names are matched
-- whatever their case. Items are asked of the client by name; spells, abilities, weapon skills, quests
-- and places are looked up in maps made once, the first time a row is hovered, and kept until Reset.
-- Nothing here raises: whatever fails is no match, or no tooltip.
local links = {}

links.Kinds = {
    { key = 'items', label = 'Items' },
    { key = 'actions', label = 'Spells And Abilities' },
    { key = 'weaponskills', label = 'Weapon Skills' },
    { key = 'quests', label = 'Quests' },
    { key = 'places', label = 'Places' },
    { key = 'autotranslate', label = 'Auto-Translate' },
}

-- Which setting each kind of reference answers to
local setting = {
    item = 'items', keyitem = 'items', spell = 'actions', ability = 'actions',
    weaponskill = 'weaponskills', quest = 'quests', place = 'places', phrase = 'autotranslate',
}

-- Of two names as long as each other, the one of the kind first here wins
local priority = { item = 1, spell = 2, ability = 3, weaponskill = 4, quest = 5, place = 6 }

local OPEN, CLOSE = '\226\157\174', '\226\157\175' -- ❮ and ❯, as log.Clean writes them
local MAX_WORDS = 6
local MAX_ROWS = 512       -- rows remembered before the cache starts again
local MAX_LOOKUPS = 8192   -- names remembered before the cache starts again
local ZONES = 299

local names = nil          -- lowercase name -> { { kind, id, log, display }, ... }; nil until first wanted
local phrases = nil        -- lowercase phrase text (English and Japanese) -> phrase id
local lookups, lookupCount = {}, 0   -- a candidate as written -> its hits
local rows, rowCount = {}, 0         -- a row's text -> what is known of it
local tips = {}                      -- a reference's key -> its tooltip, made once

-- A module, or nil where it cannot be loaded (offline, or without a device)
local function Load(name)
    local ok, module = pcall(require, name)
    return ok and module or nil
end

local function Resources()
    if AshitaCore == nil then return nil end
    local ok, manager = pcall(function() return AshitaCore:GetResourceManager() end)
    return ok and manager or nil
end

-- The English name of a client resource (Name[1]), or nil
local function ResourceName(resource)
    if resource == nil then return nil end
    local ok, name = pcall(function() return resource.Name[1] end)
    return ok and type(name) == 'string' and name ~= '' and name or nil
end

local function Collapse(text)
    return (text:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

-- Client strings are CP932; what is not plain ASCII is left out rather than drawn as noise
local function Plain(text)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('\129\64', ' '):gsub('[\128-\255]', ''):gsub('[%z\1-\9\11-\31\127]', '')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    return text ~= '' and text or nil
end

-- The server's lowercase names in the game's case, for the one-word check where the client is not
-- there to say: "cure iv" is Cure IV
local function Title(name)
    return (name:gsub("[%w']+", function(word)
        if word:match('^[ivx]+$') then return word:upper() end
        return word:sub(1, 1):upper() .. word:sub(2)
    end))
end

local function Add(map, key, entry)
    key = Collapse(key):lower()
    if key == '' then return end
    local list = map[key]
    if list == nil then list = {}; map[key] = list end
    for _, other in ipairs(list) do
        if other.kind == entry.kind and other.id == entry.id and other.log == entry.log then return end
    end
    list[#list + 1] = entry
end

local catalogKinds = {
    { module = 'winxi.spells', kind = 'spell' },
    { module = 'winxi.abilities', kind = 'ability' },
    { module = 'winxi.weaponskills', kind = 'weaponskill' },
}

-- The one map of spell, ability, weapon skill, quest and place names, made once
local function Names()
    if names ~= nil then return names end
    local map = {}
    for _, source in ipairs(catalogKinds) do
        local api = Load(source.module)
        if api ~= nil then
            pcall(function()
                for _, id in ipairs(api.Ids()) do
                    local record = api.Get(id)
                    if record ~= nil and type(record.Name) == 'string' then
                        local server = record.Name:gsub('_', ' ')
                        local client = ResourceName(api.ClientResource(id))
                        local entry = { kind = source.kind, id = id, display = client or Title(server) }
                        if client ~= nil then Add(map, client, entry) end
                        Add(map, server, entry)
                    end
                end
            end)
            pcall(api.Clear) -- the map is what is wanted; the pages come back for a tooltip
        end
    end
    local quests = Load('winxi.quests')
    if quests ~= nil then
        pcall(function()
            for _, key in ipairs(quests.Keys()) do
                local record = quests.GetKey(key)
                if record ~= nil and type(record.Name) == 'string' and record.Log ~= nil then
                    local name = Collapse(record.Name:gsub('_', ' '))
                    Add(map, name, { kind = 'quest', id = record.Id, log = record.Log, display = name })
                end
            end
        end)
        pcall(quests.Clear)
    end
    local manager = Resources()
    if manager ~= nil then
        for id = 0, ZONES do
            local ok, name = pcall(function() return manager:GetString('zones.names', id) end)
            name = ok and Plain(name) or nil
            if name ~= nil and name:lower() ~= 'none' then
                Add(map, name, { kind = 'place', id = id, display = name })
            end
        end
    end
    names = map
    return names
end

-- Auto-translate phrases by their text, for brackets whose token is not known
local function Phrases()
    if phrases ~= nil then return phrases end
    local map = {}
    local auto = Load('winxi.autotranslate')
    if auto ~= nil then
        pcall(function()
            for _, id in ipairs(auto.Ids()) do
                local record = auto.Get(id)
                for _, locale in ipairs({ 'en', 'ja' }) do
                    local text = record and record.Text and record.Text[locale]
                    if type(text) == 'string' and map[text:lower()] == nil then map[text:lower()] = id end
                end
            end
        end)
    end
    phrases = map
    return phrases
end

-- Every kind a written name could be: { { kind, id, log }, ... }, remembered by the name as written
local function Lookup(candidate, words)
    local hits = lookups[candidate]
    if hits ~= nil then return hits end
    hits = {}
    -- One word must be at least three letters long and written as the game writes it
    if candidate:find('%a') and (words > 1 or #candidate >= 3) then
        local lower = candidate:lower()
        local manager = Resources()
        if manager ~= nil then
            local ok, item = pcall(function() return manager:GetItemByName(candidate, 0) end)
            local name = ok and ResourceName(item)
            if name ~= nil and (words > 1 and name:lower() == lower or name == candidate) then
                local found, id = pcall(function() return item.Id end)
                if found and type(id) == 'number' and id > 0 then hits[#hits + 1] = { kind = 'item', id = id } end
            end
        end
        for _, entry in ipairs(Names()[lower] or {}) do
            if words > 1 or entry.display == candidate then
                hits[#hits + 1] = { kind = entry.kind, id = entry.id, log = entry.log }
            end
        end
    end
    if lookupCount >= MAX_LOOKUPS then lookups, lookupCount = {}, 0 end
    lookups[candidate], lookupCount = hits, lookupCount + 1
    return hits
end

-- A timestamp at the start of a row, as log.Stamp knows them ([23:55:59], [11:55 PM])
local function StampEnd(text)
    local stamp = text:match('^(%[%d%d?:%d%d[%d:]*%s?[AaPp]?[Mm]?%])')
    return stamp and #stamp or 0
end

-- The words of a row past its timestamp: runs of letters, digits, apostrophes, hyphens and plus signs
-- (and anything not ASCII but the brackets), less the quotes round them
local function Words(text, from)
    local words = {}
    local i, length = from + 1, #text
    while i <= length do
        local b = text:byte(i)
        local open = b >= 0x80 and text:sub(i, i + 2) ~= OPEN and text:sub(i, i + 2) ~= CLOSE
            or (b < 0x80 and text:sub(i, i):match("[%w'%-+]") ~= nil)
        if open then
            local first = i
            while i <= length do
                b = text:byte(i)
                if b >= 0x80 then
                    local three = text:sub(i, i + 2)
                    if three == OPEN or three == CLOSE then break end
                    i = i + 1
                elseif text:sub(i, i):match("[%w'%-+]") then
                    i = i + 1
                else
                    break
                end
            end
            local last = i - 1
            local word = text:sub(first, last)
            if not word:match('^%-+$') then
                -- quotes and dashes round a word are not part of it
                while first <= last and text:sub(first, first):match("['%-]") do first = first + 1 end
                while last >= first and text:sub(last, last):match("['%-]") do last = last - 1 end
            end
            if first <= last then words[#words + 1] = { first = first, last = last } end
        elseif b >= 0x80 then
            i = i + 3 -- a bracket
        else
            i = i + 1
        end
    end
    return words
end

-- The complete bracket pairs of a row, in order: { open, close } (close is the last byte of ❯)
local function Pairs(text, from)
    local pairs_ = {}
    local at = from + 1
    while true do
        local open = text:find(OPEN, at, true)
        if open == nil then break end
        local close = text:find(CLOSE, open + 3, true)
        if close == nil then break end
        local reopen = text:find(OPEN, open + 3, true)
        if reopen ~= nil and reopen < close then
            at = reopen -- an opening without its close (the line wrapped); the next one is the pair's
        else
            pairs_[#pairs_ + 1] = { open = open, close = close + 2 }
            at = close + 3
        end
    end
    return pairs_
end

local function Row(text, tokens)
    local row = rows[text]
    if row ~= nil and row.tokens == tokens then return row end
    local stamp = StampEnd(text)
    row = { tokens = tokens, words = Words(text, stamp), pairs = Pairs(text, stamp), results = {} }
    if rows[text] == nil then
        if rowCount >= MAX_ROWS then rows, rowCount = {}, 0 end
        rowCount = rowCount + 1
    end
    rows[text] = row
    return row
end

local function On(enabled, kind)
    return enabled == nil or enabled[setting[kind]] == true
end

local function Reference(hit, text, first, last)
    return { kind = hit.kind, id = hit.id, log = hit.log, name = text:sub(first, last), first = first, last = last }
end

-- Of the hits of one candidate, the enabled one of the kind first in priority
local function Best(hits, enabled)
    local best = nil
    for _, hit in ipairs(hits) do
        if On(enabled, hit.kind) and (best == nil or priority[hit.kind] < priority[best.kind]) then best = hit end
    end
    return best
end

local tokenKinds = { phrase = 'phrase', item = 'item', keyitem = 'keyitem' }

local function InBracket(row, text, offset, enabled)
    for n, pair in ipairs(row.pairs) do
        if offset >= pair.open and offset <= pair.close then
            local first, last = pair.open + 3, pair.close - 3
            local token = row.tokens and row.tokens[n]
            local kind = token and tokenKinds[token.kind]
            if kind ~= nil and type(token.id) == 'number' then
                if not On(enabled, kind) then return false end
                local inner = first <= last and Collapse(text:sub(first, last)) or ''
                return { kind = kind, id = token.id, name = inner, first = pair.open, last = pair.close }
            end
            if first > last then return nil end
            local inner = Collapse(text:sub(first, last))
            local words = select(2, inner:gsub('%S+', ''))
            if words > 0 and words <= MAX_WORDS then
                local hit = Best(Lookup(inner, words), enabled)
                if hit ~= nil then
                    local reference = Reference(hit, text, pair.open, pair.close)
                    reference.name = inner
                    return reference
                end
            end
            local phrase = On(enabled, 'phrase') and Phrases()[inner:lower()]
            if phrase then
                return { kind = 'phrase', id = phrase, name = inner, first = pair.open, last = pair.close }
            end
            return nil
        end
    end
    return nil
end

-- The longest name round the word at index w, of the enabled kinds
local function AtWord(row, text, w, enabled)
    local words = row.words
    -- how far a name can run: words parted only by spaces
    local low, high = w, w
    while low > 1 and w - low < MAX_WORDS - 1 and not text:sub(words[low - 1].last + 1, words[low].first - 1):find('%S') do
        low = low - 1
    end
    while high < #words and high - w < MAX_WORDS - 1 and not text:sub(words[high].last + 1, words[high + 1].first - 1):find('%S') do
        high = high + 1
    end
    for count = MAX_WORDS, 1, -1 do
        local found = nil
        for first = math.max(low, w - count + 1), w do
            local last = first + count - 1
            if last >= w and last <= high then
                local candidate = Collapse(text:sub(words[first].first, words[last].last))
                local hit = Best(Lookup(candidate, count), enabled)
                if hit ~= nil and (found == nil or priority[hit.kind] < priority[found.hit.kind]) then
                    found = { hit = hit, first = words[first].first, last = words[last].last }
                end
            end
        end
        if found ~= nil then return Reference(found.hit, text, found.first, found.last) end
    end
    return false
end

local function Signature(enabled)
    if enabled == nil then return '*' end
    local parts = {}
    for i, kind in ipairs(links.Kinds) do parts[i] = enabled[kind.key] and '1' or '0' end
    return table.concat(parts)
end

local function Find(text, offset, tokens, enabled)
    local row = Row(text, tokens)
    local signature = Signature(enabled)
    local results = row.results[signature]
    if results == nil then results = {}; row.results[signature] = results end
    -- by the bracket pair or the word under the mouse: every byte of one has the same answer
    for n, pair in ipairs(row.pairs) do
        if offset >= pair.open and offset <= pair.close then
            local slot = 'p' .. n
            if results[slot] == nil then results[slot] = InBracket(row, text, offset, enabled) or false end
            if results[slot] then return results[slot] end
            -- a link switched off is nothing; a bracket of words unknown as a whole can still hold a name
            if row.tokens and row.tokens[n] then return nil end
            break
        end
    end
    local w = nil
    for i, word in ipairs(row.words) do
        if offset >= word.first and offset <= word.last then w = i; break end
        if word.first > offset then break end
    end
    if w == nil then return nil end
    if results[w] == nil then results[w] = AtWord(row, text, w, enabled) end
    return results[w] or nil
end

function links.At(text, offset, tokens, enabled)
    if type(text) ~= 'string' or type(offset) ~= 'number' or offset < 1 or offset > #text then return nil end
    if tokens ~= nil and type(tokens) ~= 'table' then tokens = nil end
    if enabled ~= nil and type(enabled) ~= 'table' then enabled = nil end
    local ok, reference = pcall(Find, text, math.floor(offset), tokens, enabled)
    if not ok or not reference then return nil end
    -- a copy, so what chatbox does with it never reaches the cache
    return { kind = reference.kind, id = reference.id, log = reference.log, name = reference.name,
        first = reference.first, last = reference.last }
end

function links.Tokens(raw)
    local found = {}
    if type(raw) ~= 'string' then return found end
    pcall(function()
        local auto = require('winxi.autotranslate')
        local i = raw:find('\253', 1, true)
        while i ~= nil and i + 5 <= #raw do
            local decoded = raw:byte(i + 5) == 0xFD and auto.Decode(raw:sub(i, i + 5)) or nil
            if decoded ~= nil and tokenKinds[decoded.Kind] then
                found[#found + 1] = { kind = decoded.Kind, id = decoded.Id }
                i = raw:find('\253', i + 6, true)
            else
                i = raw:find('\253', i + 1, true)
            end
        end
    end)
    return found
end

-- Tooltips ----------------------------------------------------------------------------------------

-- A tooltip is made once for each reference: { title, icon, lines = { { text, dim } } }
local function Tip()
    local tip = { lines = {} }
    function tip.Line(text, dim)
        if type(text) == 'string' and text ~= '' then tip.lines[#tip.lines + 1] = { text = text, dim = dim } end
    end
    function tip.Gap()
        if #tip.lines > 0 and not tip.lines[#tip.lines].gap then tip.lines[#tip.lines + 1] = { gap = true } end
    end
    function tip.Model(model)
        if model == nil then return end
        if model.ClientDescription then tip.Line(Plain(model.ClientDescription)); tip.Gap() end
        for _, line in ipairs(model.Lines or {}) do tip.Line(line) end
        if model.Warnings and #model.Warnings > 0 then tip.Gap() end
        for _, line in ipairs(model.Warnings or {}) do tip.Line(line, true) end
    end
    return tip
end

local function ItemTip(reference)
    local tip = Tip()
    local manager = Resources()
    local resource = nil
    if manager ~= nil then
        local ok, found = pcall(function() return manager:GetItemById(reference.id) end)
        resource = ok and found or nil
    end
    tip.title = ResourceName(resource) or reference.name
    tip.icon = reference.id
    local items = Load('winxi.items')
    local model = nil
    if items ~= nil then
        local ok, made = pcall(items.Tooltip, reference.id, resource)
        model = ok and made or nil
    end
    if model ~= nil then
        tip.title = tip.title or model.Name
        tip.Model(model)
    elseif resource ~= nil then
        local ok, description = pcall(function() return resource.Description[1] end)
        tip.Line(ok and Plain(description) or nil)
    end
    return tip
end

local function KeyItemTip(reference)
    local tip = Tip()
    local manager = Resources()
    local function String(table_)
        if manager == nil then return nil end
        local ok, text = pcall(function() return manager:GetString(table_, reference.id) end)
        return ok and Plain(text) or nil
    end
    tip.title = type(reference.name) == 'string' and reference.name ~= '' and reference.name or String('keyitems.names')
    tip.Line('Key item')
    local description = String('keyitems.descriptions')
    if description then tip.Gap(); tip.Line(description) end
    return tip
end

local actionModules = { spell = 'winxi.spells', ability = 'winxi.abilities', weaponskill = 'winxi.weaponskills' }

local function ActionTip(reference)
    local tip = Tip()
    local api = Load(actionModules[reference.kind])
    if api ~= nil then
        local resource = nil
        local ok, found = pcall(api.ClientResource, reference.id)
        resource = ok and found or nil
        local made
        ok, made = pcall(api.Tooltip, reference.id, resource)
        if ok and made then
            tip.title = ResourceName(resource) or reference.name or made.Name
            tip.Model(made)
        end
    end
    tip.title = tip.title or reference.name
    return tip
end

local function QuestTip(reference)
    local tip = Tip()
    local quests = Load('winxi.quests')
    if quests ~= nil then
        local ok, made = pcall(quests.Tooltip, reference.log, reference.id)
        if ok and made then
            tip.title = made.Name
            tip.Model(made)
        end
    end
    tip.title = tip.title or reference.name
    return tip
end

local function PlaceTip(reference)
    local tip = Tip()
    tip.title = reference.name
    local manager = Resources()
    if manager ~= nil then
        local ok, name = pcall(function() return manager:GetString('zones.names', reference.id) end)
        tip.title = ok and Plain(name) or tip.title
    end
    local mobs = Load('winxi.mobs')
    local zone = nil
    if mobs ~= nil then
        local ok, found = pcall(mobs.Zone, reference.id)
        zone = ok and found or nil
    end
    if zone ~= nil and zone.Names ~= nil then
        local low, high, kinds, notorious = nil, nil, {}, {}
        for name, monster in pairs(zone.Names) do
            if type(monster) == 'table' then
                -- one monster in several herds ("Bull [Herd2]") is counted once
                local base = tostring(name):gsub('%s*%[.-%]$', '')
                kinds[base] = true
                if monster.Notorious then notorious[base] = true end
                if type(monster.MinLevel) == 'number' and monster.MinLevel > 0 then low = math.min(low or monster.MinLevel, monster.MinLevel) end
                if type(monster.MaxLevel) == 'number' and monster.MaxLevel > 0 then high = math.max(high or monster.MaxLevel, monster.MaxLevel) end
            end
        end
        local count, named = 0, 0
        for base in pairs(kinds) do count = count + 1; if notorious[base] then named = named + 1 end end
        if low and high then
            tip.Line(low == high and ('Monsters: level %d'):format(low) or ('Monsters: levels %d to %d'):format(low, high))
        end
        if count > 0 then
            tip.Line(('%d %s, %d notorious'):format(count, count == 1 and 'monster' or 'monsters', named))
        end
    end
    local quests = Load('winxi.quests')
    if quests ~= nil then
        -- counted from the index, as ForZone would list them, without reading every quest log
        local ok, count = pcall(function()
            local n = 0
            for _, key in ipairs((quests.Index().ByZone or {})[reference.id] or {}) do
                if key:sub(1, 7) ~= 'hidden:' then n = n + 1 end
            end
            return n
        end)
        if ok and count > 0 then tip.Line(('%d %s mention this place'):format(count, count == 1 and 'quest' or 'quests')) end
    end
    return tip
end

local function PhraseTip(reference)
    local tip = Tip()
    local auto = Load('winxi.autotranslate')
    if auto ~= nil then
        pcall(function()
            local record = auto.Get(reference.id)
            tip.title = auto.Text(reference.id, 'en')
            tip.Line(auto.Text(reference.id, 'ja'))
            for _, category in ipairs(auto.Categories()) do
                if record and category.Id == record.Category then
                    tip.Line('Category: ' .. tostring(category.Names and category.Names.en or category.Id), true)
                    break
                end
            end
        end)
    end
    tip.title = tip.title or reference.name
    tip.Line('Auto-Translate', true)
    return tip
end

local makers = {
    item = ItemTip, keyitem = KeyItemTip, spell = ActionTip, ability = ActionTip, weaponskill = ActionTip,
    quest = QuestTip, place = PlaceTip, phrase = PhraseTip,
}

local function Draw(imgui, tip, notes)
    if tip.icon ~= nil then
        local icons = Load('winxi.itemicons')
        if icons ~= nil then
            pcall(function()
                local sheet = icons.Frame()
                local uv = sheet and icons.Place(tip.icon)
                if uv then
                    imgui.Image(sheet, { 32, 32 }, { uv[1], uv[2] }, { uv[3], uv[4] })
                    imgui.SameLine()
                end
            end)
        end
    end
    local theme = Load('winxi.theme')
    local look = theme and theme.Get() or {}
    local colour = look.TitleColor or look.TextColor
    if colour and imgui.TextColored then imgui.TextColored(colour, tip.title or '') else imgui.Text(tip.title or '') end
    -- a gap is drawn only before a line that follows it; without the notes, none may
    local gap = false
    for _, line in ipairs(tip.lines) do
        if line.gap then
            gap = true
        elseif not line.dim or notes then
            if gap and imgui.Spacing then imgui.Spacing() end
            gap = false
            if line.dim and imgui.TextDisabled then imgui.TextDisabled(line.text) else imgui.Text(line.text) end
        end
    end
end

function links.Tooltip(reference, notes)
    if type(reference) ~= 'table' or makers[reference.kind] == nil or type(reference.id) ~= 'number' then return false end
    local key = ('%s:%s:%d'):format(reference.kind, tostring(reference.log), reference.id)
    local tip = tips[key]
    if tip == nil then
        local ok, made = pcall(makers[reference.kind], reference)
        tip = ok and made or false
        tips[key] = tip
    end
    if not tip then return false end
    local imgui = Load('imgui')
    local tooltip = Load('winxi.tooltip')
    if imgui == nil or tooltip == nil then return false end
    local ok, shown = pcall(tooltip.Begin)
    if not ok or not shown then return false end
    pcall(Draw, imgui, tip, notes ~= false)
    pcall(tooltip.End)
    return true
end

function links.Reset()
    names, phrases = nil, nil
    lookups, lookupCount = {}, 0
    rows, rowCount = {}, 0
    tips = {}
end

return links
