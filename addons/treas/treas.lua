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
--   /treas focus     gives the window the controller, or takes it away again

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
local controller = require('winxi.controller')
local sound = require('winxi.sound')

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
    if treasure.id == 0
    or treasure.current.hasRolled
    or treasure.current.hasPassed then
        return
    end

    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasureLot:make(treasure.slot))
end

local function Pass(treasure)
    if treasure.id == 0 or treasure.current.hasPassed then
        return
    end

    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasurePass:make(treasure.slot))
end

-- Experimental: working the pool with a controller (the Controller Navigation setting).
--
-- The window is there whenever there is treasure, in the middle of a fight as much as after it, so it
-- does not take the controller just by showing: /treas focus (from a macro) gives it the controller
-- and B, or /treas focus again, gives it back. While it has it, up and down move a highlight over the
-- items, A opens a menu for the highlighted one (lot, pass), and Y one for all of them. X (square)
-- is the window cycle's: it gives the window the controller in its turn, and passes it on.
local pad = {
    options = nil,     -- the settings, as of the frame last drawn
    focused = false,   -- whether the window has been given the controller
    drawn = 0,         -- when the window was last drawn
    active = false,    -- as of the frame being drawn
    grid = controller.NewGrid(),
    items = { },       -- the treasure at each place in the grid
    menu = nil,        -- the menu that is open, and the pool slot it is for (none, for the menu for all)
    menuSlot = nil,
    pool = nil,        -- the pool as last drawn, for the menu for all
    bottom = 0,        -- where the last row ends
}

local padColor = imgui.GetColorU32({ 1.0, 0.85, 0.3, 1.0 })

-- Whether the window has the controller: the setting is on, it has been given it, and it is showing
local function PadIsActive()
    local options = pad.options
    return options ~= nil
        and options.controller[1]
        and pad.focused
        and options.isVisible[1]
        and os.clock() - pad.drawn < 0.25
        or false
end

