-- Attachment contributions, not the pet's final stats (gear, caps and other buffs are excluded).
-- The attachments are the chosen server's attachments set (winxi's data, tools/build_puppet_attachments.py):
-- each one's element, modifiers by maneuvers and Repair Kit or Mana Tank formula, and each frame's divisor.
local gamedata = require('winxi.gamedata')
local data = gamedata.Lookup('attachments')
local M = {}
local labels = {
    ENMITY = { 'Enmity' }, STORETP = { 'Store TP' }, ATTP = { 'Attack', '%' },
    RATTP = { 'Ranged attack', '%' }, DEFP = { 'Defense', '%' },
    ACC = { 'Accuracy' }, RACC = { 'Ranged accuracy' }, EVA = { 'Evasion' },
    MATT = { 'Magic attack' }, MDEF = { 'Magic defense' }, MACC = { 'Magic accuracy' },
    HASTE_GEAR = { 'Gear haste', '%', 100 }, HASTE_MAGIC = { 'Magic haste', '%', 100 },
    DMGPHYS = { 'Physical damage taken', '%', 100 },
    AUTO_MAGIC_COOLDOWN = { 'Magic cooldown', 's' }, AUTO_RANGED_DELAY = { 'Shot delay reduction', 's' },
    AUTO_HEALING_DELAY = { 'Healing delay reduction', 's' },
    AUTO_HEALING_THRESHOLD = { 'Master heal threshold', '% HP' },
    AUTO_SHIELD_BASH_DELAY = { 'Bash delay reduction', 's' },
    AUTO_PERFORMANCE_BOOST = { 'Attachment enhancement', '%' },
    BURDEN_DECAY = { 'Extra burden decay', '/tick' }, OVERLOAD_THRESH = { 'Overload threshold' },
    DOUBLE_ATTACK = { 'Double attack', '%' }, COUNTER = { 'Counter', '%' },
    CRITHITRATE = { 'Critical rate', '%' }, SHIELDBLOCKRATE = { 'Shield block rate', '%' },
    WEAPONSKILL_DAMAGE_BASE = { 'WS fTP multiplier', 'x', 100 },
    AUTO_MAB_COEFFICIENT = { 'Ice Maker coefficient', '%' },
    AUTO_STEAM_JACKET_REDUCTION = { 'Repeated-type damage reduction', '%' },
    MAGIC_DAMAGE = { 'Magic damage' }, MAGIC_BURST_BONUS_UNCAPPED = { 'Magic burst bonus', '%' },
    CURE_POTENCY = { 'Cure potency', '%' }, MP_COST_REDUCTION = { 'MP cost reduction', '%' },
    CONSERVE_MP = { 'Conserve MP', '%' }, DOUBLE_SHOT_RATE = { 'Double shot rate', '%' },
    COMBAT_SKILLUP_RATE = { 'Combat skillup rate', '%' }, STATUSRES = { 'Status resistance' },
    AUTO_RANGED_DAMAGEP = { 'Ranged base damage', '%' }, SHIELD_BASH = { 'Bash damage', '%' },
    SKILLCHAINBONUS = { 'Skillchain bonus', '%' }, OCCULT_ACUMEN = { 'Occult Acumen' },
    ELEMENTAL_CELERITY = { 'Elemental Celerity' },
    AUTO_DECISION_DELAY = { 'Decision delay modifier', ' (server units)' },
    REGEN = { 'Regen' }, REFRESH = { 'Refresh' },
}
local function count(state, element)
    local n = math.min(3, math.max(0, (state.maneuvers or {})[element] or 0))
    return state.overdrive and n > 0 and 3 or n
end
local function signed(n) return n > 0 and ('+' .. tostring(n)) or tostring(n) end
local function describe(key, value)
    local label = labels[key]
    if not label then return key .. ' ' .. signed(value) .. ' (server units)' end
    return label[1] .. ' ' .. signed(value / (label[3] or 1)) .. (label[2] or '')
end
local function special(key, n)
    if key == 'shock_absorber' then return 'Stoneskin 100 HP on activation' end
    if key == 'replicator' then return n > 0 and ('Blink %d shadows; consumes Wind'):format(n + 1) or 'Blink needs Wind' end
    if key == 'economizer' then return ('Recover %d%% max MP; needs Dark; consumes Dark'):format(n * 20) end
    if key == 'eraser' then return ('Remove up to %d ailments; needs Light; consumes all maneuvers'):format(n) end
    if key == 'analyzer' then return ('Repeated analyzed skill damage -%d%% (one skill)'):format(10 + 10 * n) end
    if key == 'volt_gun' then return 'Enthunder damage depends on pet skill and target INT' end
end
-- What the window calls the server when an attachment is not in its data
local function Server()
    local made = gamedata.Manifest().Source
    return made and made.Name or 'the server'
end

function M.Rows(equipped, state)
    state = state or {}
    local definitions = data.attachments or {}
    local frames = data.frames or {}
    local boost, rows, ids = 0, {}, {}
    for id, fitted in pairs(equipped or {}) do
        if fitted then
            ids[#ids + 1] = id
            local def = definitions[id]
            if def and def.key:find('optic_fiber', 1, true) then
                boost = boost + def.mods[1].values[count(state, 'light') + 1]
            end
        end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local def = definitions[id]
        if not def then
            rows[#rows + 1] = { name = 'Attachment #' .. tostring(id), text = ('Not in %s\'s data'):format(Server()) }
        else
            local n, parts = count(state, def.element), {}
            local note = special(def.key, n)
            if note then parts[#parts + 1] = note end
            for _, mod in ipairs(def.mods) do
                if not (note and (def.key == 'analyzer' or def.key == 'volt_gun')) then
                    local value = mod.values[n + 1]
                    if value ~= nil then
                        if mod.optic then value = math.floor(value * (1 + boost / 100)) end
                        parts[#parts + 1] = describe(mod.key, value)
                    elseif def.base then
                        local base, scale = def.base[n + 1], def.scale[n + 1]
                        local factor = mod.optic and (1 + boost / 100) or 1
                        local label = labels[mod.key] and labels[mod.key][1] or mod.key
                        if scale == 0 then
                            parts[#parts + 1] = label .. ' ' .. signed(math.floor(base * factor)) .. '/tick'
                        else
                            parts[#parts + 1] = ('%s floor((%g + %g%% max %s) x %g)/tick'):format(label, base, scale, def.resource, factor)
                        end
                    end
                end
            end
            if def.resource then
                -- the server's divisor for the frame; a frame it has none for (Valoredge and Sharpshot for
                -- MP) has no pool for the attachment to raise
                local divisor = (frames[def.resource] or {})[state.frame]
                parts[#parts + 1] = divisor and ('Max %s +%g%% (frame bonus)'):format(def.resource, def.boost / divisor * 100)
                    or state.frame and frames[def.resource] and ('No max %s bonus on this frame'):format(def.resource)
                    or ('Max ' .. def.resource .. ' bonus depends on frame')
            end
            if def.key == 'flame_holder' then parts[#parts + 1] = 'Consumes Fire on WS' end
            if def.key == 'ice_maker' then parts[#parts + 1] = 'Consumes Ice on elemental magic' end
            if #parts == 0 then parts[1] = 'Action/conditional effect; no passive modifier' end
            rows[#rows + 1] = { name = def.name, element = def.element, count = n, text = table.concat(parts, '; ') }
        end
    end
    return rows
end
return M
