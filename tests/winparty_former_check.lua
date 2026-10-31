-- winparty was party up to 0.4: a character's settings saved under party are brought over once, as the
-- settings are loaded with the character known, and not again
local o = H.options()
H.print('nothing under party: nothing brought over, and not looked for again', o.fromParty == true)

local legacy = require('winxi.legacy')
local readSettings, asked = legacy.ReadSettings, nil
legacy.ReadSettings = function(name) asked = name; return { clickThrough = { false }, automaticPositioning = { true } } end
o.fromParty = false
H.resettle()
H.print('settings saved under party brought over and said', asked == 'party', o.clickThrough[1] == false,
    o.automaticPositioning[1] == true, o.fromParty == true, H.printed[#H.printed]:find('brought over from party', 1, true) ~= nil)

asked = nil
o.clickThrough[1] = true
H.resettle()
H.print('once only', asked == nil, o.clickThrough[1] == true)
legacy.ReadSettings = readSettings
