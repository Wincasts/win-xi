-- winxi.statustimes: the label under a status's icon. The player's own from the game's timers, to the
-- second; a party member's from when it was seen to land or to appear on them; anyone else's from
-- winxi.debuffs; '-' where none of those can say.
require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's durations set, from the repository's data
local debuffs = require('winxi.debuffs')
local statustimes = require('winxi.statustimes')
local now = 5000
os.time = function() return now end

-- the game: the player (0x100) under Protect with 90 s left, Signet that does not run out, and two
-- marches, 30 s and 75 s; the game writes no time under status 13 (HideTimer)
local EPOCH, STAMP = 0x3C307D70, 0x3C307D70 + 7000
local function ends(seconds) return (STAMP - EPOCH) * 60 + seconds * 60 end
local icons = { 40, 253, 214, 214, 13, 255 }
local timers = { ends(90), 0x7FFFFFFF, ends(30), ends(75), ends(40), 0 }
local memory = { [0x9000] = 0x9100, [0x9100] = 0x9200, [0x9200 + 0x0C] = STAMP }
ashita = ashita or {}
ashita.memory = ashita.memory or {}
ashita.memory.find = function(module) return module == 'FFXiMain.dll' and 0x9000 or 0 end
ashita.memory.read_uint32 = function(at) return memory[at] or 0 end
local player = { GetIsZoning = function() return 0 end, GetStatusIcons = function() return icons end,
    GetStatusTimers = function() return timers end }
local party = { GetMemberServerId = function(_, place) return place == 0 and 0x100 or 0 end }
AshitaCore = AshitaCore or {}
AshitaCore.GetMemoryManager = function() return { GetPlayer = function() return player end, GetParty = function() return party end } end
AshitaCore.GetResourceManager = function() return { GetStatusIconByIndex = function(_, id) return { HideTimer = id == 13 and 1 or 0 } end } end

local function text(serverId, id, nth)
    local words, estimate = statustimes.Text(serverId, id, nth)
    return tostring(words) .. (estimate and '~' or '')
end

statustimes.Begin()
H.print('labels: seconds, then minutes, then hours', statustimes.Label(45), statustimes.Label(150), statustimes.Label(3700), statustimes.Label(-3))
H.print('own Protect: 1m left, exact', text(0x100, 40) == '1m', text(0x100, 40))
H.print('own Signet, which does not run out: nothing written', statustimes.Text(0x100, 253) == nil)
H.print('own marches, each its own: 30, then 1m', text(0x100, 214, 1), text(0x100, 214, 2))
H.print('what the game writes no time under: nothing, for anyone', statustimes.Text(0x100, 13) == nil, statustimes.Text(0x200, 13) == nil)
now = now + 1; STAMP = STAMP + 1; memory[0x9200 + 0x0C] = STAMP; statustimes.Begin()
H.print('a second on, read again: Protect 89 s', text(0x100, 40) == '1m', '| the first march', text(0x100, 214, 1))

