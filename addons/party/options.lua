-- options: the addon's settings, set out once. Each setting is an entry in a list: where it is kept,
-- what it is called, what kind of control it has and what it starts as. From the lists come the
-- defaults, whatever a saved file lacks, and the controls of the settings window's tabs (config.lua
-- draws them), so that a new setting is one more entry.
--
--     options.Defaults()           a whole set of settings, as they start
--     options.Complete(saved)      brings saved settings up to date and gives them whatever they lack
--     options.Tabs                 the tabs of entries, in order: { name, entries }
--     options.Style(saved)         how the frames are to be drawn, as frames.Draw takes it
--
-- A setting is kept in a table of one value where a checkbox or a slider has to change it in place
-- (enabled[1]), and in a table of two for a place or an offset.
--
-- The settings are kept by section: style (how every frame is drawn), party, target and pets, and
-- beside those what the addon keeps for winxi (the theme, the rules for hiding, fading, links). The
-- window border, the bars' texture and bookends and the custom status icons are winxi's theme's.
require('common')
local settings = require('settings')
local legacy = require('winxi.legacy')
local theme = require('winxi.theme')
local notices = require('notices')
local debuffs = require('debuffs')

local options = { }

options.Version = 2

-- How far a figure can be moved: across, from one side of a frame (136 units wide) to the other whichever
-- end it starts at; down, past the top and bottom of a line (32 units high)
local valueReach = { 140, 40 }

local unitsNote = '\nThe number is in the frames\' own units, so it keeps its proportion as the scale changes.'

-- A distance in the settings is in units of this many pixels at a scale of 100: what the frames were
-- laid out in when the settings were first kept, so that what was set then still means what it did.
-- Everything that draws works in pixels: options.Style, and whoever else reads a distance from the
-- settings, turns units into them.
options.Unit = 1.2

