-- Content lookup works without imgui and leaves rendering to the caller.
package.path = 'addons/libs/?.lua;' .. package.path
local tips = require('winxi.tips')
local data = require('winxi.data.tooltips.name')
local count = 0
for id, text in pairs(data) do
    assert(tips.Get(id) == text, id)
    count = count + 1
end
assert(count > 0)
assert(tips.Get('name.does_not_exist') == '[Missing tooltip: name.does_not_exist]')
assert(not pcall(tips.Get, 'invalid'))

-- A second namespace, repeated placeholders and literal substitutions (not format strings).
local loads = 0
package.preload['winxi.data.tooltips.testtips'] = function()
    loads = loads + 1
    return { ['testtips.example'] = '{value} / {value} / {missing}' }
end
assert(tips.Get('testtips.example', { value = '100% [name] \\" café' }) == '100% [name] \\" café / 100% [name] \\" café / {missing}')
assert(tips.Get('testtips.example', { value = false }) == 'false / false / {missing}')
assert(tips.Get('testtips.example') == '{value} / {value} / {missing}')
assert(loads == 1, 'catalogues are loaded only once')
print('WinXI tooltip content: generated entries, namespaces, caching and literal substitutions passed')
