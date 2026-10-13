-- mark's data and its Treasure Hunter sums. Run from the top of the project: luajit tests/mark_data_check.lua
package.path = 'addons/mark/?.lua;' .. package.path
addon = { path = 'addons/mark/' }
ashita = { fs = { exists = function(path) local file = io.open(path, 'rb') if file then file:close() end return file ~= nil end } }
AshitaCore = nil -- no game: the zones go by the data's own names
local hunts = require('hunts')

-- every monster listed has a record, and every record is of the shape the window expects
local zones, monsters, lotteries, unknown, problems = hunts.Zones(true), 0, 0, 0, {}
for _, zone in ipairs(zones) do
    for _, name in ipairs(zone.monsters) do
        monsters = monsters + 1
        local record = hunts.Monster(zone.id, name)
        if record == nil then
            problems[#problems + 1] = ('%s: no record for %s'):format(zone.name, name)
        else
            if record.lottery ~= nil then
                lotteries = lotteries + 1
                if record.lottery.chance == nil then unknown = unknown + 1 end
            end
            for _, roll in ipairs(record.drops) do
                local shares = 0
                for _, item in ipairs(roll.items) do shares = shares + item[2] end
                if roll.rate < 0 or roll.rate > 1000 or shares > 10000 or #roll.items == 0 then
                    problems[#problems + 1] = ('%s: a roll of %s out of bounds'):format(zone.name, name)
                end
            end
            for _, placeholder in ipairs(record.placeholders or {}) do
                if placeholder.index < 1 or placeholder.index > 0xFFF or placeholder.name == name then
                    problems[#problems + 1] = ('%s: a placeholder of %s out of bounds'):format(zone.name, name)
                end
            end
            -- put into words without error, whatever it holds
            local ok, why = pcall(function()
                hunts.Appears(record, tostring); hunts.Drops(record, tostring); hunts.Places(record.points, record.areas)
            end)
            if not ok then problems[#problems + 1] = ('%s: %s: %s'):format(zone.name, name, why) end
        end
    end
end
print('zones', #zones, '| monsters', monsters, '| lotteries', lotteries, '| of unknown chance', unknown)
print('every record sound', #problems == 0)
for place = 1, math.min(#problems, 10) do print('  ' .. problems[place]) end

print('percentages', hunts.Percent(2400) == '24%', hunts.Percent(50) == '0.5%', hunts.Percent(6666) == '66.66%', hunts.Percent(10000) == '100%')
print('waits', hunts.Duration(45) == '45 sec', hunts.Duration(2400) == '40 min', hunts.Duration(5400) == '1 hr 30 min',
    hunts.Duration(75600) == '21 hr', hunts.Duration(259200) == '3 days')
print('compass', hunts.Compass(0, 1) == 'N', hunts.Compass(1, 1) == 'NE', hunts.Compass(1, 0) == 'E', hunts.Compass(-1, -1) == 'SW', hunts.Compass(-1, 0) == 'W')
print('a roll that always drops is left alone; a rare one is helped', hunts.Chance(0, 1000) == 10000, hunts.Chance(14, 1000) == 10000,
    hunts.Chance(0, 10) == 100, hunts.Chance(4, 10) == 250, hunts.Chance(0, 0) == 0)

-- against the server's own function, where its source is at hand
local source = io.open('references/Phoenix/scripts/combat/basic/treasure_hunter.lua', 'rb')
if source == nil then
    print('the server\'s Treasure Hunter function: no source at hand, not compared')
else
    source:close()
    xi = nil
    utils = { defaultIfNil = function(value, default) if value == nil then return default end return value end,
        clamp = function(value, low, high) return math.max(low, math.min(high, value)) end }
    dofile('references/Phoenix/scripts/combat/basic/treasure_hunter.lua')
    local same, compared = true, 0
    for th = 0, 14 do
        for rate = 0, 1000 do
            compared = compared + 1
            same = same and hunts.Chance(th, rate) == xi.combat.treasureHunter.getDropRate(th, rate * 10)
        end
    end
    print('the server\'s Treasure Hunter function: the same at every level and rate', same, compared)
end
