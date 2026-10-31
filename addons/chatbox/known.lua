-- The items and key items a character's auto-translate list holds, as the game's own Items and Key Items lists:
-- what the character has held, kept between sessions in a file of their own, and what was heard in chat (an item
-- or key item token in any line), kept until the game shuts down and shared by every character played until then.
-- Plain data, no game calls: the caller says who the character is, what they hold and what was heard.
local M = {}
M.Kinds = { 'item', 'keyitem' }

local function Empty() return { item = {}, keyitem = {} } end
local function Valid(kind, id)
    return (kind == 'item' or kind == 'keyitem') and type(id) == 'number' and id >= 0 and id <= 65535 and id == math.floor(id)
end

-- The file's ids, or an empty list where it is missing or not what was written: it is data, loaded with no globals.
function M.Parse(text)
    local list = Empty()
    if type(text) ~= 'string' then return list end
    local chunk = loadstring(text)
    if not chunk then return list end
    setfenv(chunk, {})
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then return list end
    for _, kind in ipairs(M.Kinds) do
        if type(data[kind]) == 'table' then
            for _, id in ipairs(data[kind]) do
                if Valid(kind, id) then list[kind][id] = true end
            end
        end
    end
    return list
end

function M.Format(list)
    local parts = {}
    for _, kind in ipairs(M.Kinds) do
        local ids = {}
        for id in pairs(list[kind]) do ids[#ids + 1] = id end
        table.sort(ids)
        parts[#parts + 1] = '    ' .. kind .. ' = { ' .. table.concat(ids, ', ') .. ' },'
    end
    return '-- chatbox: the items and key items in this character\'s auto-translate list\nreturn {\n' .. table.concat(parts, '\n') .. '\n}\n'
end

-- files: { Read(character) -> text or nil, Write(character, text) -> true or nil, error }
function M.New(files)
    local store = { character = nil, problem = nil }
    local held, heard, dirty = Empty(), Empty(), false

    -- Who is playing: a key naming the character, or nil while it cannot be told. A character's held list is read
    -- each time they are switched to; what was heard stays, for whoever plays next.
    function store.Use(character)
        if character == nil or character == store.character then return end
        store.Save()
        store.character, dirty = character, false
        local ok, text = pcall(files.Read, character)
        held = M.Parse(ok and text or nil)
    end

    function store.Hold(kind, id)
        if Valid(kind, id) and not held[kind][id] then held[kind][id], dirty = true, true end
    end

    function store.Hear(kind, id)
        if Valid(kind, id) and not held[kind][id] then heard[kind][id] = true end
    end

    function store.Save()
        if not dirty or store.character == nil then return true end
        local ok, written, err = pcall(files.Write, store.character, M.Format(held))
        if ok and written then dirty, store.problem = false, nil; return true end
        store.problem = tostring(ok and err or written)
        return false
    end

    -- Each id once, held before heard: fn(kind, id, heard)
    function store.Each(fn)
        for _, kind in ipairs(M.Kinds) do
            for id in pairs(held[kind]) do fn(kind, id, false) end
            for id in pairs(heard[kind]) do if not held[kind][id] then fn(kind, id, true) end end
        end
    end

    function store.Counts()
        local counts = { held = 0, heard = 0 }
        store.Each(function(_, _, wasHeard) if wasHeard then counts.heard = counts.heard + 1 else counts.held = counts.held + 1 end end)
        return counts
    end

    return store
end

return M
