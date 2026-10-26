-- damage with no namehook loaded: namehook's memory never searched or touched, why said once in the
-- chat log, nothing thrown; a namehook too old to list popups said once too
local finds = 0
ashita.memory.find = function() finds = finds + 1; return 0 end
local before = #H.printed
H.frames(10)
local said = #H.printed - before
H.print('no namehook: said once, nothing searched', said == 1, H.printed[#H.printed]:find('/load namehook', 1, true) ~= nil, finds == 0)
H.loaded('namehook', true)
H.frames(130)
H.print('an old namehook: said once', #H.printed - before == 2, H.printed[#H.printed]:find('older than 1.38', 1, true) ~= nil)
