-- The marks by a member: the party leader's dot yellow, the alliance leader's white (above the party's
-- yellow), and the level sync designee's red, at the top right of their line; roster reads the designee
-- from the party's flags (0x100, bit 8, as the server sends it; 0x80 is a linkshell sub-master's).
H.load()
local o = H.options()
local options, frames, draw, colors = require('options'), require('frames'), require('draw'), require('colors')
local style = options.Style(o)
local circles = { }
local packed, circle = draw.Packed, draw.Circle
draw.Packed = function(color, ...)
    if color == colors.PartyLeader then return 'yellow' elseif color == colors.AllianceLeader then return 'white'
    elseif color == colors.LevelSync then return 'red' end
    return packed(color, ...)
end
draw.Circle = function(x, y, radius, color, ...)
    if type(color) == 'string' then circles[#circles + 1] = { x = x, y = y, color = color } end
    return circle(x, y, radius, type(color) == 'string' and 0 or color, ...)
end
local member = { name = 'Member', serverId = 1, hp = 500, hpp = 50, mp = 200, mpp = 50, tp = 0, isInZone = true,
    isPlayer = true, statusIds = { } }
local function Marks(fields)
    for _, key in ipairs({ 'isPartyLeader', 'isAllianceLeader', 'isLevelSync' }) do member[key] = fields[key] end
    circles = { }
    frames.Draw({ member }, 'party', nil, style)
    local seen = { }
    for _, mark in ipairs(circles) do seen[#seen + 1] = mark.color end
    return table.concat(seen, ','), circles
end

assert(Marks({ isPartyLeader = true }) == 'yellow', 'the party leader\'s dot is yellow')
assert(Marks({ isAllianceLeader = true }) == 'white,yellow', 'the alliance leader\'s white above the party\'s yellow')
local seen = Marks({ isLevelSync = true })
assert(seen == 'red', 'the level sync designee\'s dot is red')
local _, leader = Marks({ isPartyLeader = true, isLevelSync = true })
assert(leader[2].color == 'red' and leader[2].x > leader[1].x + 100 and leader[2].y <= leader[1].y,
    'the red dot at the line\'s top right, the leader\'s at its left')
assert(Marks({ }) == '', 'no marks for anyone else')
assert(colors.Alliance ~= colors.AllianceLeader, 'an alliance invitation keeps its own colour')

-- roster: the designee from the party's flags
local roster = require('roster')
local flags = 0x100
local party = setmetatable({ GetMemberFlagMask = function() return flags end, GetMemberIsActive = function() return 1 end,
    GetMemberName = function(_, place) return 'Member ' .. place end, GetMemberServerId = function(_, place) return 100 + place end },
    { __index = function() return function() return 0 end end })
local core = AshitaCore
-- what roster reads of the player that the harness has not: nothing, or no buffs
local player = setmetatable({ }, { __index = function(_, key)
    return core.GetMemoryManager():GetPlayer()[key] or (key:find('Buffs') and function() return { } end) or function() return 0 end
end })
local targets = setmetatable({ }, { __index = function(_, key) return core.GetMemoryManager():GetTarget()[key] or function() return 0 end end })
local memory = setmetatable({ GetParty = function() return party end, GetPlayer = function() return player end,
    GetTarget = function() return targets end },
    { __index = core.GetMemoryManager() })
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })
GetEntity = GetEntity or function() return nil end
roster.Forget()
assert(roster.Members(1, false, false)[1].isLevelSync == true, 'flag 0x100: the level sync designee')
flags = 0x04 + 0x80
GetEntity = GetEntity or function() return nil end
roster.Forget()
local read = roster.Members(1, false, false)[1]
assert(read.isLevelSync == false and read.isPartyLeader, 'a leader and a linkshell sub-master (0x80): not the designee')
AshitaCore = core
H.print('marks: party leader yellow, alliance leader white, level sync designee red at the top right', true)
