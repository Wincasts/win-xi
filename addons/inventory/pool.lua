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
local packets = require('winxi.packets')

local pool = {}

local windowName = 'winxi.inventory.pool'
local title = 'Treasure'
local gold = { 1.0, 215/255, 0.0, 1.0 }
local red = { 0.95, 0.20, 0.20, 1.0 }
local framePadding = { 4, 1 }
local poolTime = 300 -- seconds an item stays in the pool

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

local function Lot(item)
    if item.sample or item.lotted or item.passed then
        return
    end
    AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.treasureLot:make(item.slot))
end

local function Pass(item)
    if item.sample or item.passed then
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
local function DrawWindow()
    DrawContent()
    if options.treasureDetached[1] then
        options.treasurePos[1], options.treasurePos[2] = imgui.GetWindowPos()
    end
end

function pool.Draw(drawOptions, at, invShown)
    options = drawOptions
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

    if attachedFlags == nil then
        detachedFlags = style.TitlelessFlags()
        attachedFlags = bit.bor(detachedFlags, ImGuiWindowFlags_NoMove)
    end

    local flags
    if detached then
        imgui.SetNextWindowPos(options.treasurePos, ImGuiCond_FirstUseEver)
        flags = detachedFlags
    else
        placed[1], placed[2] = at[1], at[2]
        imgui.SetNextWindowPos(placed, ImGuiCond_Always)
        flags = attachedFlags
    end
    local width = math.min(600, math.max(200, options.treasureWidth[1]))
    sizeMin[1], sizeMax[1] = width, width
    sizeMin[2], sizeMax[2] = 0, 10000
    imgui.SetNextWindowSizeConstraints(sizeMin, sizeMax)

    window.Full(windowName, open, flags, DrawWindow, windowStyle)
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
        tooltip.Hover('Keeps the pool on screen, while there is treasure, when /inv toggle hides the inventory.\nAttached, it then takes the inventory window\'s place, at its top-left corner, or beside the equipment monitor if that is there too.')
        if drawOptions.treasureDetached[1] then
            widgets.Label('Position')
            imgui.SetNextItemWidth(widgets.NumberWidth(2))
            if imgui.InputInt2('##inv.pool.position', drawOptions.treasurePos) then
                imgui.SetWindowPos(windowName, drawOptions.treasurePos)
            end
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
        widgets.Label('Show When Empty')
        imgui.Checkbox('##inv.pool.showEmpty', drawOptions.treasureShowEmpty)
        tooltip.Hover('Fills an empty pool with sample treasure, to see where it sits and how it looks. Its buttons do nothing.')
    end
end

return pool
