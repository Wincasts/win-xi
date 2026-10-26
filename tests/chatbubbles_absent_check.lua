-- chatbubbles with no namehook loaded: nothing drawn or searched, why said once in the chat log, and
-- what it keeps let go of once rather than made again every frame
local finds = 0
ashita.memory.find = function(m) if m == 'namehook.dll' then finds = finds + 1 end return 0 end
local before = #H.printed
local bubbles = require('bubbles')
local made, new = 0, bubbles.New
bubbles.New = function(...) made = made + 1; return new(...) end
H.frames(600)
bubbles.New = new
local said = #H.printed - before
H.print('no namehook: said once, nothing searched, let go of once', said == 1,
    H.printed[#H.printed]:find('/load namehook', 1, true) ~= nil, finds == 0, made == 1)
