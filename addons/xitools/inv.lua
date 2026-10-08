require('common')
local bit = require('bit')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local ffxi = require('utils/ffxi')
local debounce = require('utils/debounce')
local packets = require('utils/packets')
local imgui = require('imgui')
local ui = require('ui')
local controller = require('winxi.controller')
local sound = require('winxi.sound')

local textures = { }
local gfxDevice = d3d8.get_device()
local fontWidth = imgui.CalcTextSize('A')
local inventories = T{
    gil = 0,
    bag = T{
        all  = T{},
        inv  = T{},
        temp = T{},
    },
    satchel = T{
        all = T{},
        satchel = T{},
        case = T{},
        sack = T{},
    },
    wardrobe = T{
        all = T{},
        wardrobe1 = T{},
        wardrobe2 = T{},
        wardrobe3 = T{},
        wardrobe4 = T{},
        wardrobe5 = T{},
        wardrobe6 = T{},
        wardrobe7 = T{},
        wardrobe8 = T{},
    },
    house = T{
        all = T{},
        mogSafe1 = T{},
        mogSafe2 = T{},
        storage = T{},
        mogLocker = T{},
    },
}

-- How many slots each bag has, by group and bag as inventories is (and 'all' for a group's bags
-- together). Filled in by UpdateInventories.
local capacities = { bag = { }, satchel = { }, wardrobe = { }, house = { } }

-- Puts together the row at the foot of each tab; defined with the row, further down
local BuildCounts

-- Whether a spot is drawn for each empty slot as well: the Show Empty Slots setting, as of this frame
local showEmptySlots = false

local itemTypes = {
    misc       = 1,
    weapon     = 4,
    armor      = 5,
    consumable = 7,
}

local slots = {
    [    1] = 'Main',
    [    2] = 'Sub',
    [    3] = 'Weapon',
    [    4] = 'Range',
    [    8] = 'Ammo',
    [   16] = 'Head',
    [   32] = 'Body',
    [   64] = 'Hands',
    [  128] = 'Legs',
    [  256] = 'Feet',
    [  512] = 'Neck',
    [ 1024] = 'Waist',
    [ 2048] = 'L.Ear',
    [ 4096] = 'R.Ear',
    [ 6144] = 'Earring',
    [ 8192] = 'L.Ring',
    [16384] = 'R.Ring',
    [24576] = 'Ring',
    [32768] = 'Back',
}

local skills = {
    [ 1] = 'Fists',
    [ 2] = 'Dagger',
    [ 3] = 'Sword',
    [ 4] = 'Great Sword',
    [ 5] = 'Axe',
    [ 6] = 'Great Axe',
    [ 7] = 'Scythe',
    [ 8] = 'Polearm',
    [ 9] = 'Katana',
    [10] = 'Great Katana',
    [11] = 'Club',
    [12] = 'Staff',
    [25] = 'Bow',
    [26] = 'Crossbow',
    [27] = 'Throwable',
    -- [28] = 'Guarding',
    -- [29] = 'Evasion',
    [30] = 'Shield',
    -- [31] = 'Parrying',
    -- [32] = 'Divine',
    -- [33] = 'Healing',
    -- [34] = 'Enhancing',
    -- [35] = 'Enfeebling',
    -- [36] = 'Elemental',
    -- [37] = 'Dark',
    -- [38] = 'Summoning',
    -- [39] = 'Ninjutsu',
    [40] = 'Instrument',
    [41] = 'Instrument',
    [42] = 'Instrument',
    -- [43] = 'Blue',
    -- [44] = 'Geomancy',
}

local jobs = {
    [ 1] = 'WAR',
    [ 2] = 'MNK',
    [ 3] = 'WHM',
    [ 4] = 'BLM',
    [ 5] = 'RDM',
    [ 6] = 'THF',
    [ 7] = 'PLD',
    [ 8] = 'DRK',
    [ 9] = 'BST',
    [10] = 'BRD',
    [11] = 'RNG',
    [12] = 'SAM',
    [13] = 'NIN',
    [14] = 'DRG',
    [15] = 'SMN',
    [16] = 'BLU',
    [17] = 'COR',
    [18] = 'PUP',
    [19] = 'DNC',
    [20] = 'SCH',
    [21] = 'GEO',
    [22] = 'RUN',
}

local bags = {
    inventory      = 0,
    mogSafe        = 1,
    storage        = 2,
    tempItems      = 3,
    mogLocker      = 4,
    mogSatchel     = 5,
    mogSack        = 6,
    mogCase        = 7,
    wardrobe       = 8,
    mogSafe2       = 9,
    wardrobe2      = 10,
    wardrobe3      = 11,
    wardrobe4      = 12,
    wardrobe5      = 13,
    wardrobe6      = 14,
    wardrobe7      = 15,
    wardrobe8      = 16,
    recycleBin     = 17,
    maxContainerId = 18,
}

local moveableBags = {
    { id =  0, hasAccess = false, isGearOnly = false, name = 'inventory' },
    { id =  5, hasAccess = false, isGearOnly = false, name = 'satchel' },
    { id =  6, hasAccess = false, isGearOnly = false, name = 'sack' },
    { id =  7, hasAccess = false, isGearOnly = false, name = 'case' },
    { id =  8, hasAccess = false, isGearOnly = true,  name = 'wardrobe 1' },
    { id = 10, hasAccess = false, isGearOnly = true,  name = 'wardrobe 2' },
    { id = 11, hasAccess = false, isGearOnly = true,  name = 'wardrobe 3' },
    { id = 12, hasAccess = false, isGearOnly = true,  name = 'wardrobe 4' },
    { id = 13, hasAccess = false, isGearOnly = true,  name = 'wardrobe 5' },
    { id = 14, hasAccess = false, isGearOnly = true,  name = 'wardrobe 6' },
    { id = 15, hasAccess = false, isGearOnly = true,  name = 'wardrobe 7' },
    { id = 16, hasAccess = false, isGearOnly = true,  name = 'wardrobe 8' },
}

