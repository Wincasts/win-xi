-- Deliberately conservative message coverage. Unknown outcomes remain diagnostics,
-- never guessed damage. Message numbers are protocol identifiers, not localized text.
local M = {}
local finished = { [1]=true, [2]=true, [3]=true, [4]=true, [6]=true, [11]=true, [13]=true, [14]=true, [15]=true }
local spells = { [2]=true, [227]=true }
local bursts = { [252]=true, [265]=true, [274]=true, [379]=true, [747]=true, [748]=true }
local skills = { [185]=true, [187]=true, [197]=true }
local abilities = { [77]=true, [110]=true, [157]=true, [317]=true, [522]=true, [802]=true }
local ranged = { [352]=true, [353]=true, [576]=true, [577]=true }
local magicSuccess = { [82]=true, [230]=true, [236]=true, [237]=true, [277]=true, [278]=true }
local magicResist = { [85]=true, [284]=true, [653]=true, [654]=true, [655]=true, [656]=true }
local magicExcluded = { [75]=true, [283]=true } -- no effect is not proof of an accuracy failure
local sc = { [732]=true, [767]=true, [768]=true, [769]=true, [770]=true }
for i = 288, 302 do sc[i] = true end
for i = 385, 398 do sc[i] = true end
local ignored = { [0]=true, [7]=true, [24]=true, [82]=true, [85]=true, [100]=true, [101]=true,
    [102]=true, [103]=true, [186]=true, [189]=true, [230]=true, [236]=true, [237]=true,
    [238]=true, [242]=true, [243]=true, [263]=true, [266]=true, [267]=true, [277]=true,
    [278]=true, [283]=true, [284]=true, [319]=true, [320]=true, [323]=true, [367]=true }
local function category(c)
    if c == 3 then return 'ws' end
    if c == 4 then return 'spell' end
    if c == 11 or c == 13 then return 'pet_ability' end
    return 'ability'
end
function M.Events(action, resolve)
    local events, unknown = {}, {}
    if not finished[action.category] then return events, unknown end
    local actor = resolve(action.actor)
    local function friendly(entity) return entity and entity.kind ~= 'mob' and entity.kind ~= 'other' end
    local function relevant(source, target) return friendly(source) and target and target.kind == 'mob' end
    local function emit(source, target, kind, value, outcome, critical)
        if relevant(source, target) then
            events[#events + 1] = { actor = source, target = target, category = kind, damage = value,
                outcome = outcome, critical = critical == true, ability = action.ability, ability_category = action.category }
        end
    end
    local function unclassified(part, message, source, target)
        if relevant(source, target) and message ~= 0 then
            local key = ('%d:%s:%d'):format(action.category, part, message)
            unknown[key] = (unknown[key] or 0) + 1
        end
    end
    for _, targetData in ipairs(action.targets) do
        local target = resolve(targetData.id)
        for _, r in ipairs(targetData.results) do
            local m, c = r.message, action.category
            if c == 4 then
                if spells[m] or bursts[m] or m == 264 or magicSuccess[m] then
                    emit(actor, target, 'magic_accuracy', 0, 'hit')
                elseif magicResist[m] then
                    emit(actor, target, 'magic_accuracy', 0, 'miss')
                elseif magicExcluded[m] then
                    emit(actor, target, 'magic_accuracy', 0, 'excluded')
                end
            end
            if m == 33 then
                emit(target, actor, 'counter', r.value, 'hit')
                if c == 1 then emit(actor, target, 'melee', 0, 'excluded') end
            elseif c == 1 and (m == 1 or m == 67) then
                emit(actor, target, 'melee', r.value, 'hit', m == 67)
            elseif c == 1 and (m == 15 or m == 63 or m == 282) then
                emit(actor, target, 'melee', 0, 'miss')
            elseif c == 1 and (m == 14 or m == 30 or m == 31 or m == 32 or m == 70) then
                -- These are not evidence of an accuracy miss. Keep them separately.
                emit(actor, target, 'melee', 0, 'excluded')
            elseif c == 2 and ranged[m] then
                emit(actor, target, 'ranged', r.value, 'hit', m == 353)
            elseif c == 2 and m == 354 then
                emit(actor, target, 'ranged', 0, 'miss')
            elseif (c == 3 or c == 11 or c == 13) and skills[m] then
                emit(actor, target, category(c), r.value, 'hit')
            elseif c == 3 and m == 188 then
                emit(actor, target, 'ws', 0, 'miss')
            elseif (c == 4 and spells[m]) or bursts[m] then
                emit(actor, target, bursts[m] and 'burst' or 'spell', r.value, 'hit')
            elseif abilities[m] then
                emit(actor, target, 'ability', r.value, 'hit')
            elseif m == 158 or m == 324 then
                emit(actor, target, 'ability', 0, 'miss')
            elseif m == 264 then
                -- AoE secondary results use the packet category, not previous target order.
                emit(actor, target, category(c), r.value, 'hit')
            elseif not ignored[m] and not (c == 4 and (magicSuccess[m] or magicResist[m] or magicExcluded[m])) then
                unclassified('base', m, actor, target)
            end
            local p = r.additional
            if p then
                if sc[p.message] then
                    emit(actor, target, 'skillchain', p.value, 'hit')
                elseif p.message == 163 or p.message == 229 then
                    emit(actor, target, 'additional', p.value, 'hit')
                else
                    -- HP/MP drain is not blindly added to damage (may be part of the hit).
                    unclassified('additional', p.message, actor, target)
                end
            end
            local react = r.reactive
            if react then
                if react.message == 33 then
                    if m ~= 33 then emit(target, actor, 'counter', react.value, 'hit') end
                elseif react.message == 44 or react.message == 132 or react.message == 536 then
                    emit(target, actor, react.message == 536 and 'retaliation' or 'spikes', react.value, 'hit')
                elseif react.message ~= 373 and react.message ~= 535 then -- healing / shadows are not damage
                    unclassified('reactive', react.message, target, actor)
                end
            end
        end
    end
    if action.category == 3 then
        -- One count per recognized WS packet, not one per AoE target or inferred strike.
        for _, event in ipairs(events) do
            if event.category == 'ws' or event.category == 'burst' then
                emit(actor, event.target, 'ws_count', 0, 'excluded')
                break
            end
        end
    end
    return events, unknown
end
return M
