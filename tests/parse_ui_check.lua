local ffi = require('ffi')
local fixture = require('parse_packets')
local function check(name, value) assert(value, name); H.print(name, value) end
local function total() return PARSE.session.core:Snapshot(PARSE.now, { combinePets = true }).total end
local data = fixture.Single(1, 1, 1, 100)
local chunk = ffi.new('uint8_t[512]')
local function boundary()
    PARSE.packet({ id = 0x037, data_raw = chunk, chunk_data_raw = chunk })
end
local function send(bytes, extra)
    local event = { id = 0x028, data = bytes, data_raw = chunk + 8, chunk_data_raw = chunk }
    for key, value in pairs(extra or {}) do event[key] = value end
    PARSE.packet(event)
end
H.load(); H.play(true)
check('chunk support requested', PARSE.feature == 1)
boundary(); PARSE.now = 1; send(data); send(data)
check('legitimate identical hits in a chunk counted', total() == 200)
boundary(); send(data); send(data)
check('retransmitted chunk does not double count', total() == 200)
PARSE.now = 2
send(fixture.Single(2, 1, 1, 50))
check('pet with mob flags resolved before mob classification', total() == 250)
send(data, { injected = true })
check('injected packet excluded', total() == 250)
send(fixture.Single(1, 1, 1, 10, 100, 2), { blocked = true })
check('display-blocked server packet still counted', total() == 260)
H.frames(20)
check('themed overlay draws a table', (H.calls.BeginTable or 0) > 0)
PARSE.now = 5
check('commands consumed by shell', H.command('/parse pause'))
PARSE.now = 50; send(fixture.Single(1, 1, 1, 999, 100, 3))
check('pause freezes counting and duration', total() == 260 and PARSE.session.core:Duration(50) == 4)
H.command('/parse pause'); PARSE.now = 52
check('pause command toggles back to recording and excludes paused time', PARSE.session.core.running and PARSE.session.core:Duration(52) == 6)
H.command('/parse resume')
check('explicit resume alias remains supported', PARSE.session.core.running)
PARSE.packet({ id = 0x00A })
check('zone boundary pauses and scopes actor identities', not PARSE.session.core.running and PARSE.session.epoch == 2)
check('clear command consumed', H.command('/parse clear'))
check('clear resets totals and resumes recording', total() == 0 and PARSE.session.core.running)
H.command('/parse report')
H.command('/parse config'); H.frames(1)
check('settings window draws', (H.calls.BeginTabBar or 0) > 0)
H.command('/parse capture ../bad')
check('capture filename cannot traverse directories', PARSE.session.file == nil)
H.command('/parse config') -- close settings before measuring the results viewport
local imgui = require('imgui')
local begin, row, freeze, text = imgui.BeginTable, imgui.TableNextRow, imgui.TableSetupScrollFreeze, imgui.Text
local submitted, viewport, frozen, words = 0, nil, nil, {}
local tableFlags, tableId, definitions = nil, nil, {}
local setupColumn = imgui.TableSetupColumn
imgui.TableSetupColumn = function(label, flags, width, id)
    definitions[#definitions + 1] = { label = label, flags = flags, width = width, id = id }
    return setupColumn(label, flags, width, id)
end
imgui.BeginTable = function(id, columns, flags, size)
    if id:find('##parse.results', 1, true) == 1 then
        submitted, viewport, words, definitions = 0, size, {}, {}
        tableFlags, tableId = flags, id
    end
    return begin(id, columns, flags, size)
end
imgui.TableNextRow = function(...) submitted = submitted + 1; return row(...) end
imgui.TableSetupScrollFreeze = function(columns, rows) frozen = rows; return freeze(columns, rows) end
imgui.Text = function(value) words[#words + 1] = value; return text(value) end
H.options().maxRows[1] = 5
check('test command consumed', H.command('/parse test'))
H.frames(1)
check('18-person preview submits everyone in the available viewport', submitted == 18 and viewport[1] == 200 and viewport[2] == 96)
check('scrolling results keep the header frozen', frozen == 1)
check('preview never populates live totals', total() == 0)
local liveBefore = PARSE.session.core
H.command('/parse reset')
check('live controls protected while previewing', PARSE.session.core == liveBefore and total() == 0)
PARSE.now = 53; boundary(); send(fixture.Single(1, 1, 1, 125, 100, 10))
check('live observations continue behind preview', total() == 125)
H.command('/parse test 6'); H.frames(1)
check('preview size configurable', submitted == 6)
H.command('/parse test off'); H.frames(1)
check('test off restores live observations', submitted == 1 and total() == 125 and table.concat(words, ' '):find('Tester', 1, true) ~= nil)
H.command('/parse test invalid'); H.frames(1)
check('invalid test size rejected without enabling preview', submitted == 1)
H.command('/parse test 19'); H.frames(1)
check('preview limited to 18 people', submitted == 1)
H.options().isVisible[1] = false
H.command('/parse test on'); H.frames(1)
check('test on opens the overlay', H.options().isVisible[1] and submitted == 18)
H.command('/parse test'); H.frames(1)
check('bare test command toggles preview off', submitted == 1 and total() == 125)
local beginWindow, setSize = imgui.Begin, imgui.SetNextWindowSize
local mainFlags, sizeRequests = nil, 0
imgui.Begin = function(name, open, flags)
    if name == 'winxi.parse' then mainFlags = flags end
    return beginWindow(name, open, flags)
end
imgui.SetNextWindowSize = function(size, condition)
    sizeRequests = sizeRequests + 1
    return setSize(size, condition)
end
H.ret.GetWindowSize = { 900, 500 }
H.ret.GetContentRegionAvail = { 860, 390 }
H.resettle(); H.frames(1)
check('main window uses resizable flags instead of auto-fit', mainFlags == require('winxi.style').ResizableFlags())
check('user-resized dimensions retained in settings', H.options().size[1] == 900 and H.options().size[2] == 500)
check('table follows resized content area with room for footer', viewport[1] == 860 and viewport[2] == 368)
local requests = sizeRequests
H.frames(1)
check('saved window size not forced every frame', sizeRequests == requests)
local expectedTableFlags = require('bit').bor(ImGuiTableFlags_ScrollY, ImGuiTableFlags_ScrollX,
    ImGuiTableFlags_Resizable, ImGuiTableFlags_SizingFixedFit, ImGuiTableFlags_RowBg,
    ImGuiTableFlags_BordersInnerV, ImGuiTableFlags_BordersOuterV)
check('table enables resizing, horizontal scroll and native saved layout', tableFlags == expectedTableFlags)
local expectedLabels = { 'Actor', 'Damage', 'Share', 'DPS', 'Melee', 'Ranged' }
local fixed = #definitions == 6
for index, column in ipairs(definitions) do
    fixed = fixed and column.label == expectedLabels[index] and column.flags == ImGuiTableColumnFlags_WidthFixed
        and column.width > 0 and column.id == index
end
check('all six columns have fixed initial widths and stable saved IDs', fixed)
local savedId = tableId
H.command('/parse reset'); H.frames(1)
check('new encounters keep the table identity used for saved widths', tableId == savedId and #definitions == 6)
local smallButton, button, checkbox = imgui.SmallButton, imgui.Button, imgui.Checkbox
local clicked, changed, editorOpen = nil, nil, false
local buttonLabels = {}
imgui.SmallButton = function(label)
    buttonLabels[label] = true
    if clicked == label then clicked = nil; return true end
    return smallButton(label)
end
imgui.Button = function(label, size)
    buttonLabels[label] = true
    if clicked == label then clicked = nil; return true end
    return button(label, size)
end
local cursorX, cogX = imgui.SetCursorPosX, nil
imgui.SetCursorPosX = function(x) cogX = x; return cursorX(x) end
imgui.OpenPopup = function(id) if id == '##parse.columnEditor' then editorOpen = true end end
imgui.BeginPopup = function(id) return id == '##parse.columnEditor' and editorOpen end
imgui.Checkbox = function(label, value)
    if label == changed then changed = nil; value[1] = not value[1]; return true end
    return checkbox(label, value)
end
H.command('/parse test on')
clicked = '##parse.columns'; H.frames(1)
check('cog button opens column editor', editorOpen)
check('cog right-aligned to available window content', cogX == 5 + 860 - (14 + 8))
check('cog drawn without requiring an icon font', (H.calls['draw.AddCircle'] or 0) > 0 and (H.calls['draw.AddLine'] or 0) >= 32)
local saves = H.saves()
changed = 'Share##parse.column.share'; H.frames(1)
check('column checkbox hides the selected column and saves', #definitions == 5 and H.options().columnShown.share == false and H.saves() > saves)
clicked = 'Up##parse.column.damage'; H.frames(1)
check('Up changes displayed column order with stable stat IDs', definitions[1].label == 'Damage' and definitions[1].id == 2
    and definitions[2].label == 'Actor' and definitions[2].id == 1)
check('reordered cell values still match their headers', words[1]:match('^%d+$') ~= nil and words[2]:find('[', 1, true) ~= nil)
local editedId = tableId
H.resettle(); H.frames(1)
check('column choices survive settings reload', H.options().columnOrder[1] == 'damage' and not H.options().columnShown.share
    and tableId == editedId and #definitions == 5)
clicked = 'Down##parse.column.damage'; H.frames(1)
check('Down moves the selected column right', definitions[1].label == 'Actor' and definitions[2].label == 'Damage')
for key in pairs(H.options().columnShown) do H.options().columnShown[key] = false end
local tables = H.calls.BeginTable
H.frames(1)
check('all hidden columns handled without creating a zero-column table', H.calls.BeginTable == tables)
clicked = 'Reset columns##parse.columns.reset'; H.frames(1)
check('reset columns restores all six and original saved-width layout', #definitions == 6 and tableId == '##parse.results'
    and definitions[1].label == 'Actor' and H.options().columnShown.share)
changed = 'Magic Damage##parse.column.magic'; H.frames(1)
check('Magic Damage available as an optional seventh column', #definitions == 7 and definitions[7].label == 'Magic Damage'
    and definitions[7].id == 7 and H.options().columnShown.magic)
local sample = require('parse_preview').New(18):Snapshot(180, { combinePets = true })
check('magic column shows spell plus burst damage in preview', words[7] == tostring(sample.rows[1].categories.spell.damage))
H.resettle(); H.frames(1)
check('magic column selection survives settings reload', H.options().columnShown.magic and #definitions == 7)
editorOpen = false
H.command('/parse test off'); H.frames(1)
check('encounter and pause buttons removed from overlay', not buttonLabels['New encounter'] and not buttonLabels.Pause and not buttonLabels.Resume)
PARSE.now = 56; boundary(); send(fixture.Single(1, 1, 1, 77, 100, 25))
H.command('/parse pause')
check('toggle pauses live parser before clear', not PARSE.session.core.running and total() == 77)
H.command('/parse clear')
check('clear from paused state starts a fresh parser', PARSE.session.core.running and total() == 0
    and PARSE.session.core.event_count == 0 and #PARSE.session.core.history == 0 and PARSE.session.core:Duration(100) == 0)
local oldMemory, oldResources = AshitaCore.GetMemoryManager, AshitaCore.GetResourceManager
AshitaCore.GetMemoryManager = function(...)
    local memory = oldMemory(...)
    local party, player, inventory = memory:GetParty(), memory:GetPlayer(), memory:GetInventory()
    party.GetMemberHP = function() return 1000 end
    player.GetMainJob = function() return 7 end
    player.GetSubJob = function() return 3 end
    player.GetStatusIcons = function() return {} end
    memory.GetPlayer = function() return player end
    inventory.GetEquippedItem = function(_, slot) return slot == 0 and { Index = 257 } or nil end
    inventory.GetContainerItem = function(_, bag, index) return bag == 1 and index == 1 and { Id = 500 } or nil end
    return memory
end
AshitaCore.GetResourceManager = function(...)
    local resources = oldResources(...)
    resources.GetItemById = function() return { Type = 5, Skill = 3 } end
    return resources
end
check('WS profile command consumed', H.command('/parse wsprofile 80 120 0 4'))
check('calibration saved per WS', H.options().wsProfiles['80'].base == 120 and H.options().wsProfiles['80'].attempts == 4)
PARSE.now = 57; boundary(); send(fixture.Single(1, 7, 43, 80, 100, 30))
PARSE.now = 57.1; send(fixture.Packet(1, 3, 80, { { id = 100, results = { { message = 185, value = 500 } } } }, 31))
local tpPacket = '\0\0\0\0' .. string.char(1,0,0,0,232,3,0,0,0,0,0,0,140,0,0,0)
PARSE.now = 57.2
PARSE.packet({ id = 0x0DF, data = tpPacket, data_raw = chunk + 16, chunk_data_raw = chunk })
PARSE.now = 57.7; H.frames(1)
local observed = PARSE.session.core:Snapshot(PARSE.now).rows[1]
check('live TP packet correlates with local WS through settling window', observed.categories.ws_hits
    and observed.categories.ws_hits.hits == 3 and observed.categories.ws_hits.misses == 1)
check('live WS inference does not double-count damage', observed.damage == 500 and observed.categories.ws_count.count == 1)
PARSE.now = 58
send(fixture.Single(1, 1, 15, 0, 100, 32))
send(fixture.Single(1, 4, 2, 100, 100, 33))
send(fixture.Single(1, 4, 85, 0, 100, 34))
send(fixture.Single(1, 4, 75, 0, 100, 35))
observed = PARSE.session.core:Snapshot(PARSE.now).rows[1]
check('displayed melee rate includes inferred WS strike misses', require('parse_columns').Value('melee', observed) == '60.0%')
check('live magic damage and resist outcomes remain separate', observed.damage == 600
    and require('parse_columns').Value('magic_accuracy', observed) == '50.0%' and observed.categories.magic_accuracy.excluded == 1)
for _, key in ipairs({ 'ws_count', 'ws_accuracy', 'ws_unknown', 'magic_accuracy', 'magic_resists' }) do H.options().columnShown[key] = true end
H.resettle(); H.frames(1)
check('all accuracy and count columns available through saved column choices', #definitions == 12 and definitions[8].label == 'WS Count'
    and definitions[9].label == 'WS Hit % (TP)' and definitions[11].label == 'Magic Land %' and definitions[12].label == 'Magic Resists')
send(fixture.Packet(1, 3, 81, { { id = 100, results = { { message = 185, value = 500 } } } }, 36))
observed = PARSE.session.core:Snapshot(PARSE.now).rows[1]
check('unconfigured live WS recorded as unknown, not guessed accuracy', observed.categories.ws_unknown.count == 1
    and require('parse_columns').Value('melee', observed) == '60.0%')
H.command('/parse wsprofile off')
check('profile inference can be disabled without clearing combat totals', next(H.options().wsProfiles) == nil and total() == 1100)
local windows = require('winxi.window')
local plain, minimalStyle, minimalFlags = windows.Plain, nil, nil
windows.Plain = function(name, open, flags, draw, options)
    if name == 'winxi.parse.minimal' then minimalStyle, minimalFlags = options, flags end
    return plain(name, open, flags, draw, options)
end
H.command('/parse test on')
local fullSize = { H.options().size[1], H.options().size[2] }
H.command('/parse minimal on'); H.frames(20)
check('minimal mode uses a separate transparent borderless window', H.options().minimal[1]
    and minimalStyle.background[4] == 0 and minimalStyle.border[4] == 0 and minimalStyle.shadow == false
    and minimalStyle.title == nil and minimalStyle.alpha <= 0.75)
check('minimal window removes background and uses smaller text', require('bit').band(minimalFlags, ImGuiWindowFlags_NoBackground) ~= 0
    and minimalStyle.fontSize == 12)
H.options().minimalLocked[1] = true; H.frames(1)
check('minimal lock passes input through to the game', minimalStyle.locked == true and minimalStyle.clickThrough == true) -- winxi.window's options: NoMove and NoInputs
check('minimal mode preserves full window dimensions and live totals', H.options().size[1] == fullSize[1]
    and H.options().size[2] == fullSize[2] and total() == 1100)
H.resettle(); H.frames(1)
check('minimal preferences survive settings reload', H.options().minimal[1] and H.options().minimalLocked[1])
local minimalModule = require('parse_minimal')
check('compact numbers are optional and preserve small values', minimalModule.Number(1234, true) == '1.2K'
    and minimalModule.Number(2345678, true) == '2.3M' and minimalModule.Number(1234, false) == '1234'
    and minimalModule.Number(42, true) == '42')
local minimalColumns, minimalRows, minimalWords = nil, 0, {}
local currentBegin, currentRow, currentText = imgui.BeginTable, imgui.TableNextRow, minimalModule.Text
local badges = {}
imgui.BeginTable = function(id, count, ...)
    if id == '##parse.minimal.rows' then minimalColumns, minimalRows, minimalWords = count, 0, {} end
    return currentBegin(id, count, ...)
end
imgui.TableNextRow = function(...) minimalRows = minimalRows + 1; return currentRow(...) end
minimalModule.Text = function(value, color, edge)
    minimalWords[#minimalWords + 1] = value; badges[value] = true
    return currentText(value, color, edge)
end
H.options().minimalShare[1], H.options().minimalDamage[1], H.options().minimalDPS[1] = false, false, false
H.options().minimalRanks[1], H.options().minimalSummary[1], H.options().minimalRows[1] = true, false, 3
H.frames(1)
check('minimal columns can be hidden independently and row limit applied', minimalColumns == 1 and minimalRows == 3
    and minimalWords[1]:find('1. ', 1, true) == 1)
H.frames(1)
check('test label remains visible with encounter summary disabled', badges.TEST)
local fontLibrary, outlineLibrary = require('winxi.fonts'), require('winxi.text')
local getFont, pushFont, outlineDraw = fontLibrary.Get, imgui.PushFont, outlineLibrary.Draw
local selectedFont, selectedSize, outlines = nil, nil, 0
fontLibrary.Get = function(file) if file == 'test.ttf' then return 'test-font' end; return getFont(file) end
imgui.PushFont = function(font, size) selectedFont, selectedSize = font, size; return pushFont(font, size) end
outlineLibrary.Draw = function(...) outlines = outlines + 1; return outlineDraw(...) end
local look = require('winxi.theme').Get() -- the outline is the theme's Text Outline, every addon's alike
H.options().minimalFontFile, look.TextOutline = 'test.ttf', 2
H.frames(1)
check('minimal custom font and the theme\'s outline apply to every rendered line', selectedFont == 'test-font'
    and selectedSize == 12 and outlines >= 4)
outlines = 0; look.TextOutline = 0; H.frames(1)
check('zero outline uses plain text without outline draws', outlines == 0)
H.resettle(); H.frames(1)
check('font preference survives settings reload', H.options().minimalFontFile == 'test.ttf' and H.options().minimalOutline == nil)
look.TextOutline = 1
fontLibrary.Get, imgui.PushFont, outlineLibrary.Draw = getFont, pushFont, outlineDraw
H.options().minimalFontFile = ''
local draws = 0
windows.Plain = function(...) draws = draws + 1; return plain(...) end
local o = H.options()
local oldFade = o.fadeInOut[1]
o.fadeInOut[1], o.minimalHideEmpty[1] = false, true
minimalModule.Draw(o, { rows = {}, total = 0, duration = 0, running = true }, false)
check('hide when empty suppresses the minimal window', draws == 0)
o.fadeInOut[1] = oldFade
imgui.BeginTable, imgui.TableNextRow, minimalModule.Text = currentBegin, currentRow, currentText
H.command('/parse minimal off'); H.frames(20)
check('full layout restored without changing preview or live recording', not H.options().minimal[1] and submitted == 18 and total() == 1100)
H.command('/parse minimal invalid')
check('invalid minimal command leaves mode unchanged', not H.options().minimal[1])
local tab, tabs = imgui.BeginTabItem, {}
imgui.BeginTabItem = function(label, ...) tabs[label] = true; return tab(label, ...) end
H.command('/parse config'); H.frames(1)
check('settings organized into focused tabs without Winxi Theme', tabs.General and tabs['Full View'] and tabs.Minimal
    and tabs.Accuracy and tabs.Diagnostics and not tabs['Winxi Theme'])
H.unload()
