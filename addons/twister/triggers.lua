-- The triggers as the settings hold them: a sound of your choosing when a mob of a kind of your
-- choosing begins a spell or a weaponskill of your choosing, or uses an ability. Each is
-- { mob = the kind of mob, kind = 'spell', 'skill' or 'ability', ids = the numbers the game has the
-- thing done under, name = what it is called, sound, enabled }.
local shared = require('shared')
local playing = require('playing')
local mobdata = require('mobdata')

local Boxed = shared.Boxed
local Renamed = playing.Renamed
local ActionName, Area = mobdata.ActionName, mobdata.Area

local kindLabels = { spell = 'Spell', skill = 'Weaponskill', ability = 'Ability' }
local triggerSound = 'voicef-trigger.wav' -- what a trigger starts with

-- The triggers by what they are for: the kind of thing done -> its number -> the triggers for it,
-- switched on or not. Put together again when a trigger is made or removed, and when the settings
-- are loaded.
local triggersFor = { }

local function IndexTriggers(triggers)
    triggersFor = { }
    for _, trigger in ipairs(triggers) do
        local byId = triggersFor[trigger.kind]
        if byId == nil then
            byId = { }
            triggersFor[trigger.kind] = byId
        end
        for _, id in ipairs(trigger.ids) do
            local found = byId[id]
            if found == nil then
                found = { }
                byId[id] = found
            end
            found[#found + 1] = trigger
        end
    end
end

-- The triggers for a thing done, or nil
local function For(kind, id)
    local byId = triggersFor[kind]
    return byId and byId[id]
end

-- Whether something is a trigger as the settings hold one, now or as they once did
local function IsTrigger(trigger)
    return type(trigger) == 'table' and (type(trigger.id) == 'number' or type(trigger.ids) == 'table' and type(trigger.ids[1]) == 'number')
        and type(trigger.mob) == 'string' and kindLabels[trigger.kind] ~= nil
end

-- The triggers of saved settings: what is not one is dropped, and one made as triggers once were is
-- made over
local function Complete(options)
    local triggers = T{ }
    for _, trigger in ipairs(type(options.triggers) == 'table' and options.triggers or { }) do
        if IsTrigger(trigger) then
            Boxed(trigger, 'enabled', 'boolean', true)
            if type(trigger.sound) ~= 'string' or trigger.sound == '' then trigger.sound = triggerSound end
            trigger.sound = Renamed(trigger.sound)
            -- one made when a trigger was for a single number
            if type(trigger.ids) ~= 'table' then trigger.ids = T{ trigger.id } end
            trigger.id = nil
            if type(trigger.name) ~= 'string' then trigger.name = ActionName(trigger.kind, trigger.ids[1]) end
            -- one made when a trigger was for an area, and at first for one mob of it: it is for that
            -- mob's kind now, or the kind it was for, everywhere
            if type(trigger.zone) == 'number' then
                trigger.mob = Area(trigger.zone).kindOf[trigger.mob:lower()] or trigger.mob
            end
            trigger.zone, trigger.mobs = nil, nil
            triggers[#triggers + 1] = trigger
        end
    end
    options.triggers = triggers
    IndexTriggers(triggers)
end

return {
    kindLabels = kindLabels,
    defaultSound = triggerSound,
    Index = IndexTriggers,
    For = For,
    Complete = Complete,
}
