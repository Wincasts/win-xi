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
assert(display(format.Compile(text)) == text)
local parts = format.Compile(text)
assert(parts.level and parts.aggro and not parts.distance and not parts.checked and not parts.letter and not parts.icons)
assert(format.Compile(text) == parts, 'compiled formats must be cached')
local tinted = format.Compile('[aggro:red] Lv [level:yellow]. [name:cyan] [distance]')
assert(display(tinted) == '[aggro] Lv [level]. [name] [distance]' and tinted.distance)
assert(tinted[1].color == 0xFFFF4040 and tinted[3].color == 0xFFFFE040 and tinted[5].color == 0xFF60E0E0 and tinted[7].color == nil)
assert(format.Compile('[checked][name]').checked and format.Compile('[name] [letter]').letter)
assert(format.Compile('[letter:yellow] [name]')[1].color == 0xFFFFE040 and format.Compile('[letters: type=double]').doubleLetters)
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
assert(format.Compile('[name: spacing=2]')[1].spacing == 2 and format.Compile('[level: spacing=99]')[1].spacing == 10
    and format.Compile('[distance: spacing=-3]')[1].spacing == 0, 'spacing= on name, level and distance, kept within 0 to 10')
assert(format.Compile('[aggro: size=200]')[1].size == 200 and format.Compile('[checked: size=10]')[1].size == 25,
    'size= on [aggro] and [checked], kept within 25 to 300')
assert(format.Serialize(format.Compile('[aggro: size=150, space=4]')) == '[aggro: space=4, size=150]', 'size= written back')
local calm = format.Compile('Lv [level: nocombat, exact]')
assert(calm[2].nocombat and calm[2].exact and calm.rules and calm.ruleCombat, '[level: nocombat] a rule of its own')
assert(format.Compile('[level: nocombat=false]')[1].nocombat == nil and format.Compile('[name: nocombat]')[1].text == '[name: nocombat]',
    'nocombat=false is none, and only [level] has it')
assert(format.Serialize(calm) == 'Lv [level: exact, nocombat]', 'nocombat written back')
assert(format.Serialize(format.Compile('[name: spacing=3, space=4]')) == '[name: space=4, spacing=3]', 'spacing= written back')
for _, bad in ipairs({ '[name: nope=4]', '[level: decimals=2]', '[icons: size=oops]',
    '[icons: space=1e999]', '[name:color=nocolour]', '[name:]', '[distance:decimals=nan]', '[icons: spacing=2]', '[aggro: spacing=2]', '[name: size=200]', '[level: size=200]' }) do
    assert(format.Compile(bad)[1].text == bad, 'invalid/unsupported modifiers must remain literal: ' .. bad)
end
assert(format.Compile('[name:yellow]')[1].color == 0xFFFFE040, 'legacy colour syntax must remain supported')
print('name formats: colours, inline icons, bounded token options, invalid syntax and caching\ttrue')
