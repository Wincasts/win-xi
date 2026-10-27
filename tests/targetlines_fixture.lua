-- Loads targetlines' settings (config.lua) for the shared Ashita harness: the addon's main file needs
-- the Direct3D device for its lines, which the harness has not, and the settings window is config's.
package.path = 'addons/libs/?.lua;addons/targetlines/?.lua;' .. package.path;
package.preload['chat'] = function()
    return setmetatable({}, { __index = function() return function(text) return tostring(text or ''); end; end });
end;

-- what Ashita's 'common' adds and the harness has not
table.contains = table.contains or function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end;
H.targetlines = require('config');
