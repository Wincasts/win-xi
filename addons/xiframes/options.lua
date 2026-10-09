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
-- beside those what the addon keeps for winxi (the theme, the rules for hiding, fading, links).
require('common')
local notices = require('notices')

local options = { }

options.Version = 2

local unitsNote = '\nThe number is in the frames\' own units, so it keeps its proportion as the scale changes.'

-- The kinds of entry:
--   check     a checkbox                        default true or false
--   slider    a whole number between two        default, min, max, format
--   offset    two sliders, across and down      reach: how far either way
--   choice    one of several, as radio buttons  default, choices: { key, label }, two to a line
--   place     where a window is, as two numbers default { x, y }, window: its key in windows.List
--   gap       a little room between two families of settings
-- when, if given, says whether the entry is shown, from the settings.
options.Tabs = {
    { name = 'Style', entries = {
        { kind = 'slider', section = 'style', key = 'scale', label = 'Scale (%)', default = 100, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the party lists and the target windows are drawn: the bars, the text and the buffs together.' },
        { kind = 'slider', section = 'style', key = 'nameSize', label = 'Name Text Size (%)', default = 100, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the names are written, apart from everything else.' },
        { kind = 'slider', section = 'style', key = 'buffSize', label = 'Buff Icon Size (%)', default = 100, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the buff and debuff icons beside your party are drawn, apart from everything else.' },
        { kind = 'slider', section = 'style', key = 'buffSpacing', label = 'Buff Spacing', default = 0, min = -5, max = 20,
          tooltip = 'How much room there is between one buff icon and the next. At 0 they touch; less than 0 overlaps them.' .. unitsNote },
        { kind = 'slider', section = 'style', key = 'buffDistance', label = 'Buff Distance', default = 0, min = -60, max = 200,
          tooltip = 'How far from your party\'s window the buff icons start. 0 is just clear of its left edge; more moves them further left, and less than 0 brings them right, over the window.' .. unitsNote },
        { kind = 'slider', section = 'style', key = 'valueSize', label = 'Value Text Size (%)', default = 100, min = 50, max = 200, format = '%d%%',
          tooltip = 'How big the HP, MP and TP values are written, apart from everything else.' },
        { kind = 'offset', section = 'style', key = 'hpOffset', label = 'HP Value Offset', reach = 40,
          tooltip = 'Moves the HP value from its usual place: X to the right, Y down. Less than 0 moves it left or up.' .. unitsNote },
        { kind = 'offset', section = 'style', key = 'mpOffset', label = 'MP Value Offset', reach = 40,
          tooltip = 'Moves the MP value from its usual place: X to the right, Y down. Less than 0 moves it left or up.' .. unitsNote },
        { kind = 'offset', section = 'style', key = 'tpOffset', label = 'TP Value Offset', reach = 40,
          tooltip = 'Moves the TP value from its usual place: X to the right, Y down. Less than 0 moves it left or up.\nA target\'s distance and HP percentage go up and down with it.' .. unitsNote },
        { kind = 'check', section = 'style', key = 'outline', label = 'Outline Text', default = true,
          tooltip = 'Gives the names and the HP, MP and TP values a dark edge, so they can be read where they are written over a bar.' },
        { kind = 'check', section = 'style', key = 'bookends', label = 'Bar Bookends', default = true,
          tooltip = 'Puts a small silver cap at each end of the HP and MP bars, like the ones on the game\'s own party list.' },
        { kind = 'check', section = 'style', key = 'showMp', label = 'Show MP Values', default = true,
          tooltip = 'Writes each member\'s MP beside their MP bar. Off leaves the bar alone.' },
        { kind = 'check', section = 'style', key = 'showTp', label = 'Show TP Values', default = true,
          tooltip = 'Writes each member\'s TP on their line. TP has no bar, so off leaves TP out altogether.' },
        { kind = 'check', section = 'style', key = 'tpFlash', label = 'Flash TP When Ready', default = true,
          tooltip = 'A TP value of 1000 or over pulses between a light blue and a deeper one. Off, it is simply blue.' },
    } },
    { name = 'Party', entries = {
        { kind = 'check', section = 'party', key = 'enabled', label = 'Enabled', default = true },
        { kind = 'gap' },
        { kind = 'check', section = 'party', key = 'hideWhenSolo', label = 'Hide When Solo', default = false },
        { kind = 'check', section = 'party', key = 'showInvites', label = 'Show Invites', default = true,
          tooltip = 'Marks an invitation that is waiting for your answer with an envelope beside your party\'s window: yellow for a party invite, red for an alliance invite.\nWith Hide When Solo on, the window shows while an invitation is waiting.' },
        { kind = 'check', section = 'party', key = 'showTreasure', label = 'Show Treasure Pool', default = true,
          tooltip = 'Shows a chest beside your party\'s window while there is anything in the treasure pool. With an invite waiting too, it goes beside the envelope.' },
        { kind = 'choice', section = 'party', key = 'iconCorner', label = 'Icon Corner', default = 'TopRight', choices = notices.Corners,
          when = function(saved) return saved.party.showInvites[1] or saved.party.showTreasure[1] end,
          tooltip = 'The corner of your party\'s window the invite and treasure icons go beside: above a top corner, below a bottom one.' },
        { kind = 'offset', section = 'party', key = 'iconOffset', label = 'Icon Offset', reach = 300,
          when = function(saved) return saved.party.showInvites[1] or saved.party.showTreasure[1] end,
          tooltip = 'Moves the invite and treasure icons from their corner: X to the right, Y down. Less than 0 moves them left or up.' .. unitsNote },
        { kind = 'check', section = 'party', key = 'sortByRole', label = 'Sort By Role', default = false,
          tooltip = 'Off lists members in the game\'s own party order.\nOn lists you first, then tanks (PLD, NIN, WAR, RUN), melee damage (MNK, SAM, DRK, DRG, THF, DNC, BLU, BST, PUP),\nranged damage (RNG), support (BRD, COR, GEO), mages (BLM, SMN, SCH) and healers (RDM, WHM).\nEach party of the alliance is sorted on its own.' },
        { kind = 'gap' },
        { kind = 'place', section = 'party', key = 'pos1', label = 'Alliance 1 Position', default = { 392, 628 }, window = 'party1' },
        { kind = 'place', section = 'party', key = 'pos2', label = 'Alliance 2 Position', default = { 107, 628 }, window = 'party2' },
        { kind = 'place', section = 'party', key = 'pos3', label = 'Alliance 3 Position', default = { 0, 628 }, window = 'party3' },
    } },
    { name = 'Target', entries = {
        { kind = 'check', section = 'target', key = 'enabled', label = 'Enabled', default = true },
        { kind = 'check', section = 'target', key = 'showMain', label = 'Show Target', default = true },
        { kind = 'check', section = 'target', key = 'mainDebuffs', label = 'Target Debuffs', default = false },
        { kind = 'check', section = 'target', key = 'showSub', label = 'Show Sub-Target', default = false },
        { kind = 'check', section = 'target', key = 'subDebuffs', label = 'Sub-Target Debuffs', default = false },
        { kind = 'check', section = 'target', key = 'showTot', label = 'Show Target Of Target', default = false },
        { kind = 'check', section = 'target', key = 'totDebuffs', label = 'Target Of Target Debuffs', default = false },
        { kind = 'gap' },
        { kind = 'place', section = 'target', key = 'mainPos', label = 'Target Position', default = { 100, 100 }, window = 'main' },
        { kind = 'place', section = 'target', key = 'subPos', label = 'Sub-Target Position', default = { 100, 200 }, window = 'sub' },
        { kind = 'place', section = 'target', key = 'totPos', label = 'Target Of Target Position', default = { 386, 100 }, window = 'tot' },
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

-- What an entry's setting starts as, made afresh each time: nothing for an entry with no setting
local function Start(entry)
    if entry.kind == 'check' or entry.kind == 'slider' then
        return T{ entry.default }
    elseif entry.kind == 'offset' then
        return T{ 0, 0 }
    elseif entry.kind == 'place' then
        return T{ entry.default[1], entry.default[2] }
    elseif entry.kind == 'choice' then
        return entry.default
    end
    return nil
end

-- Whether a value is of the kind an entry keeps
local function Fits(entry, value)
    if entry.kind == 'check' then
        return type(value) == 'table' and type(value[1]) == 'boolean'
    elseif entry.kind == 'slider' then
        return type(value) == 'table' and type(value[1]) == 'number'
    elseif entry.kind == 'offset' or entry.kind == 'place' then
        return type(value) == 'table' and type(value[1]) == 'number' and type(value[2]) == 'number'
    elseif entry.kind == 'choice' then
        return type(value) == 'string'
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
        end
    end
end

function options.Defaults()
    local defaults = T{
        version = options.Version,
        showConfig = T{ false },
        -- for winxi: when the windows get out of the way, whether the mouse goes through them, the
        -- theme (the shared one, or this addon's own), fading while idle and which groups of windows
        -- it applies to, and which window is held against which
        hide = T{ },
        clickThrough = T{ false },
        useSharedTheme = true,
        theme = T{ },
        fade = T{ windows = T{ } },
        links = T{ },
    }
    CompleteEntries(defaults)
    return defaults
end

-- Settings from before they were set out by section had everything under tools (us, tgt and pet, from
-- the addon's days as three of xitools' tools) and globals. What was set there is carried over, and
-- the old tables dropped.
local styleKeys = {
    scale = 'xivScale', nameSize = 'xivNameSize', valueSize = 'xivValueSize', buffSize = 'xivBuffSize',
    buffSpacing = 'xivBuffSpacing', buffDistance = 'xivBuffDistance', hpOffset = 'xivHpOffset', mpOffset = 'xivMpOffset',
    tpOffset = 'xivTpOffset', outline = 'xivOutline', bookends = 'xivBookends', showMp = 'xivShowMp', showTp = 'xivShowTp',
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

function options.Complete(saved)
    for _, section in ipairs(sections) do
        if type(saved[section]) ~= 'table' then
            saved[section] = T{ }
        end
    end
    if saved.tools ~= nil or saved.globals ~= nil then
        FromTools(saved)
    end
    saved.version = options.Version

    CompleteEntries(saved)
    if type(saved.showConfig) ~= 'table' then saved.showConfig = T{ false } end
    if type(saved.clickThrough) ~= 'table' then saved.clickThrough = T{ false } end
    if saved.useSharedTheme == nil then saved.useSharedTheme = true end
    for _, key in ipairs({ 'hide', 'theme', 'links', 'fade' }) do
        if type(saved[key]) ~= 'table' then
            saved[key] = T{ }
        end
    end
    if type(saved.fade.windows) ~= 'table' then
        saved.fade.windows = T{ }
    end
    return saved
end

-- How the frames are to be drawn, from the settings: one table, filled in afresh each time it is
-- asked for, to be used at once. Whoever asks may set what is their own on it: nameChars and trimLast
-- are left out here, and whether TP is shown may be overruled.
local style = { }

function options.Style(saved)
    local kept = saved.style
    style.scale, style.nameSize, style.valueSize, style.buffSize = kept.scale[1], kept.nameSize[1], kept.valueSize[1], kept.buffSize[1]
    style.buffSpacing, style.buffDistance = kept.buffSpacing[1], kept.buffDistance[1]
    style.hpOffset, style.mpOffset, style.tpOffset = kept.hpOffset, kept.mpOffset, kept.tpOffset
    style.outline, style.bookends, style.tpFlash = kept.outline[1], kept.bookends[1], kept.tpFlash[1]
    style.showMp, style.showTp = kept.showMp[1], kept.showTp[1]
    style.nameChars, style.trimLast = nil, nil
    return style
end

return options
