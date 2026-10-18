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
local inline = format.Compile('[icons: space=4, size=150; gap = 3 color=cyan][name: color=yellow, space=8] [distance: decimals=2]')
assert(inline.icons and inline.distance and inline[1].space == 4 and inline[1].size == 150 and inline[1].gap == 3)
assert(inline[1].color == 0xFF60E0E0 and inline[2].color == 0xFFFFE040 and inline[2].space == 8)
assert(inline[4].decimals == 2)
for _, token in ipairs({ 'name', 'distance', 'level', 'checked', 'aggro', 'letter', 'icons' }) do
    local part = format.Compile('[' .. token .. ': space=5 color=#123]')[1]
    assert(part.kind == token and part.space == 5 and part.color == 0xFF112233)
end
assert(format.Compile('[ ICONS : space = 4 ]')[1].space == 4)
assert(format.Compile('[icons: size=999 gap=-1 space=999]')[1].size == 300)
assert(format.Compile('[icons: gap=-1]')[1].gap == 0)
assert(format.Compile('[distance: decimals=9]')[1].decimals == 2)
for _, bad in ipairs({ '[name: nope=4]', '[level: decimals=2]', '[icons: size=oops]',
    '[icons: space=1e999]', '[name:color=nocolour]', '[name:]', '[distance:decimals=nan]' }) do
    assert(format.Compile(bad)[1].text == bad, 'invalid/unsupported modifiers must remain literal: ' .. bad)
end
local filtered = format.Mob('[aggro: space=5] Lv [level]. [name: space=9][icons: size=90, gap=7]', false, true, false)
assert(filtered[1].space == 5 and filtered[#filtered].gap == 7 and filtered[#filtered].size == 90)
assert(filtered.icons, 'mob variants must preserve inline-icon metadata')
assert(format.Compile('[name:yellow]')[1].color == 0xFFFFE040, 'legacy colour syntax must remain supported')
print('name formats: toggles, colours, inline icons, bounded token options, invalid syntax and caching\ttrue')
