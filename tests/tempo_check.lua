-- tempo: the attack delay worked out as the server does, the timer's holds, and the resting ticks
-- put where the server lands them. Run alone: luajit tests/tempo_check.lua
package.path = 'addons/tempo/?.lua;' .. package.path
local swing = require('swing')
local rest = require('rest')

local failed = 0
local function check(label, ok, ...)
    print(label, ok, ...)
    if not ok then failed = failed + 1 end
end
local function near(a, b, within) return a ~= nil and math.abs(a - b) <= (within or 0.001) end

-- the delay
local none = {}
local sword = { id = 16535, delay = 224, skill = 3 }
local war = { main = sword, mainJob = 1, mainLevel = 75, subJob = 13, subLevel = 37, buffs = none }
check('one sword: 224 delay is 3.733 s', near(swing.Estimate(war), 3.733))
local dual = { main = sword, sub = sword, mainJob = 13, mainLevel = 75, subJob = 1, subLevel = 37, buffs = none }
-- (3733 + 3733) * 0.70 = 5226
check('two swords, NIN 75 Dual Wield 30%', near(swing.Estimate(dual), 5.226))
local mnk = { main = { id = 1, delay = 96, skill = 1 }, mainJob = 2, mainLevel = 75, subJob = 1, subLevel = 37, buffs = none }
-- (96 + 240) - 180 Martial Arts = 156 units: 5600 - 3000 = 2600 ms
check('MNK 75, 96 knuckles with Martial Arts', near(swing.Estimate(mnk), 2.6))
local hasted = { main = sword, mainJob = 1, mainLevel = 75, subJob = 13, subLevel = 37, buffs = { [33] = true } }
check('Haste takes 14.65% off', near(swing.Estimate(hasted), math.floor(3733 * (1 - 0.1465)) / 1000))
check('a buff changes the key', swing.Key(war) ~= swing.Key(hasted))

-- the timer
local d = swing.Estimate(war)
local key = swing.Key(war)
swing.Engage(0, d, key, false)
local _, left = swing.Progress(0)
check('first round 2.8 s after engaging', near(left, 2.8))
swing.Round(2.9, d, key)
_, left = swing.Progress(3.9)
check('then the delay', near(left, d - 1))
swing.Ability(3.9)
_, left = swing.Progress(3.9)
check('an ability holds it 2 s', near(left, d - 1 + 2))
swing.CastBegin(4.0, 'spell')
local _, l1, _, _, why = swing.Progress(6.0)
check('a spell holds it while cast', near(l1, d - 1 + 2 - 0.1) and why == 'Casting', why)
swing.CastEnd(6.0)
_, left = swing.Progress(6.0)
check('and 2 s after', near(left, d - 1 + 2 - 0.1 + 2))
swing.OutOfReach('Too Far')
local _, _, _, _, said = swing.Progress(6.0)
check('too far is said', said == 'Too Far')
-- three clean rounds learn a delay the estimate does not know
local t = 20
swing.Round(t, d, key)
for _ = 1, 4 do t = t + 3.5; swing.Round(t, d, key) end
local _, _, used, learned = swing.Progress(t)
check('learned from rounds 3.5 s apart', learned and near(used, 3.5), used)
swing.Stopped(t + 1, 'Asleep')
local _, l2 = swing.Progress(t + 5)
check('asleep stops the bar', near(l2, 2.5))
swing.Stopped(t + 5, nil)
_, l2 = swing.Progress(t + 5)
check('and it goes on from where it was', near(l2, 2.5))
swing.Disengage()
check('out of a fight: nothing', swing.Progress(t) == nil)

-- the resting ticks. The server: tick k at the first 3 s pass after sat + 10k. Here the passes fall
-- at 1.1 + 3j, so tick 2 (the first that restores) lands at 22.1, tick 3 at 31.1, tick 4 at 40.1,
-- tick 5 at 52.1: 9, 9, 12.
local function landing(k) local mark = 10 * k; return 1.1 + math.ceil((mark - 1.1) / 3) * 3 end
local sat = 0.25 -- resting shows on the character a moment after the server starts it
local hp, mp, hpMax, mpMax = 100, 50, 900, 400
rest.Start(sat, hp, mp, hpMax, mpMax)
local fill, l3, gh, gm = rest.Progress(sat)
check('first tick put about 21.4 s off', near(l3, 21.4, 0.3) and gh == 10 and gm == 12, l3, gh, gm)
-- tick 2 restores 10 HP and 12 MP, plus 3 HP of gear here
local now = sat
local function step(to)
    while now < to do now = now + 0.05; rest.Frame(now, hp, mp, hpMax, mpMax) end
end
step(landing(2)); hp, mp = hp + 13, mp + 12; rest.Frame(now, hp, mp, hpMax, mpMax)
_, l3, gh, gm = rest.Progress(now)
check('tick 3 put on the pass 9 s on', near(l3, 9, 0.06) and gh == 14 and gm == 13, l3, gh, gm)
step(landing(3)); hp, mp = hp + 14, mp + 13; rest.Frame(now, hp, mp, hpMax, mpMax)
_, l3 = rest.Progress(now)
check('tick 4: 9 s on', near(l3, 9, 0.06), l3)
step(landing(4)); hp, mp = hp + 15, mp + 14; rest.Frame(now, hp, mp, hpMax, mpMax)
_, l3 = rest.Progress(now)
check('tick 5: 12 s on', near(l3, 12, 0.06), l3)
-- at full nothing shows: the ticks go on being counted
hp, mp = hpMax, mpMax
step(landing(7) + 2)
local _, l4, g1, g2, full = rest.Progress(now)
check('at full, ticks still counted (next is tick 8)', near(now + l4, landing(8), 0.1) and g1 == 0 and g2 == 0 and full == 0, l4)
rest.Stop()
check('standing up: nothing', rest.Progress(now) == nil)

-- loaded mid-rest: the first tick seen says which it was, by its MP
hp, mp = 300, 100
rest.Start(100, hp, mp, hpMax, mpMax, true)
check('joined: nothing told yet', select(2, rest.Progress(100)) == nil)
now = 100
step(103); hp, mp = hp + 16, mp + 18; rest.Frame(now, hp, mp, hpMax, mpMax) -- 18 MP: tick 8
_, l3, gh, gm = rest.Progress(now)
check('joined: tick 9 next, 9 or 12 s on', (near(l3, 9, 0.06) or near(l3, 12, 0.06)) and gm == 19, l3, gm)

if failed > 0 then
    print(('%d failed'):format(failed))
    os.exit(1)
end
print('all passed')
