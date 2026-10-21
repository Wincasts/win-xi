local imgui = require('imgui')
local window = require('winxi.window')
local packets = require('winxi.packets')
local game, options = RECAST_GAME, H.options()
local count = 0
local function check(ok, message)
    assert(ok, message); count = count + 1
end
local drawn, active, colors, countdownColor = {}, false, {}, nil
local countdownEdges, cursorX, paddingRows = {}, nil, {}
local Style = require('winxi.style')
imgui.CalcTextSize = function(text) return #text * 7, 14 end
imgui.SetCursorPosX = function(x) if active then cursorX = x end end
local realFull, recastStyle = window.Full, nil
window.Full = function(name, open, flags, draw, style)
    if name ~= 'Cooldowns' then return realFull(name, open, flags, draw, style) end
    recastStyle = style
    Style.PushFull(style)
    active = true; draw(); active = false
    Style.Pop()
end
imgui.Text = function(text)
    if active then
        drawn[#drawn + 1] = text; colors[text] = countdownColor or 'theme'
        if cursorX then countdownEdges[#countdownEdges + 1] = cursorX + imgui.CalcTextSize(text); cursorX = nil end
    end
end
imgui.TextColored = function(color, text)
    if active then drawn[#drawn + 1] = text; colors[text] = color end
end
local realPushColor, realPopColor = imgui.PushStyleColor, imgui.PopStyleColor
imgui.PushStyleColor = function(index, color)
    if active and index == ImGuiCol_Text then countdownColor = color end
    realPushColor(index, color)
end
imgui.PopStyleColor = function(...)
    if active then countdownColor = nil end
    realPopColor(...)
end
imgui.Separator = function() if active then drawn[#drawn + 1] = '<separator>' end end
imgui.Dummy = function(size)
    if active then paddingRows[#paddingRows + 1] = size[2] end
end
local function shown()
    drawn, colors, countdownEdges, paddingRows = {}, {}, {}, {}; cursorX = nil
    H.wait(0.11) -- allow the throttled player snapshot to refresh after fixture changes
    H.frames(1); return table.concat(drawn, '|')
end
local action
packets.inbound.action.parse = function() return action end
local function did(actor, id)
    action = { actor_id = actor, category = 11, param = id, targets = {} }
    H.packetData(packets.inbound.action.id, '')
end
local function parts(head, frame, attachments)
    local bytes = {}
    for i = 1, 0x7A do bytes[i] = 0 end
    bytes[5], bytes[9], bytes[10] = 18, head, frame
    for i, id in ipairs(attachments or {}) do bytes[10 + i] = id end
    H.packetData(0x044, string.char(unpack(bytes)))
end
check(COOLDOWNS_DEFAULTS_CHECKED, 'fresh-install defaults satisfy native settings loader contract')
check(addon.name == 'cooldowns' and options.windowName == 'Cooldowns', 'folder, registered name and window consistently use cooldowns')
check(options.legacySettingsChecked, 'legacy settings migration marked complete')
check(not H.command('/imrecast') and not H.command('/recast'), 'old commands are not registered aliases')
check(options.showPetCooldowns, 'pet cooldowns enabled by default')
check(options.sortByTime == false and options.sortDescending == false, 'time sorting defaults off, ascending selected')
check(options.warningSeconds == 20 and options.criticalSeconds == 5, 'default color thresholds retain existing behavior')
check(options.useSharedTheme == nil and options.theme == nil, 'no local theme overrides')
options.abilityNameColor, options.spellNameColor = { 0.2, 0.7, 0.3, 1 }, { 0.4, 0.5, 0.9, 1 }
shown()
check(recastStyle and recastStyle.title == 'Cooldowns' and recastStyle.kind == nil,
    'cooldowns frame uses winxi Full game-window title styling')
check(colors.Maneuver == options.abilityNameColor and colors['Cure IV'] == options.spellNameColor,
    'ability and spell names use distinct configured colors')
check(colors['10s'][1] == 1 and colors['10s'][2] == 1 and colors['10s'][3] == 0,
    'yellow countdown unchanged')
check(colors['5s'][1] == 0.95 and colors['5s'][2] == 0.20, 'red countdown unchanged')
parts(3, 0x21, { 1, 194 })
check(options.petAutomaton.frame == 0x21 and #options.petAutomaton.attachments == 2, 'parts cached from packet')
check(not shown():find('Bash', 1, true), 'unobserved cooldowns omitted')
-- Native Ashita bit parsing needs data_raw. The generic harness uses the same string for
-- all three packet fields, so explicitly distinguish them here to catch buffer mix-ups.
local raw, received, parsed = {}, nil, 0
local normalParse = packets.inbound.action.parse
packets.inbound.action.parse = function(buffer)
    received, parsed = buffer, parsed + 1
    return nil
end
local petRecasts = require('winxi.automaton.recasts')
petRecasts.Packet({ id = packets.inbound.action.id, data_raw = raw,
    data = 'original string', data_modified = 'modified string' }, options.petAutomaton)
check(received == raw and parsed == 1, 'action parser receives raw buffer, never packet strings')
petRecasts.Packet({ id = packets.inbound.action.id, data = 'no raw buffer' }, options.petAutomaton)
check(parsed == 1, 'missing raw action buffer safely skipped')
packets.inbound.action.parse = normalParse
did(99, 1944)
check(not shown():find('Bash', 1, true), 'other actors ignored')
did(2, 1944); did(2, 1945)
local recasts = require('winxi.automaton.recasts')
local before = recasts.Timers(options.petAutomaton)[1].timer
parts(3, 0x21, { 1, 194, 107 })
game.buffs = { 303, 303 }
check(recasts.Timers(options.petAutomaton)[1].timer == before - 600, 'Barrier Module and Earth maneuvers shorten Bash')
shown()
check(colors.Bash == require('winxi.automaton.colors')[4], 'attachment-linked Bash uses Puppet Earth color')
game.buffs = {}
parts(3, 0x21, { 1, 194 })
local text = shown()
check(text:find('Maneuver', 1, true) < text:find('Cure IV', 1, true), 'normal recasts remain first')
check(text:find('Cure IV', 1, true) < text:find('<separator>', 1, true)
    and text:find('<separator>', 1, true) < text:find('Bash', 1, true), 'themed separator divides player and pet recasts')
check(#paddingRows == 2 and paddingRows[1] == Style.Padding() and paddingRows[2] == Style.Padding(),
    'separator has shared window padding above and below')
for _, edge in ipairs(countdownEdges) do check(edge == 205, 'player and pet countdowns share the content right edge') end
check(not text:find(' - ', 1, true), 'no dash between names and countdowns')
check(text:find('Provoke', 1, true) and not text:find('WS', 1, true) and not text:find('Magic', 1, true), 'actual attachment cooldowns only')
options.showPetCooldowns = false
check(not shown():find('Bash', 1, true) and not shown():find('<separator>', 1, true), 'toggle hides pets and separator')
options.showPetCooldowns = true
game.playerTimer, game.spellTimer = 0, 0
text = shown()
check(text:find('Bash', 1, true) and not text:find('<separator>', 1, true), 'pet-only window has no leading separator')
H.wait(181)
check(shown() == '', 'expired pet cooldowns removed')
did(2, 1944); game.pet = 3
check(shown() == '', 'changing pet clears cooldowns')
did(3, 1944); H.packet(0x00A)
check(shown() == '', 'zoning clears cooldowns')
did(3, 1944); game.owner = 5
check(shown() == '', 'changing character clears cooldowns')
parts(5, 0x22, {})
did(3, 1949)
check(shown():find('Shot', 1, true), 'Sharpshot ranged cooldown')
game.job = 1
check(shown() == '', 'changing job removes automaton cooldowns')
game.job = 18
parts(5, 0x22, { 69 })
did(3, 1949)
local shot = recasts.Timers(options.petAutomaton)[1].timer
game.buffs = { 302 }
check(recasts.Timers(options.petAutomaton)[1].timer == shot - 120, 'Drum Magazine and Wind maneuvers shorten Shot')
game.buffs = {}
H.resettle()
check(shown() == '', 'settings reload clears runtime observations')
H.packetData(0x044, '')
check(shown() == '', 'truncated parts packet ignored')

-- Spell timers are observed independently of current spell eligibility or target state.
local function cast(actor, spell, param)
    action = { actor_id = actor, category = 8, param = param or 0x68776163,
        targets = { { id = 900, actions = { { param = spell } } } } }
    H.packetData(packets.inbound.action.id, '')
end
local function petTimers()
    local found = {}
    for _, timer in ipairs(recasts.Timers(options.petAutomaton)) do found[timer.name] = timer end
    return found
end
parts(4, 0x23, { 33, 195 })
check(not shown():find('Magic', 1, true), 'unobserved spell timers are omitted')
cast(99, 1)
check(not shown():find('Magic', 1, true), 'another actor casting does not start pet spell timers')
cast(3, 1)
local spells = petTimers()
check(spells.Magic.timer == 23 * 60 and spells.Healing.timer == 12 * 60,
    'Cure starts shared and healing timers with Mana Booster and Damage Gauge reductions')
check(not spells.Enfeebling and not spells.Elemental, 'unobserved spell types remain absent')
text = shown()
check(text:find('Magic', 1, true) and text:find('Healing', 1, true), 'running pet spell recasts rendered')
check(colors.Magic == options.spellNameColor and colors.Healing == require('winxi.automaton.colors')[7],
    'pet magic uses spell name color and healing uses Light')
game.buffs = { 301, 301 }
check(petTimers().Magic.timer < spells.Magic.timer - 3 * 60, 'Ice maneuvers update shared magic reduction')
H.wait(25)
check(shown() == '', 'expired spell timers disappear')
cast(3, 59, 0x68777073)
check(shown() == '', 'spell interruption without observed start does not invent a cooldown')
cast(3, 59, 0x6B626163)
check(petTimers().Enfeebling and petTimers().Magic, 'enfeebling spell starts both timer kinds')
H.wait(20)
spells = petTimers()
check(not spells.Magic and spells.Enfeebling, 'spell-type recast remains after shared timer expires')
cast(3, 144, 0x6B626163)
check(petTimers().Elemental, 'elemental spell starts elemental timer')
parts(5, 0x23, {})
cast(3, 143)
check(petTimers()['Status removal'], 'status-removal spell starts status timer')
options.showPetCooldowns = false
check(shown() == '', 'pet toggle hides spell recasts too')
options.showPetCooldowns = true
parts(5, 0x22, {})
check(not petTimers().Magic and not petTimers()['Status removal'], 'noncasting frame has no spell recast rows')
game.buffs = {}
H.packet(0x00A)
check(H.command('/cooldowns'), 'cooldowns command opens settings and is blocked from game')
local click
imgui.Checkbox = function(label, value)
    if label == click then value[1] = not value[1]; click = nil; return true end
    return false
end
click = 'Show sample data'
text = shown()
check(text:find('Maneuver (sample)', 1, true) and text:find('Bash', 1, true)
    and text:find('Shot', 1, true) and text:find('Flash', 1, true), 'sample mode previews player and pet cooldowns')
check(colors.Magic == options.spellNameColor and text:find('Healing', 1, true)
    and text:find('Enfeebling', 1, true), 'sample mode includes pet spell recasts')
local elements = require('winxi.automaton.colors')
check(colors.Bash == elements[4] and colors.Shot == elements[3]
    and colors.Provoke == elements[1] and colors.Flash == elements[7], 'sample pet names use Puppet maneuver colors')
check(colors['2m 22s'] == 'theme' and colors['7s'][3] == 0
    and colors['4s'][1] == 0.95, 'pet countdowns keep normal/yellow/red urgency independent of names')
check(text:find('Overdrive', 1, true) and text:find('1h 59m 17s', 1, true),
    'preview uses current job two-hour ability with an hours-long recast')
check(colors.Overdrive == options.abilityNameColor and colors['1h 59m 17s'] == 'theme',
    'long two-hour recast retains normal ability-name and timer colors')
local sampleEdge = countdownEdges[1]
for _, edge in ipairs(countdownEdges) do check(edge == sampleEdge, 'all sample countdowns share a right edge, including hours') end
check(sampleEdge >= 5 + #('Maneuver (sample)') * 7 + 8 + #('1h 59m 17s') * 7,
    'auto-fit layout reserves room for the longest name and countdown')
local function before(a, b)
    return text:find(a, 1, true) < text:find(b, 1, true)
end
check(before('Overdrive', 'Cure IV (sample)') and before('Magic', 'Flash'), 'default sample keeps original order')
local sortSaves = H.saves()
click = 'Sort by time remaining'
text = shown()
check(options.sortByTime and H.saves() > sortSaves, 'sort checkbox enables and saves time sorting')
check(before('Cure IV (sample)', 'Maneuver (sample)') and before('Maneuver (sample)', 'Overdrive'),
    'ascending sorts player spells and abilities together by remaining time')
check(before('Flash', 'Healing') and before('Healing', 'Shot') and before('Shot', 'Magic')
    and before('Magic', 'Provoke') and before('Provoke', 'Enfeebling') and before('Enfeebling', 'Bash'),
    'ascending sorts all pet timer types together with stable equal-duration order')
check(before('Overdrive', '<separator>') and before('<separator>', 'Flash'), 'sorting keeps player and pet sections separate')
local directionClick
imgui.RadioButton = function(label)
    if label == directionClick then directionClick = nil; return true end
    return false
end
directionClick = 'Descending (longest first)'
sortSaves = H.saves()
text = shown()
check(options.sortDescending and H.saves() > sortSaves, 'descending selection is saved')
check(before('Overdrive', 'Maneuver (sample)') and before('Maneuver (sample)', 'Cure IV (sample)'),
    'descending sorts player countdowns longest first')
check(before('Bash', 'Enfeebling') and before('Enfeebling', 'Provoke') and before('Provoke', 'Magic')
    and before('Magic', 'Healing') and before('Healing', 'Shot') and before('Shot', 'Flash'),
    'descending sorts pet countdowns longest first without reversing ties')
H.resettle()
text = shown()
check(options.sortByTime and options.sortDescending and before('Bash', 'Flash'), 'sorting preferences survive settings reload')
directionClick = 'Ascending (shortest first)'
text = shown()
check(not options.sortDescending and before('Flash', 'Bash'), 'ascending can be selected again')
click = 'Sort by time remaining'
text = shown()
check(not options.sortByTime and before('Overdrive', 'Cure IV (sample)') and before('Magic', 'Flash'),
    'disabling sorting restores original order in both sections')
local thresholdEdits = {}
imgui.InputInt = function(label, value)
    if thresholdEdits[label] ~= nil then
        value[1] = thresholdEdits[label]; thresholdEdits[label] = nil
        return true
    end
    return false
end
local function thresholds(warning, critical)
    thresholdEdits['Warning below (seconds)'] = warning
    thresholdEdits['Critical at or below (seconds)'] = critical
    return shown()
end
local thresholdSaves = H.saves()
thresholds(40, 15)
check(options.warningSeconds == 40 and options.criticalSeconds == 15 and H.saves() == thresholdSaves + 1,
    'threshold controls update and save both values')
check(colors['30s'][3] == 0 and colors['12s'][1] == 0.95, 'custom thresholds apply to player countdowns')
check(colors['18s'][3] == 0 and colors['7s'][1] == 0.95, 'custom thresholds apply to pet countdowns')
check(colors['Maneuver (sample)'] == options.abilityNameColor and colors.Magic == options.spellNameColor,
    'threshold changes never override name colors')
thresholds(30, 7)
check(colors['30s'] == 'theme' and colors['7s'][1] == 0.95,
    'yellow is exclusive at threshold and red is inclusive')
thresholds(10, 25)
check(options.warningSeconds == 10 and options.criticalSeconds == 10,
    'red threshold is clamped to yellow threshold')
thresholds(-3, -8)
check(options.warningSeconds == 0 and options.criticalSeconds == 0 and colors['4s'] == 'theme',
    'negative thresholds clamp to zero, disabling urgency for positive timers')
thresholds(40, 15)
H.resettle(); shown()
check(options.warningSeconds == 40 and options.criticalSeconds == 15 and colors['12s'][1] == 0.95,
    'custom thresholds survive settings reload')
options.warningSeconds, options.criticalSeconds = 'invalid', math.huge
H.resettle()
check(options.warningSeconds == 20 and options.criticalSeconds == 5, 'malformed saved thresholds safely default')
thresholds(40, 15)
local warning = { 0.1, 0.8, 0.9, 0.6 }
local critical = { 0.9, 0.3, 0.7, 0.8 }
local colorEdits = { ['Warning countdown color'] = warning, ['Critical countdown color'] = critical }
imgui.ColorEdit4 = function(label, color)
    local edit = colorEdits[label]
    if not edit then return false end
    for i = 1, 4 do color[i] = edit[i] end
    colorEdits[label] = nil
    return true
end
local colorSaves = H.saves()
shown()
check(H.saves() == colorSaves + 2, 'each threshold color picker saves per-character settings')
check(colors['30s'] == options.warningColor and colors['12s'] == options.criticalColor,
    'player countdowns use independently configured threshold colors')
check(colors['18s'] == options.warningColor and colors['7s'] == options.criticalColor,
    'pet countdowns use independently configured threshold colors')
check(colors['18s'][4] == 0.6 and colors['7s'][4] == 0.8, 'threshold colors retain configurable alpha')
check(colors['1h 59m 17s'] == 'theme' and colors['Maneuver (sample)'] == options.abilityNameColor
    and colors.Magic == options.spellNameColor, 'threshold colors leave normal countdown and name colors unchanged')
H.resettle(); shown()
check(options.warningColor[1] == 0.1 and options.criticalColor[3] == 0.7
    and colors['7s'] == options.criticalColor, 'custom threshold colors survive settings reload')
options.warningColor, options.criticalColor = 'invalid', { 0/0, math.huge, -2, 4 }
H.resettle(); shown()
check(options.warningColor[1] == 1 and options.warningColor[2] == 1 and options.warningColor[3] == 0,
    'malformed warning color restores yellow defaults')
check(options.criticalColor[1] == 0.95 and options.criticalColor[2] == 0.20
    and options.criticalColor[3] == 0 and options.criticalColor[4] == 1,
    'invalid critical channels default safely and finite channels clamp to RGBA range')
thresholds(20, 5)
local settingsLabels = {}
imgui.ColorEdit4 = function(label, color)
    settingsLabels[#settingsLabels + 1] = label
    color[1] = 0.6
    return true
end
local priorSaves = H.saves()
shown()
check(H.saves() == priorSaves + 4 and #settingsLabels == 4
    and settingsLabels[1] == 'Ability name color' and settingsLabels[2] == 'Spell name color'
    and settingsLabels[3] == 'Warning countdown color' and settingsLabels[4] == 'Critical countdown color',
    'settings expose and save name colors plus both threshold colors without local window style controls')
click = 'Show pet cooldowns'
local saves = H.saves()
text = shown()
check(not options.showPetCooldowns and H.saves() > saves and not text:find('Bash', 1, true), 'settings checkbox persists pet toggle')
H.command('/cooldowns')
check(shown() == '', 'samples disappear when config closes')
H.print(('cooldowns: %d assertions passed'):format(count))
