-- TP, HP, MP and the party's HP: from the game's own numbers, looked at a few times a second.
local game = require('winxi.game')
local shared = require('shared')
local playing = require('playing')
local mobdata = require('mobdata')

local Sound = playing.Sound
local Area = mobdata.Area

local lookEvery = 0.1  -- seconds between looks
local settleFor = 3    -- seconds after arriving in an area before anything is believed
local rearmOver = 5    -- how far over its threshold HP or MP has to climb before it can sound again

local lastLook, arrived = 0, nil
local lastTp = nil
local lowHp, lowMp = nil, nil -- whether each was low when last looked at; nil: not looked at yet

-- A member arriving in the area is shown with no HP for a moment before their own is known, and so
-- may one who is leaving it. So a member is not believed until they have been here a while, and one
-- with no HP is not taken for knocked out until they have had none for a second.
local memberSettle = 5 -- seconds a member has to have been in the area before their HP is believed
local downFor = 1      -- seconds without HP before it is a knockout

-- party place (1 to 5) -> { id = who is in it, since = when they were first seen in this area,
-- hp = their HP percentage when last looked at, downSince = when it went from some to none }
local members = { }

local function ForgetMembers()
    for place = 1, 5 do
        members[place] = nil
    end
end

local function Forget()
    lastTp, lowHp, lowMp = nil, nil, nil
    ForgetMembers()
end

-- Low is at or under the threshold; once low, not low again until over it by a margin, so that a
-- number hovering at the threshold does not sound over and over
local function IsLow(percent, threshold, wasLow)
    if wasLow then
        return percent < threshold + rearmOver
    end
    return percent <= threshold
end

local function Look(now)
    lastLook = now

    if game.IsLoading() then
        arrived = nil
        Forget()
        return
    end
    arrived = arrived or now
    if now - arrived < settleFor then
        return
    end

    local options = shared.app.options
    local memory = AshitaCore:GetMemoryManager()
    local party = memory:GetParty()
    local zone = party:GetMemberZone(0)

    -- which kind each of the area's mobs is, for the triggers: found out here, once for the area,
    -- and not as a mob of it acts
    if #options.triggers > 0 then
        Area(zone)
    end

    local tp = party:GetMemberTP(0)
    if lastTp ~= nil and lastTp < 1000 and tp >= 1000 then
        Sound('tp')
    end
    lastTp = tp

    -- knocked out is not low: there is nothing left to warn of
    local hp = party:GetMemberHPPercent(0)
    local hpLow = hp > 0 and IsLow(hp, options.lowHpPercent[1], lowHp)
    if hpLow and lowHp == false then
        Sound('lowhp')
    end
    lowHp = hpLow

    if memory:GetPlayer():GetMPMax() > 0 then
        local mpLow = hp > 0 and IsLow(party:GetMemberMPPercent(0), options.lowMpPercent[1], lowMp)
        if mpLow and lowMp == false then
            Sound('lowmp')
        end
        lowMp = mpLow
    else
        lowMp = nil
    end

    -- the others of the party: one who was standing and has no HP now. Someone in another area has
    -- none either, as far as the game here knows, so only those in this one are watched.
    if not options.events.ko.enabled[1] then
        -- nothing is kept of them meanwhile: what was true before it was switched off may not be now
        ForgetMembers()
        return
    end
    for place = 1, 5 do
        if party:GetMemberIsActive(place) == 1 and party:GetMemberZone(place) == zone then
            -- someone else in this place of the party is someone new
            local id = party:GetMemberServerId(place)
            local member = members[place]
            if member == nil or member.id ~= id then
                member = { id = id, since = now }
                members[place] = member
            end

            if now - member.since >= memberSettle then
                local memberHp = party:GetMemberHPPercent(place)
                if memberHp > 0 then
                    member.downSince = nil
                elseif member.hp ~= nil and member.hp > 0 then
                    member.downSince = now
                end
                if member.downSince ~= nil and now - member.downSince >= downFor then
                    member.downSince = nil
                    Sound('ko')
                end
                member.hp = memberHp
            end
        else
            members[place] = nil
        end
    end
end

-- Once a frame: the game's numbers a few times a second, not every frame
local function Frame(now)
    if now - lastLook >= lookEvery then
        Look(now)
    end
end

return { Frame = Frame, Forget = Forget }