-- What can be done with one item of the pool, as menu entries
local function PadEntries(treasure)
    local entries = { }
    if treasure.id == 0 then
        return entries
    end
    if not treasure.current.hasRolled and not treasure.current.hasPassed then
        entries[#entries + 1] = { label = 'Lot', run = function() Roll(treasure) end }
    end
    if not treasure.current.hasPassed then
        entries[#entries + 1] = { label = 'Pass', run = function() Pass(treasure) end }
    end
    if #entries > 0 then
        entries[#entries + 1] = { label = 'Cancel' }
    end
    return entries
end

-- The menu for the whole pool. Passing on everything is asked about first, with Cancel highlighted.
local function PadAllMenu()
    return controller.NewMenu('All Items', {
        { label = 'Lot All', run = function()
            for _, treasure in ipairs(pad.pool or { }) do
                Roll(treasure)
            end
        end },
        { label = 'Pass All...', run = function()
            return controller.NewMenu('Pass On Everything?', {
                { label = 'Cancel' },
                { label = 'Pass All', run = function()
                    for _, treasure in ipairs(pad.pool or { }) do
                        Pass(treasure)
                    end
                end },
            })
        end },
        { label = 'Cancel' },
    })
end

local function PadPress(action)
    if pad.menu ~= nil then
        pad.menu = pad.menu:Press(action)
        return
    end

    if action == 'up' or action == 'down' then
        pad.grid:Move(action)
    elseif action == 'confirm' then
        local treasure = pad.items[pad.grid.cursor]
        local entries = treasure ~= nil and PadEntries(treasure) or nil
        if entries ~= nil and #entries > 0 then
            pad.menu = controller.NewMenu(treasure.name, entries)
            pad.menuSlot = treasure.slot
            sound.Play('confirm')
        else
            -- an empty place, or an item already passed on
            sound.Play('error')
        end
    elseif action == 'sort' then
        pad.menu = PadAllMenu()
        pad.menuSlot = nil
        sound.Play('confirm')
    elseif action == 'back' then
        -- the controller goes back to the game; the window stays
        pad.focused = false
        sound.Play('back')
    end
end

-- Only the buttons the window has a use for are taken: left, right and the shoulder buttons still
-- reach the game
local padButtons = controller.Button
pad.binding = controller.Bind({
    active = PadIsActive,
    actions = {
        [padButtons.DpadUp] = 'up', [padButtons.DpadDown] = 'down',
        [padButtons.A] = 'confirm', [padButtons.B] = 'back', [padButtons.Y] = 'sort',
        -- kept from the game and nothing more: the window can have the controller while one of the
        -- game's own menus is still open behind it
        [padButtons.DpadLeft] = 'kept', [padButtons.DpadRight] = 'kept',
        [padButtons.LB] = 'kept', [padButtons.RB] = 'kept',
    },
    repeats = { up = true, down = true },
    press = PadPress,
})

-- The treasure pool comes after the inventory in the window cycle: X (square) from the inventory, or
-- from the game's status icons where the inventory is not taking part, gives it the controller, and
-- X again gives the controller back
controller.Cycle({
    order = 2,
    available = function()
        local options = pad.options
        return options ~= nil and options.controller[1] and options.isVisible[1]
            and os.clock() - pad.drawn < 0.25
            or false
    end,
    focused = PadIsActive,
    focus = function()
        pad.focused = true
    end,
    unfocus = function()
        pad.focused = false
    end,
    busy = function()
        return pad.menu ~= nil
    end,
})

-- Starts a frame in which the window is drawn
local function PadBeginFrame(options, treasurePool)
    if options.controllerType ~= nil and options.controllerType ~= controller.GetLayout() then
        controller.SetLayout(options.controllerType)
    end
    sound.SetEnabled(options.controllerSounds[1])

    pad.options = options
    pad.pool = treasurePool
    pad.drawn = os.clock()
    pad.active = PadIsActive()
    if not pad.active then
        pad.menu = nil
    end
    pad.grid:Begin()
end

local padMin, padMax = { 0, 0 }, { 0, 0 }

-- Inside the window, once the rows are drawn: the highlight around the row the controller is on
local function PadDrawHighlight()
    pad.grid:End()
    if not pad.active or pad.grid.count == 0 then
        return
    end

    local cursor = pad.grid.cursor
    local _, top = pad.grid:Position()
    if top == nil then
        return
    end
    local bottom = pad.grid.ys[cursor + 1]
    if cursor >= pad.grid.count or bottom == nil then
        bottom = pad.bottom
    end

    local x = imgui.GetWindowPos()
    local width = imgui.GetWindowSize()
    local inset = style.Padding() - 4
    local drawList = imgui.GetWindowDrawList()
    -- two outlines, one inside the other, for a border two pixels thick
    for grow = 0, 1 do
        padMin[1], padMin[2] = x + inset - grow, top - 2 - grow
        padMax[1], padMax[2] = x + width - inset + grow, bottom - 2 + grow
        drawList:AddRect(padMin, padMax, padColor, 0.0)
    end

    controller.Highlight(pad.binding)
end

-- After the window: the open menu, beside the row it is for
local function PadEndFrame()
    if not pad.active or pad.menu == nil then
        return
    end

    -- an item's menu belongs to the item it was opened for: if that has gone, so does the menu
    local treasure = pad.items[pad.grid.cursor]
    if pad.menuSlot ~= nil and (treasure == nil or treasure.slot ~= pad.menuSlot) then
        pad.menu = nil
        return
    end

    local x, y = pad.grid:Position()
    if x == nil then
        x, y = pad.options.pos[1], pad.options.pos[2]
    end
    pad.menu:Draw(x + 60, y)
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
            -- with the controller: note where the row is, and which item it is
            if pad.active then
                local x, y = imgui.GetCursorScreenPos()
                pad.items[pad.grid:Add(x, y)] = treasure
            end
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

    if pad.active then
        local _, bottom = imgui.GetCursorScreenPos()
        pad.bottom = bottom
        PadDrawHighlight()
    end
end

-- The settings, kept for each character
local defaults = T{
    isVisible = T{ true },
    showAllSlots = T{ false },
    pos = T{ 100, 100 },
    fadeInOut = T{ true }, -- the window fades in as it is shown and out as it is hidden
    controller = T{ false }, -- experimental: work the window with a controller
    controllerSounds = T{ false }, -- sounds as the controller works the window
    controllerType = 'xinput', -- which kind: a key of winxi.controller's Layouts
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

    -- settings saved before the controller was added
    for _, key in ipairs({ 'controller', 'controllerSounds' }) do
        if type(options[key]) ~= 'table' then
            options[key] = T{ false }
        end
    end
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
        -- nothing left to work: the controller goes back to the game
        pad.focused = false
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

    PadBeginFrame(options, treasurePool)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, itemSpacing)
    window.Full(windowName, wanted and options.isVisible or lingeringOpen, style.TitlelessFlags(), DrawWindow, windowStyle)
    imgui.PopStyleVar()
    PadEndFrame()
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
    widgets.Label('Controller Navigation (Experimental)')
    imgui.Checkbox('##treas.controller', options.controller)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Work the treasure pool with a controller.\nThe window does not take the controller by itself. X (square) gives it the controller in its turn, after the game\'s own round of windows (the chat windows, then the status icons) and the inventory; so does /treas focus. B gives it back.\nUp / down: move the highlight.  A: lot or pass on the highlighted item.  Y (triangle): lot or pass on everything.  X: on to the next window.')
    end
    if options.controller[1] then
        widgets.Label('Controller Sounds')
        imgui.Checkbox('##treas.controllerSounds', options.controllerSounds)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Plays a sound as the window takes the controller, the highlight moves, a menu opens, a choice is made or backed out of.')
        end

        widgets.Label('Controller Type')
        local current = controller.GetLayout()
        local column = imgui.GetCursorPosX()
        for index, layout in ipairs(controller.Layouts) do
            if index > 1 then
                -- one to a line, under the first
                imgui.SetCursorPosX(column)
            end
            if imgui.RadioButton(('%s##treas.controllerType'):format(layout.label), current == layout.key) then
                options.controllerType = layout.key
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('XInput is an Xbox controller, or one set to behave as one. DirectInput is anything else: pick the make whose buttons match.')
        end
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
    elseif verb == 'focus' then
        if not options.controller[1] then
            Say('Controller Navigation is off: switch it on in /treas config.')
        elseif pad.focused then
            pad.focused = false
        elseif os.clock() - pad.drawn > 0.25 or not options.isVisible[1] then
            Say('There is no treasure window to work just now.')
        else
            pad.focused = true
        end
    else
        Say('/treas shows or hides the window; /treas config opens or closes the settings; /treas focus gives the window the controller.')
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