local function FormatGil(number)
    local str = tostring(number)
    local len = #str
    local numSeps = math.ceil((len / 3) - 1)
    local strTbl = str:explode()
    for i = 1, numSeps do
        table.insert(strTbl, len - (3 * i) + 1, ',')
    end
    return strTbl:join('')
end

local function CreateTexture(bitmap, size)
    local c = ffi.C
    local texturePtr = ffi.new('IDirect3DTexture8*[1]')

    local width = 0xFFFFFFFF
    local height = 0xFFFFFFFF
    local mipLevels = 1
    local usage = 0
    local colorKey = 0xFF000000

    local textureSuccess = c.D3DXCreateTextureFromFileInMemoryEx(
        gfxDevice,
        bitmap,
        size,
        width,
        height,
        mipLevels,
        usage,
        c.D3DFMT_A8R8G8B8,
        c.D3DPOOL_MANAGED,
        c.D3DX_DEFAULT,
        c.D3DX_DEFAULT,
        colorKey,
        nil,
        nil,
        texturePtr)

    if textureSuccess == c.S_OK then
        return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texturePtr[0]))
    else
        return nil
    end
end

local function EscapeString(str)
    -- shamelessly stolen from Shinzaku's GearFinder
    if str then
        return str:
            replace('\x81\x60', '~'):
            replace('\xEF\x1F', 'Fire Res'):
            replace('\xEF\x20', 'Ice Res'):
            replace('\xEF\x21', 'Wind Res'):
            replace('\xEF\x22', 'Earth Res'):
            replace('\xEF\x23', 'Ltng Res'):
            replace('\xEF\x24', 'Water Res'):
            replace('\xEF\x25', 'Light Res'):
            replace('\xEF\x26', 'Dark Res'):
            replace('\x25',     '%')
    end

    return ''
end

local function GetJobs(bitfield)
    if bitfield == 8388606 then
        return T{ 'All jobs' }
    end

    local jobList = T{}
    for i = 1, 23 do
        if bit.band(1, bit.rshift(bitfield, i)) == 1 then
            table.insert(jobList, jobs[i])
        end
    end
    return jobList
end

local function GetSlots(bitfield, skill)
    if bitfield <= 3 then
        return skills[skill]
    else
        return slots[bitfield]
    end
end

local function SortInventory(lhs, rhs)
    if lhs.sortId == rhs.sortId then
        if lhs.id == rhs.id then
            return lhs.stackCur > rhs.stackCur
        end

        return lhs.id < rhs.id
    end

    return lhs.sortId < rhs.sortId
end

local function UpdateInventory(inv, res, bagId)
    local inventory = T{ }
    local itemCount = inv:GetContainerCountMax(bagId)

    for i = 0, itemCount do
        local invItem = inv:GetContainerItem(bagId, i)
        local itemRes = res:GetItemById(invItem.Id)

        if itemRes ~= nil and invItem.Id ~= 65535 then
            if textures[invItem.Id] == nil then
                textures[invItem.Id] = CreateTexture(itemRes.Bitmap, itemRes.ImageSize)
            end

            local coolItem = {
                id = invItem.Id,
                bagId = bagId,
                sortId = itemRes.ResourceId,
                slotId = invItem.Index,
                uniqueId = ('%i.%i.%s'):format(bagId, invItem.Index, itemRes.Name[1]),
                type = itemRes.Type,
                flags = itemRes.Flags,
                targets = itemRes.Targets,
                isUsable = bit.band(1, bit.rshift(itemRes.Flags, 10)) == 1,
                isMoveable = true,
                isTradeable = true,
                isLocked = bit.band(1, invItem.Flags) == 1 or bagId > 0,
                isEquippable = itemRes.Type == 4 or itemRes.Type == 5,
                name = ('%s [%i]'):format(itemRes.LogNameSingular[1], invItem.Id),
                shortName = itemRes.Name[1],
                longNameS = itemRes.LogNameSingular[1],
                longNameP = itemRes.LogNamePlural[1],
                desc = EscapeString(itemRes.Description[1]),
                stack = nil,
                stackCur = invItem.Count,
                stackMax = itemRes.StackSize,
                level = nil,
                jobs = nil,
                iconPtr = tonumber(ffi.cast('uint32_t', textures[invItem.Id]))
            }

            if coolItem.stackMax > 1 then
                coolItem.stack = ('%i / %i'):format(coolItem.stackCur, coolItem.stackMax)
                coolItem.stackText = tostring(coolItem.stackCur or 0) -- drawn over the icon
            end

            if coolItem.type == itemTypes.armor
            or coolItem.type == itemTypes.weapon then
                local itemSlots = GetSlots(itemRes.Slots, itemRes.Skill)
                local itemJobs = GetJobs(itemRes.Jobs)
                coolItem.level = ('Lv %i %s'):format(itemRes.Level, itemSlots)
                coolItem.jobs = itemJobs:join(', ')
                coolItem.slots = itemRes.Slots
            end

            inventory:append(coolItem)
        end
    end

    return inventory
end

