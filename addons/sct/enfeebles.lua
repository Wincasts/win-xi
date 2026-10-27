-- The statuses that count as enfeebles: drawn in the enfeeble colour as they land, the rest in the
-- buff colour. The game says nothing of which is which: winxi.statuses' Harmful does, the one list
-- every addon tells debuffs by.
local Harmful = require('winxi.statuses').Harmful;
return setmetatable({}, { __index = function (_, id) return Harmful(id) or nil; end });
