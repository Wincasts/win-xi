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
local style = require('winxi.style')
local widgets = require('winxi.widgets')
local shell = require('winxi.shell')
local packets = require('winxi.packets')
local controller = require('winxi.controller')
local sound = require('winxi.sound')

local TextBaseWidth = imgui.CalcTextSize('A')
local WeirdTimestamps = {}

local gold = { 1.0, 215/255, 0.0, 1.0 }

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
-- items, A opens a menu for the highlighted one (lot, pass), and X one for all of them.
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
        [padButtons.A] = 'confirm', [padButtons.B] = 'back', [padButtons.X] = 'sort',
    },
    repeats = { up = true, down = true },
    press = PadPress,
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

-- The settings, kept for each character. The shell adds its own: fading in and out, the rules for
-- hiding, the theme.
local defaults = T{
    isVisible = T{ true },
    showAllSlots = T{ false },
    pos = T{ 100, 100 },
    controller = T{ false }, -- experimental: work the window with a controller
    controllerSounds = T{ false }, -- sounds as the controller works the window
    controllerType = 'xinput', -- which kind: a key of winxi.controller's Layouts
}

local windowName = 'winxi.treas'
local controllerTooltip = 'Work the treasure pool with a controller.\nThe window does not take the controller by itself: /treas focus (from a macro) gives it the controller, and B gives it back.\nUp / down: move the highlight.  A: lot or pass on the highlighted item.  X (square): lot or pass on everything.\nOnly those buttons are kept from the game, and only while the window has the controller.'

local function DrawSettings(options)
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
    shell.ControllerSettings(options, controllerTooltip)
end

-- The settings, the settings window, the command and the main window's frame are the shell's. The
-- treasure pool was a tool of xitools, which kept its settings among its own: the shell brings them
-- over once for each character, with xitools' theme and rules for hiding.
local app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Treasure Settings',
    command = '/treas',
    help = '/treas shows or hides the window; /treas config opens or closes the settings; /treas focus gives the window the controller.',
    drawSettings = DrawSettings,
    import = { tool = 'treas', keys = { 'isVisible', 'showAllSlots', 'pos' } },
    onSettings = function(options)
        -- settings saved before the controller was added
        for _, key in ipairs({ 'controller', 'controllerSounds' }) do
            if type(options[key]) ~= 'table' then
                options[key] = T{ false }
            end
        end
    end,
    commands = {
        focus = function(options)
            if not options.controller[1] then
                Say('Controller Navigation is off: switch it on in /treas config.')
            elseif pad.focused then
                pad.focused = false
            elseif os.clock() - pad.drawn > 0.25 or not options.isVisible[1] then
                Say('There is no treasure window to work just now.')
            else
                pad.focused = true
            end
        end,
    },
})

-- What the window shows this frame, for DrawWindow
local currentPool = nil

local function DrawWindow()
    DrawTreasure(currentPool)
end

ashita.events.register('d3d_present', 'treas_present', function()
    if not app:BeginFrame() then
        return
    end
    local options = app.options

    -- the window is there only while there is treasure to show
    local treasurePool = GetTreasure(options)
    if #treasurePool == 0 then
        WeirdTimestamps = {}
        -- nothing left to work: the controller goes back to the game
        pad.focused = false
        return
    end

    currentPool = treasurePool
    PadBeginFrame(options, treasurePool)
    app:Window(options.isVisible, DrawWindow)
    PadEndFrame()
end)