local function UpdateInventories()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local res = AshitaCore:GetResourceManager()
    local gil = inv:GetContainerItem(0, 0)
    local invSize = inv:GetContainerCountMax(0)
    if gil == nil or invSize == 0 then return end

    for _, bag in ipairs(moveableBags) do
        if bag.id > 10 then
            bag.hasAccess = ffxi.HasBagAccess(bag.id)
        else
            bag.hasAccess = inv:GetContainerCountMax(bag.id) > 0
        end
    end

    inventories.gil = FormatGil(gil.Count)
    inventories.bag.inv = UpdateInventory(inv, res, bags.inventory):sort(SortInventory)
    inventories.bag.temp = UpdateInventory(inv, res, bags.tempItems):sort(SortInventory)
    inventories.satchel.satchel = UpdateInventory(inv, res, bags.mogSatchel):sort(SortInventory)
    inventories.satchel.case = UpdateInventory(inv, res, bags.mogCase):sort(SortInventory)
    inventories.satchel.sack = UpdateInventory(inv, res, bags.mogSack):sort(SortInventory)
    inventories.wardrobe.wardrobe1 = UpdateInventory(inv, res, bags.wardrobe):sort(SortInventory)
    inventories.wardrobe.wardrobe2 = UpdateInventory(inv, res, bags.wardrobe2):sort(SortInventory)
    inventories.wardrobe.wardrobe3 = UpdateInventory(inv, res, bags.wardrobe3):sort(SortInventory)
    inventories.wardrobe.wardrobe4 = UpdateInventory(inv, res, bags.wardrobe4):sort(SortInventory)
    inventories.wardrobe.wardrobe5 = UpdateInventory(inv, res, bags.wardrobe5):sort(SortInventory)
    inventories.wardrobe.wardrobe6 = UpdateInventory(inv, res, bags.wardrobe6):sort(SortInventory)
    inventories.wardrobe.wardrobe7 = UpdateInventory(inv, res, bags.wardrobe7):sort(SortInventory)
    inventories.wardrobe.wardrobe8 = UpdateInventory(inv, res, bags.wardrobe8):sort(SortInventory)
    inventories.house.mogSafe1 = UpdateInventory(inv, res, bags.mogSafe):sort(SortInventory)
    inventories.house.mogSafe2 = UpdateInventory(inv, res, bags.mogSafe2):sort(SortInventory)
    inventories.house.storage = UpdateInventory(inv, res, bags.storage):sort(SortInventory)
    inventories.house.locker = UpdateInventory(inv, res, bags.mogLocker):sort(SortInventory)

    inventories.bag.all = T{}
        :extend(inventories.bag.inv)
        :extend(inventories.bag.temp)
        :sort(SortInventory)

    inventories.satchel.all = T{}
        :extend(inventories.satchel.satchel)
        :extend(inventories.satchel.case)
        :extend(inventories.satchel.sack)
        :sort(SortInventory)

    inventories.wardrobe.all = T{}
        :extend(inventories.wardrobe.wardrobe1)
        :extend(inventories.wardrobe.wardrobe2)
        :extend(inventories.wardrobe.wardrobe3)
        :extend(inventories.wardrobe.wardrobe4)
        :extend(inventories.wardrobe.wardrobe5)
        :extend(inventories.wardrobe.wardrobe6)
        :extend(inventories.wardrobe.wardrobe7)
        :extend(inventories.wardrobe.wardrobe8)
        :sort(SortInventory)

    inventories.house.all = T{}
        :extend(inventories.house.mogSafe1)
        :extend(inventories.house.mogSafe2)
        :extend(inventories.house.storage)
        :extend(inventories.house.locker)
        :sort(SortInventory)

    -- How many slots each bag has, for showing the empty ones. Temporary items have no fixed slots
    -- worth showing, and a bag the player cannot use has none.
    local function Slots(bagId)
        if bagId >= bags.wardrobe3 and bagId <= bags.wardrobe8 and not ffxi.HasBagAccess(bagId) then
            return 0
        end
        return math.max(0, inv:GetContainerCountMax(bagId))
    end

    capacities.bag = { inv = Slots(bags.inventory), temp = 0 }
    capacities.satchel = { satchel = Slots(bags.mogSatchel), case = Slots(bags.mogCase), sack = Slots(bags.mogSack) }
    capacities.wardrobe = {
        wardrobe1 = Slots(bags.wardrobe), wardrobe2 = Slots(bags.wardrobe2), wardrobe3 = Slots(bags.wardrobe3),
        wardrobe4 = Slots(bags.wardrobe4), wardrobe5 = Slots(bags.wardrobe5), wardrobe6 = Slots(bags.wardrobe6),
        wardrobe7 = Slots(bags.wardrobe7), wardrobe8 = Slots(bags.wardrobe8),
    }
    capacities.house = {
        mogSafe1 = Slots(bags.mogSafe), mogSafe2 = Slots(bags.mogSafe2),
        storage = Slots(bags.storage), locker = Slots(bags.mogLocker),
    }

    -- the unified view of a group has the slots of all its bags together
    for _, group in pairs(capacities) do
        local total = 0
        for _, slots in pairs(group) do
            total = total + slots
        end
        group.all = total
    end

    BuildCounts()
end

-- What can be done with an item. Each is offered by the right-click menu, and by the controller's.
local function UseItem(item)
    local target = '<me>'

    -- target determination courtesy of Thorny's thotbar
    local targetsOthers = bit.band(item.targets, 0xFC) ~= 0
    if targetsOthers then
        target = '<t>'
    end

    AshitaCore:GetChatManager():QueueCommand(1, ('/item "%s" %s'):format(item.shortName, target))
end

