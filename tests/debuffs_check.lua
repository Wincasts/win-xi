-- winxi.debuffs on its own: what is on an enemy, from the spells seen to land on it
local debuffs = require('winxi.debuffs')
local now = 1000
os.time = function() return now end

-- a spell finishing (category 4), as winxi.packets parses it: who cast it, which spell, and the
-- message it gave for each target
local function cast(actor, spell, results)
    local targets = {}
    for id, message in pairs(results) do
        targets[#targets + 1] = { id = id, actions = { { message = message } } }
    end
    debuffs.Action({ actor_id = actor, category = 4, param = spell, targets = targets })
end
local function names(id)
    local list = {}
    for _, entry in ipairs(debuffs.Active(id)) do list[#list + 1] = entry.name .. ' ' .. (entry.expires - now) end
    return table.concat(list, ', ')
end

H.print('nothing seen: nothing on it', #debuffs.Active(900) == 0, debuffs.Remaining(900, 'dia') == nil)
cast(1, 23, { [900] = 2 }); H.print('Dia lands:', names(900), '| by', debuffs.Get(900, 'dia').by)
cast(1, 56, { [900] = 85 }); H.print('Slow is resisted: not on it', debuffs.Get(900, 'slow') == nil)
cast(2, 56, { [900] = 236, [901] = 85 }); H.print('Slow on one of two:', names(900), '| the other', names(901) == '')
cast(2, 230, { [900] = 2 }); H.print('Bio takes Dia\'s place:', names(900))
cast(2, 3, { [900] = 2 }); H.print('a spell that leaves nothing: unchanged', #debuffs.Active(900) == 2)
debuffs.Action({ actor_id = 2, category = 3, param = 23, targets = { { id = 900, actions = { { message = 2 } } } } })
H.print('a weapon skill with a spell\'s number: unchanged', #debuffs.Active(900) == 2)
now = now + 30; H.print('half a minute on:', names(900), '| Slow has', debuffs.Remaining(900, debuffs.Kinds.Slow))
debuffs.Message({ target = 900, message = 206, param = 13 }); H.print('Slow wears off early:', names(900))
debuffs.Message({ target = 900, message = 206, param = 4 }); H.print('something not on it wears off: unchanged', names(900))
now = now + 60; H.print('Bio runs out by itself', #debuffs.Active(900) == 0, debuffs.Get(900, 'bio') == nil)
cast(1, 23, { [900] = 2, [901] = 2 }); debuffs.Message({ target = 900, message = 6, param = 0 })
H.print('one enemy is defeated: forgotten', names(900) == '', '| the other kept', names(901))
cast(3, 454, { [901] = 237 }); H.print('a threnody has its element:', debuffs.Get(901, 'threnody') and debuffs.Get(901, 'threnody').element)
debuffs.HandlePacket({ id = 0x00A }); H.print('a change of area: all forgotten', names(901) == '')
cast(1, 23, { [900] = 2 }); debuffs.Clear(); H.print('cleared', names(900) == '')

-- any status by its number: whatever put it there, for as long as the server's scripts say
local function statuses(id)
    local list = {}
    for status, entry in pairs(debuffs.Statuses(id) or {}) do
        if now < entry.expires then list[#list + 1] = status .. ':' .. (entry.expires - now) end
    end
    table.sort(list)
    return table.concat(list, ' ')
end
debuffs.Clear()
cast(1, 58, { [900] = 236 }); H.print('Paralyze by its number, for its base 120 s:', statuses(900))
cast(1, 23, { [900] = 2 }); H.print('Dia, which says only its damage, kept by number too:', statuses(900))
cast(1, 230, { [900] = 2 }); H.print('Bio takes its place:', statuses(900))
debuffs.Action({ actor_id = 5, category = 11, param = 999, targets = { { id = 901, actions = { { message = 242, param = 7 } } } } })
H.print('a monster\'s move nothing is known of: Petrification for its usual time', statuses(901))
debuffs.Action({ actor_id = 5, category = 3, param = 1, targets = { { id = 901, actions = { { message = 1, param = 300, proc_message = 160, proc_param = 6 } } } } })
H.print('a weapon skill\'s additional effect: Silence', statuses(901))
debuffs.Action({ actor_id = 5, category = 6, param = 1, targets = { { id = 902, actions = { { message = 127, param = 600 } } } } })
H.print('an ability, a status with no known length: the default', statuses(902) == '600:180')
debuffs.Action({ actor_id = 5, category = 4, param = 260, targets = { { id = 901, actions = { { message = 341, param = 7 } } } } })
H.print('dispelled: gone', statuses(901))
debuffs.Message({ target = 901, message = 206, param = 6 }); H.print('wears off: gone', statuses(901) == '')
debuffs.Message({ target = 900, message = 6, param = 0 }); H.print('defeated: forgotten', statuses(900) == '', debuffs.StatusRemaining(900, 4) == nil)
cast(1, 58, { [900] = 236 }); now = now + 30; H.print('remaining', debuffs.StatusRemaining(900, 4))
debuffs.HandlePacket({ id = 0x00A }); H.print('a change of area: all forgotten', statuses(900) == '', statuses(902) == '')

-- an action on many: the first target's message names who did it, the others' only the target
debuffs.Action({ actor_id = 5, category = 11, param = 999, targets = {
    { id = 900, actions = { { message = 243, param = 6 } } },
    { id = 901, actions = { { message = 278, param = 6 } } },
    { id = 902, actions = { { message = 277, param = 6 } } } } })
H.print('a move on three: Silence on each', statuses(900) ~= '', statuses(901) ~= '', statuses(902) ~= '')
debuffs.Action({ actor_id = 6, category = 4, param = 125, targets = {
    { id = 1, actions = { { message = 230, param = 40 } } },
    { id = 2, actions = { { message = 266, param = 40 } } } } })
H.print('Protectra on two: Protect on both', debuffs.StatusRemaining(1, 40) ~= nil, debuffs.StatusRemaining(2, 40) ~= nil)

-- how long: the server's base duration where its scripts have one, this file's own where not
debuffs.Clear()
cast(3, 454, { [900] = 237 }); H.print('Fire Threnody lasts the server\'s 60 s:', names(900), '| by number', statuses(900))
cast(3, 368, { [901] = 237 }); H.print('Foe Requiem lasts the server\'s 64 s:', names(901), '| by number', statuses(901))
cast(1, 23, { [902] = 2 }); H.print('Dia, which the scripts do not say: this file\'s 60 s:', names(902), '| by number', statuses(902))

-- being hurt wakes a sleeper, and so does being cured; the server says nothing of it to most
debuffs.Clear()
local function act(actor, category, param, id, message, amount, proc, procParam)
    debuffs.Action({ actor_id = actor, category = category, param = param,
        targets = { { id = id, actions = { { message = message, param = amount, proc_message = proc, proc_param = procParam } } } } })
end
cast(1, 253, { [900] = 236 }); H.print('Sleep lands:', names(900), '| by number', statuses(900))
act(5, 1, 0, 900, 1, 0); H.print('hit for nothing: still asleep', names(900) ~= '', statuses(900) ~= '')
act(5, 1, 0, 900, 1, 48); H.print('hit for 48: awake', names(900) == '', statuses(900) == '')
cast(1, 253, { [900] = 236 }); act(5, 2, 0, 900, 353, 120); H.print('a ranged critical: awake', names(900) == '')
cast(1, 253, { [900] = 236 }); act(5, 4, 144, 900, 2, 90); H.print('a spell\'s damage: awake', names(900) == '')
cast(1, 253, { [900] = 236 }); act(5, 3, 1, 900, 185, 200); H.print('a weapon skill: awake', names(900) == '')
cast(1, 253, { [900] = 236 }); act(5, 4, 1, 900, 7, 60); H.print('cured: awake', names(900) == '')
cast(1, 253, { [900] = 236 }); act(5, 1, 0, 900, 15, 0, 163, 12)
H.print('a miss whose additional effect hurts: awake', names(900) == '')
cast(1, 253, { [900] = 236 }); act(5, 1, 0, 901, 1, 48); H.print('another is hit: still asleep', names(900) ~= '')
act(1, 11, 999, 902, 242, 19); H.print('Sleep II by number from a move:', statuses(902))
act(5, 11, 998, 902, 185, 30, 160, 4); H.print('a move that hurts and paralyses: awake, paralysed', statuses(902))
act(1, 11, 999, 903, 185, 30, 160, 2); H.print('a move that hurts and then sleeps: asleep', statuses(903))
-- something eating its HP: the next tick wakes it, three seconds away at most
debuffs.Clear()
cast(1, 253, { [900] = 236 }); cast(2, 23, { [900] = 2 })
H.print('Dia on a sleeper: sleep has', debuffs.Remaining(900, 'sleep'), '| by number', debuffs.StatusRemaining(900, 2), '| Dia its own', debuffs.StatusRemaining(900, 134))
now = now + 3; H.print('three seconds on: awake', names(900) == 'Dia 57', statuses(900) == '134:57')
cast(2, 220, { [901] = 236 }); cast(1, 253, { [901] = 236 })
H.print('Sleep on one poisoned: sleep has', debuffs.Remaining(901, 'sleep'), '| Poison its own', debuffs.StatusRemaining(901, 3) > 3)
cast(1, 253, { [902] = 236 }); cast(2, 56, { [902] = 236 })
H.print('Slow on a sleeper, which does not bleed: sleep has', debuffs.Remaining(902, 'sleep'))
