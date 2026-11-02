-- The treasure pool, small, beside the inventory window: what the treas addon shows, in a line for
-- each item. It sits against the right of the inventory window, its top in line with the window's;
-- or, detached in the settings, it is a window of its own that can be moved. Either way it is there
-- while there is treasure and the inventory is shown, or, pinned, whether the inventory is or not:
-- attached, with the inventory hidden, it then takes the inventory's place.
--
--   pool.Draw(options, at, invShown)   once a frame, after the inventory window: at is where the pool
--                               goes attached ({ x, y }, or nil before the inventory has a place),
--                               and invShown whether the inventory window is to be shown
--   pool.DrawSettings(options)  its section of the settings
--
-- With the controller (winventory.lua's cycle brings it here) a highlight goes over the buttons: it
-- starts on the first item's Lot, left and right go between Lot and Pass, up and down between the
-- lines, and up from the first line to Lot All and Pass All. A presses the button the highlight is on.
--
--   pool.Focus(binding)         this frame, the pool has the controller: binding marks its window;
--                               nil, it has not. The highlight is winxi.selection's
--   pool.Reset()                the highlight back on the first item's Lot
--   pool.Shown()                whether the pool was on screen last frame, with treasure in it
--   pool.Move(direction)        the highlight to another button: true if it moved
--   pool.Press()                presses the button the highlight is on: true if anything was sent
--   pool.Highlighted()          the item of the highlighted line, or nil on Lot All and Pass All
--   pool.Place()                where its label goes: beside the pool, level with the highlight
--
-- With Show When Empty an empty pool is filled with sample treasure, in each of the states an item can
-- be in, to see how it looks. Its buttons do nothing.
--
-- Each line: the item, the best lot so far, the time left, and the player's own lot or a button to lot,
-- then a button to pass. The winner's name is in the line's tooltip. Above them, Lot All and Pass All.
local bit = require('bit')
local imgui = require('imgui')
local style = require('winxi.style')
local window = require('winxi.window')
local fade = require('winxi.fade')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local tipwindow = require('tipwindow') -- tooltips go to the Tooltip Window when it is on
local sizing = require('sizing')
local packets = require('winxi.packets')
local controller = require('winxi.controller')
local sound = require('winxi.sound')
local selection = require('winxi.selection')

local pool = {}

local windowName = 'winxi.inventory.pool'
local title = 'Treasure'
local gold = { 1.0, 215/255, 0.0, 1.0 }
local red = { 0.95, 0.20, 0.20, 1.0 }
local framePadding = { 4, 1 }
-- seconds an item stays in the pool: the server's (winxi.rules, from its treasure_pool.cpp), or its
-- five minutes where winxi's data is not installed
local poolTime = 300
do
    local ok, rules = pcall(require, 'winxi.rules')
    local pool = ok and rules.Get('treasurePool') or nil
    poolTime = pool and pool.Seconds or poolTime
end

-- The sample treasure: one the player is winning, one lotted and losing, one others have lotted, one
-- nobody has, one passed on. left is how many seconds it starts with.
local samples = {
    { name = 'Ridill', winnerLot = 874, lot = 874, left = 285 },
    { name = 'Behemoth Hide', winner = 'Ayame', winnerLot = 912, lot = 403, left = 172 },
    { name = 'Dragon Heart', winner = 'Zeid', winnerLot = 655, left = 96 },
    { name = 'Kraken Club', left = 41 },
    { name = 'Fire Crystal', winner = 'Lion', winnerLot = 120, passed = true, left = 230 },
}
local sampleStart = nil -- when the sample treasure was first shown
local options = nil     -- the settings, as of the frame being drawn

-- When each item will leave the pool, by the time it dropped: the game's drop times are not the clock's
local leaves = {}
local itemNames = {} -- resource names do not change when lots or pool slots do

local items = {}   -- the pool this frame, made again each frame from the same tables
local count = 0
for i = 1, 10 do
    items[i] = { lotText = '', winnerLotText = '', timeText = '' }
end

-- With the controller: which button the highlight is on, and where that was drawn, to outline it
-- after the table (a cell's clip would cut the outline to its column)
local pad = {
    binding = nil,      -- this frame: the inventory's binding, while the pool has the controller
    row = 1,            -- 0 for Lot All and Pass All, else the item's line
    column = 1,         -- 1 Lot (Lot All), 2 Pass (Pass All)
    found = false,      -- whether the highlighted button was drawn this frame, at min to max
    min = { 0, 0 }, max = { 0, 0 },
    shown = false,      -- whether the pool was on screen last frame, with treasure in it
    windowX = 0, windowY = 0, windowWidth = 0, windowHeight = 0, -- its window, as last drawn
}

-- Notes where a button (or what stands in a button's place) was drawn, if the highlight is on it
local function Mark(row, column, x1, y1, x2, y2)
    if pad.binding ~= nil and row == pad.row and column == pad.column then
        pad.found = true
        pad.min[1], pad.min[2], pad.max[1], pad.max[2] = x1, y1, x2, y2
    end
end

-- The same, for a cell of the table: as wide as its column and as tall as a button
local function MarkCell(row, column, width)
    if pad.binding ~= nil and row == pad.row and column == pad.column then
        local x, y = imgui.GetCursorScreenPos()
        Mark(row, column, x, y, x + width, y + (imgui.GetFontSize() or 14) + framePadding[2] * 2)
    end
end

local function MarkItem(row, column)
    if pad.binding ~= nil and row == pad.row and column == pad.column then
        local x1, y1 = imgui.GetItemRectMin()
        local x2, y2 = imgui.GetItemRectMax()
        Mark(row, column, x1, y1, x2, y2)
    end
end

-- Each says whether it sent anything
local function Lot(item)
    if item.sample or item.lotted or item.passed then
        return false
    end
    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasureLot:make(item.slot))
    return true
end

local function Pass(item)
    if item.sample or item.passed then
        return false
    end
    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasurePass:make(item.slot))
    return true
end

local function LotAll()
    local sent = false
    for i = 1, count do
        sent = Lot(items[i]) or sent
    end
    return sent
end

local function PassAll()
    local sent = false
    for i = 1, count do
        sent = Pass(items[i]) or sent
    end
    return sent
end

-- The numbers shown are made into words only when they change
local function Number(item, key, textKey, value, format)
    if item[key] ~= value then
        item[key] = value
        item[textKey] = format:format(value)
    end
end

local function Read()
    local res = AshitaCore:GetResourceManager()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local player = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    local now = os.time()

    count = 0
    for slot = 0, 9 do
        local treasure = inv:GetTreasurePoolItem(slot)
        if treasure ~= nil and treasure.ItemId > 0 then
            local name = itemNames[treasure.ItemId]
            if name == nil then
                local info = res:GetItemById(treasure.ItemId)
                if info ~= nil then
                    name = info.Name[1]
                    itemNames[treasure.ItemId] = name
                end
            end
            if leaves[treasure.DropTime] == nil then
                leaves[treasure.DropTime] = now + poolTime
            end

            count = count + 1
            local item = items[count]
            item.sample = false
            item.slot = slot
            item.id = treasure.ItemId
            item.name = name or '?'
            item.winner = treasure.WinningLot > 0 and treasure.WinningEntityName or nil
            item.winning = item.winner ~= nil and item.winner == player
            item.lotted = treasure.Lot > 0 and treasure.Lot < 1000
            item.passed = treasure.Lot > 1000
            Number(item, 'lot', 'lotText', treasure.Lot, '%d')
            Number(item, 'winnerLot', 'winnerLotText', treasure.WinningLot, '%d')
            local left = math.max(0, leaves[treasure.DropTime] - now)
            if item.left ~= left then
                item.left = left
                item.timeText = ('%d:%02d'):format(math.floor(left / 60), left % 60)
            end
        end
    end
    if count == 0 then
        leaves = {}
    end
    if count > 0 or not options.treasureShowEmpty[1] then
        sampleStart = nil
        return
    end

    -- nothing in the pool, and Show When Empty: the sample treasure, its times counting down and
    -- starting again
    sampleStart = sampleStart or now
    for i, sample in ipairs(samples) do
        local item = items[i]
        item.sample = true
        item.slot = i - 1
        item.id = nil -- no icon for made-up treasure
        item.name = sample.name
        item.winner = sample.winner or (sample.winnerLot and player) or nil
        item.winning = item.winner ~= nil and item.winner == player
        item.lotted = sample.lot ~= nil
        item.passed = sample.passed == true
        Number(item, 'lot', 'lotText', sample.lot or 0, '%d')
        Number(item, 'winnerLot', 'winnerLotText', sample.winnerLot or 0, '%d')
        local left = (sample.left - (now - sampleStart)) % poolTime
        if item.left ~= left then
            item.left = left
            item.timeText = ('%d:%02d'):format(math.floor(left / 60), left % 60)
        end
    end
    count = #samples
end

local function Write(item, text)
    if item.passed then
        imgui.TextDisabled(text)
    elseif item.winning then
        imgui.TextColored(gold, text)
    else
        imgui.Text(text)
    end
end

local lotWidth, timeWidth, passWidth = nil, nil, nil

-- What draws a line's tooltip: winventory's, which knows the items (cycle.DrawPoolLine)
local details = nil

function pool.SetDetails(draw)
    details = draw
end

-- Who is winning a line's item, as its tooltip says it under the item: made again only as that changes
function pool.LotLine(item)
    if item.lotLine == nil or item.lotLineBy ~= item.winner or item.lotLineAt ~= item.winnerLotText then
        item.lotLineBy, item.lotLineAt = item.winner, item.winnerLotText
        item.lotLine = item.winner ~= nil and ('Best lot: %s, by %s'):format(item.winnerLotText, item.winner)
            or 'No one has lotted yet.'
    end
    return item.lotLine
end

-- Each slot's Lot and Pass buttons' labels (the pool has ten, 0 to 9), made once rather than every frame
local lotIds, passIds = {}, {}
for slot = 0, 9 do
    lotIds[slot], passIds[slot] = ('Lot##inv.pool.lot%d'):format(slot), ('Pass##inv.pool.pass%d'):format(slot)
end

local measuredAt = nil -- the font size the columns were measured at: again at another (the pool's Scale)

local function DrawContent()
    local fontSize = imgui.GetFontSize()
    if lotWidth == nil or fontSize ~= measuredAt then
        measuredAt = fontSize
        lotWidth = imgui.CalcTextSize('Lot') + framePadding[1] * 2
        timeWidth = imgui.CalcTextSize('0:00')
        passWidth = imgui.CalcTextSize('Pass') + framePadding[1] * 2
        lotWidth = math.max(lotWidth, imgui.CalcTextSize('999'))
    end

    pad.row = math.min(pad.row, count)
    pad.found = false
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if imgui.SmallButton('Lot All##inv.pool.lotAll') then
        LotAll()
    end
    MarkItem(0, 1)
    imgui.SameLine()
    if imgui.SmallButton('Pass All##inv.pool.passAll') then
        PassAll()
    end
    MarkItem(0, 2)

    local flags = bit.bor(ImGuiTableFlags_SizingFixedFit, ImGuiTableFlags_NoPadOuterX)
    if imgui.BeginTable('##inv.pool', 5, flags) then
        imgui.TableSetupColumn('##item', ImGuiTableColumnFlags_WidthStretch)
        imgui.TableSetupColumn('##best', ImGuiTableColumnFlags_WidthFixed, lotWidth)
        imgui.TableSetupColumn('##time', ImGuiTableColumnFlags_WidthFixed, timeWidth)
        imgui.TableSetupColumn('##lot', ImGuiTableColumnFlags_WidthFixed, lotWidth)
        imgui.TableSetupColumn('##pass', ImGuiTableColumnFlags_WidthFixed, passWidth)

        for i = 1, count do
            local item = items[i]
            imgui.TableNextRow()

            imgui.TableNextColumn()
            Write(item, item.name)
            if imgui.IsItemHovered() and details ~= nil then
                -- all there is to say of the item, then who is winning it: in the Tooltip Window, or beside the mouse
                if tipwindow.On() then
                    tipwindow.Offer(details, item, item.id)
                elseif tooltip.Begin() then
                    details(item)
                    tooltip.End()
                end
            end

            imgui.TableNextColumn()
            if item.winner ~= nil then
                Write(item, item.winnerLotText)
            end

            imgui.TableNextColumn()
            if item.left < 60 and not item.passed then
                imgui.TextColored(red, item.timeText)
            else
                Write(item, item.timeText)
            end

            imgui.TableNextColumn()
            MarkCell(i, 1, lotWidth)
            if item.lotted then
                Write(item, item.lotText)
            elseif item.passed then
                imgui.TextDisabled('-')
            elseif imgui.SmallButton(lotIds[item.slot] or ('Lot##inv.pool.lot%d'):format(item.slot)) then
                Lot(item)
            end

            imgui.TableNextColumn()
            MarkCell(i, 2, passWidth)
            if not item.passed and imgui.SmallButton(passIds[item.slot] or ('Pass##inv.pool.pass%d'):format(item.slot)) then
                Pass(item)
            end
        end
        imgui.EndTable()
    end
    imgui.PopStyleVar()

    -- the highlighted button, in the theme's selection box
    if pad.found then
        selection.Draw(imgui.GetWindowDrawList(), pad.min[1], pad.min[2], pad.max[1], pad.max[2])
    end
end

local windowStyle = { alpha = 1, title = title }
local open = { true }
local sizeMin, sizeMax = { 0, 0 }, { 0, 0 }
local placed = { 0, 0 }
local attachedFlags, detachedFlags = nil, nil
local function DrawWindow()
    DrawContent()
    pad.windowX, pad.windowY = imgui.GetWindowPos()
    pad.windowWidth, pad.windowHeight = imgui.GetWindowSize()
    pad.shown = true
    if pad.binding ~= nil then
        controller.Highlight(pad.binding)
    end
    if options.treasureDetached[1] then
        options.treasurePos[1], options.treasurePos[2] = imgui.GetWindowPos()
    end
end

function pool.Draw(drawOptions, at, invShown)
    options = drawOptions
    pad.shown = false
    if not options.treasurePool[1] then
        return
    end

    local detached = options.treasureDetached[1]
    if not detached and at == nil then
        return
    end
    local wanted = invShown or options.treasurePinned[1]
    if not wanted then
        -- Keep drawing during the fade-out, but do not poll a pool that is fully hidden.
        if not options.fadeInOut[1] or not fade.Lingering(windowName) then
            return
        end
    end

    Read()
    local shown = count > 0
    wanted = shown and wanted
    local alpha = wanted and 1 or 0
    if options.fadeInOut[1] then
        alpha = fade.Presence(windowName, wanted)
    end
    if alpha <= 0.01 or not shown then
        return
    end
    windowStyle.alpha = alpha
    -- the inventory's size attached, its own detached
    local scale = sizing.Clamp(detached and options.treasureScale[1] or options.inventoryScale[1])
    windowStyle.fontSize = sizing.FontSize(scale)

    if attachedFlags == nil then
        detachedFlags = style.TitlelessFlags()
        attachedFlags = bit.bor(detachedFlags, ImGuiWindowFlags_NoMove)
    end

    local flags
    if detached then
        imgui.SetNextWindowPos(options.treasurePos, ImGuiCond_FirstUseEver)
        flags = options.treasureLock[1] and attachedFlags or detachedFlags -- locked, held still as attached
    else
        placed[1], placed[2] = at[1], at[2]
        imgui.SetNextWindowPos(placed, ImGuiCond_Always)
        flags = attachedFlags
    end
    local width = math.floor(math.min(600, math.max(200, options.treasureWidth[1])) * scale + 0.5)
    sizeMin[1], sizeMax[1] = width, width
    sizeMin[2], sizeMax[2] = 0, 10000
    imgui.SetNextWindowSizeConstraints(sizeMin, sizeMax)

    window.Full(windowName, open, flags, DrawWindow, windowStyle)
end

-- Drawn this frame: where its window is, x, y, width and height, and how faded it is drawn, for what
-- goes beside or under it (the Tooltip Window, attached); otherwise nil. attachedOnly leaves out a pool
-- detached from the inventory
function pool.Rect(attachedOnly)
    if not pad.shown or (attachedOnly and options.treasureDetached[1]) then
        return nil
    end
    return pad.windowX, pad.windowY, pad.windowWidth, pad.windowHeight, windowStyle.alpha
end

function pool.Focus(binding)
    pad.binding = binding
end

function pool.Shown()
    return pad.shown and count > 0
end

function pool.Reset()
    pad.row, pad.column = 1, 1
end

function pool.Move(direction)
    local row, column = pad.row, pad.column
    if direction == 'up' then
        row = math.max(0, row - 1)
    elseif direction == 'down' then
        row = math.min(count, row + 1)
    elseif direction == 'left' then
        column = 1
    elseif direction == 'right' then
        column = 2
    end
    if row == pad.row and column == pad.column then
        return false
    end
    pad.row, pad.column = row, column
    sound.Play('move')
    return true
end

function pool.Press()
    if not pool.Shown() then
        return false
    end
    if pad.row == 0 then
        return pad.column == 1 and LotAll() or (pad.column == 2 and PassAll())
    end
    local item = items[pad.row]
    if item == nil then
        return false
    end
    if pad.column == 1 then
        return Lot(item)
    end
    return Pass(item)
end

function pool.Highlighted()
    if not pool.Shown() or pad.row < 1 then
        return nil
    end
    return items[math.min(pad.row, count)]
end

-- Beside the pool's right edge, level with the highlighted button
function pool.Place()
    if not pad.found then
        return nil
    end
    return pad.windowX + pad.windowWidth + 6, pad.min[2]
end

-- Its tab of the settings: what turns it on, whether it is attached to the inventory window, its pin
-- and where it is; then how it looks
function pool.DrawSettings(drawOptions)
    if widgets.Header('Treasure Pool', true) then
        widgets.Label('Enable')
        imgui.Checkbox('##inv.pool.show', drawOptions.treasurePool)
        tooltip.Hover('The treasure pool, a line for each item, with buttons to lot and pass. It is there only while there is treasure.')
        if not drawOptions.treasurePool[1] then
            return
        end
        widgets.Label('Detach From Inventory')
        imgui.Checkbox('##inv.pool.detached', drawOptions.treasureDetached)
        tooltip.Hover('Attached, the pool sits to the right of the inventory window.\nDetached, it is a window of its own that can be moved.\nEither way it shows while there is treasure and the inventory does, or, pinned, whether the inventory does or not.')
        widgets.Label('Pin Treasure Pool')
        imgui.Checkbox('##inv.pool.pinned', drawOptions.treasurePinned)
        tooltip.Hover('Keeps the pool on screen, while there is treasure, when /winventory toggle hides the inventory.\nAttached, it then takes the inventory window\'s place, at its top-left corner, or beside the equipment monitor if that is there too.')
        if drawOptions.treasureDetached[1] then
            widgets.Label('Position')
            imgui.SetNextItemWidth(widgets.NumberWidth(2))
            if imgui.InputInt2('##inv.pool.position', drawOptions.treasurePos) then
                imgui.SetWindowPos(windowName, drawOptions.treasurePos)
            end
            widgets.Label('Lock')
            imgui.Checkbox('##inv.pool.lock', drawOptions.treasureLock)
            tooltip.Hover('Prevent dragging the pool. The Position fields can still move it.')
        end
    end
    if not drawOptions.treasurePool[1] then
        return
    end

    if widgets.Header('Display') then
        widgets.Label('Width')
        imgui.SetNextItemWidth(widgets.NumberWidth(1))
        imgui.InputInt('##inv.pool.width', drawOptions.treasureWidth, 0, 0)
        tooltip.Hover('How wide the pool is, in pixels, from 200 to 600.')
        widgets.Label('Scale')
        imgui.BeginDisabled(not drawOptions.treasureDetached[1])
        imgui.SliderFloat('##inv.pool.scale', drawOptions.treasureScale, sizing.Least, sizing.Most, '%.2fx')
        imgui.EndDisabled()
        tooltip.Hover('How big the detached pool and its words are, its width included.\nAttached, it is the inventory\'s Scale.')
        widgets.Label('Show When Empty')
        imgui.Checkbox('##inv.pool.showEmpty', drawOptions.treasureShowEmpty)
        tooltip.Hover('Fills an empty pool with sample treasure, to see where it sits and how it looks. Its buttons do nothing.')
    end
end

return pool