local function TradeItem(item)
    AshitaCore:GetChatManager():QueueCommand(1, ('/item "%s" <t>'):format(item.shortName))
end

local function EquipItem(item, slotName)
    AshitaCore:GetChatManager():QueueCommand(1, ('/equip %s "%s"'):format(slotName, item.shortName))
end

local function MoveItem(item, bag)
    AshitaCore:GetPacketManager():AddOutgoingPacket(
        packets.outbound.inventoryMove:make(item.stackCur, item.bagId, bag.id, item.slotId))
end

local function DropItem(item)
    AshitaCore:GetPacketManager():AddOutgoingPacket(
        packets.outbound.inventoryDrop:make(item.stackCur, 0, item.slotId))
end

-- The names of the slots an item can be equipped to
local function EquipSlots(item)
    local names = { }
    for i = 0, 16 do
        local slot = bit.band(item.slots or 0, bit.lshift(1, i))
        if slot > 0 and slots[slot] then
            names[#names + 1] = slots[slot]
        end
    end
    return names
end

-- Whether an item can be moved to a bag: one the player has, other than the one it is in, and not a
-- gear-only bag unless it is gear
local function CanMoveTo(item, bag)
    return bag.hasAccess
        and bag.id ~= item.bagId
        and (not bag.isGearOnly or bag.isGearOnly and item.isEquippable)
end

local function DropLabel(item)
    local itemName = item.longNameS
    if item.stackCur > 1 then
        itemName = item.longNameP
    end
    return ('Drop %i %s'):format(item.stackCur, itemName)
end

local function TryToUse(item)
    if imgui.Selectable('Use') then
        UseItem(item)
    end
end

local function TryToTrade(item)
    if imgui.Selectable('Trade') then
        TradeItem(item)
    end
end

local function TryToEquip(item)
    for _, slotName in ipairs(EquipSlots(item)) do
        if imgui.Selectable(('Equip to %s'):format(slotName)) then
            EquipItem(item, slotName)
        end
    end
end

local function TryToMove(item)
    if imgui.BeginMenu('Move') then
        for _, bag in ipairs(moveableBags) do
            if CanMoveTo(item, bag) and imgui.MenuItem(('to %s'):format(bag.name)) then
                MoveItem(item, bag)
            end
        end

        imgui.EndMenu()
    end
end

local function TryToDrop(item)
    if imgui.BeginMenu('Drop') then
        -- TODO: add quantity picker

        if imgui.MenuItem(DropLabel(item)) then
            DropItem(item)
        end

        imgui.EndMenu()
    end
end

-- The colours of a stack's size, worked out once a frame (they take in the window's fade) rather than
-- for every item, and the tables for where it goes, used again for each
local stackWhite, stackBlack = { 1, 1, 1, 1 }, { 0, 0, 0, 1 }
local stackMain, stackShadow = 0, 0
local stackPos, stackShadowPos = { 0, 0 }, { 0, 0 }

local function AddStackSize(posX, posY, text, drawList)
    stackShadowPos[1], stackShadowPos[2] = posX + 1, posY + 1
    stackPos[1], stackPos[2] = posX, posY
    drawList:AddText(stackShadowPos, stackShadow, text)
    drawList:AddText(stackPos, stackMain, text)
end

local highlightColor = imgui.GetColorU32({ 0.23, 0.67, 0.91, 1.0 })
local function AddHighlight(posX, posY, size, drawList)
    local pad = 2
    local upperLeft = { posX - pad, posY - pad }
    local bottomRight = { posX + size + pad, posY + size + pad }
    drawList:AddRect(upperLeft, bottomRight, highlightColor, 0.0)
end

local function AddTooltip(item)
    imgui.BeginTooltip()

    imgui.PushTextWrapPos(fontWidth * 64)
    imgui.Text(item.name)
    imgui.Text(item.desc)
    imgui.PopTextWrapPos()

    if item.stack then
        imgui.Text(item.stack)
    end

    imgui.PushTextWrapPos(fontWidth * 40)
    if item.level then
        imgui.Text(item.level)
    end
    if item.jobs then
        imgui.Text(item.jobs)
    end
    imgui.PopTextWrapPos()

    imgui.EndTooltip()
end

local function AddFullCtxMenu(item)
    local menuOpened = false
    local menuOpenable = item.isUsable or item.isMoveable or item.isEquippable or not item.isLocked

    if menuOpenable and imgui.BeginPopupContextItem(item.uniqueId) then
        menuOpened = true

        if item.isUsable then
            TryToUse(item)
        end

        if item.isTradeable then
            TryToTrade(item)
        end

        if item.isEquippable then
            TryToEquip(item)
        end

        if item.isMoveable then
            TryToMove(item)
        end

        if not item.isLocked then
            TryToDrop(item)
        end

        if imgui.Selectable('Cancel') then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    return menuOpened
end

local function AddWardrobeCtxMenu(item)
    local menuOpened = false
    local menuOpenable = item.isUsable or item.isMoveable or item.isEquippable or not item.isLocked

    if menuOpenable and imgui.BeginPopupContextItem(item.uniqueId) then
        menuOpened = true

        if item.isUsable then
            TryToUse(item)
        end

        if item.isEquippable then
            TryToEquip(item)
        end

        if item.isMoveable then
            TryToMove(item)
        end

        if not item.isLocked then
            TryToDrop(item)
        end

        if imgui.Selectable('Cancel') then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    return menuOpened
end

