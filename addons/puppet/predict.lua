-- predict: the enfeebling spells an automaton will cast, in the order it will cast them, and the
-- weapon skill it will use.
--
--     local queue, reason = predict.Queue({
--         head = 1, frame = 0x20,              -- as the server names them
--         skill = 120,                         -- the automaton's magic skill
--         maneuvers = { light = 1, dark = 0 }, -- how many of each element are up
--         has = function(kind) ... end,        -- whether the target has a debuff, by winxi.debuffs' kinds
--         hpp = 100, mpp = 100,                -- the automaton's own HP and MP, as percentages
--     })
--
-- queue is a list of spell names, the next to be cast first. When it is empty, reason says why.
--
-- This is the server's own choosing, from its automaton controller, as Phoenix runs it: every head
-- has a set order, each maneuver moves the spells of its element to the front, and a spell is passed
-- over when the automaton lacks the skill for it or the target has its effect already. Addle,
-- Poison II, Dispel, Aspir II and Absorb-INT are left out: no automaton can cast them in this era.
--
-- It says nothing of when: healing and nuking can come first, each spell waits on its own timer, and
-- an enemy immune to a spell is passed over without this knowing.
--
--     local name, reason = predict.Weaponskill({
--         frame = 0x21,
--         melee = 180, ranged = 0,             -- the automaton's skills
--         maneuvers = { fire = 1 },
--     })
--
-- The weapon skill is the one of the frame's with the most maneuvers of its element up; between two
-- with as many, the one needing more skill. Bone Crusher, Armor Piercer and Magic Mortar are left
-- out, as no automaton has them in this era. With an Inhibitor the automaton may instead close a
-- skillchain that is open, which this does not see.
local predict = {}

predict.Heads = {
    Harlequin = 1,
    Valoredge = 2,
    Sharpshot = 3,
    Stormwaker = 4,
    Soulsoother = 5,
    Spiritreaver = 6,
}

-- The frames that cast at all
local castingFrames = { [0x20] = true, [0x23] = true } -- Harlequin, Stormwaker

-- kind: the debuff it leaves. skill: the magic skill it needs. unless: a debuff it will not be cast over.
-- element: the maneuver that brings the spell forward, which the window colours its name with
local BioII    = { name = 'Bio II',   kind = 'bio',     skill = 111, unless = 'dia', element = 'dark' }
local DiaII    = { name = 'Dia II',   kind = 'dia',     skill =  96, unless = 'bio', element = 'light' }
local Bio      = { name = 'Bio',      kind = 'bio',     skill =  33, unless = 'dia', element = 'dark' }
local Dia      = { name = 'Dia',      kind = 'dia',     skill =   0, unless = 'bio', element = 'light' }
local Poison   = { name = 'Poison',   kind = 'poison',  skill =  18, element = 'water' }
local Silence  = { name = 'Silence',  kind = 'silence', skill =  57, element = 'wind' }
local Slow     = { name = 'Slow',     kind = 'slow',    skill =  42, element = 'earth' }
local Blind    = { name = 'Blind',    kind = 'blind',   skill =  27, element = 'dark' }
local Paralyze = { name = 'Paralyze', kind = 'para',    skill =  21, element = 'ice' }
local Aspir    = { name = 'Aspir',    skill = 78, element = 'dark' }
local Drain    = { name = 'Drain',    skill = 45, element = 'dark' }

-- The element a spell answers to, by its name: for the window
predict.SpellElements = {}
for _, spell in ipairs({ BioII, DiaII, Bio, Dia, Poison, Silence, Slow, Blind, Paralyze, Aspir, Drain }) do
    predict.SpellElements[spell.name] = spell.element
end

