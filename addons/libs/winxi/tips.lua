-- Editable tooltip content, independent of rendering. See tooltips/README.md.
--   tips.Get('name.appearance.bold')
--   tips.Get('name.format.options', { default_format = '[name]' })
-- Pass the returned plain text to winxi.tooltip or an addon's own help control.
local tips = {};
local catalogues = {};

function tips.Get(id, values)
    local namespace = type(id) == 'string' and id:match('^([a-z][a-z0-9_]*)%.');
    assert(namespace ~= nil, 'tips.Get needs a namespaced tooltip ID');
    local catalogue = catalogues[namespace];
    if catalogue == nil then
        catalogue = require('winxi.data.tooltips.' .. namespace);
        catalogues[namespace] = catalogue;
    end
    local text = catalogue[id];
    -- Build validation catches missing IDs; retain a visible diagnostic if installed
    -- code and generated data are accidentally from different versions.
    if text == nil then return '[Missing tooltip: ' .. id .. ']'; end
    if values == nil then return text; end
    return (text:gsub('{([a-z][a-z0-9_]*)}', function(key)
        local value = values[key];
        return value ~= nil and tostring(value) or ('{' .. key .. '}');
    end));
end

return tips;
