-- Text diagnostics, not executable Lua. Every data record carries its resolved identity
-- snapshot so offline replay does not depend on the client's current memory or roster.
local M = { Header = 'winxi-parse\t2\n' }
function M.Hex(text)
    return (text:gsub('.', function(c) return ('%02x'):format(c:byte()) end))
end
function M.Unhex(text)
    assert(#text % 2 == 0 and not text:find('[^%x]'), 'invalid hexadecimal field')
    return (text:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)) end))
end
function M.Data(now, data, identities)
    local actors = {}
    for _, info in pairs(identities) do
        actors[#actors + 1] = table.concat({ tostring(info.id), M.Hex(info.key), info.kind,
            M.Hex(info.name), tostring(info.owner_id or 0), M.Hex(info.owner_key or ''), M.Hex(info.owner_name or '') }, ',')
    end
    table.sort(actors)
    return ('D\t%.6f\t%s\t%s\n'):format(now, M.Hex(data), table.concat(actors, ';'))
end
function M.Control(kind, now) return ('%s\t%.6f\n'):format(kind, now) end
function M.WS(now, result)
    local p = result.profile or {}
    return table.concat({ 'W', ('%.6f'):format(now), M.Hex(result.actor.key), M.Hex(result.target.key),
        tostring(result.ability), tostring(result.tp or -1), tostring(p.base or 0), tostring(p.store or 0),
        tostring(p.attempts or 0), tostring(result.hits or -1), tostring(result.misses or -1), M.Hex(result.reason or 'accepted') }, '\t') .. '\n'
end
function M.Read(line)
    local ok, record = pcall(function()
        assert(#line <= 65536, 'capture record too large')
        local kind, stamp, tail = line:match('^(%u)\t([%d%.]+)(.*)$')
        local now = tonumber(stamp)
        assert(now and now >= 0 and now < math.huge, 'invalid capture timestamp')
        if kind == 'W' then
            local fields = {}
            for field in (tail:sub(2) .. '\t'):gmatch('(.-)\t') do fields[#fields + 1] = field end
            assert(tail:sub(1,1) == '\t' and #fields == 10, 'invalid WS result record')
            local record = { kind = kind, time = now, actor_key = M.Unhex(fields[1]), target_key = M.Unhex(fields[2]) }
            local keys = { 'ability', 'tp', 'base', 'store', 'attempts', 'hits', 'misses' }
            for i, key in ipairs(keys) do
                local n = tonumber(fields[i + 2])
                assert(n and n == math.floor(n) and n >= -1 and n <= 65535, 'invalid WS numeric field')
                record[key] = n
            end
            record.reason = M.Unhex(fields[10])
            if record.reason == 'accepted' then record.reason = '' end
            assert(#record.actor_key > 0 and #record.target_key > 0, 'missing WS identity')
            return record
        end
        if kind ~= 'D' then
            assert((kind == 'R' or kind == 'S' or kind == 'U') and tail == '', 'invalid control record')
            return { kind = kind, time = now }
        end
        local hex, actors = tail:match('^\t(%x+)\t(.*)$')
        assert(hex and #hex <= 1024, 'invalid packet field')
        local identities = {}
        for actor in actors:gmatch('[^;]+') do
            local id, key, entityKind, name, owner, ownerKey, ownerName = actor:match('^(%d+),(%x+),(%a+),(%x*),(%d+),(%x*),(%x*)$')
            id, owner = tonumber(id), tonumber(owner)
            assert(id and id > 0 and id < 2^32 and owner and owner < 2^32, 'invalid actor identity')
            assert(entityKind == 'mob' or entityKind == 'other' or entityKind == 'me' or entityKind == 'party'
                or entityKind == 'alliance' or entityKind == 'trust' or entityKind == 'pet' or entityKind == 'fellow', 'invalid entity kind')
            identities[id] = { id = id, key = M.Unhex(key), kind = entityKind, name = M.Unhex(name),
                owner_id = owner ~= 0 and owner or nil,
                owner_key = ownerKey ~= '' and M.Unhex(ownerKey) or nil,
                owner_name = ownerName ~= '' and M.Unhex(ownerName) or nil }
        end
        return { kind = kind, time = now, data = M.Unhex(hex), identities = identities }
    end)
    if not ok then return nil, tostring(record) end
    return record
end
return M