-- Each head's order, and for each spell the element whose maneuver brings it forward
local usualOrder = {
    { BioII, 'dark' }, { DiaII, 'light' }, { Bio, 'dark' }, { Dia, 'light' }, { Poison, 'water' },
    { Silence, 'wind' }, { Slow, 'earth' }, { Blind, 'dark' }, { Paralyze, 'ice' },
}
local soulsootherOrder = {
    { Slow, 'earth' }, { Poison, 'water' }, { Blind, 'dark' }, { BioII, 'dark' }, { DiaII, 'light' },
    { Bio, 'dark' }, { Dia, 'light' }, { Silence, 'wind' }, { Paralyze, 'ice' },
}
-- A Spiritreaver's Blind and Bio are never brought forward: it takes one Dark maneuver to have it
-- enfeeble at all, and two of another element to bring that element's spell forward
local spiritreaverOrder = {
    { Blind }, { BioII }, { DiaII, 'light' }, { Bio }, { Dia, 'light' }, { Poison, 'water' },
    { Silence, 'wind' }, { Slow, 'earth' }, { Paralyze, 'ice' },
}
local spiritreaverNeeds = 75 -- below this much of its own MP it casts Aspir, and of its HP Drain

function predict.Queue(state)
    if state.head == nil or state.frame == nil then
        return {}, 'Not told about the automaton yet. Change area or an attachment.'
    end
    if not castingFrames[state.frame] then
        return {}, 'This frame casts no spells.'
    end
    if state.head == predict.Heads.Valoredge then
        return {}, 'A Valoredge head only heals.'
    end

    local maneuvers = state.maneuvers or {}
    local function up(element)
        return maneuvers[element] or 0
    end

    local first, rest = {}, {}
    local order, needed = usualOrder, 1

    if state.head == predict.Heads.Soulsoother then
        order = soulsootherOrder
    elseif state.head == predict.Heads.Spiritreaver then
        order, needed = spiritreaverOrder, 2
        local lowMp = (state.mpp or 100) < spiritreaverNeeds
        local lowHp = (state.hpp or 100) < spiritreaverNeeds
        if up('dark') == 0 and not lowMp and not lowHp then
            return {}, 'A Spiritreaver head needs a Dark maneuver to enfeeble.'
        end
        if lowMp then
            first[#first + 1] = Aspir
        end
        if lowHp then
            first[#first + 1] = Drain
        end
        if up('dark') == 0 then
            order = {}
        end
    end

    for _, entry in ipairs(order) do
        local spell, element = entry[1], entry[2]
        if not (spell.unless and state.has(spell.unless)) then
            if element and up(element) >= needed then
                first[#first + 1] = spell
            else
                rest[#rest + 1] = spell
            end
        end
    end

    -- one spell for each debuff: the first the automaton can cast, where the target has not got it
    local queue, taken = {}, {}
    local function consider(spell)
        if (state.skill or 0) < spell.skill then
            return
        end
        if spell.kind then
            if state.has(spell.kind) or taken[spell.kind] then
                return
            end
            -- once Bio or Dia is on, the other is not cast
            if spell.unless and taken[spell.unless] then
                return
            end
            taken[spell.kind] = true
        end
        queue[#queue + 1] = spell.name
    end
    for _, spell in ipairs(first) do consider(spell) end
    for _, spell in ipairs(rest) do consider(spell) end

    if #queue == 0 then
        return queue, 'Nothing left to cast on this target.'
    end
    return queue, nil
end

local frameSharpshot = 0x22

-- Each frame's weapon skills: the skill it needs (ranged for a Sharpshot, melee for the rest), the
-- element whose maneuvers it answers to, and the server's number for it, which settles a tie
local harlequinSkills = {
    { name = 'Slapstick', skill =   0, element = 'thunder', id = 1943 },
    { name = 'Knockout',  skill = 145, element = 'wind',    id = 2067 },
}
local weaponskills = {
    [0x20] = harlequinSkills,
    [0x21] = {
        { name = 'Chimera Ripper',  skill =   0, element = 'fire',    id = 1940 },
        { name = 'String Clipper',  skill =   0, element = 'thunder', id = 1941 },
        { name = 'Cannibal Blade',  skill = 150, element = 'dark',    id = 2065 },
        { name = 'String Shredder', skill = 324, element = 'thunder', id = 2743 },
    },
    [frameSharpshot] = {
        { name = 'Arcuballista',    skill =   0, element = 'fire',    id = 1942 },
        { name = 'Daze',            skill = 150, element = 'thunder', id = 2066 },
        { name = 'Armor Shatterer', skill = 324, element = 'wind',    id = 2744 },
    },
    [0x23] = harlequinSkills, -- a Stormwaker has the Harlequin's
}

-- Returns the weapon skill's name and the element whose maneuvers it answers to
function predict.Weaponskill(state)
    local skills = state.frame and weaponskills[state.frame]
    if skills == nil then
        return nil, nil, 'Not told about the automaton yet. Change area or an attachment.'
    end

    local maneuvers = state.maneuvers or {}
    local has = (state.frame == frameSharpshot and state.ranged or state.melee) or 0

    local best, bestUp = nil, -1
    for _, skill in ipairs(skills) do
        if has >= skill.skill then
            local up = maneuvers[skill.element] or 0
            if up > bestUp
                or (up == bestUp and skill.skill > best.skill)
                or (up == bestUp and skill.skill == best.skill and skill.id > best.id) then
                best, bestUp = skill, up
            end
        end
    end
    return best and best.name or nil, best and best.element or nil, nil
end

---------------------------------------------------------------------------------------------------
-- The order of everything
---------------------------------------------------------------------------------------------------

-- Every three seconds or so the automaton tries one thing after another and does the first it can:
-- a shield bash, a spell, a weapon skill, a shot, then whatever its attachments do of their own
-- accord. Which spell it tries first is the head's to say, and the maneuvers'. The rows are named
-- short, for a small window: Bash, Magic (every spell as one: what it would cast first, Heal, an
-- enfeeble by name, Nuke or Erase, with the timer on that), WS (the weapon skill), Shot, and then one
-- for each attachment fitted that acts on a timer of its own (Provoke for a Strobe, Flash for a
-- Flashbulb, and so on).
--
--     local rows = predict.Priority({
--         head = 1, frame = 0x20, maneuvers = { light = 1 },
--         enfeebles = { 'Bio', 'Poison' },                  -- from Queue: the spells, next first; nil or empty for none. The first is named
--         weaponskill = 'Slapstick', weaponskillElement = 'thunder', -- from Weaponskill: nil where there is none
--         masterHpp = 82, hpp = 100, mpp = 60, tp = 640,   -- the master's HP, and the automaton's own
--         tpIn = 12,                                        -- seconds until it has 1000 TP, at the rate it gains it (tp.Until), or nil
--         since = function(kind) ... end,                   -- seconds since it last did a thing: tracker.Since
--         attachments = { [33] = true },                    -- those fitted, by the server's number for each
--     })
--
-- Each row is { name, section, element, detail, state, wait, ready, unsure }: section is 'queue' for
-- what the maneuvers choose (the spells, the weapon skill) and 'cooldown' for what runs on a timer of
-- its own and is not chosen (the bash, the shot, what an attachment fitted does when its maneuver is
-- up), which the window shows only while the timer runs; element is the maneuver the
-- thing answers to, if any, for the window to colour its name with; detail is what it would do (the
-- spell it would cast, or Heal, Nuke or Erase, or the weapon skill, as { name, element }), or nil; state is 'waiting' (on a
-- timer, wait seconds of it left, whether or not it has anything to do), 'idle' (nothing for it to do
-- as things stand) or 'ready'; ready marks the
-- one row the automaton will act on next; unsure marks a row whose condition the game is not told of
-- (an enemy casting, an ailment to remove), which is never called next. The timers are Phoenix's for
-- this era.
--
-- What comes next is the first row ready with nothing in doubt. With none ready, it is whichever comes
-- soonest of the rows waiting on a timer with something to do, and the weapon skill at the time it will
-- have the TP (tpIn); the weapon skill's row then shows that time as an estimate. With no rate known,
-- or nothing waiting, the weapon skill is named, as the thing it will do once it has the TP.

local cooldowns = { -- by head: between any two spells, and between two of a kind
    [1] = { magic = 30, heal = 20, enfeeble = 20 },
    [2] = { magic = 45, heal = 30 },
    [3] = { magic = 45, heal = 30, enfeeble = 30 },
    [4] = { magic = 25, heal = 15, enfeeble = 30, elemental = 30 },
    [5] = { magic = 25, heal = 15, enfeeble = 30, status = 15 },
    [6] = { magic = 25, enfeeble = 45, elemental = 15 },
}

local rangedCooldown = { [1] = 25, [3] = 20 } -- by head, on a Sharpshot frame: 36 for any other
local rangedLeast = { [3] = 5 }               -- and the least it can be brought down to: 10 for any other
local bashCooldown = 180

local attachmentManaBooster, attachmentDrumMagazine = 33, 69
local attachmentDamageGauge, attachmentDamageGaugeII = 195, 207
local attachmentBarrierModule, attachmentBarrierModuleII = 107, 104
local attachmentHammermill = 103

local healAt = { [0] = 30, [1] = 40, [2] = 50, [3] = 75 } -- the master's HP it heals at, by Light maneuvers
local spellKinds = { heal = 'Heal', enfeeble = 'Enfeeble', nuke = 'Nuke', erase = 'Erase' } -- what the Magic row says it would do, by kind
local healSelfAt = 50

-- The attachments that act on their own, each on a timer of its own, as the server scripts them: the
-- attachments that give the action (by the server's number for each), its name, the maneuver it waits
-- for, its recast in seconds, the kind tracker.lua knows it by, and what else it needs. More than one
-- attachment giving the same action (a Strobe and a Strobe II) share the one row.
--
-- mp: the automaton's MP, as a percentage, it must be at or under, by maneuvers of its element; hp the
-- same of its HP (75 instead of 50 with a Damage Gauge); unsure where the game is not told the condition.
local attachmentActions = {
    { fitted = { 1, 9 },         name = 'Provoke',      element = 'fire',  cooldown = 30,  kind = 'provoke' },
    { fitted = { 194 },          name = 'Flash',        element = 'light', cooldown = 45,  kind = 'flash' },
    { fitted = { 97, 105, 109 }, name = 'Stoneskin',    element = 'earth', cooldown = 180, kind = 'stoneskin' },
    { fitted = { 6 },            name = 'Blaze Spikes', element = 'fire',  cooldown = 60,  kind = 'spikes' },
    { fitted = { 71 },           name = 'Blink',        element = 'wind',  cooldown = 60,  kind = 'blink', hp = 50 },
    { fitted = { 197 },          name = 'Eraser',       element = 'light', cooldown = 30,  kind = 'eraser', unsure = true },
    { fitted = { 230 },          name = 'Economizer',   element = 'dark',  cooldown = 180, kind = 'economizer', mp = { 40, 50, 60 }, needsMp = true },
    { fitted = { 226 },          name = 'Mana Conv.',   element = 'dark',  cooldown = 180, kind = 'converter', mp = { 40, 60, 70 }, needsMp = true },
    { fitted = { 72 },           name = 'Barrage',      element = 'wind',  cooldown = 180, kind = 'barrage' },
    { fitted = { 8, 13 },        name = 'Heat Cap.',    element = 'fire',  cooldown = 90,  kind = 'capacitor' },
    { fitted = { 232 },          name = 'Disruptor',    element = 'dark',  cooldown = 60,  kind = 'disruptor', unsure = true },
    { fitted = { 234 },          name = 'Regulator',    element = 'dark',  cooldown = 60,  kind = 'regulator', unsure = true },
}
predict.AttachmentActions = attachmentActions

function predict.Priority(state)
    local rows = {}
    if state.head == nil or state.frame == nil then
        return rows
    end

    local maneuvers = state.maneuvers or {}
    local fitted = state.attachments or {}
    local function up(element)
        return math.min(maneuvers[element] or 0, 3)
    end
    local function left(kind, cooldown)
        local since = state.since(kind)
        if since == nil or cooldown == nil then
            return 0
        end
        return math.max(0, cooldown - since)
    end
    local section = 'cooldown'
    local function add(name, element, detail, needed, wait, unsure)
        rows[#rows + 1] = { name = name, section = section, element = element, detail = detail, wait = wait or 0, unsure = unsure or nil,
            needed = needed and true or false, state = ((wait or 0) > 0 and 'waiting') or (not needed and 'idle') or 'ready' }
    end

    -- a shield bash, on a Valoredge frame: only when the enemy is doing something it would break. An
    -- Earth maneuver shortens it with a Barrier Module, and strengthens it with a Hammermill.
    if state.frame == 0x21 then
        local cooldown = bashCooldown
        local earthy = fitted[attachmentBarrierModule] or fitted[attachmentBarrierModuleII]
        if earthy then
            cooldown = cooldown - 5 * up('earth')
        end
        add('Bash', (earthy or fitted[attachmentHammermill]) and 'earth' or nil, nil, true, left('bash', cooldown), true)
    end

    -- spells, on the frames that cast
    section = 'queue'
    local timers = cooldowns[state.head]
    if castingFrames[state.frame] and timers ~= nil then
        local magic = timers.magic
        if fitted[attachmentManaBooster] then
            magic = magic - 2 * (up('ice') + 1)
        end
        local magicLeft = left('magic', magic)

        local healTimer = timers.heal
        local threshold = healAt[up('light')]
        if fitted[attachmentDamageGaugeII] then
            threshold = threshold + 60 + 10 * up('light')
        elseif fitted[attachmentDamageGauge] then
            threshold = threshold + 50 + 10 * up('light')
        end
        if healTimer and (fitted[attachmentDamageGauge] or fitted[attachmentDamageGaugeII]) then
            healTimer = healTimer - 3
        end
        threshold = math.max(30, math.min(90, threshold))

        local enfeebles = state.enfeebles or {}
        local spell = nil
        if #enfeebles > 0 then
            spell = { name = enfeebles[1], element = predict.SpellElements[enfeebles[1]] }
        end

        local function heal()
            if healTimer == nil then return end
            local needed = (state.masterHpp or 100) <= threshold or (state.hpp or 100) <= healSelfAt
            add('Heal', 'light', nil, needed, math.max(magicLeft, left('heal', healTimer)))
            rows[#rows].kind = 'heal'
        end
        local function enfeeble()
            if timers.enfeeble == nil then return end
            add('Enfeeble', nil, spell, spell ~= nil, math.max(magicLeft, left('enfeeble', timers.enfeeble)))
            rows[#rows].kind = 'enfeeble'
        end
        local function nuke()
            if timers.elemental == nil then return end
            add('Nuke', 'ice', nil, (state.mpp or 100) > 0, math.max(magicLeft, left('elemental', timers.elemental)))
            rows[#rows].kind = 'nuke'
        end
        local function cleanse()
            if timers.status == nil then return end
            add('Erase', 'water', nil, true, math.max(magicLeft, left('status', timers.status)), true)
            rows[#rows].kind = 'erase'
        end

        -- the kinds of spell in the head's order, then as one row: the first that can be cast now, else
        -- the soonest to be among those with something to cast, else the first, with its timer
        local firstSpell = #rows + 1
        local light, ice = up('light') > 0, up('ice') > 0
        if state.head == predict.Heads.Valoredge then
            heal()
        elseif state.head == predict.Heads.Stormwaker then
            if light then heal() end
            if ice then nuke() end
            enfeeble()
            if not light then heal() end
            if not ice then nuke() end
        elseif state.head == predict.Heads.Soulsoother then
            if light then heal() end
            cleanse()
            if not light then heal() end
            enfeeble()
        elseif state.head == predict.Heads.Spiritreaver then
            if ice then nuke() end
            enfeeble()
            if not ice then nuke() end
        else
            if light then heal() end
            enfeeble()
            if not light then heal() end
        end

        local spells = {}
        for i = #rows, firstSpell, -1 do
            table.insert(spells, 1, table.remove(rows, i))
        end
        local chosen = nil
        for _, spell in ipairs(spells) do
            if spell.state == 'ready' and not spell.unsure then
                chosen = spell
                break
            end
        end
        if chosen == nil then
            for _, spell in ipairs(spells) do
                if spell.state == 'waiting' and spell.needed and not spell.unsure and (chosen == nil or spell.wait < chosen.wait) then
                    chosen = spell
                end
            end
        end
        -- with nothing to cast, the row is the first kind's timer and names nothing: a heal is named
        -- only while the master or the automaton is low enough to be healed
        if chosen ~= nil then
            chosen.detail = chosen.detail or { name = spellKinds[chosen.kind], element = chosen.element }
        else
            chosen = spells[1]
            if chosen ~= nil then
                chosen.detail, chosen.element = nil, nil
            end
        end
        if chosen ~= nil then
            chosen.name = 'Magic'
            rows[#rows + 1] = chosen
        end
    end

    -- the weapon skill, once it has the TP: the one named is the maneuvers' choice
    if state.weaponskill ~= nil then
        add('WS', nil, { name = state.weaponskill, element = state.weaponskillElement }, (state.tp or 0) >= 1000, 0)
    end

    -- a shot, on a Sharpshot frame: a Wind maneuver quickens it with a Drum Magazine
    section = 'cooldown'
    if state.frame == frameSharpshot then
        local cooldown = rangedCooldown[state.head] or 36
        local drummed = fitted[attachmentDrumMagazine]
        if drummed then
            cooldown = cooldown - 2 * (up('wind') + 1)
        end
        cooldown = math.max(cooldown, rangedLeast[state.head] or 10)
        add('Shot', drummed and 'wind' or nil, nil, true, left('ranged', cooldown))
    end

    -- what the attachments fitted do of their own accord, each while a maneuver of its element is up
    local gauged = fitted[attachmentDamageGauge] or fitted[attachmentDamageGaugeII]
    for _, action in ipairs(attachmentActions) do
        local present = false
        for _, id in ipairs(action.fitted) do
            if fitted[id] then present = true end
        end
        if present then
            local count = up(action.element)
            local needed = count > 0
            if needed and action.hp then
                needed = (state.hpp or 100) <= (gauged and 75 or action.hp)
            end
            if needed and action.mp then
                needed = castingFrames[state.frame] == true and (state.mpp or 100) <= action.mp[count]
            end
            add(action.name, action.element, nil, needed, left(action.kind, action.cooldown), action.unsure)
        end
    end

    -- the first with something to do and nothing to wait for is what comes next, unless its condition
    -- is one the game is not told of: an enemy casting, an ailment or a buff to take off
    local weaponskill = nil
    for _, row in ipairs(rows) do
        if row.state == 'ready' and not row.unsure then
            row.ready = true
            return rows
        end
        if row.name == 'WS' then
            weaponskill = row
        end
    end

    -- none ready: the soonest of those waiting with something to do, against the weapon skill at the
    -- time it will have the TP. The weapon skill where nothing is waiting, or no rate is known.
    local soonest = nil
    for _, row in ipairs(rows) do
        if row.state == 'waiting' and row.needed and not row.unsure and (soonest == nil or row.wait < soonest.wait) then
            soonest = row
        end
    end
    local tpIn = state.tpIn
    if weaponskill ~= nil and (soonest == nil or (tpIn ~= nil and tpIn < soonest.wait)) then
        if tpIn ~= nil and tpIn > 0 then
            weaponskill.state, weaponskill.wait, weaponskill.estimate = 'waiting', tpIn, true
        end
        weaponskill.ready = true
    elseif soonest ~= nil then
        soonest.ready = true
    end
    return rows
end

return predict
