-- Preferred Name defaults, taken from the author's own settings.
-- Existing character settings take precedence. A table of named keys is merged into the defaults'
-- own; a list (statusList, or a setting's T{ value }) takes their place whole.
require('common');

return T{
    font = 'trebucbi.ttf',
    fontBold = T{ false },
    fontSize = T{ 30 },
    minSize = T{ 10 },
    subtargetScale = T{ 125 },
    outline = T{ 1 },
    iconSize = T{ 90 },
    iconSpacing = T{ 4 },
    showIcons = T{ true },
    showStars = T{ false },
    showMobLevel = T{ true },
    showAggroIcons = T{ true },
    showMobLetter = T{ false },
    doubleMobLetters = T{ false },
    showCheckDetails = T{ true },
    checkSize = T{ 90 },
    huntScale = T{ 120 },
    statusAlign = T{ 'left' },
    statusSize = T{ 100 },
    statusOffsetX = T{ 2 },
    statusOffsetY = T{ -5 },
    statusList = T{ 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 19, 132, 133, 134, 135, 156, 192, 194, 217 },
    healthBarWidth = T{ 120 },
    healthBarHeight = T{ 7 },
    abbreviateDifficulty = T{ true },
    checkDetailsInWords = T{ false },
    nameFormat = T{ '[icons: space=4][name]' },
    monsterFormat = T{ '[aggro] [name] [letters]' },
    showSelf = T{ false },
    showParty = T{ true },
    showAlliance = T{ true },
    showPlayers = T{ true },
    showMyPet = T{ true },
    showPets = T{ true },
    showNpcs = T{ true },
    showMonsters = T{ true },
    alwaysTarget = T{ false },
    fadeInOut = T{ true },
    useSharedTheme = true,
    -- only the states given here; the others keep name_colours' own
    nameColours = T{
        playerNames = T{
            normal = T{ enabled = T{ true }, color = T{ 0.759, 0.898, 0.962, 1 } },
            alliance = T{ enabled = T{ true }, color = T{ 0.907, 0.757, 0.524, 1 } },
        },
    },
    hide = T{
        UnderChat = true, WhileLoading = true, DuringEvent = true,
        UnderMap = true, WithInterface = true,
    },
};
