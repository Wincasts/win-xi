local Settings = require('settings')
COOLDOWNS_LEGACY = {
    windowName = 'Recast', windowPos = { 321, 654 }, windowSize = { -1, -1 },
    abilityNameColor = { 0.2, 0.3, 0.4, 1 }, spellNameColor = { 0.5, 0.6, 0.7, 1 },
    showPetCooldowns = false, petAutomaton = { head = 4, frame = 0x23, attachments = { 33 } },
    useSharedTheme = false, theme = { Padding = 50 },
}
COOLDOWNS_IMPORTS = 0
Settings.settings_path = function() return 'C:\\ashita\\config\\addons\\cooldowns\\Tester_1\\' end
local originalLoadfile = loadfile
loadfile = function(path)
    if path == 'C:\\ashita\\config\\addons\\recast\\Tester_1\\settings.lua' then
        COOLDOWNS_IMPORTS = COOLDOWNS_IMPORTS + 1
        return function() return COOLDOWNS_LEGACY end
    end
    return originalLoadfile(path)
end
dofile('tests/cooldowns_stand_in.lua')
