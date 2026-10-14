-- The treasure pool, small, under the inventory window: what the treas addon shows, in a line for each
-- item. It sits against the foot of the inventory window, as wide as it, and comes and goes with it;
-- or, detached in the settings, it is a window of its own that is there whenever there is treasure.
--
--   pool.Draw(options, frame, invWanted)   once a frame, after the inventory window: frame is where
--                               that window is ({ x, y, width, height }, or nil before it is first
--                               drawn), and invWanted whether it is switched on
--   pool.Bottom()               where the pool's window ends, this frame, while it is attached; or nil
--   pool.DrawSettings(options)  its section of the settings
--
-- Each line: the item, the best lot so far, the time left, and the player's own lot or a button to lot,
-- then a button to pass. The winner's name is in the line's tooltip. Above them, Lot All and Pass All.
local bit = require('bit')
local imgui = require('imgui')
local style = require('winxi.style')
local window = require('winxi.window')
local fade = require('winxi.fade')
local theme = require('winxi.theme')
local widgets = require('winxi.widgets')
local packets = require('winxi.packets')

local pool = {}

local windowName = 'winxi.inv.pool'
local title = 'Treasure'
local gold = { 1.0, 215/255, 0.0, 1.0 }
local red = { 0.95, 0.20, 0.20, 1.0 }
local framePadding = { 4, 1 }
local poolTime = 300 -- seconds an item stays in the pool

-- When each item will leave the pool, by the time it dropped: the game's drop times are not the clock's
local leaves = {}

local items = {}   -- the pool this frame, made again each frame from the same tables
local count = 0
for i = 1, 10 do
    items[i] = { lotText = '', winnerLotText = '', timeText = '' }
end

local function Lot(item)
    if item.lotted or item.passed then
        return
    end
    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasureLot:make(item.slot))
end

local function Pass(item)
    if item.passed then
        return
    end
    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasurePass:make(item.slot))
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
            local info = res:GetItemById(treasure.ItemId)
            if leaves[treasure.DropTime] == nil then
                leaves[treasure.DropTime] = now + poolTime
            end

            count = count + 1
            local item = items[count]
            item.slot = slot
            item.name = info ~= nil and info.Name[1] or '?'
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

local function DrawContent()
    if lotWidth == nil then
        lotWidth = imgui.CalcTextSize('Lot') + framePadding[1] * 2
        timeWidth = imgui.CalcTextSize('0:00')
        passWidth = imgui.CalcTextSize('Pass') + framePadding[1] * 2
        lotWidth = math.max(lotWidth, imgui.CalcTextSize('999'))
    end

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if imgui.SmallButton('Lot All##inv.pool.lotAll') then
        for i = 1, count do
            Lot(items[i])
        end
    end
    imgui.SameLine()
    if imgui.SmallButton('Pass All##inv.pool.passAll') then
        for i = 1, count do
            Pass(items[i])
        end
    end

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
            if imgui.IsItemHovered() then
                if item.winner ~= nil then
                    imgui.SetTooltip(('%s\nBest lot: %s, by %s'):format(item.name, item.winnerLotText, item.winner))
                else
                    imgui.SetTooltip(('%s\nNo one has lotted yet.'):format(item.name))
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
            if item.lotted then
                Write(item, item.lotText)
            elseif item.passed then
                imgui.TextDisabled('-')
            elseif imgui.SmallButton(('Lot##inv.pool.lot%d'):format(item.slot)) then
                Lot(item)
            end

            imgui.TableNextColumn()
            if not item.passed and imgui.SmallButton(('Pass##inv.pool.pass%d'):format(item.slot)) then
                Pass(item)
            end
        end
        imgui.EndTable()
    end
    imgui.PopStyleVar()
end

local windowStyle = { alpha = 1, title = title }
local open = { true }
local sizeMin, sizeMax = { 0, 0 }, { 0, 0 }
local placed = { 0, 0 }
local attachedFlags, detachedFlags = nil, nil
local bottom = nil
local options = nil

local function DrawWindow()
    DrawContent()
    local x, y = imgui.GetWindowPos()
    local _, height = imgui.GetWindowSize()
    if options.treasureDetached[1] then
        options.treasurePos[1], options.treasurePos[2] = x, y
    else
        bottom = y + height
    end
end

-- The room the pool's title needs above it, half of which stands out over the window's top edge
local function TitleRoom()
    local current = theme.Get()
    if not current.FrameTitles then
        return 4
    end
    local size = tonumber(current.TitleSize) or 0
    if size <= 0 then
        size = imgui.GetFontSize()
    end
    return math.ceil(size / 2) + 4 - math.min(0, tonumber(current.TitleOffsetY) or 0)
end

function pool.Bottom()
    return bottom
end

function pool.Draw(drawOptions, frame, invWanted)
    options = drawOptions
    bottom = nil
    if not options.treasurePool[1] then
        return
    end

    Read()
    local detached = options.treasureDetached[1]
    if not detached and frame == nil then
        return
    end
    local wanted = count > 0 and (detached or invWanted)
    local alpha = wanted and 1 or 0
    if options.fadeInOut[1] then
        alpha = fade.Presence(windowName, wanted)
    end
    if alpha <= 0.01 or count == 0 then
        return
    end
    windowStyle.alpha = alpha

    if attachedFlags == nil then
        detachedFlags = style.TitlelessFlags()
        attachedFlags = bit.bor(detachedFlags, ImGuiWindowFlags_NoMove)
    end

    local flags
    if detached then
        imgui.SetNextWindowPos(options.treasurePos, ImGuiCond_FirstUseEver)
        sizeMin[1], sizeMax[1] = options.treasureWidth[1], options.treasureWidth[1]
        flags = detachedFlags
    else
        placed[1], placed[2] = frame.x, frame.y + frame.height + TitleRoom()
        imgui.SetNextWindowPos(placed, ImGuiCond_Always)
        sizeMin[1], sizeMax[1] = frame.width, frame.width
        flags = attachedFlags
    end
    sizeMin[2], sizeMax[2] = 0, 10000
    imgui.SetNextWindowSizeConstraints(sizeMin, sizeMax)

    window.Full(windowName, open, flags, DrawWindow, windowStyle)
end

function pool.DrawSettings(drawOptions)
    if not widgets.Header('Treasure Pool') then
        return
    end
    widgets.Label('Show Treasure Pool')
    imgui.Checkbox('##inv.pool.show', drawOptions.treasurePool)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The treasure pool, a line for each item, with buttons to lot and pass. It is there only while there is treasure.')
    end
    if not drawOptions.treasurePool[1] then
        return
    end

    widgets.Label('Detach From Inventory')
    imgui.Checkbox('##inv.pool.detached', drawOptions.treasureDetached)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Attached, the pool sits under the inventory window, as wide as it, and shows only while the inventory does.\nDetached, it is a window of its own that can be moved, and shows whenever there is treasure.')
    end
    if drawOptions.treasureDetached[1] then
        widgets.Label('Treasure Position')
        if imgui.InputInt2('##inv.pool.position', drawOptions.treasurePos) then
            imgui.SetWindowPos(windowName, drawOptions.treasurePos)
        end
        widgets.Label('Treasure Width')
        imgui.SliderInt('##inv.pool.width', drawOptions.treasureWidth, 200, 600)
    end
end

return pool
