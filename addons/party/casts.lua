-- casts: a member's spell while they cast it, from winxi.castbar's watch on the action packets, for
-- Show Cast Bars. A line given one has its cast in place of its HP bar and name (frames: cast).
local castbar = require('winxi.castbar')

local casts = { }

local wanted = false
local who = { ServerId = 0, EntityIndex = 0 } -- the member asked about, as winxi.castbar takes one
-- A cast is kept by the caster's server ID, which is never another's, and roster has already checked
-- their entity (member.entity): winxi.castbar is not to read it again, nor drop a cast for a member
-- too far away to have one
local entities = { GetServerId = function() return who.ServerId end }

-- Every inbound packet, whether the windows are drawn or not: a cast begun while they were hidden ends
-- as it should
function casts.HandlePacket(e, on)
    wanted = on and true or false
    if e.id ~= 0x00A then castbar.Configure(wanted, false) end
    castbar.HandlePacket(e)
end

-- A made-up line casting (sampleCast) while the windows are arranged, to see how a cast looks
local sample = { kind = 'spell', name = 'Cure IV', progress = 0, timer = '' }
local sampleTenth = nil

-- Gives each line in the area the cast it is in the middle of, or none
function casts.Mark(members, on, now)
    wanted = on and true or false
    castbar.Begin(wanted, false, now)
    for _, member in ipairs(members) do
        local cast = nil
        if wanted and member.sampleCast then
            local elapsed = now % 3
            local tenth = math.floor((3 - elapsed) * 10 + 0.5)
            if tenth ~= sampleTenth then sampleTenth, sample.timer = tenth, ('~%.1fs'):format(tenth / 10) end
            sample.progress = elapsed / 3
            cast = sample
        elseif wanted and member.isInZone and member.targetIndex and (member.serverId or 0) > 0 then
            who.ServerId, who.EntityIndex = member.serverId, member.targetIndex
            cast = castbar.Of(who, entities, now, (member.hpp or 0) == 0)
        end
        member.cast = cast
    end
    return members
end

return casts
