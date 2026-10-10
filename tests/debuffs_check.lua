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
