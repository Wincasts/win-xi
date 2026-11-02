-- winxi.cleanse: what takes a status off, as the server's scripts have it, and whether the player can
-- now: the spell learned, and its job's level reached by the main job or a support job not restricted.
-- The levels are the game's own, so a level sync lowers them as it does.
require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's statuses and spells, from the repository's data
local cleanse = require('winxi.cleanse')

H.print('kinds: Paralysis cure, Petrification cure (Stona), Slow cure (Erase), Protect dispel, Sleep none',
    cleanse.Kind(4) == 'cure', cleanse.Kind(7) == 'cure', cleanse.Kind(13) == 'cure', cleanse.Kind(40) == 'dispel', cleanse.Kind(2) == nil)
H.print('Paralysis: Paralyna and Esuna', table.concat(cleanse.Spells(4), ',') == '15,95', table.concat(cleanse.Spells(4), ','))
H.print('Slow: Erase', table.concat(cleanse.Spells(13), ','))
H.print('Doom: Cursna', table.concat(cleanse.Spells(15), ','))
H.print('Protect: Dispel, Dispelga, Magic Finale, Blank Gaze, Geist Wall', table.concat(cleanse.Spells(40), ','))

-- the player: jobs, levels, what is learned, and their statuses
local game = { main = 3, mainLevel = 20, sub = 0, subLevel = 0, learned = { [14] = true, [15] = true, [143] = true }, icons = {} }
AshitaCore = AshitaCore or {}
AshitaCore.GetMemoryManager = function() return { GetPlayer = function() return {
    GetMainJob = function() return game.main end, GetMainJobLevel = function() return game.mainLevel end,
    GetSubJob = function() return game.sub end, GetSubJobLevel = function() return game.subLevel end,
    GetStatusIcons = function() return game.icons end,
    HasSpell = function(_, id) return game.learned[id] == true end } end } end
local function can(status) cleanse.Clear(); return cleanse.Can(status) end

H.print('WHM 20, Paralyna learned (WHM 9): Paralysis yes', can(4))
H.print('Erase learned but WHM 32: Slow no', not can(13))
game.mainLevel = 40
H.print('WHM 40: Slow yes', can(13))
game.mainLevel = 25 -- a level sync to 25
H.print('synced to 25: Slow no again, Paralysis still', not can(13), can(4))
game.learned[15] = nil; game.mainLevel = 75
H.print('Paralyna not learned, Esuna neither: Paralysis no', not can(4))
-- RDM 40 with WHM 20 support: Dispel (RDM 32) learned, Paralyna by the support job (WHM 9)
game.main, game.mainLevel, game.sub, game.subLevel = 5, 40, 3, 20
game.learned = { [260] = true, [15] = true }
H.print('RDM 40: Protect dispellable by Dispel', can(40))
H.print('WHM 20 support: Paralysis by Paralyna', can(4))
game.icons = { 157 } -- the support job restricted
H.print('support job restricted: Paralysis no, Protect still', not can(4), can(40))
game.icons = {}
game.mainLevel = 30 -- synced under Dispel's 32
H.print('synced to RDM 30: Protect no', not can(40))
H.print('Sleep: nothing takes it off by spell', not can(2))
