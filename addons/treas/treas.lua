addon.name    = 'treas'
addon.author  = 'lin, Win'
addon.version = '1.0'
addon.desc    = 'The treasure pool in a window, with buttons to cast lots and pass.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- The treasure pool window that was a tool of xitools, as an addon of its own. It needs only winxi:
-- the look of its windows, the packets and what is asked of the game are all the library's.
--
--   /treas           shows or hides the window (it only appears while there is treasure)
--   /treas config    opens or closes the settings

require('common')
local bit = require('bit')
local imgui = require('imgui')
local settings = require('settings')
local theme = require('winxi.theme')
local style = require('winxi.style')
local window = require('winxi.window')
local widgets = require('winxi.widgets')
local fade = require('winxi.fade')
local game = require('winxi.game')
local legacy = require('winxi.legacy')
local packets = require('winxi.packets')

local TextBaseWidth = imgui.CalcTextSize('A')
local WeirdTimestamps = {}

local gold = { 1.0, 215/255, 0.0, 1.0 }
local itemSpacing = { 8, 4 }
local framePadding = { 4, 2 }

local function Say(text)
    print(('\30\81[treas]\30\01 %s'):format(text))
end

local function GetTreasure(options)
    local res = AshitaCore:GetResourceManager()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local player = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    local now = os.time()

    local treasurePool = T{ }
    for i = 0,9 do
        local treasureItem = inv:GetTreasurePoolItem(i)
        if treasureItem ~= nil and treasureItem.ItemId > 0 then
            local itemInfo = res:GetItemById(treasureItem.ItemId)

            if not WeirdTimestamps[treasureItem.DropTime] then
                WeirdTimestamps[treasureItem.DropTime] = now + 300
            end

            treasurePool:append{
                id = itemInfo.Id,
                slot = i,
                name = itemInfo.Name[1],
                time = string.format('%4i', WeirdTimestamps[treasureItem.DropTime] - now),
                winner = {
                    exists = treasureItem.WinningLot > 0,
                    name = treasureItem.WinningEntityName,
                    lot = string.format('%4i', treasureItem.WinningLot),
                },
                current = {
                    name = player,
                    lot = string.format('%4i', treasureItem.Lot),
                    hasRolled = treasureItem.Lot > 0 and treasureItem.Lot < 1000,
                    hasPassed = treasureItem.Lot > 1000,
                },
            }
        elseif options.showAllSlots[1] then
            treasurePool:append{
                id = 0,
                slot = i,
                name = '',
                time = '',
                winner = { exists = false },
                current = { name = player, hasRolled = false, hasPassed = true },
            }
        end
    end

    return treasurePool
end

local function Roll(treasure)
    if treasure.current.hasRolled
    or treasure.current.hasPassed then
        return
    end

    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasureLot:make(treasure.slot))
end

local function Pass(treasure)
    if treasure.current.hasPassed then
        return
    end

    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasurePass:make(treasure.slot))
end

local function DrawTreasure(treasurePool)
    if imgui.Button('Roll All') then
        for _, treasure in pairs(treasurePool) do
            Roll(treasure)
        end
    end

    imgui.SameLine()
    if imgui.Button('Pass All') then
        for _, treasure in pairs(treasurePool) do
            Pass(treasure)
        end
    end

    if imgui.BeginTable('treas.pool', 6, ImGuiTableFlags_SizingFixedFit) then
        imgui.TableSetupScrollFreeze(0, 1)
        imgui.TableSetupColumn('Treasure', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 17)
        imgui.TableSetupColumn('Time', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 6)
        imgui.TableSetupColumn('##Winning Lot', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 4)
        imgui.TableSetupColumn('Winner', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 16)
        imgui.TableSetupColumn('Lot', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 6)
        imgui.TableSetupColumn('##Pass', ImGuiTableColumnFlags_NoHide, TextBaseWidth * 6)
        imgui.TableHeadersRow()

        for i, treasure in ipairs(treasurePool) do
            imgui.TableNextRow()

            local Write = imgui.Text
            if treasure.current.hasPassed then
                Write = imgui.TextDisabled
            elseif treasure.winner.name == treasure.current.name then
                Write = imgui.TextColored:bindn(gold)
            end

            imgui.TableNextColumn()
            imgui.AlignTextToFramePadding()
            Write(treasure.name)

            imgui.TableNextColumn()
            Write(treasure.time)

            imgui.TableNextColumn()
            if treasure.winner.exists then
                Write(treasure.winner.lot)
            end

            imgui.TableNextColumn()
            if treasure.winner.exists then
                Write(treasure.winner.name)
            end

            imgui.TableNextColumn()
            if not treasure.current.hasRolled
            and not treasure.current.hasPassed then
                if imgui.Button(('Roll##%i'):format(i)) then
                    Roll(treasure)
                end
            elseif treasure.current.hasRolled then
                Write(treasure.current.lot)
            elseif treasure.current.hasPassed then
                Write('---')
            end

            imgui.TableNextColumn()
            if imgui.Button(('Pass##%i'):format(i))
            and not treasure.current.hasPassed then
                Pass(treasure)
            end
        end

        imgui.EndTable()
    end
end

-- The settings, kept for each character
local defaults = T{
    isVisible = T{ true },
    showAllSlots = T{ false },
    pos = T{ 100, 100 },
    fadeInOut = T{ true }, -- the window fades in as it is shown and out as it is hidden
    hide = T{ }, -- when the window gets out of the way: winxi.game's rules
    useSharedTheme = true, -- whether the windows follow the theme shared with other winxi addons
    theme = T{ }, -- this addon's own colours, padding and drop shadow, used when they do not
    importedFromXitools = false, -- whether what xitools kept for its treas tool has been brought over
}

