-- winparty's pets: each pet row has the statuses seen to land on the pet, beside it as a party member's
-- buffs are, with the time under each when Show Durations is on; a made-up pet the sample statuses
H.load()
require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's durations set, from the repository's data
local o = H.options()
local options, frames, draw, imgui = require('options'), require('frames'), require('draw'), require('imgui')
local pets, partyDebuffs = require('pets'), require('debuffs')
local tracker = require('winxi.debuffs')
local statustimes = require('winxi.statustimes')

-- the player's pet (server id 0x5001) and Owner1's (0x5002)
local party = { GetMemberTargetIndex = function(_, i) return i + 10 end,
    GetMemberIsActive = function(_, i) return i <= 1 and 1 or 0 end, GetMemberZone = function() return 1 end,
    GetMemberName = function(_, i) return 'Owner' .. i end, GetMemberServerId = function(_, i) return i == 0 and 0x100 or 0x200 + i end }
local player = { GetPetMPPercent = function() return 50 end, GetPetTP = function() return 0 end,
    GetMainJob = function() return 1 end, GetSubJob = function() return 1 end, GetIsZoning = function() return 0 end,
    GetStatusIcons = function() return {} end, GetStatusTimers = function() return {} end }
AshitaCore.GetMemoryManager = function() return { GetParty = function() return party end, GetPlayer = function() return player end } end
local realPlayer, realEntity = GetPlayerEntity, GetEntity
local resources = AshitaCore.GetResourceManager
AshitaCore.GetResourceManager = function()
    local base = resources and resources() or {}
    return setmetatable({ GetStatusIconByIndex = function() return { HideTimer = 0 } end }, { __index = base })
end
GetPlayerEntity = function() return {} end
GetEntity = function(index)
    if index < 20 then return { PetTargetIndex = index + 10 } end
    return { Name = 'Pet' .. index, HPPercent = 100, ServerId = 0x5000 + index - 19 }
end
o.pets.showParty[1] = true
pets.Forget()
local lines = pets.Lines(false, o.pets)
H.print('each pet\'s line has its server id for its statuses', #lines == 2, lines[1].statusServerId == 0x5001, lines[2].statusServerId == 0x5002,
    '| its line id still its place', lines[1].serverId == -1001)
pets.Forget()
GetPlayerEntity = function() return nil end
local samples = pets.Lines(true, o.pets)
H.print('a made-up pet: no server id, so sample statuses', samples[1].statusServerId == nil)
GetPlayerEntity = function() return {} end

-- a monster paralyzes the player's pet (spell 58), and the player casts Protect on it (spell 43)
tracker.Clear()
tracker.Action({ actor_id = 0x9999, category = 4, param = 58, targets = { { id = 0x5001, actions = { { message = 236 } } } } })
tracker.Action({ actor_id = 0x100, category = 4, param = 43, targets = { { id = 0x5001, actions = { { message = 230, param = 40 } } } } })
local ids = partyDebuffs.Ids(0x5001, {})
H.print('what landed on the pet: Paralysis and Protect', table.concat(ids, ','))

-- drawn: beside the pet's row, with their times
local icons, texts = {}, {}
draw.Texture = function() return 1 end
draw.Packed = function(color) return color end
draw.Image = function(texture, x1, y1, x2, y2) if texture >= 1000 then icons[#icons + 1] = texture - 1000 end end
draw.Text = function(x, y, color, words) texts[#texts + 1] = { words = words, color = color } end
imgui.CalcTextSize = function(text) return #text * 8, 14 end
o.style.showDurations[1] = true
local style = options.Style(o)
style.bookends, style.barGlow, style.buffDirection, style.buffFitScreen, style.buffLimit = false, 0, 'right', false, 8
lines = pets.Lines(false, o.pets)
lines[1].statusIds, lines[2].statusIds = ids, {}
statustimes.Begin()
frames.Draw(lines, 'pets', function(id) return 1000 + id, false end, style)
local words, colours = {}, {}
local timesOf = { ['2m'] = true, ['30m'] = true }
for _, text in ipairs(texts) do if timesOf[text.words] then words[#words + 1] = text.words; colours[text.words] = text.color end end
H.print('the pet\'s icons drawn', table.concat(icons, ','))
H.print('their times: Paralysis 2m, Protect 30m', table.concat(words, ' '))
H.print('the monster\'s in Estimate Color, yours in Your Color', colours['2m'] == style.estimateColor, colours['30m'] == style.mineColor)

-- a made-up pet while arranging: the sample statuses with sample times
icons, texts = {}, {}
pets.Forget()
GetPlayerEntity = function() return nil end
samples = pets.Lines(true, o.pets) -- the lines are kept and filled again: read afresh
GetPlayerEntity = function() return {} end
samples[1].statusIds, samples[2].statusIds = { 4, 13, 134 }, {}
frames.Draw(samples, 'pets', function(id) return 1000 + id, false end, style)
words = {}
local sampleTimes = { ['25m'] = true, ['2m'] = true, ['45'] = true }
for _, text in ipairs(texts) do if sampleTimes[text.words] then words[#words + 1] = text.words end end
H.print('a made-up pet: three sample icons and times', #icons == 3, #words == 3, table.concat(words, ' '))

-- followed while a real pet is listed with statuses shown, durations or not; not with no pet, or pets off
o.style.showDurations[1] = false
o.target.enabled[1], o.target.debuffList[1] = false, false
require('game').StPartyIndex = function() return nil end
require('winxi.game').IsHidden = function() return false end
local windows = require('windows')
windows.UpdateFade, windows.Draw, windows.IsFadedOut = function() end, function() end, function() return false end
require('roster').Counts = function() return 1, 0, 0, false end
local listed = { { name = 'Pet', serverId = -1001, statusServerId = 0x5001, isInZone = true } }
local realLines = pets.Lines
pets.Lines = function() return listed end
local handled = 0
local realHandle = partyDebuffs.HandlePacket
partyDebuffs.HandlePacket = function() handled = handled + 1 end
local function followed()
    H.frames(1)
    local before = handled
    H.packet(0x028)
    return handled > before
end
o.pets.enabled[1], o.style.showStatuses[1] = true, true
H.print('a pet listed: what lands is followed', followed())
listed = {}
H.print('no pet: not followed', not followed())
listed = { { name = 'Pet', serverId = -1001, statusServerId = 0x5001, isInZone = true } }
o.pets.enabled[1] = false
H.print('pets off: not followed', not followed())
o.pets.enabled[1], o.style.showStatuses[1] = true, false
H.print('statuses off: not followed', not followed())
o.style.showStatuses[1] = true
partyDebuffs.HandlePacket, pets.Lines, GetPlayerEntity, GetEntity = realHandle, realLines, realPlayer, realEntity
AshitaCore.GetResourceManager = resources