-- The kinds of entry:
--   check     a checkbox                        default true or false
--   slider    a whole number between two        default, min, max, format
--   offset    two sliders, across and down      default { x, y }, reach: how far either way, or
--                                               { across, down } where the two differ
--   choice    one of several, as radio buttons  default, choices: { key, label }, two to a line
--   dropdown  one of several, as a combo        default, choices: { key, label }
--   font      a font of C:\Windows\Fonts, as a combo   default '': the theme's font
--   place     where a window is, as two numbers default { x, y }, window: its key in windows.List
--   gap       a little room between two families of settings
--   header    a collapsible Winxi section heading (no saved value)
-- when, if given, says whether the entry is shown, from the settings.
options.Tabs = {
    { name = 'Style', entries = {
        { kind = 'slider', section = 'style', key = 'scale', label = 'Frame Scale (%)', default = 100, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the party lists and the target windows are drawn: the bars, the text and the buffs together.' },
        { kind = 'slider', section = 'style', key = 'nameSize', label = 'Name Text Size (%)', default = 110, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the names are written, apart from everything else.' },
        { kind = 'font', section = 'style', key = 'nameFont', label = 'Name Font', default = 'trebucbi.ttf',
          tooltip = 'The font the names, and the area of a member who is elsewhere, are written in: a font of Windows\' own, by its file in C:\\Windows\\Fonts. Theme Font is the one set in Winxi Theme.' },
        { kind = 'slider', section = 'style', key = 'buffSize', label = 'Buff Icon Size (%)', default = 120, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the buff and debuff icons beside your party are drawn, apart from everything else.' },
        { kind = 'slider', section = 'style', key = 'buffSpacing', label = 'Buff Spacing', default = 2, min = -5, max = 20,
          tooltip = 'How much room there is between one buff icon and the next. At 0 they touch; less than 0 overlaps them.' .. unitsNote },
        { kind = 'slider', section = 'style', key = 'buffDistance', label = 'Buff Distance', default = 4, min = -60, max = 200,
          tooltip = 'How far status icons start from the chosen window edge. Positive values move them farther outward; negative values overlap the window. Status Growth chooses left, right, or the side with more space.' .. unitsNote },
        { kind = 'slider', section = 'style', key = 'valueSize', label = 'Value Text Size (%)', default = 130, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the HP, MP and TP values are written, apart from everything else.' },
        { kind = 'font', section = 'style', key = 'valueFont', label = 'Value Font', default = 'ubuntu-bi.ttf',
          tooltip = 'The font the HP, MP and TP values (and a target\'s distance and HP percentage) are written in: a font of Windows\' own, by its file in C:\\Windows\\Fonts. Theme Font is the one set in Winxi Theme.' },
        { kind = 'check', section = 'style', key = 'showMp', label = 'Show MP Values', default = true,
          tooltip = 'Writes each member\'s MP beside their MP bar. Off leaves the bar alone.' },
        { kind = 'check', section = 'style', key = 'showTp', label = 'Show TP Values', default = true,
          tooltip = 'Writes each member\'s TP on their line. TP has no bar, so off leaves TP out altogether.' },
        { kind = 'check', section = 'style', key = 'tpFlash', label = 'Flash TP When Ready', default = true,
          tooltip = 'TP of 1000 or more pulses between the TP Ready Color and a lighter shade of it. Off, ready TP is simply that colour.' },
        { kind = 'color', section = 'style', key = 'tpColor', label = 'TP Ready Color', default = { 0x50 / 255, 0xB4 / 255, 0xFA / 255, 1 },
          tooltip = 'The colour TP of 1000 or more is written in, blue to begin with.' },
        { kind = 'check', section = 'style', key = 'zoneAbbr', label = 'Short Zone Names', default = true,
          tooltip = 'A member in another area has that area written where their bars would be, in the game\'s own short form for it\n(as its search list writes it). Off, the area\'s whole name, cut short where it does not fit.' },
    } },
    { name = 'Party', entries = {
        { kind = 'check', section = 'party', key = 'enabled', label = 'Enabled', default = true },
        { kind = 'gap' },
        { kind = 'check', section = 'party', key = 'hideWhenSolo', label = 'Hide When Solo', default = false },
        { kind = 'check', section = 'party', key = 'showInvites', label = 'Show Invites', default = true,
          tooltip = 'Marks an invitation that is waiting for your answer with the game\'s invitation icon beside your party\'s window, for a party or an alliance invite alike.\nWith Hide When Solo on, the window shows while an invitation is waiting.' },
        { kind = 'check', section = 'party', key = 'showTreasure', label = 'Show Treasure Pool', default = true,
          tooltip = 'Shows the game\'s treasure chest icon beside your party\'s window while there is anything in the treasure pool. With an invite waiting too, it goes beside the invite\'s.' },
        { kind = 'choice', section = 'party', key = 'iconCorner', label = 'Icon Corner', default = 'TopRight', choices = notices.Corners,
          when = function(saved) return saved.party.showInvites[1] or saved.party.showTreasure[1] end,
          tooltip = 'The corner of your party\'s window the invite and treasure icons go beside: above a top corner, below a bottom one.' },
        { kind = 'offset', section = 'party', key = 'iconOffset', label = 'Icon Offset', default = { -5, 21 }, reach = 300,
          when = function(saved) return saved.party.showInvites[1] or saved.party.showTreasure[1] end,
          tooltip = 'Moves the invite and treasure icons from their corner: X to the right, Y down. Less than 0 moves them left or up.' .. unitsNote },
        { kind = 'check', section = 'party', key = 'sortByRole', label = 'Sort By Role', default = false,
          when = function() return false end, -- hide the control without changing saved behavior
          tooltip = 'Off lists members in the game\'s own party order.\nOn lists you first, then tanks (PLD, NIN, WAR, RUN), melee damage (MNK, SAM, DRK, DRG, THF, DNC, BLU, BST, PUP),\nranged damage (RNG), support (BRD, COR, GEO), mages (BLM, SMN, SCH) and healers (RDM, WHM).\nEach party of the alliance is sorted on its own.' },
        { kind = 'slider', section = 'party', key = 'allianceScale', label = 'Alliance Scale (%)', default = 80, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the alliance\'s other two parties are drawn, both alike, on top of the Scale in Style. Your own party is left as it is.' },
        { kind = 'gap' },
        -- kept in style, as they were when they were on the Style tab
        { kind = 'offset', section = 'style', key = 'hpOffset', label = 'HP Value Offset', default = { -6, 0 }, reach = valueReach,
          tooltip = 'Moves the HP value of your party, the alliance and pets from its usual place: X to the right, Y down. Less than 0 moves it left or up.' .. unitsNote },
        { kind = 'offset', section = 'style', key = 'mpOffset', label = 'MP Value Offset', default = { -2, 0 }, reach = valueReach,
          tooltip = 'Moves the MP value of your party, the alliance and pets from its usual place: X to the right, Y down. Less than 0 moves it left or up.' .. unitsNote },
        { kind = 'offset', section = 'style', key = 'tpOffset', label = 'TP Value Offset', default = { -3, -2 }, reach = valueReach,
          tooltip = 'Moves the TP value of your party and the alliance from its usual place: X to the right, Y down. Less than 0 moves it left or up.' .. unitsNote },
        { kind = 'place', section = 'party', key = 'pos1', label = 'Alliance 1 Position', default = { 2098, 1215 }, window = 'party1' },
        { kind = 'place', section = 'party', key = 'pos2', label = 'Alliance 2 Position', default = { 2098, 333 }, window = 'party2' },
        { kind = 'place', section = 'party', key = 'pos3', label = 'Alliance 3 Position', default = { 2098, 593 }, window = 'party3' },
    } },
    { name = 'Target', entries = {
        { kind = 'check', section = 'target', key = 'enabled', label = 'Enabled', default = true },
        { kind = 'check', section = 'target', key = 'showMain', label = 'Show Target', default = true },
        { kind = 'check', section = 'target', key = 'mainDebuffs', label = 'Target Debuffs', default = false },
        { kind = 'check', section = 'target', key = 'showSub', label = 'Show Sub-Target', default = false },
        { kind = 'check', section = 'target', key = 'subDebuffs', label = 'Sub-Target Debuffs', default = false },
        { kind = 'check', section = 'target', key = 'showTot', label = 'Show Target Of Target', default = false },
        { kind = 'check', section = 'target', key = 'totDebuffs', label = 'Target Of Target Debuffs', default = false },
        { kind = 'check', section = 'target', key = 'gameNameColors', label = 'Game Name Colors', default = false,
          tooltip = 'The name is written in the colour the game gives it over the head: an enemy yellow while unclaimed, red claimed by your party or alliance, purple by anyone else and orange once help is called for; a player white, or blue in your party or alliance; an NPC green; anything dead grey.' },
        { kind = 'check', section = 'target', key = 'monsterLetters', label = 'Monster Letters', default = true,
          tooltip = 'A monster\'s spawn letter after its name, in a small box in the name\'s colour, the same letter name writes over it:\nthe monsters of one name in an area lettered A, B, C and on by their places in the game\'s own list of the area, so every player sees the same.\nPast Z the letters start again at A. Where the game\'s list cannot be read, or differs from what the game shows, there are none.' },
        { kind = 'check', section = 'target', key = 'lockBrackets', label = 'Lock-On Brackets', default = true,
          tooltip = 'While you are locked on to your target, brackets stand at the left and right of the target window, as the game frames its own.' },
        { kind = 'color', section = 'target', key = 'bracketColor', label = 'Bracket Color', default = { 1, 1, 1, 1 },
          when = function(saved) return saved.target.lockBrackets[1] end,
          tooltip = 'The colour of the lock-on brackets, edged with the Text Outline of Winxi Theme.' },
        { kind = 'choice', section = 'target', key = 'debuffStyle', label = 'Debuff Style', default = 'icons', choices = debuffs.Styles,
          when = function(saved) return saved.target.enabled[1] and ((saved.target.showMain[1] and saved.target.mainDebuffs[1])
              or (saved.target.showSub[1] and saved.target.subDebuffs[1]) or (saved.target.showTot[1] and saved.target.totDebuffs[1])) end,
          tooltip = 'Letters: a letter under the window for each of the usual debuffs, lit while it is on.\nIcons: an icon beside the window for every status seen to take hold on the target, drawn as your party\'s buffs are:\nthe Buff Icon Size, Buff Spacing and Buff Distance of the Style tab, and Custom Icons of Winxi Theme.' },
        { kind = 'gap' },
        -- defaults as the target's figures were drawn when they followed the party's TP offset (-3, -2)
        { kind = 'offset', section = 'target', key = 'hpOffset', label = 'HP % Offset', default = { 0, -2 }, reach = valueReach,
          tooltip = 'Moves the target\'s HP percentage from its usual place: X to the right, Y down. Less than 0 moves it left or up.' .. unitsNote },
        { kind = 'offset', section = 'target', key = 'distanceOffset', label = 'Distance Offset', default = { -3, -2 }, reach = valueReach,
          tooltip = 'Moves the target\'s distance from its usual place: X to the right, Y down. Less than 0 moves it left or up.' .. unitsNote },
        { kind = 'place', section = 'target', key = 'mainPos', label = 'Target Position', default = { 2098, 865 }, window = 'main' },
        { kind = 'place', section = 'target', key = 'subPos', label = 'Sub-Target Position', default = { 34, 296 }, window = 'sub' },
        { kind = 'place', section = 'target', key = 'totPos', label = 'Target Of Target Position', default = { 34, 223 }, window = 'tot' },
    } },
    { name = 'Pets', entries = {
        { kind = 'check', section = 'pets', key = 'enabled', label = 'Enabled', default = true,
          tooltip = 'Lists the pets under your party, below a line.' },
        { kind = 'gap' },
        { kind = 'check', section = 'pets', key = 'showParty', label = 'Show Party Members\' Pets', default = true,
          tooltip = 'Lists the pets of the other members of your party under your own, with their owner\'s name.\nOnly their HP is shown: a pet\'s MP and TP are sent to its owner alone.' },
        { kind = 'check', section = 'pets', key = 'exactAutomaton', label = 'Exact HP And MP (Puppetmaster)', default = true,
          tooltip = 'Shows your automaton\'s HP and MP as numbers rather than percentages.\nOnly applies while you are a puppetmaster; other pets always show percentages.' },
    } },
}

-- Additional controls share the same default/validation/reset machinery.
local extra = {
    Style = {
        { kind = 'dropdown', key = 'barShadows', label = 'Bar Shadows', default = 'full', choices = {
            { key = 'off', label = 'Off' }, { key = 'simple', label = 'Simple' }, { key = 'full', label = 'Full' } } },
        { kind = 'slider', key = 'castRange', label = 'Near Range (m)', default = 2079, min = 100, max = 5000, displayDivisor = 100,
          tooltip = 'Approximate range indicator only; individual actions have different ranges.' },
        { kind = 'slider', key = 'targetRange', label = 'Far Range (m)', default = 50, min = 1, max = 100, format = '%d m' },
        { kind = 'slider', key = 'nearOpacity', label = 'Beyond Near Range Opacity (%)', default = 70, min = 0, max = 100 },
        { kind = 'slider', key = 'farOpacity', label = 'Beyond Far Range Opacity (%)', default = 45, min = 0, max = 100 },
        { kind = 'slider', key = 'lowHp', label = 'Low HP Warning (%)', default = 0, min = 0, max = 100,
          tooltip = 'Adds a ! before names at or below this HP percentage. Zero disables it.' },
        { kind = 'check', key = 'hoverDetails', label = 'Show Tooltips', default = false,
          when = function() return false end, -- drawn beside Clickthrough in Behavior; storage stays compatible
          tooltip = 'Hovering the windows shows full names, jobs and pet owners, and each buff and debuff with its estimated time left.' },
        { kind = 'check', key = 'showStatuses', label = 'Show Statuses', default = true,
          tooltip = 'The buff and debuff icons beside your party and alliance. Off, the settings for them are kept, greyed.\nA target\'s debuffs follow the Target tab.' },
        { kind = 'check', key = 'debuffsFirst', label = 'Debuffs First', default = false,
          tooltip = 'Debuffs are drawn nearest the frame, before every buff, in the Status Growth direction. Priority Effects order the debuffs among themselves, and the buffs.' },
        { kind = 'statuslist', key = 'priorityStatuses', label = 'Priority Effects', default = '', ordered = true,
          tooltip = 'Comma-separated numeric status IDs, in priority order. Hidden IDs take precedence.' },
        { kind = 'statuslist', key = 'hiddenStatuses', label = 'Hidden Effects', default = '', tooltip = 'Hidden effects take precedence over priority effects.' },
        { kind = 'slider', key = 'buffLimit', label = 'Maximum Status Icons', default = 16, min = 1, max = 32 },
        { kind = 'slider', key = 'buffRows', label = 'Status Rows', default = 1, min = 1, max = 2 },
        { kind = 'check', key = 'buffOverflow', label = 'Status Overflow Count', default = true },
        { kind = 'dropdown', key = 'buffDirection', label = 'Status Growth', default = 'left', choices = {
            { key = 'left', label = 'Left' }, { key = 'right', label = 'Right' }, { key = 'auto', label = 'Most Available Space' } } },
        { kind = 'check', key = 'buffFitScreen', label = 'Fit Status Icons To Screen', default = true },
    },
    Pets = {
        { kind = 'slider', key = 'reserve', label = 'Reserved Pet Rows', default = 2, min = 1, max = 6,
          when = function(saved) return saved.automaticPositioning[1] and saved.pets.enabled[1] and saved.pets.showParty[1] end,
          tooltip = 'Automatic positioning reserves at least this many rows, and expands for the actual pet count. Six keeps a stable full-party reservation.' },
        { kind = 'dropdown', key = 'nameFormat', label = 'Pet Names', default = 'ownerPet', choices = {
            { key = 'pet', label = 'Pet' }, { key = 'ownerPet', label = 'Owner: Pet' }, { key = 'petOwner', label = 'Pet (Owner)' } } },
    },
}
for _, tab in ipairs(options.Tabs) do
    for _, entry in ipairs(extra[tab.name] or {}) do
        entry.section = tab.name:lower()
        tab.entries[#tab.entries + 1] = entry
    end
end

-- Presentation order is separate from the setting definitions so regrouping never changes defaults.
local groups = {
    Style = {
        { 'Appearance', 'scale', 'barShadows' },
        { 'Names', 'nameFont', 'nameSize', 'zoneAbbr' },
        { 'Values', 'valueFont', 'valueSize', 'showMp', 'showTp' },
        { 'Status Display', 'showStatuses', 'buffSize', 'buffSpacing', 'buffDistance', 'buffLimit', 'buffRows', 'buffDirection', 'buffFitScreen', 'buffOverflow', statuses = true },
        { 'Status Filtering', 'debuffsFirst', 'priorityStatuses', 'hiddenStatuses', statuses = true },
        { 'Warnings', 'lowHp', 'tpFlash', 'tpColor' },
        { 'Advanced: Range Indicators', 'castRange', 'targetRange', 'nearOpacity', 'farOpacity', collapsed = true },
        { 'Advanced: Status IDs', collapsed = true, statuses = true },
        -- Retained in the schema for existing settings, presented in Behavior instead.
        { 'hoverDetails', hiddenGroup = true },
    },
    Party = {
        { 'Visibility', 'enabled', 'hideWhenSolo', 'sortByRole' },
        { 'Notifications', 'showInvites', 'showTreasure', 'iconCorner', 'iconOffset' },
        { 'Alliance', 'allianceScale' },
        { 'Positioning', 'pos1', 'pos2', 'pos3' },
        { 'Advanced: Value Positioning', 'hpOffset', 'mpOffset', 'tpOffset', collapsed = true },
    },
    Target = {
        { 'Frames', 'enabled', 'showMain', 'mainDebuffs', 'showSub', 'subDebuffs', 'showTot', 'totDebuffs', 'debuffStyle' },
        { 'Names', 'gameNameColors', 'monsterLetters' },
        { 'Lock-On', 'lockBrackets', 'bracketColor' },
        { 'Positioning', 'mainPos', 'subPos', 'totPos' },
        { 'Advanced: Value Positioning', 'hpOffset', 'distanceOffset', collapsed = true },
    },
    Pets = {
        { 'Visibility', 'enabled', 'showParty' },
        { 'Automaton', 'exactAutomaton' },
        { 'Layout', 'reserve', 'nameFormat' },
    },
}
for _, tab in ipairs(options.Tabs) do
    local entries, byKey = {}, {}
    for _, entry in ipairs(tab.entries) do
        if entry.key then byKey[entry.key] = entry end
    end
    for _, group in ipairs(groups[tab.name]) do
        if not group.hiddenGroup then
            entries[#entries + 1] = { kind = 'header', label = group[1], defaultCollapsed = group.collapsed, statuses = group.statuses }
        end
        for index = group.hiddenGroup and 1 or 2, #group do
            local key = group[index]
            local entry = assert(byKey[key], 'Unknown setting: ' .. key)
            if tab.name == 'Target' and (key == 'showMain' or key == 'showSub' or key == 'showTot'
                or key == 'mainDebuffs' or key == 'subDebuffs' or key == 'totDebuffs') then entry.targetRow = true end
            -- greyed while Show Statuses is off; the toggle itself never is
            entry.statuses = group.statuses and key ~= 'showStatuses' or nil
            entries[#entries + 1] = entry
            byKey[key] = nil
        end
    end
    assert(next(byKey) == nil, 'Ungrouped settings in ' .. tab.name)
    tab.entries = entries
end

-- What an entry's setting starts as, made afresh each time: nothing for an entry with no setting
local function Start(entry)
    if entry.kind == 'text' or entry.kind == 'statuslist' then
        return T{ entry.default }
    elseif entry.kind == 'check' or entry.kind == 'slider' then
        return T{ entry.default }
    elseif entry.kind == 'offset' or entry.kind == 'place' then
        return T{ entry.default[1], entry.default[2] }
    elseif entry.kind == 'color' then
        return T{ entry.default[1], entry.default[2], entry.default[3], entry.default[4] }
    elseif entry.kind == 'choice' or entry.kind == 'dropdown' or entry.kind == 'font' then
        return entry.default
    end
    return nil
end

-- Whether a value is of the kind an entry keeps
local function Fits(entry, value)
    if entry.kind == 'text' or entry.kind == 'statuslist' then
        return type(value) == 'table' and type(value[1]) == 'string'
    elseif entry.kind == 'check' then
        return type(value) == 'table' and type(value[1]) == 'boolean'
    elseif entry.kind == 'slider' then
        return type(value) == 'table' and type(value[1]) == 'number'
    elseif entry.kind == 'offset' or entry.kind == 'place' then
        return type(value) == 'table' and type(value[1]) == 'number' and type(value[2]) == 'number'
    elseif entry.kind == 'color' then
        return type(value) == 'table' and type(value[1]) == 'number' and type(value[2]) == 'number'
            and type(value[3]) == 'number' and type(value[4]) == 'number'
    elseif entry.kind == 'choice' or entry.kind == 'dropdown' then
        return type(value) == 'string'
    elseif entry.kind == 'font' then
        -- a file's name alone, not a path, or '' for the theme's
        return type(value) == 'string' and (value == '' or (value:lower():match('%.ttf$') ~= nil and not value:find('[\\/]')))
    end
    return true
end

local sections = { 'style', 'party', 'target', 'pets' }

-- Gives settings whatever the entries call for that they lack, or have as the wrong kind of thing
local function CompleteEntries(saved)
    for _, section in ipairs(sections) do
        if type(saved[section]) ~= 'table' then
            saved[section] = T{ }
        end
    end
    for _, tab in ipairs(options.Tabs) do
        for _, entry in ipairs(tab.entries) do
            if entry.key ~= nil and not Fits(entry, saved[entry.section][entry.key]) then
                saved[entry.section][entry.key] = Start(entry)
            end
            if entry.kind == 'slider' then
                local value = saved[entry.section][entry.key]
                if value[1] ~= value[1] then value[1] = entry.default end
                value[1] = math.max(entry.min, math.min(entry.max, value[1]))
            elseif entry.kind == 'choice' or entry.kind == 'dropdown' then
                local valid = false
                for _, choice in ipairs(entry.choices) do
                    if saved[entry.section][entry.key] == choice.key then valid = true end
                end
                if not valid then saved[entry.section][entry.key] = Start(entry) end
            end
        end
    end
end

-- What settings start as is how the addon's author has it set up, places on screen and all: those
-- suit a screen 2560 by 1440, and want moving on any other.
--
-- Ashita gives saved settings whatever the defaults have that they lack, each time they are loaded.
-- So what may be taken out again is not among the defaults, or it would come back: which window is
-- held against which, and the corner the party's window is held by. Those are given once, to
-- settings that are new (StartNew). Nor is the version: settings without one are new, or old.
function options.Defaults()
    local defaults = T{
        showConfig = T{ false },
        -- for winxi: when the windows get out of the way, whether the mouse goes through them, the
        -- theme (the shared one, or this addon's own), and fading while idle and which groups of
        -- windows it applies to
        hide = T{ DuringEvent = true, UnderChat = true, UnderMap = true, WhileLoading = true, WithInterface = true },
        clickThrough = T{ true },
        automaticPositioning = T{ false },
        nativeHook = T{ false }, -- uihook used at all; Party and Target below choose what it draws
        nativeParty = T{ false }, -- experimental partyhook rendering; never enabled by migration
        nativeTarget = T{ false }, -- independent opt-in
        nativePositioning = T{ false }, -- parked/hidden; forcibly disabled during settings completion
        nativeBehavior = T{ false }, -- native draw visibility/order, without addon idle/presence fading
        nativeAlliance2 = T{ true },
        nativeAlliance3 = T{ true },
        useSharedTheme = true,
        theme = T{ }, -- filled from the shared theme if the addon leaves it (winxi.theme's Configure)
        fade = T{
            Enabled = true, Delay = 8, Duration = 1, Opacity = 0, Transition = 0.08,
            Combat = true, MissingHp = true, Moving = true, Party = true, Resting = true, Target = true,
            windows = T{ party = T{ true }, target = T{ true } },
        },
    }
    CompleteEntries(defaults)
    return defaults
end

-- What new settings are given once: the party's window held by its bottom left corner, so that it
-- grows upward from there, the target's window above it, and the alliance's second party over its third
local function StartNew(saved)
    saved.party.corner1 = T{ 2098, 1278 }
    saved.links = T{
        T{ child = 'xiframes.tgt.sub', parent = 'xiframes.tgt.tot', side = 'below' },
        T{ child = 'xiframes.tgt.main', parent = 'xiframes.us.1', side = 'above' },
        T{ child = 'xiframes.us.3', parent = 'xiframes.us.2', side = 'below' },
    }
end

-- Settings from before they were set out by section had everything under tools (us, tgt and pet, from
-- the addon's days as three of xitools' tools) and globals. What was set there is carried over, and
-- the old tables dropped.
local styleKeys = {
    scale = 'xivScale', nameSize = 'xivNameSize', valueSize = 'xivValueSize', buffSize = 'xivBuffSize',
    buffSpacing = 'xivBuffSpacing', buffDistance = 'xivBuffDistance', hpOffset = 'xivHpOffset', mpOffset = 'xivMpOffset',
    tpOffset = 'xivTpOffset', bookends = 'xivBookends', showMp = 'xivShowMp', showTp = 'xivShowTp',
    tpFlash = 'xivTpFlash',
}
local partyKeys = {
    enabled = 'isEnabled', hideWhenSolo = 'hideWhenSolo', sortByRole = 'sortByRole', showInvites = 'showInvite',
    showTreasure = 'showTreasure', iconCorner = 'inviteCorner', iconOffset = 'inviteOffset',
}
local targetKeys = { enabled = 'isEnabled', showMain = 'showMain', showSub = 'showSub', showTot = 'showTot' }
local petKeys = { enabled = 'isEnabled', showParty = 'showParty', exactAutomaton = 'exactAutomaton' }

local function Carry(into, from, keys)
    if type(from) ~= 'table' then
        return
    end
    for new, old in pairs(keys) do
        if from[old] ~= nil then
            into[new] = from[old]
        end
    end
end

local function FromTools(saved)
    local tools, globals = saved.tools, saved.globals
    if type(tools) == 'table' then
        local us, tgt = tools.us, tools.tgt
        Carry(saved.style, us, styleKeys)
        Carry(saved.party, us, partyKeys)
        if type(us) == 'table' then
            for list = 1, 3 do
                local old = us['alliance' .. list]
                if type(old) == 'table' then
                    saved.party['pos' .. list] = old.pos
                    if list == 1 then
                        saved.party.corner1 = old.corner
                    end
                end
            end
        end
        Carry(saved.target, tgt, targetKeys)
        if type(tgt) == 'table' then
            for key, old in pairs({ main = tgt.mainWindow, sub = tgt.subWindow, tot = tgt.totWindow }) do
                if type(old) == 'table' then
                    saved.target[key .. 'Pos'] = old.pos
                    saved.target[key .. 'Debuffs'] = old.showStatus
                end
            end
        end
        Carry(saved.pets, tools.pet, petKeys)
    end

    if type(globals) == 'table' then
        saved.hide = globals.hide
        saved.clickThrough = globals.isClickThru
        saved.useSharedTheme = globals.useSharedTheme
        saved.theme = globals.theme
        saved.links = globals.links
        if type(globals.fade) == 'table' then
            -- which tools fade was by the tool's name; the windows that fade are by their group's
            local faded = globals.fade.tools
            globals.fade.tools = nil
            saved.fade = globals.fade
            if type(faded) == 'table' then
                saved.fade.windows = T{ party = faded.us, target = faded.tgt }
            end
        end
    end

    saved.tools, saved.globals, saved.importedFromXilite = nil, nil, nil
end

-- The addon was called xiframes, and kept each character's settings under that name. Once for each
-- character, when it is known, what xiframes kept is taken as the settings, and brought up to date as
-- any other; the flag says it has been looked for, whether or not anything was found.
local function FromXiframes(saved)
    if saved.fromXiframes or not settings.logged_in then
        return
    end
    local old = legacy.ReadSettings('xiframes')
    if old ~= nil then
        for key, value in pairs(old) do
            saved[key] = value
        end
    end
    saved.fromXiframes = true
end

-- The styles that were the addon's own before they were winxi's theme's. What was set is carried into
-- the addon's own theme, and what was set other than as the theme starts is kept aside as carriedTheme,
-- for party.lua to hand to the shared theme if the addon follows it.
local themeKeys = { borderStyle = 'BorderStyle', barTexture = 'BarTexture', bookends = 'Bookends', bookendStyle = 'BookendStyle', ffxivIcons = 'StatusIcons' }

local function ToTheme(saved)
    for old, new in pairs(themeKeys) do
        local value = saved.style[old]
        if type(value) == 'table' then
            value = value[1]
        end
        saved.style[old] = nil
        if value ~= nil then
            saved.theme[new] = value
            if value ~= theme.Defaults[new] then
                saved.carriedTheme = saved.carriedTheme or T{ }
                saved.carriedTheme[new] = value
            end
        end
    end
end

function options.Complete(saved)
    FromXiframes(saved)
    saved.profiles = nil -- the profiles of earlier versions, gone with them
    for _, section in ipairs(sections) do
        if type(saved[section]) ~= 'table' then
            saved[section] = T{ }
        end
    end
    if saved.tools ~= nil or saved.globals ~= nil then
        FromTools(saved)
    elseif saved.version == nil then
        StartNew(saved)
    end
    saved.version = options.Version

    CompleteEntries(saved)
    -- A target's HP percentage and distance went with the party's TP offset before they had offsets of
    -- their own: they take it once, so they stay where they were. ownOffsets marks it, kept out of the
    -- defaults so that Ashita does not give it to settings that have not had it done.
    if saved.target.ownOffsets == nil then
        local tp = saved.style.tpOffset
        saved.target.hpOffset = T{ 0, tp[2] }
        saved.target.distanceOffset = T{ tp[1], tp[2] }
        saved.target.ownOffsets = true
    end
    if type(saved.showConfig) ~= 'table' then saved.showConfig = T{ false } end
    if type(saved.clickThrough) ~= 'table' then saved.clickThrough = T{ false } end
    if type(saved.nativeParty) ~= 'table' or type(saved.nativeParty[1]) ~= 'boolean' then
        saved.nativeParty = T{ false }
    end
    if type(saved.nativeTarget) ~= 'table' or type(saved.nativeTarget[1]) ~= 'boolean' then
        saved.nativeTarget = T{ false }
    end
    -- Settings from before the toggle keep their hooked windows hooked
    if type(saved.nativeHook) ~= 'table' or type(saved.nativeHook[1]) ~= 'boolean' then
        saved.nativeHook = T{ saved.nativeParty[1] or saved.nativeTarget[1] }
    end
    for key, default in pairs({ nativePositioning=false, nativeBehavior=false, nativeAlliance2=true, nativeAlliance3=true }) do
        if type(saved[key]) ~= 'table' or type(saved[key][1]) ~= 'boolean' then saved[key]=T{ default } end
    end
    if type(saved.style) == 'table' then saved.style.tpReady = nil end -- TP is ready at 1000, as in the game
    saved.nativePositioning[1]=false -- paused for testing, including previously enabled settings
    if type(saved.automaticPositioning) ~= 'table' or type(saved.automaticPositioning[1]) ~= 'boolean' then
        saved.automaticPositioning = T{ false }
    end
    if saved.useSharedTheme == nil then saved.useSharedTheme = true end
    for _, key in ipairs({ 'hide', 'theme', 'links', 'fade' }) do
        if type(saved[key]) ~= 'table' then
            saved[key] = T{ }
        end
    end
    ToTheme(saved)
    if type(saved.fade.windows) ~= 'table' then
        saved.fade.windows = T{ }
    end
    return saved
end

-- How the frames are to be drawn, from the settings and winxi's theme: one table, filled in afresh each time it is
-- asked for, to be used at once. Whoever asks may set what is their own on it: nameChars and trimLast
-- are left out here, and whether TP is shown may be overruled.
local style = { hpOffset = { 0, 0 }, mpOffset = { 0, 0 }, tpOffset = { 0, 0 }, targetHpOffset = { 0, 0 }, distanceOffset = { 0, 0 } }

local function Pixels(into, offset)
    into[1], into[2] = (tonumber(offset[1]) or 0) * options.Unit, (tonumber(offset[2]) or 0) * options.Unit
end

function options.Style(saved)
    local kept = saved.style
    style.scale, style.nameSize, style.valueSize, style.buffSize = kept.scale[1], kept.nameSize[1], kept.valueSize[1], kept.buffSize[1]
    style.buffSpacing, style.buffDistance = kept.buffSpacing[1] * options.Unit, kept.buffDistance[1] * options.Unit
    local look = theme.Get()
    style.ffxivIcons, style.bookends, style.bookendOpacity = look.StatusIcons, look.Bookends, look.BookendOpacity
    style.barTexture, style.bookendStyle, style.borderStyle = look.BarTexture, look.BookendStyle, look.BorderStyle
    style.barFrame, style.barFrameOpacity = look.BarFrame, look.BarFrameOpacity
    style.barGlow, style.barBackdrop = look.BarGlow, look.BarBackdrop and look.BarBackdropColor or nil
    Pixels(style.hpOffset, kept.hpOffset)
    Pixels(style.mpOffset, kept.mpOffset)
    Pixels(style.tpOffset, kept.tpOffset)
    Pixels(style.targetHpOffset, saved.target.hpOffset)
    Pixels(style.distanceOffset, saved.target.distanceOffset)
    style.tpFlash, style.tpColor = kept.tpFlash[1], kept.tpColor
    style.bracketColor = saved.target.bracketColor
    style.zoneAbbr = kept.zoneAbbr[1]
    style.showMp, style.showTp = kept.showMp[1], kept.showTp[1]
    style.nameFont, style.valueFont = kept.nameFont, kept.valueFont
    style.barShadows = kept.barShadows
    style.castRange, style.targetRange = kept.castRange[1] / 100, kept.targetRange[1]
    style.nearOpacity, style.farOpacity = kept.nearOpacity[1] / 100, kept.farOpacity[1] / 100
    style.lowHp = kept.lowHp[1]
    style.hoverDetails = kept.hoverDetails[1]
    style.debuffsFirst = kept.debuffsFirst[1]
    style.priorityStatuses, style.hiddenStatuses = kept.priorityStatuses[1], kept.hiddenStatuses[1]
    style.buffLimit, style.buffRows = kept.buffLimit[1], kept.buffRows[1]
    style.buffOverflow, style.buffFitScreen = kept.buffOverflow[1], kept.buffFitScreen[1]
    style.buffDirection = kept.buffDirection
    style.nameChars, style.trimLast, style.showJobs = nil, nil, false
    return style
end

return options