local options = settings.load(defaults)

-- The treasure pool was a tool of xitools, which kept its settings among its own. They are brought
-- over once for each character, the first time this addon is loaded with that character logged in.
local importKeys = { 'isVisible', 'showAllSlots', 'pos' }

local function ImportFromXitools()
    -- not before the character is known: the settings then are nobody's
    if options.importedFromXitools or not settings.logged_in then
        return
    end
    options.importedFromXitools = true

    if legacy.FromXitools('treas', options, importKeys) then
        Say('Settings brought over from xitools.')
    end
    settings.save()
end

-- Makes good whatever the settings lack, and brings xitools' over where that is still to do
local function PrepareSettings()
    if type(options.hide) ~= 'table' then
        options.hide = T{ }
    end
    if type(options.theme) ~= 'table' then
        options.theme = T{ }
    end

    ImportFromXitools()
    game.CompleteHide(options.hide)
end

PrepareSettings()

-- The treasure window, drawn with winxi's theme. It is there only while there is treasure to show;
-- hidden by the player meanwhile, it goes on being drawn until it has faded out.
local windowName = 'winxi.treas'
local windowStyle = { alpha = 1 }
local lingeringOpen = { true } -- stands in for the window's own switch while it fades out
local currentPool = nil -- what the window shows this frame, for DrawWindow

local function DrawWindow()
    DrawTreasure(currentPool)

    -- where the window is, kept in the settings
    options.pos[1], options.pos[2] = imgui.GetWindowPos()
end

local function DrawTreasureWindow()
    local treasurePool = GetTreasure(options)
    if #treasurePool == 0 then
        WeirdTimestamps = {}
        return
    end

    local wanted = options.isVisible[1]
    local alpha = wanted and 1 or 0
    if options.fadeInOut[1] then
        alpha = fade.Presence(windowName, wanted)
    end
    if alpha <= 0.01 then
        return
    end

    imgui.SetNextWindowPos(options.pos, ImGuiCond_FirstUseEver)

    windowStyle.alpha = alpha
    lingeringOpen[1] = true
    currentPool = treasurePool

    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, itemSpacing)
    window.Full(windowName, wanted and options.isVisible or lingeringOpen, style.TitlelessFlags(), DrawWindow, windowStyle)
    imgui.PopStyleVar()
end

-- The settings window, opened by /treas config
local showConfig = { false }

local function Save()
    settings.save()
end

local appearanceHooks = {
    onUseShared = function(useShared)
        options.useSharedTheme = useShared
        settings.save()
    end,
    onOwnChanged = Save,
}

local function DrawSettings()
    widgets.BeginLabels('treas.settings')
    widgets.Label('Visible')
    imgui.Checkbox('##treas.visible', options.isVisible)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Whether the window shows while there is treasure in the pool. /treas switches this.')
    end
    widgets.Label('Position')
    if imgui.InputInt2('##treas.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos)
    end

    widgets.Gap()
    widgets.Label('Show Empty Slots')
    imgui.Checkbox('##treas.emptySlots', options.showAllSlots)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Lists all ten places in the pool, empty or not: the window is then always there.')
    end

    widgets.Gap()
    widgets.Hide(options.hide, Save)
end

-- The Theme and Window sections are winxi's; the Addon section is what is this addon's own
local function DrawAppearance()
    widgets.Appearance(appearanceHooks)

    widgets.Header('Addon')
    widgets.Label('Fade In And Out')
    imgui.Checkbox('##treas.fadeInOut', options.fadeInOut)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The window fades in as it is shown and out as it is hidden, in place of appearing and going at once.')
    end
end

-- The settings window keeps the default padding, whatever the theme's: the padding slider must not
-- squeeze the window it is in
local configStyle = { padding = theme.Defaults.Padding }
local configFlags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings)

local function DrawConfigContent()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if imgui.BeginTabBar('##treas.config', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if imgui.BeginTabItem('Settings') then
            DrawSettings()
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem('Appearance') then
            DrawAppearance()
            imgui.EndTabItem()
        end
        imgui.EndTabBar()
    end
    imgui.PopStyleVar()
end

local function DrawConfig()
    if not showConfig[1] then
        return
    end

    window.Full('Treasure Settings', showConfig, configFlags, DrawConfigContent, configStyle)
    if not showConfig[1] then
        -- closed by its own button: what was set in it is kept
        settings.save()
    end
end

ashita.events.register('unload', 'treas_unload', function()
    settings.save()
end)

-- Another character's settings have been loaded, or these have been changed from outside
settings.register('settings', 'treas_settings_update', function(s)
    if s ~= nil then
        options = s
    end
    PrepareSettings()
    settings.save()
end)

ashita.events.register('command', 'treas_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/treas' then
        return
    end
    e.blocked = true

    local verb = args[2] and args[2]:lower() or nil
    if verb == nil then
        options.isVisible[1] = not options.isVisible[1]
    elseif verb == 'config' then
        showConfig[1] = not showConfig[1]
    else
        Say('/treas shows or hides the window; /treas config opens or closes the settings.')
    end
end)

ashita.events.register('d3d_present', 'treas_present', function()
    -- every frame, cheaply: nothing happens unless the choice of theme or the settings table has changed
    theme.Configure(options.useSharedTheme, options.theme)

    DrawConfig()

    if game.IsHidden(options.hide) then
        return
    end

    DrawTreasureWindow()
end)
