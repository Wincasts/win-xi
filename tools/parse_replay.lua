-- Usage from the repository root: luajit tools/parse_replay.lua capture.txt [--separate-pets] [--no-skillchains]
package.path = 'addons/parse/?.lua;' .. package.path
local capture = require('parse_capture')
local session = require('parse_session').New()
local core = require('parse_core')
local function main()
    assert(arg[1], 'usage: luajit tools/parse_replay.lua capture.txt [--separate-pets] [--no-skillchains]')
    local options = { combinePets = true, includeSkillchains = true }
    for i = 2, #arg do
        if arg[i] == '--separate-pets' then options.combinePets = false
        elseif arg[i] == '--no-skillchains' then options.includeSkillchains = false
        else error('unknown option: ' .. arg[i]) end
    end
    local file = assert(io.open(arg[1], 'rb'))
    local header = file:read('*l')
    header = header and header:gsub('\r$', '')
    assert(header == 'winxi-parse\t1' or header == 'winxi-parse\t2', 'unsupported capture format')
    local lineNumber, now = 1, 0
    for line in file:lines() do
        lineNumber = lineNumber + 1
        local record, err = capture.Read(line:gsub('\r$', ''))
        assert(record, ('line %d: %s'):format(lineNumber, tostring(err)))
        assert(record.time >= now, ('line %d: time moved backwards'):format(lineNumber))
        now = record.time
        assert(session:Replay(record), ('line %d: malformed action packet'):format(lineNumber))
    end
    file:close()
    local snapshot = session.core:Snapshot(now, options)
    print(('Observed damage: %d | active encounter: %.3fs | events: %d'):format(snapshot.total, snapshot.duration, session.core.event_count))
    for _, row in ipairs(snapshot.rows) do
        -- Character names are data; print never interprets them as a format string.
        print(('%s [%s]: %d | %s DPS | %.2f%%'):format(row.name, row.key, row.damage,
            row.dps and ('%.2f'):format(row.dps) or '--', row.share or 0))
        local melee = core.MeleeRate(row)
        print(('  melee including accepted WS TP estimates: %s'):format(melee and ('%.2f%%'):format(melee) or '--'))
        local categories = {}
        for category in pairs(row.categories) do categories[#categories + 1] = category end
        table.sort(categories)
        for _, category in ipairs(categories) do
            local stat = row.categories[category]
            local rate = core.Rate(stat)
            print(('  %s: damage %d, hits %d, misses %d, excluded %d, crits %d, observed hit rate %s'):format(
                category, stat.damage, stat.hits, stat.misses, stat.excluded, stat.criticals,
                rate and ('%.2f%%'):format(rate) or '--'))
        end
    end
    local unknown = {}
    for key in pairs(session.core.unknown) do unknown[#unknown + 1] = key end
    table.sort(unknown)
    for _, key in ipairs(unknown) do print(('Unclassified %s: %d'):format(key, session.core.unknown[key])) end
    print(('Unresolved identity observations: %d'):format(session.diagnostics.unresolved))
end
local ok, err = pcall(main)
if not ok then io.stderr:write('parse replay: ' .. tostring(err) .. '\n'); os.exit(1) end