local function AddSatchelCtxMenu(item)
    local menuOpened = false
    local menuOpenable = item.isMoveable or not item.isLocked

    if menuOpenable and imgui.BeginPopupContextItem(item.uniqueId) then
        menuOpened = true

        if item.isMoveable then
            TryToMove(item)
        end

        if not item.isLocked then
            TryToDrop(item)
        end

        if imgui.Selectable('Cancel') then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    return menuOpened
end

local function AddHouseCtxMenu(item)
    return false
end

local contextMenus = {
    bag      = AddFullCtxMenu,
    satchel  = AddSatchelCtxMenu,
    wardrobe = AddWardrobeCtxMenu,
    house    = AddHouseCtxMenu,
}

-- Experimental: working the inventory with an XInput controller (the Controller Navigation setting).
-- The controller itself is winxi's: which buttons are taken and kept from the game, the highlight that
-- moves over the items, and the menu. What is here is what the buttons do in this window.
--
-- While the window is showing, the d-pad moves a highlight over the items, the shoulder buttons change
-- tab, A opens a menu of what can be done with the highlighted item and chooses from it, and B backs
-- out of the menu or closes the window.
local pad = {
    options = nil,     -- the tool's settings, as of the frame last drawn
    drawn = 0,         -- when the window was last drawn: the controller is only the inventory's while it is
    active = false,    -- as of the frame being drawn
    grid = controller.NewGrid(),
    items = { },       -- the item at each place in the grid, and the group of bags it is in
    groups = { },
    tab = 1,           -- the tab that is showing
    wantTab = nil,     -- the tab to switch to on the next frame
    menu = nil,        -- the menu that is open, and the item it is for
    menuItem = nil,
}

local padTabs = 4
local padColor = imgui.GetColorU32({ 1.0, 0.85, 0.3, 1.0 })

-- Whether the inventory has the controller: the setting is on, and the window is showing and being
-- drawn (it is not, while the tool is switched off or the whole UI is hidden)
local function PadIsActive()
    local options = pad.options
    return options ~= nil
        and options.controller ~= nil and options.controller[1]
        and options.isVisible[1]
        and os.clock() - pad.drawn < 0.25
        or false
end

