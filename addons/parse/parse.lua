addon.name = 'parse'
addon.author = 'win'
addon.version = '0.5.0'
addon.desc = 'Packet-based combat damage, observed hit rates and manual encounter DPS.'
local winxiNeeded = 6
do
    local ok, version = pcall(require, 'winxi.version')
    local number = ok and type(version) == 'table' and version.Number or 0
    if number < winxiNeeded then
        local message = ('parse needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(winxiNeeded, number)
        print('[parse] ' .. message)
        error(message, 0)
    end
end
require('common')
local imgui = require('imgui')
local ffi = require('ffi')
local bit = require('bit')
local previewData = require('parse_preview')
local columns = require('parse_columns')
local controls = require('parse_controls')
local ws = require('parse_ws')
local wsLive = require('parse_ws_live')
local shell = require('winxi.shell')
local widgets = require('winxi.widgets')
local identity = require('parse_identity')
local session = require('parse_session').New()
local core = require('parse_core')
local dedupe = require('parse_dedupe').New()
local frequency = tonumber(ashita.time.qpf().q)
local function Now() return tonumber(ashita.time.qpc().q) / frequency end
local chunkSupport = false
if ashita.addons_version and ashita.addons_version >= 4.3 and addon_feature and addon_feature.use_packet_chunks then
    addon.instance:enable_feature(addon_feature.use_packet_chunks)
    chunkSupport = true
end
local app, snapshot, nextRefresh = nil, nil, 0
local resizePending = true
local duplicates = 0
local preview
local lastWS
local wsTracker = ws.New(function(result, now)
    lastWS = result
    session:WSResult(result, now)
    nextRefresh = 0
end)
local function CancelWS(reason)
    wsTracker.now = Now()
    wsTracker:Finish(reason)
    wsTracker:Clear()
end
local function WSContext()
    return wsLive.Context(AshitaCore:GetMemoryManager(), AshitaCore:GetResourceManager())
end
local function Refresh()
    local options = app.options
    snapshot = (preview or session.core):Snapshot(preview and previewData.Duration or Now(), {
        combinePets = options.combinePets[1], includeSkillchains = options.includeSkillchains[1] })
    nextRefresh = Now() + 0.25
end
local function Test(_, args)
    local value = args[3] and args[3]:lower()
    if value == 'off' or (not value and preview) then
        preview = nil
    else
        local count = value == 'on' and 18 or tonumber(value or '18')
        if not count or count ~= math.floor(count) or count < 1 or count > 18 then
            app:Say('Use /parse test [on|off|1-18].'); return
        end
        preview = previewData.New(count)
        app.options.isVisible[1] = true
    end
    Refresh()
    app:Say(preview and 'TEST preview on. Live recording continues separately.' or 'Test preview off; showing live observations.')
end
local function Change(kind)
    if preview then app:Say('Turn the test preview off before changing the live encounter: /parse test off.'); return end
    local now = Now()
    CancelWS('parser control changed')
    if kind == 'reset' then session:Reset(now); duplicates = 0; lastWS = nil
    elseif kind == 'pause' then session:Pause(now)
    else session:Resume(now) end
    Refresh()
end
local function UnknownCount()
    local count = 0
    for _, value in pairs(session.core.unknown) do count = count + value end
    return count
end
local function Rate(stat)
    local value = stat and core.Rate(stat)
    return value and ('%.1f%%'):format(value) or '--'
end
local function Report(_, args)
    Refresh()
    app:Say(('%sObserved damage %d; active encounter %.1fs (%s).'):format(preview and '[TEST] ' or '', snapshot.total, snapshot.duration, snapshot.running and 'running' or 'paused'))
    for _, row in ipairs(snapshot.rows) do
        app:Say(('%s [%s]: %d, %s DPS, melee %s, ranged %s'):format(row.name, row.key, row.damage,
            row.dps and ('%.1f'):format(row.dps) or '--', columns.Value('melee', row), Rate(row.categories.ranged)))
        app:Say(('  WS count %s; TP-inferred WS hit rate %s; WS unknown %s; magic land %s; resists %s'):format(
            columns.Value('ws_count', row), columns.Value('ws_accuracy', row), columns.Value('ws_unknown', row),
            columns.Value('magic_accuracy', row), columns.Value('magic_resists', row)))
        if args and args[3] == 'detail' then
            local names = {}
            for category in pairs(row.categories) do names[#names + 1] = category end
            table.sort(names)
            for _, category in ipairs(names) do
                local stat = row.categories[category]
                app:Say(('  %s: %d damage, %d hits, %d misses, %d excluded, %d crits'):format(
                    category, stat.damage, stat.hits, stat.misses, stat.excluded, stat.criticals))
            end
        end
    end
    if not preview then
        app:Say(('Unclassified %d; unresolved identities %d; malformed %d; duplicate packets %d.'):format(
            UnknownCount(), session.diagnostics.unresolved, session.diagnostics.malformed, duplicates))
    end
end
local function Capture(_, args)
    local name = args[3]
    if not name or name == 'off' then
        CancelWS('capture ended before TP observation')
        session:EndCapture(Now()); app:Say('Capture off.'); return
    end
    if preview then app:Say('Turn the test preview off before starting a capture: /parse test off.'); return end
    if not name:match('^[%w_-]+$') or #name > 64 then app:Say('Use a capture name of 1-64 letters, numbers, underscores or hyphens.'); return end
    local directory = addon.path .. 'captures\\'
    ashita.fs.create_directory(directory)
    local path = directory .. name .. '.txt'
    local existing = io.open(path, 'rb')
    if existing then existing:close(); app:Say('That capture exists; choose another name.'); return end
    local file, err = io.open(path, 'wb')
    if not file then app:Say('Cannot capture: ' .. tostring(err)); return end
    CancelWS('new capture')
    session:StartCapture(file, Now())
    duplicates = 0; Refresh()
    app:Say(session.file and ('New encounter; capturing packets and identities to ' .. path) or ('Capture failed: ' .. tostring(session.error)))
end
local function WSProfile(options, args)
    if args[3] == 'off' then options.wsProfiles = {}; CancelWS('profiles disabled'); app.save(); app:Say('WS TP profiles cleared.'); return end
    local id = tonumber(args[3])
    local profile = { base = tonumber(args[4]), store = tonumber(args[5]), attempts = tonumber(args[6]) }
    if not id or id ~= math.floor(id) or id < 1 or id > 191 or not ws.Valid(profile) then
        app:Say('Usage: /parse wsprofile <WS ID 1-191> <first-hit TP after Store TP> <total Store TP %> <known attempts 1-8>, or wsprofile off.'); return
    end
    options.wsProfiles[tostring(id)] = profile
    CancelWS('profile changed'); app.save()
    app:Say('Experimental WS TP profile saved. Single weapon only; assumes the exact attempt count, no multi-attacks, no Save/Conserve TP. Invalid samples stay unknown.')
end
local function DrawColumnEditor(options)
    imgui.TextDisabled('Top to bottom here = left to right in the table.')
    for index, key in ipairs(options.columnOrder) do
        local shown = { options.columnShown[key] }
        if imgui.Checkbox(columns.Definitions[key].label .. '##parse.column.' .. key, shown) then
            options.columnShown[key] = shown[1]
            app.save()
        end
        imgui.SameLine()
        imgui.BeginDisabled(index == 1)
        local up = imgui.SmallButton('Up##parse.column.' .. key)
        imgui.EndDisabled()
        imgui.SameLine()
        imgui.BeginDisabled(index == #options.columnOrder)
        local down = imgui.SmallButton('Down##parse.column.' .. key)
        imgui.EndDisabled()
        if (up and columns.Move(options, index, -1)) or (down and columns.Move(options, index, 1)) then
            app.save()
            break -- render the new order on the next frame
        end
    end
    if imgui.SmallButton('Reset columns##parse.columns.reset') then
        options.columnOrder, options.columnShown = columns.DefaultOrder(), columns.DefaultShown()
        app.save()
    end
end
local function DrawSettings(options)
    if widgets.Header('Accounting', true) then
        widgets.Label('Combine Pets')
        if imgui.Checkbox('##parse.pets', options.combinePets) then app.save(); Refresh() end
        widgets.Label('Include Skillchains')
        if imgui.Checkbox('##parse.sc', options.includeSkillchains) then app.save(); Refresh() end
        widgets.Label('Visible Rows (preset)')
        if imgui.SliderInt('##parse.rows', options.maxRows, 1, 18) then
            options.size[2] = (options.maxRows[1] + 1) * (imgui.GetFontSize() + 6) + 110
            resizePending = true
            app.save()
        end
        imgui.TextWrapped('Drag an edge or the bottom-right corner to resize. The table fills the window; scroll to see everyone. The row preset adjusts its height.')
        if imgui.SmallButton(preview and 'Stop test preview' or 'Test 18 people') then Test(nil, {}) end
        imgui.TextWrapped('Grouping changes the view, not the observations. DPS uses one shared encounter clock; pauses are excluded. Zoning pauses recording.')
    end
    if widgets.Header('Accuracy / experimental WS TP') then
        imgui.TextWrapped('Melee includes auto-attack outcomes plus accepted TP-inferred WS strikes. WS Hit % uses inferred strikes only. WS Count counts recognized WS actions. Unknown samples never add guessed misses.')
        imgui.TextWrapped('Magic Land % counts recognized successful spell outcomes versus explicit resists, including enfeebles. Partial damage resists count as landed; no-effect results are excluded. This is not the Magic Accuracy stat.')
        imgui.TextWrapped('WS TP inference is opt-in, for your own character and controlled single-weapon physical WS only. Configure /parse wsprofile <WS ID> <first-hit TP after Store TP> <total Store TP %> <known attempts>. Do not use with multi-attack, Conserve/Save TP or hidden TP sources. WAR/THF/BLU/RNG/DRG/DNC main/sub are conservatively excluded. Hypothetical example: /parse wsprofile 80 120 0 3')
        if lastWS then
            imgui.TextWrapped(('Last local WS %d: %s (TP %s)'):format(lastWS.ability,
                lastWS.reason or ('estimated %d hits, %d misses'):format(lastWS.hits, lastWS.misses), tostring(lastWS.tp or '--')))
        end
        local ids = {}
        for id in pairs(options.wsProfiles) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local p = options.wsProfiles[id]
            imgui.Text(('WS %s: base %d, Store TP %d%%, attempts %d'):format(id, p.base, p.store, p.attempts))
            imgui.SameLine()
            if imgui.SmallButton('Remove##parse.wsprofile.' .. id) then options.wsProfiles[id] = nil; CancelWS('profile removed'); app.save(); break end
        end
    end
    if widgets.Header('Columns') then DrawColumnEditor(options) end
    if widgets.Header('Diagnostics') then
        imgui.TextWrapped('Unknown messages may be harmless utility actions or unsupported damage. Periodic damage and defensive rates are not measured.')
        if imgui.SmallButton('Print status') then Report() end
        if session.error then imgui.TextWrapped(session.error) end
        local keys = {}
        for key in pairs(session.core.unknown) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do imgui.Text(('%s: %d'):format(key, session.core.unknown[key])) end
    end
end
app = shell.New({
    defaults = T{ isVisible = T{ true }, pos = T{ 500, 200 }, size = T{ 800, 400 }, combinePets = T{ true },
        includeSkillchains = T{ true }, maxRows = T{ 12 },
        columnOrder = columns.DefaultOrder(), columnShown = columns.DefaultShown(), wsProfiles = T{} },
    window = 'winxi.parse', title = 'Parse', resizable = true, configTitle = 'Parse Settings', command = '/parse',
    help = '/parse: clear, pause (toggle), resume, test [on|off|1-18], config, wsprofile <id> <base TP> <Store TP %> <attempts>|off, report [detail], capture <name|off>.',
    drawSettings = DrawSettings,
    commands = {
        test = Test,
        wsprofile = WSProfile,
        clear = function() Change('reset') end,
        reset = function() Change('reset') end,
        start = function() Change('reset') end,
        pause = function() Change(session.core.running and 'pause' or 'resume') end,
        resume = function() Change('resume') end,
        report = Report,
        status = Report,
        capture = Capture,
    },
    onSettings = function(options)
        columns.Normalize(options)
        if type(options.wsProfiles) ~= 'table' then options.wsProfiles = {} end
        for id, p in pairs(options.wsProfiles) do
            local n = tonumber(id)
            if type(id) ~= 'string' or not n or n ~= math.floor(n) or n < 1 or n > 191 or not ws.Valid(p) then options.wsProfiles[id] = nil end
        end
        CancelWS('settings changed')
        options.maxRows[1] = math.max(1, math.min(18, math.floor(tonumber(options.maxRows[1]) or 12)))
        options.size[1] = math.max(480, math.min(10000, tonumber(options.size[1]) or 800))
        options.size[2] = math.max(200, math.min(10000, tonumber(options.size[2]) or 400))
        resizePending = true
        nextRefresh = 0
    end,
})
local function Draw()
    local width, height = imgui.GetWindowSize()
    app.options.size[1], app.options.size[2] = width, height
    resizePending = false
    if not snapshot or Now() >= nextRefresh then Refresh() end
    local headerRight = imgui.GetCursorPosX() + imgui.GetContentRegionAvail()
    imgui.Text(('%s%d damage | %.1fs | %s'):format(preview and '[TEST] ' or '', snapshot.total, snapshot.duration,
        preview and 'Dummy data' or snapshot.running and 'Recording' or 'Paused'))
    imgui.SameLine()
    imgui.SetCursorPosX(headerRight - controls.GearSize())
    if controls.GearButton() then imgui.OpenPopup('##parse.columnEditor') end
    if preview then
        if imgui.SmallButton('Stop test preview') then Test(nil, { [3] = 'off' }) end
        imgui.SameLine(); imgui.TextDisabled('Live recording continues separately.')
    end
    if imgui.BeginPopup('##parse.columnEditor') then
        DrawColumnEditor(app.options)
        imgui.EndPopup()
    end
    local visible = columns.Visible(app.options)
    local fontSize = imgui.GetFontSize()
    local availableWidth, availableHeight = imgui.GetContentRegionAvail()
    local spacing = imgui.GetStyle().ItemSpacing
    local gap = spacing and spacing.y or 4
    local footerLines = (#snapshot.rows == 0 and 1 or 0) + (not preview and 1 or 0)
        + (not chunkSupport and 1 or 0) + (session.file and 1 or 0)
    local tableSize = { math.max(1, availableWidth), math.max(fontSize + 8, availableHeight - footerLines * (fontSize + gap) - gap) }
    -- Keep the window/table IDs stable and leave NoSavedSettings unset: Ashita's
    -- config/imgui.ini retains the user-resized widths across addon and game loads.
    -- Fixed widths + ScrollX prevent a narrow window from squeezing saved columns.
    local tableFlags = bit.bor(ImGuiTableFlags_ScrollY, ImGuiTableFlags_ScrollX,
        ImGuiTableFlags_Resizable, ImGuiTableFlags_SizingFixedFit, ImGuiTableFlags_RowBg,
        ImGuiTableFlags_BordersInnerV, ImGuiTableFlags_BordersOuterV)
    imgui.PushStyleVar(ImGuiStyleVar_CellPadding, { 6, 3 })
    if #visible > 0 and imgui.BeginTable(columns.TableId(visible), #visible, tableFlags, tableSize) then
        imgui.TableSetupScrollFreeze(0, 1)
        -- These are initial defaults only; ImGui's loaded/user widths take precedence.
        for _, key in ipairs(visible) do
            local column = columns.Definitions[key]
            imgui.TableSetupColumn(column.label, ImGuiTableColumnFlags_WidthFixed, column.width * fontSize / 14, column.id)
        end
        imgui.TableHeadersRow()
        for _, row in ipairs(snapshot.rows) do
            imgui.TableNextRow()
            for index, key in ipairs(visible) do
                imgui.TableSetColumnIndex(index - 1)
                imgui.Text(columns.Value(key, row))
            end
        end
        imgui.EndTable()
    end
    imgui.PopStyleVar()
    if #visible == 0 then imgui.TextDisabled('No columns selected. Use the cog to show columns.') end
    if #snapshot.rows == 0 then imgui.TextDisabled('Waiting for recognized party damage.') end
    if not preview then
        imgui.TextDisabled(('Unknown %d | Unresolved %d | Bad packets %d'):format(UnknownCount(), session.diagnostics.unresolved, session.diagnostics.malformed))
    end
    if not chunkSupport then imgui.TextDisabled('Chunk deduplication unavailable (Ashita 4.3+).') end
    if session.file then imgui.TextDisabled('Diagnostic capture recording') end
end
ashita.events.register('packet_in', 'parse_packet', function(e)
    if e.injected then return end
    if chunkSupport and e.data_raw and e.chunk_data_raw then
        if ffi.cast('const void*', e.data_raw) == ffi.cast('const void*', e.chunk_data_raw) then dedupe.Boundary() end
    end
    if e.id == 0x00A then CancelWS('zoning'); session:Zone(Now()); dedupe.Clear(); nextRefresh = 0; return end
    if e.id == 0x00B then CancelWS('logout/zoning'); session:Pause(Now()); dedupe.Clear(); nextRefresh = 0; return end
    if e.id ~= 0x028 and e.id ~= 0x0DF and e.id ~= 0x029 then return end
    -- Decode the original server packet even if another addon blocks its display.
    local data = e.data
    if type(data) ~= 'string' then return end
    if chunkSupport and not dedupe.Accept(data) then duplicates = duplicates + 1; return end
    if not session.core.running then return end
    local now = Now()
    if e.id == 0x0DF then
        local id, tp, hp = wsLive.TP(data)
        if id then wsTracker:TP(id, tp, hp, now) end
        return
    end
    if e.id == 0x029 then
        if #data >= 26 then
            local message = (data:byte(25) + data:byte(26) * 256) % 32768
            if message == 6 or message == 20 or message == 97 then wsTracker:Death(wsLive.U32(data, 8), now) end
        end
        return
    end
    local memory = AshitaCore:GetMemoryManager()
    local resolve = identity.Resolver(memory, session.epoch)
    local accepted, action, events = session:Process(data, now, resolve)
    if accepted then
        local context = { id = memory:GetParty():GetMemberServerId(0) }
        if action.actor == context.id and (action.category == 3 or action.category == 7) then context = WSContext() end
        wsTracker:Action(action, events, now, context, app.options.wsProfiles)
    end
end)
ashita.events.register('d3d_present', 'parse_present', function()
    if wsTracker.pending then wsTracker:Tick(Now(), WSContext()) end
    if app:BeginFrame() then
        app:Window(app.options.isVisible, Draw, {
            size = resizePending and app.options.size or nil,
            constraints = { { 480, 200 }, { 10000, 10000 } },
        })
    end
end)
ashita.events.register('unload', 'parse_unload', function()
    CancelWS('unloaded before TP observation')
    session:EndCapture(Now())
end)