-- a party member (0x200): under Haste when first watched, a time not known; Protect cast on them
-- (spell 43, the server's 1800 s), and Regen appearing with no landing seen
local member = { 33, count = 1 }
statustimes.Watch(0x200, member)
-- time passing as it does in the game: the member read again every few seconds
local function pass(seconds)
    for _ = 1, seconds do now = now + 1; statustimes.Begin(); statustimes.Watch(0x200, member) end
end
H.print('on them before they were watched: -, an estimate', text(0x200, 33) == '-~', text(0x200, 33))
debuffs.Action({ actor_id = 0x100, category = 4, param = 43, targets = { { id = 0x200, actions = { { message = 230, param = 40 } } } } })
member[2], member.count = 40, 2
statustimes.Watch(0x200, member)
H.print('Protect seen to land: 30m, an estimate', text(0x200, 40) == '30m~', text(0x200, 40))
pass(600)
H.print('ten minutes on: 20m', text(0x200, 40) == '20m~', text(0x200, 40))
-- Paralysis appears on them with no landing seen: its usual 60 s from now
member[3], member.count = 4, 3
statustimes.Watch(0x200, member)
H.print('Paralysis appears, nothing seen to land: its usual 60 s', text(0x200, 4) == '1m~', text(0x200, 4))
pass(61)
H.print('past its usual time and still on them: -', text(0x200, 4) == '-~', text(0x200, 4))
-- it goes and comes again: seen to begin again
member[3], member.count = nil, 2; statustimes.Watch(0x200, member)
member[3], member.count = 4, 3; statustimes.Watch(0x200, member)
H.print('gone and back: its usual time again', text(0x200, 4) == '1m~', text(0x200, 4))
-- a status the server's data has no length for, seen to appear: -
member[4], member.count = 251, 4; statustimes.Watch(0x200, member)
H.print('appears, its length not known: -', text(0x200, 251) == '-~')
-- a landing long before it last appeared on them is another time's: the appearance is used
debuffs.Action({ actor_id = 0x100, category = 4, param = 23, targets = { { id = 0x200, actions = { { message = 230, param = 5 } } } } })
pass(20)
member[5], member.count = 5, 5; statustimes.Watch(0x200, member)
H.print('Blindness landed 20 s before it appeared: its usual time from appearing', text(0x200, 5), '| not the landing\'s', text(0x200, 5) ~= statustimes.Label(debuffs.StatusRemaining(0x200, 5) or 0) .. '~' or debuffs.StatusRemaining(0x200, 5) == nil)

-- anyone else (an enemy, 0x300): what winxi.debuffs saw land
debuffs.Action({ actor_id = 0x100, category = 4, param = 58, targets = { { id = 0x300, actions = { { message = 236, param = 4 } } } } })
H.print('an enemy\'s Paralyze: the spell\'s 120 s, an estimate', text(0x300, 4) == '2m~', text(0x300, 4))
debuffs.Action({ actor_id = 0x100, category = 4, param = 9999, targets = { { id = 0x300, actions = { { message = 236, param = 251 } } } } })
H.print('a status whose length nothing gives (180 s guessed): -', text(0x300, 251) == '-~', text(0x300, 251))
H.print('nothing seen on them: -', text(0x301, 4) == '-~')

-- a member not watched for half a minute is forgotten: back, what is on them is not known
now = now + 31; statustimes.Begin()
statustimes.Watch(0x200, member)
H.print('back after half a minute: Paralysis -', text(0x200, 4) == '-~', text(0x200, 4), '| Protect still from its landing', text(0x200, 40))

-- whose it is: Protect on them (0x200) was cast by the player (0x100), seen to land after it appeared
local function whose(serverId, id) return select(3, statustimes.Text(serverId, id)) == true end
H.print('the player\'s Protect on them: yours', whose(0x200, 40))
H.print('Paralysis, which nobody was seen to cast: not yours', not whose(0x200, 4))
-- someone else (0x500) casts Protect over it: no longer yours
debuffs.Action({ actor_id = 0x500, category = 4, param = 43, targets = { { id = 0x200, actions = { { message = 230, param = 40 } } } } })
H.print('someone else\'s Protect over yours: not yours', not whose(0x200, 40), text(0x200, 40))
-- an enemy's Paralyze the player cast: yours while it lasts, and not once it has run out
H.print('the enemy\'s Paralyze you cast: yours', whose(0x300, 4))
now = now + 200; statustimes.Begin()
H.print('run out: not yours', not whose(0x300, 4))
-- the player's own Protect, cast by themselves: exact and yours
debuffs.Action({ actor_id = 0x100, category = 4, param = 43, targets = { { id = 0x100, actions = { { message = 230, param = 40 } } } } })
local words, estimate, mine = statustimes.Text(0x100, 40)
H.print('your own Protect, cast by you: exact and yours', estimate == false, mine == true, words)
