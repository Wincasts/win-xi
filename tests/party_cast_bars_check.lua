-- Show Cast Bars: a member's spell, seen in the action packets party is handed, given to their line
-- (casts.Mark) as winxi.castbar has it, until it finishes, is interrupted, the member dies or the area
-- changes; none with the setting off; a made-up member casting while the windows are arranged.
H.load()
local casts = require('casts')
local packet = dofile('tests/fixtures/parse_packets.lua')
local resources = {
    GetSpellById = function(_, id) return { Name = { id == 1 and 'Cure' or 'Fire' }, CastTime = 8 } end,
    GetAbilityById = function() return { Name = { 'Fast Blade' } } end,
    GetString = function() return '' end,
}
local core = AshitaCore
AshitaCore = setmetatable({ GetResourceManager = function() return resources end }, { __index = core })
package.loaded['winxi.spells'] = { Get = function() return nil end }

local saved = H.options()
assert(saved.party.castBars[1] == true, 'Show Cast Bars is on to begin with')
local actor, sequence = 1001, 0
local function send(category, id, param)
    sequence = sequence + 1
    local bytes = packet.Packet(actor, category, param or (category == 8 and 24931 or id),
        { { id = 2001, results = { { value = id or 0, message = 0 } } } }, sequence)
    H.packetData(0x028, bytes)
end
local member = { serverId = actor, targetIndex = 5, isInZone = true, hpp = 80, name = 'Member' }
local stranger = { serverId = 1002, targetIndex = 6, isInZone = true, hpp = 80, name = 'Other' }
local members = { member, stranger }
local now = os.clock()
local function mark(on) casts.Mark(members, on == nil and saved.party.castBars[1] or on, now) end

mark(); assert(member.cast == nil, 'no cast seen yet')
send(8, 1)
mark()
local cast = assert(member.cast, 'the cast is given to the caster\'s line')
assert(cast.name == 'Cure' and cast.progress == 0 and cast.timer == '~2.0s', 'its name, progress and timer')
assert(stranger.cast == nil, 'and no one else\'s')
now = now + 1; mark()
assert(member.cast.progress == 0.5 and member.cast.timer == '~1.0s', 'it fills as the cast goes')
member.entity = nil; mark(); assert(member.cast, 'a member too far to have an entity keeps their cast')
send(4, 1); mark(); assert(member.cast == nil, 'the spell finishing ends it')

send(8, 2); mark(); assert(member.cast and member.cast.name == 'Fire')
send(8, 0, 28787); mark(); assert(member.cast == nil, 'an interruption ends it')

send(8, 2); member.hpp = 0; mark(); assert(member.cast == nil, 'dying ends it')
member.hpp = 80
send(8, 2); H.packet(0x00A); mark(); assert(member.cast == nil, 'changing areas ends it')

send(8, 2); mark(); assert(member.cast)
member.isInZone = false; mark(); assert(member.cast == nil, 'a member in another area has none')
member.isInZone = true

saved.party.castBars[1] = false
mark(); assert(member.cast == nil, 'none with Show Cast Bars off')
send(8, 2); saved.party.castBars[1] = true; mark()
assert(member.cast == nil, 'nor any seen while it was off')

local sample = { serverId = -2005, isInZone = true, hpp = 40, sampleCast = true }
casts.Mark({ sample }, true, now)
assert(sample.cast and sample.cast.name == 'Cure IV', 'a made-up member casts while arranging')
casts.Mark({ sample }, false, now)
assert(sample.cast == nil, 'but not with Show Cast Bars off')
H.print('party cast bars: start, progress, finish, interrupt, death, zone, another area, off, sample', true)
