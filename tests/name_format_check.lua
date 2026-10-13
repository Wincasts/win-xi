package.path = 'addons/name/?.lua;' .. package.path
local format = require('format')
local function display(parts)
    local result = {}
    for _, part in ipairs(parts) do
        result[#result + 1] = part.kind == 'text' and part.text or '[' .. part.kind .. ']'
    end
    return table.concat(result)
end
local text = '[aggro] Lv [level]. [name]'
assert(display(format.Mob(text, true, true)) == text)
assert(display(format.Mob(text, false, true)) == '[aggro] [name]')
assert(display(format.Mob(text, true, false)) == 'Lv [level]. [name]')
assert(display(format.Mob(text, false, false)) == '[name]')
local tinted = '[aggro:red] Lv [level:yellow]. [name:cyan] [distance]'
local parts = format.Mob(tinted, false, false)
assert(display(parts) == '[name] [distance]')
assert(not parts.level and not parts.aggro and parts.distance)
assert(parts[#parts - 2].color == 0xFF60E0E0, 'remaining name colour must survive filtering')
assert(format.Mob(tinted, false, false) == parts, 'filtered formats must be cached')
assert(display(format.Compile(text)) == text, 'filtering must not mutate the original compiled format')
assert(display(format.Mob('[checked] [name] [level]', false, false)) == '[checked] [name]')
assert(format.Mob('[checked][name]', false, false).checked)
assert(display(format.Mob('[name]', true, true, true)) == '[name] [letter]')
assert(display(format.Mob('[letter:yellow] [name]', true, true, true)) == '[letter] [name]')
assert(format.Mob('[letter:yellow] [name]', true, true, true)[1].color == 0xFFFFE040)
assert(display(format.Mob('[name] [letter]', true, true, false)) == '[name]')
assert(display(format.Mob('[name]', true, true, false)) == '[name]')
assert(format.Mob('[name]', false, false, true).letter)
print('name formats: level/aggro toggles, standard Lv cleanup, colours, remaining tokens and caching\ttrue')
