-- Isolated, deterministic sample observations. Never written into the live session.
local core = require('parse_core')
local M = { Duration = 180 }
local names = { 'Aldric', 'Brigid', 'Caelum', 'Dahlia', 'Emrys', 'Fiora', 'Galen', 'Hazel',
    'Iona', 'Jasper', 'Kaida', 'Lorien', 'Mira', 'Nolan', 'Orla', 'Perrin', 'Quinn', 'Rowan' }
function M.New(count)
    local model = core.New()
    local target = { key = 'preview:target', id = 100, name = 'Training Target', kind = 'mob' }
    local events = {}
    local function emit(actor, category, damage, outcome, critical)
        events[#events + 1] = { actor = actor, target = target, category = category,
            damage = damage, outcome = outcome, critical = critical, ability = 42, ability_category = 1 }
    end
    for i = 1, count do
        local actor = { key = 'preview:' .. i, id = i, name = names[i], kind = 'party' }
        for hit = 1, 40 do
            local miss = hit % (5 + i % 6) == 0
            emit(actor, 'melee', miss and 0 or (19 - i) * 135 + hit * 7, miss and 'miss' or 'hit', not miss and hit % 4 == 0)
        end
        for shot = 1, 12 do
            local miss = shot % (3 + i % 5) == 0
            emit(actor, 'ranged', miss and 0 or (19 - i) * 95, miss and 'miss' or 'hit', not miss and shot % 5 == 0)
        end
        emit(actor, 'ws', (19 - i) * 2200, 'hit')
        emit(actor, 'ws_count', 0, 'excluded')
        events[#events + 1] = { actor = actor, target = target, category = 'ws_hits', damage = 0,
            hits = 4 - i % 3, misses = i % 3, ability = 42, ability_category = 3 }
        events[#events + 1] = { actor = actor, target = target, category = 'magic_accuracy', damage = 0,
            hits = 20 - i % 5, misses = i % 4, excluded = 1, ability = 42, ability_category = 4 }
        emit(actor, 'spell', i * 700, 'hit')
        emit(actor, 'skillchain', (19 - i) * 600, 'hit')
        -- Separate pet observations demonstrate the real grouping setting, too.
        if i % 3 == 0 then
            local pet = { key = 'preview:pet:' .. i, id = 200 + i, name = 'Companion', kind = 'pet',
                owner_id = i, owner_key = actor.key, owner_name = actor.name }
            emit(pet, 'melee', i * 1100, 'hit')
        end
    end
    model:Record(events, {}, 0)
    model:Pause(M.Duration)
    return model
end
return M