-- What can be done with an item from the given group of bags, as menu entries. The same choices, under
-- the same rules, as the right-click menus.
local function PadEntries(item, group)
    local entries = { }
    local function add(label, run)
        entries[#entries + 1] = { label = label, run = run }
    end

    if group == 'house' then
        return entries
    end

    local carried = (group == 'bag')
    local worn = (group == 'wardrobe')

    if (carried or worn) and item.isUsable then
        add('Use', function() UseItem(item) end)
    end
    if carried and item.isTradeable then
        add('Trade', function() TradeItem(item) end)
    end
    if (carried or worn) and item.isEquippable then
        for _, slotName in ipairs(EquipSlots(item)) do
            add(('Equip to %s'):format(slotName), function() EquipItem(item, slotName) end)
        end
    end
    if item.isMoveable then
        for _, bag in ipairs(moveableBags) do
            if CanMoveTo(item, bag) then
                add(('Move to %s'):format(bag.name), function() MoveItem(item, bag) end)
            end
        end
    end
    if not item.isLocked then
        -- dropping is asked about first, with Cancel the choice that is highlighted
        add('Drop...', function()
            return controller.NewMenu(item.shortName, {
                { label = 'Cancel' },
                { label = DropLabel(item), run = function() DropItem(item) end },
            })
        end)
    end

    return entries
end

-- One of the inventory's buttons has been pressed, or a held d-pad button has repeated
local function PadPress(action)
    if pad.menu ~= nil then
        pad.menu = pad.menu:Press(action)
        return
    end

    if action == 'up' or action == 'down' or action == 'left' or action == 'right' then
        pad.grid:Move(action)
    elseif action == 'previous' then
        pad.wantTab = (pad.tab - 2) % padTabs + 1
        sound.Play('tab')
    elseif action == 'next' then
        pad.wantTab = pad.tab % padTabs + 1
        sound.Play('tab')
    elseif action == 'confirm' then
        local item = pad.items[pad.grid.cursor]
        local entries = item ~= nil and PadEntries(item, pad.groups[pad.grid.cursor]) or nil
        if entries ~= nil and #entries > 0 then
            pad.menu = controller.NewMenu(item.shortName, entries)
            pad.menuItem = item
            sound.Play('confirm')
        else
            -- an empty slot, or an item with nothing to be done with it
            sound.Play('error')
        end
    elseif action == 'back' then
        -- the sound of it closing is made as the window is seen to have gone, however it was closed
        pad.options.isVisible[1] = false
    end
end

pad.binding = controller.Bind({
    active = PadIsActive,
    actions = controller.StandardActions(),
    repeats = controller.StandardRepeats(),
    press = PadPress,
})

-- Starts a frame of drawing
local function PadBeginFrame(options)
    -- the kind of controller, from the settings (a key winxi does not know leaves it as it was)
    if options.controllerType ~= nil and options.controllerType ~= controller.GetLayout() then
        controller.SetLayout(options.controllerType)
    end

    -- the grid and the menu make their own sounds once these are on
    sound.SetEnabled(options.controllerSounds ~= nil and options.controllerSounds[1])

    -- the window closing, whether by the controller, /xit i or anything else, sounds as backing out does
    local showing = options.controller ~= nil and options.controller[1] and options.isVisible[1] or false
    if pad.showing and not showing then
        sound.Play('back')
    end
    pad.showing = showing

    pad.options = options
    pad.drawn = os.clock()
    pad.active = PadIsActive()
    if not pad.active then
        pad.menu = nil
    end
    pad.grid:Begin()
end

-- Ends a frame of drawing: keeps the highlight on an item, and draws the open menu beside its item
local function PadEndFrame()
    pad.grid:End()
    if not pad.active or pad.menu == nil then
        return
    end

    -- the menu belongs to the item it was opened for: if that has gone (used up, moved), so does the menu
    local item = pad.items[pad.grid.cursor]
    if item == nil or pad.menuItem == nil or item.uniqueId ~= pad.menuItem.uniqueId then
        pad.menu = nil
        return
    end

    local x, y = pad.grid:Position()
    pad.menu:Draw(x + 40, y)
end

local iconSize = 32
local iconSizes = { iconSize, iconSize }
local padMin, padMax = { 0, 0 }, { 0, 0 }

-- Whether the item about to be drawn is in view. One scrolled out of sight only has its room kept: a
-- group of bags can hold hundreds, of which the window shows a few rows. Whether imgui can be asked is
-- found out the first time; if not, everything is drawn as before.
local canCull = nil

local function IsInView()
    if canCull then
        return imgui.IsRectVisible(iconSizes)
    elseif canCull == nil then
        local ok, visible = pcall(imgui.IsRectVisible, iconSizes)
        canCull = ok and type(visible) == 'boolean'
        return not canCull or visible
    end
    return true
end

-- group is the group of bags the item is being drawn in (bag, satchel, wardrobe or house)
local function DrawItem(item, addCtxMenu, group, drawList)
    local curX, curY = imgui.GetCursorScreenPos()
    local inView = IsInView()

    if inView then
        imgui.Image(item.iconPtr, iconSizes)

        if item.stackText then
            AddStackSize(curX, curY, item.stackText, drawList)
        end

        if imgui.IsItemHovered() then
            AddHighlight(curX, curY, iconSize, drawList)
            AddTooltip(item)
        end

        if addCtxMenu(item) then
            AddHighlight(curX, curY, iconSize, drawList)
        end
    else
        imgui.Dummy(iconSizes)
    end

    -- With the controller: note where the item is, and mark the one the highlight is on
    if pad.active then
        local index = pad.grid:Add(curX, curY)
        pad.items[index], pad.groups[index] = item, group

        if pad.grid:IsOn(index) then
            if inView then
                -- two outlines, one inside the other, for a border two pixels thick
                padMin[1], padMin[2] = curX - 2, curY - 2
                padMax[1], padMax[2] = curX + iconSize + 2, curY + iconSize + 2
                drawList:AddRect(padMin, padMax, padColor, 0.0)
                padMin[1], padMin[2] = curX - 3, curY - 3
                padMax[1], padMax[2] = curX + iconSize + 3, curY + iconSize + 3
                drawList:AddRect(padMin, padMax, padColor, 0.0)
            end
            if pad.grid.moved and imgui.SetScrollHereY ~= nil then
                imgui.SetScrollHereY(0.5)
            end
        end
    end
end

-- An empty slot: a faint square the size of an item's icon. The tables are shared rather than made for
-- each one: a bag can have eighty.
local emptySize = { 32, 32 }
local emptyFill = { 1.0, 1.0, 1.0, 0.04 }
local emptyEdge = { 1.0, 1.0, 1.0, 0.18 }
local emptyMin, emptyMax = { 0, 0 }, { 0, 0 }

local function DrawEmptySlot(drawList, fill, edge)
    local x, y = imgui.GetCursorScreenPos()
    imgui.Dummy(emptySize)

    emptyMin[1], emptyMin[2] = x, y
    emptyMax[1], emptyMax[2] = x + emptySize[1], y + emptySize[2]
    drawList:AddRectFilled(emptyMin, emptyMax, fill, 2)
    drawList:AddRect(emptyMin, emptyMax, edge, 2)
end

-- How many empty slots a bag (or a group's bags together) has to show: none unless they are being shown
local function EmptySlots(bagId, subId)
    if not showEmptySlots then
        return 0
    end
    return math.max(0, (capacities[bagId][subId] or 0) - #inventories[bagId][subId])
end

local tabsWidthIsh = imgui.CalcTextSize(' bag satchel ward house ')
local rowLengthIsh = math.ceil(tabsWidthIsh / (32 + 8))
local function DrawBag(bagId, subId)
    local items = inventories[bagId][subId]
    local drawList = imgui.GetWindowDrawList()
    local addCtxMenu = contextMenus[bagId]
    for i, item in ipairs(items) do
        if i % rowLengthIsh ~= 1 then
            imgui.SameLine()
        end

        DrawItem(item, addCtxMenu, bagId, drawList)
    end

    -- the empty slots carry on from the last item, in the same rows
    local empty = EmptySlots(bagId, subId)
    if empty > 0 then
        local fill, edge = imgui.GetColorU32(emptyFill), imgui.GetColorU32(emptyEdge)
        for i = #items + 1, #items + empty do
            if i % rowLengthIsh ~= 1 then
                imgui.SameLine()
            end

            DrawEmptySlot(drawList, fill, edge)
        end
    end
end

local function DrawSubInventory(title, bagId, subId)
    -- a bag with nothing in it is left out, unless its empty slots are being shown
    if #inventories[bagId][subId] == 0 and EmptySlots(bagId, subId) == 0 then
        return
    end

    imgui.Text(title)
    imgui.Separator()
    DrawBag(bagId, subId)
    imgui.NewLine()
end

-- The bags counted at the foot of each tab, with what each is called there. Temporary items are not
-- counted: they have no slots of their own to fill.
local countedBags = {
    bag = { { 'inventory', 'inv' } },
    satchel = { { 'mog satchel', 'satchel' }, { 'mog case', 'case' }, { 'mog sack', 'sack' } },
    wardrobe = {
        { 'wardrobe 1', 'wardrobe1' }, { 'wardrobe 2', 'wardrobe2' }, { 'wardrobe 3', 'wardrobe3' },
        { 'wardrobe 4', 'wardrobe4' }, { 'wardrobe 5', 'wardrobe5' }, { 'wardrobe 6', 'wardrobe6' },
        { 'wardrobe 7', 'wardrobe7' }, { 'wardrobe 8', 'wardrobe8' },
    },
    house = { { 'mog safe 1', 'mogSafe1' }, { 'mog safe 2', 'mogSafe2' }, { 'storage', 'storage' }, { 'mog locker', 'locker' } },
}

-- The row at the foot of a tab: the gil on the left and, on the right, how full each of the tab's bags
-- is, as 08/30. A tab with one bag shows the count alone; one with several names each, one to a row
-- under the first. A full bag's count is red. Bags the player does not have are left out.
--
-- What the row says only changes when the bags do, so it is put together then (by UpdateInventories)
-- and only drawn here.
local countBuffer = { 0, 3 } -- between the slots and the row
local countRows = { bag = { }, satchel = { }, wardrobe = { }, house = { } } -- each: { text, full }
local gilText = '0 G'

BuildCounts = function()
    gilText = ('%s G'):format(inventories.gil)

    for bagId, counted in pairs(countedBags) do
        local shown = 0
        for _, bag in ipairs(counted) do
            if (capacities[bagId][bag[2]] or 0) > 0 then
                shown = shown + 1
            end
        end

        local rows = { }
        for _, bag in ipairs(counted) do
            local slots = capacities[bagId][bag[2]] or 0
            if slots > 0 then
                local used = #inventories[bagId][bag[2]]
                local text = ('%02d/%02d'):format(used, slots)
                if shown > 1 then
                    text = ('%s %s'):format(bag[1], text)
                end
                rows[#rows + 1] = { text = text, full = used >= slots }
            end
        end
        countRows[bagId] = rows
    end
end

local function DrawCounts(bagId)
    -- a little room between the slots and this row
    imgui.Dummy(countBuffer)

    -- the gil against the left edge, on the same row as the first (or only) count
    imgui.Text(gilText)

    for index, row in ipairs(countRows[bagId]) do
        if index == 1 then
            imgui.SameLine()
        end

        -- against the right edge, by hand: the text starts its own width short of it
        local available = imgui.GetContentRegionAvail()
        local width = imgui.CalcTextSize(row.text)
        imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, available - width))

        if row.full then
            imgui.TextColored(ui.Colors.Red, row.text)
        else
            imgui.Text(row.text)
        end
    end
end

-- Begins one of the four tabs. With the controller it is also where a change of tab is asked for and
-- where the tab that is showing is noted.
local function BeginTab(index, label)
    local showing
    if pad.active and pad.wantTab == index then
        showing = imgui.BeginTabItem(label, 0, ImGuiTabItemFlags_SetSelected)
    else
        showing = imgui.BeginTabItem(label)
    end

    if showing then
        if pad.wantTab == index then
            pad.wantTab = nil
        end
        if pad.tab ~= index then
            -- a different tab's items: the highlight starts again from the first
            pad.tab = index
            pad.grid:Reset()
            pad.menu = nil
        end
    end
    return showing
end

local function DrawInventory()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingSome)
    if imgui.BeginTabBar('##xitools.inventories.all', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if BeginTab(1, 'bag##xitools.inventories.all.1') then
            DrawSubInventory('inventory', 'bag', 'inv')
            DrawSubInventory('temp items', 'bag', 'temp')
            DrawCounts('bag')
            imgui.EndTabItem()
        end

        if BeginTab(2, 'satchel##xitools.inventories.all.2') then
            DrawSubInventory('mog satchel', 'satchel', 'satchel')
            DrawSubInventory('mog case', 'satchel', 'case')
            DrawSubInventory('mog sack', 'satchel', 'sack')
            DrawCounts('satchel')
            imgui.EndTabItem()
        end

        if BeginTab(3, 'ward##xitools.inventories.all.3') then
            DrawSubInventory('wardrobe 1', 'wardrobe', 'wardrobe1')
            DrawSubInventory('wardrobe 2', 'wardrobe', 'wardrobe2')
            DrawSubInventory('wardrobe 3', 'wardrobe', 'wardrobe3')
            DrawSubInventory('wardrobe 4', 'wardrobe', 'wardrobe4')
            DrawSubInventory('wardrobe 5', 'wardrobe', 'wardrobe5')
            DrawSubInventory('wardrobe 6', 'wardrobe', 'wardrobe6')
            DrawSubInventory('wardrobe 7', 'wardrobe', 'wardrobe7')
            DrawSubInventory('wardrobe 8', 'wardrobe', 'wardrobe8')
            DrawCounts('wardrobe')
            imgui.EndTabItem()
        end

        if BeginTab(4, 'house##xitools.inventories.all.4') then
            DrawSubInventory('mog safe 1', 'house', 'mogSafe1')
            DrawSubInventory('mog safe 2', 'house', 'mogSafe2')
            DrawSubInventory('storage', 'house', 'storage')
            DrawSubInventory('mog locker', 'house', 'locker')
            DrawCounts('house')
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
    imgui.PopStyleVar()
end

local function DrawInventoryUnified()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingSome)
    if imgui.BeginTabBar('##xitools.inventories.unified', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if BeginTab(1, 'bag##xitools.inventories.unified.1') then
            DrawBag('bag', 'all')
            DrawCounts('bag')
            imgui.EndTabItem()
        end

        if BeginTab(2, 'satchel##xitools.inventories.unified.2') then
            DrawBag('satchel', 'all')
            DrawCounts('satchel')
            imgui.EndTabItem()
        end

        if BeginTab(3, 'ward##xitools.inventories.unified.3') then
            DrawBag('wardrobe', 'all')
            DrawCounts('wardrobe')
            imgui.EndTabItem()
        end

        if BeginTab(4, 'house##xitools.inventories.unified.4') then
            DrawBag('house', 'all')
            DrawCounts('house')
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
    imgui.PopStyleVar()
end

-- What goes in the window. The settings are kept to one side for it, so that it need not be made
-- afresh every frame.
local drawOptions = nil

local function DrawWindow()
    -- once for the frame, inside the window: they take in its fade
    stackMain, stackShadow = imgui.GetColorU32(stackWhite), imgui.GetColorU32(stackBlack)

    if drawOptions.isUnified[1] then
        DrawInventoryUnified()
    else
        DrawInventory()
    end

    -- marked as the window the controller is working, while it is
    if pad.active then
        controller.Highlight(pad.binding)
    end
end

---@type xitool
local inv = {
    Name = 'inv',
    Aliases = T{ 'i' },
    DefaultSettings = T{
        name = 'xitools.inv',
        isEnabled = T{ false },
        isVisible = T{ true },
        isUnified = T{ true },
        showEmptySlots = T{ false },
        controller = T{ false }, -- experimental: work the window with a controller
        controllerSounds = T{ false }, -- sounds as the controller works the window
        controllerType = 'xinput', -- which kind: a key of winxi.controller's Layouts
        size = T{ 0, 0 },
        maxHeight = T{ 432 },
        pos = T{ 256, 256 },
        flags = ui.StyledWindowFlags,
    },
    Load = function()
        if GetPlayerEntity() ~= nil then
            UpdateInventories()
        end
    end,
    HandleCommand = function(args, options)
        if #args == 0 then
            options.isVisible[1] = not options.isVisible[1]
        end
    end,
    HandlePacket = function(e, options)
        if e.id == 0x01D then
            local packet = packets.inbound.inventoryFinish.parse(e.data)
            if packet.flag == 1 then
                debounce(UpdateInventories)
            end
        elseif e.id == 0x01E then
            debounce(UpdateInventories)
        end
    end,
    DrawConfig = function(options)
        if imgui.BeginTabItem('inv') then
            ui.BeginLabels('xitools.inv')
            ui.Label('Enabled')
            if imgui.Checkbox('##inv.1', options.isEnabled) and options.isEnabled[1] then
                UpdateInventories()
            end

            ui.Label('Visible')
            imgui.Checkbox('##inv.2', options.isVisible)

            ui.Gap()
            -- Settings saved before this option existed have no value for it
            if options.showEmptySlots == nil then
                options.showEmptySlots = T{ false }
            end
            ui.Label('Show Empty Slots')
            imgui.Checkbox('##inv.emptySlots', options.showEmptySlots)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Draws a spot for every slot of each bag, with the empty ones as faint squares after the items.')
            end
            if options.controller == nil then
                options.controller = T{ false }
            end
            ui.Label('Controller Navigation (Experimental)')
            imgui.Checkbox('##inv.controller', options.controller)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Work the inventory with a controller while its window is showing.\nD-pad: move the highlight.  LB / RB: change tab.\nA: open the item\'s menu, and choose from it.  B: back out of the menu, or close the window.\nThose buttons do not reach the game while the window is showing. Open it with /xit i, from a macro.')
            end
            if options.controller[1] then
                if options.controllerSounds == nil then
                    options.controllerSounds = T{ false }
                end
                ui.Label('Controller Sounds')
                imgui.Checkbox('##inv.controllerSounds', options.controllerSounds)
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Plays a sound as the window opens, the highlight moves, a menu opens, a choice is made or backed out of.\nThe sounds are the wav files in libs\\winxi\\sounds: put others of the same names there to change them.')
                end
                ui.Label('Controller Type')
                local current = controller.GetLayout()
                local column = imgui.GetCursorPosX()
                for index, layout in ipairs(controller.Layouts) do
                    if index > 1 then
                        -- one to a line, under the first
                        imgui.SetCursorPosX(column)
                    end
                    if imgui.RadioButton(('%s##inv.controllerType'):format(layout.label), current == layout.key) then
                        options.controllerType = layout.key
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('XInput is an Xbox controller, or one set to behave as one. DirectInput is anything else: pick the make whose buttons match.\nOn a DirectInput controller the buttons are read by position: the bottom face button is A, the right one B.')
                end
            end
            ui.Label('Draw Unified Bags')
            imgui.Checkbox('##inv.3', options.isUnified)
            ui.Label('Max Height')
            imgui.InputInt('##inv.4', options.maxHeight)

            ui.Gap()
            ui.Label('Position')
            if imgui.InputInt2('##inv.5', options.pos) then
                imgui.SetWindowPos(options.name, options.pos)
            end

            imgui.EndTabItem()
        end
    end,
    DrawMain = function(options, gOptions)
        options.flags = ui.StyledWindowFlags
        showEmptySlots = options.showEmptySlots ~= nil and options.showEmptySlots[1] or false

        PadBeginFrame(options)
        drawOptions = options
        ui.DrawStyledWindow(options, gOptions, DrawWindow)
        PadEndFrame()
    end,
}

return inv
