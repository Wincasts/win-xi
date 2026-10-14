addon.name    = 'inv'
addon.author  = 'lin, win'
addon.version = '1.0'
addon.desc    = 'The bags in a window: what is in them, and what can be done with it, by mouse or controller.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- The inventory window that was a tool of xitools, as an addon of its own. It needs only winxi: the
-- look of its windows, the controller, the sounds, the packets and what is asked of the game are
-- all the library's.
--
--   /inv           shows or hides the window
--   /inv config    opens or closes the settings
--   /inv focus     gives the open window the controller, or takes it away again

require('common')
local bit = require('bit')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local game = require('winxi.game')
local shell = require('winxi.shell')
local packets = require('winxi.packets')
local debounce = require('winxi.debounce')
local controller = require('winxi.controller')
local sound = require('winxi.sound')

-- Colours and spacing that were xitools' own
local red = { 0.95, 0.20, 0.20, 1.0 }
local yellow = { 1.00, 1.00, 0.00, 1.0 }
local framePadding = { 4, 2 }

local function Say(text)
    print(('\30\81[inv]\30\01 %s'):format(text))
end

local textures = { }
local gfxDevice = d3d8.get_device()
local fontWidth = imgui.CalcTextSize('A')
local inventories = T{
    gil = 0,
    recycleBin = T{},
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

-- A name as the game's log has it, all in small letters, with its first letter made a capital
local function Capitalize(name)
    if name == nil or name == '' then
        return ''
    end
    return name:sub(1, 1):upper() .. name:sub(2)
end

-- The races that can wear a piece of gear, from the game's flags for them: a bit each for Hume men
-- and women, Elvaan men and women, Tarutaru men and women, Mithra and Galka, from the second bit up
local allRaces = 0x1FE
local racePairs = {
    { 'Hume', 0x02, 0x04 },
    { 'Elvaan', 0x08, 0x10 },
    { 'Tarutaru', 0x20, 0x40 },
}

local function GetRaces(bitfield)
    if bitfield == nil or bitfield == 0 or bit.band(bitfield, allRaces) == allRaces then
        return 'All Races'
    end

    local names = { }
    for _, race in ipairs(racePairs) do
        local men = bit.band(bitfield, race[2]) ~= 0
        local women = bit.band(bitfield, race[3]) ~= 0
        if men and women then
            names[#names + 1] = race[1]
        elseif men then
            names[#names + 1] = race[1] .. ' (M)'
        elseif women then
            names[#names + 1] = race[1] .. ' (F)'
        end
    end
    if bit.band(bitfield, 0x80) ~= 0 then
        names[#names + 1] = 'Mithra'
    end
    if bit.band(bitfield, 0x100) ~= 0 then
        names[#names + 1] = 'Galka'
    end
    return table.concat(names, ', ')
end

local function GetJobs(bitfield)
    if bitfield == 8388606 then
        return T{ 'All Jobs' }
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

-- The order the player has put items in themselves (the controller's Manual sort), where they have:
-- the tool's manualOrder setting, group of bags -> item -> its place. Items are placed by kind, so
-- every stack of an item sits together, and an item with no place of its own comes after those with
-- one, in the usual order. A group without an order is in the usual order throughout.
local manualOrders = nil
local unplaced = math.huge

local function OrderKey(itemId)
    return ('i%d'):format(itemId) -- a name rather than a number, so that the settings keep it as it is
end

local function GroupSorter(group)
    return function(lhs, rhs)
        local order = manualOrders and manualOrders[group]
        if order then
            local left = order[OrderKey(lhs.id)] or unplaced
            local right = order[OrderKey(rhs.id)] or unplaced
            if left ~= right then
                return left < right
            end
        end
        return SortInventory(lhs, rhs)
    end
end

local sorters = {
    bag = GroupSorter('bag'),
    satchel = GroupSorter('satchel'),
    wardrobe = GroupSorter('wardrobe'),
    house = GroupSorter('house'),
}

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
                name = ('%s [%i]'):format(Capitalize(itemRes.LogNameSingular[1]), invItem.Id),
                properName = Capitalize(itemRes.LogNameSingular[1]),
                rawDesc = itemRes.Description[1],
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
                -- for the controller's verbose box, which sets gear out in lines of its own
                coolItem.isGear = true
                coolItem.levelText = ('Lv %i'):format(itemRes.Level)
                coolItem.slotName = itemSlots
                coolItem.jobList = itemJobs
                coolItem.races = itemRes.Races
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
            bag.hasAccess = game.HasBagAccess(bag.id)
        else
            bag.hasAccess = inv:GetContainerCountMax(bag.id) > 0
        end
    end

    inventories.gil = FormatGil(gil.Count)
    inventories.bag.inv = UpdateInventory(inv, res, bags.inventory):sort(sorters.bag)
    inventories.bag.temp = UpdateInventory(inv, res, bags.tempItems):sort(sorters.bag)
    inventories.satchel.satchel = UpdateInventory(inv, res, bags.mogSatchel):sort(sorters.satchel)
    inventories.satchel.case = UpdateInventory(inv, res, bags.mogCase):sort(sorters.satchel)
    inventories.satchel.sack = UpdateInventory(inv, res, bags.mogSack):sort(sorters.satchel)
    inventories.wardrobe.wardrobe1 = UpdateInventory(inv, res, bags.wardrobe):sort(sorters.wardrobe)
    inventories.wardrobe.wardrobe2 = UpdateInventory(inv, res, bags.wardrobe2):sort(sorters.wardrobe)
    inventories.wardrobe.wardrobe3 = UpdateInventory(inv, res, bags.wardrobe3):sort(sorters.wardrobe)
    inventories.wardrobe.wardrobe4 = UpdateInventory(inv, res, bags.wardrobe4):sort(sorters.wardrobe)
    inventories.wardrobe.wardrobe5 = UpdateInventory(inv, res, bags.wardrobe5):sort(sorters.wardrobe)
    inventories.wardrobe.wardrobe6 = UpdateInventory(inv, res, bags.wardrobe6):sort(sorters.wardrobe)
    inventories.wardrobe.wardrobe7 = UpdateInventory(inv, res, bags.wardrobe7):sort(sorters.wardrobe)
    inventories.wardrobe.wardrobe8 = UpdateInventory(inv, res, bags.wardrobe8):sort(sorters.wardrobe)
    inventories.house.mogSafe1 = UpdateInventory(inv, res, bags.mogSafe):sort(sorters.house)
    inventories.house.mogSafe2 = UpdateInventory(inv, res, bags.mogSafe2):sort(sorters.house)
    inventories.house.storage = UpdateInventory(inv, res, bags.storage):sort(sorters.house)
    inventories.house.locker = UpdateInventory(inv, res, bags.mogLocker):sort(sorters.house)
    -- what has been dropped and can still be taken back: not drawn as a bag, but listed by the
    -- controller's sort menu
    inventories.recycleBin = UpdateInventory(inv, res, bags.recycleBin)

    inventories.bag.all = T{}
        :extend(inventories.bag.inv)
        :extend(inventories.bag.temp)
        :sort(sorters.bag)

    inventories.satchel.all = T{}
        :extend(inventories.satchel.satchel)
        :extend(inventories.satchel.case)
        :extend(inventories.satchel.sack)
        :sort(sorters.satchel)

    inventories.wardrobe.all = T{}
        :extend(inventories.wardrobe.wardrobe1)
        :extend(inventories.wardrobe.wardrobe2)
        :extend(inventories.wardrobe.wardrobe3)
        :extend(inventories.wardrobe.wardrobe4)
        :extend(inventories.wardrobe.wardrobe5)
        :extend(inventories.wardrobe.wardrobe6)
        :extend(inventories.wardrobe.wardrobe7)
        :extend(inventories.wardrobe.wardrobe8)
        :sort(sorters.wardrobe)

    inventories.house.all = T{}
        :extend(inventories.house.mogSafe1)
        :extend(inventories.house.mogSafe2)
        :extend(inventories.house.storage)
        :extend(inventories.house.locker)
        :sort(sorters.house)

    -- How many slots each bag has, for showing the empty ones. Temporary items have no fixed slots
    -- worth showing, and a bag the player cannot use has none.
    local function Slots(bagId)
        if bagId >= bags.wardrobe3 and bagId <= bags.wardrobe8 and not game.HasBagAccess(bagId) then
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

-- All there is to say of an item: its name, its description (where the game puts an item's stats and
-- what it has to say of it), how many of how many, and for gear its level, slot and jobs
local function DrawItemInfo(item)
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
end

local function AddTooltip(item)
    imgui.BeginTooltip()
    DrawItemInfo(item)
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
-- The window takes the controller as it is opened. While it has it, the d-pad moves a highlight over
-- the items, the shoulder buttons change tab, A opens a menu of what can be done with the highlighted
-- item and chooses from it, B backs out of the menu or gives the controller back to the game (the
-- window stays open), and X opens the sort menu.
local pad = {
    options = nil,     -- the tool's settings, as of the frame last drawn
    focused = false,   -- whether the window has the controller: from being opened (or /inv focus)
                       -- until B, /inv focus again, or its being closed
    drawn = 0,         -- when the window was last drawn: the controller is only the inventory's while it is
    active = false,    -- as of the frame being drawn
    grid = controller.NewGrid(),
    items = { },       -- the item at each place in the grid, and the group of bags it is in
    groups = { },
    tab = 1,           -- the tab that is showing
    wantTab = nil,     -- the tab to switch to on the next frame
    swap = nil,        -- while sorting by hand: { first = the item picked to be swapped, once one is }
    menu = nil,        -- the menu that is open, and the item it is for (none, for the sort menu)
    menuItem = nil,
}

local padTabs = 4
local iconSize = 32 -- an item's icon, square
local labelGap = 6  -- between the highlight's outline and the box that names the item
local padColor = imgui.GetColorU32({ 1.0, 0.85, 0.3, 1.0 })
local swapColor = imgui.GetColorU32({ 0.3, 0.9, 0.4, 1.0 })
local swapTextColor = { 0.3, 0.9, 0.4, 1.0 }

-- Whether the inventory has the controller: the setting is on, the window has been given it, and it
-- is showing and being drawn (it is not, while the whole UI is hidden)
local function PadIsActive()
    local options = pad.options
    return options ~= nil
        and options.controller ~= nil and options.controller[1]
        and pad.focused
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

-- The bags of each tab, by the game's number for them, with what each is called
local tabBags = {
    { { bags.inventory, 'inventory' } },
    { { bags.mogSatchel, 'satchel' }, { bags.mogSack, 'sack' }, { bags.mogCase, 'case' } },
    {
        { bags.wardrobe, 'wardrobe 1' }, { bags.wardrobe2, 'wardrobe 2' }, { bags.wardrobe3, 'wardrobe 3' },
        { bags.wardrobe4, 'wardrobe 4' }, { bags.wardrobe5, 'wardrobe 5' }, { bags.wardrobe6, 'wardrobe 6' },
        { bags.wardrobe7, 'wardrobe 7' }, { bags.wardrobe8, 'wardrobe 8' },
    },
    { { bags.mogSafe, 'safe 1' }, { bags.mogSafe2, 'safe 2' }, { bags.storage, 'storage' }, { bags.mogLocker, 'locker' } },
}

-- The server takes sorting the same bag twice within a second for a cheating tool, and after a few
-- of those removes the player. So a bag is never sorted again until this long after the last time.
local sortCooldown = 3.0
local sortedAt = { } -- bag -> when it was last sorted

-- Sorts the bags of the tab that is showing: the server puts together the part stacks of the same
-- item in each. Returns whether anything was asked of it.
local function SortTab()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local now = os.clock()
    local sorted = { }

    for _, bag in ipairs(tabBags[pad.tab] or { }) do
        local id = bag[1]
        local usable = inv:GetContainerCountMax(id) > 0
            and (id < bags.wardrobe3 or id > bags.wardrobe8 or game.HasBagAccess(id))
        if usable and now - (sortedAt[id] or -sortCooldown) >= sortCooldown then
            sortedAt[id] = now
            AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.inventorySort:make(id))
            sorted[#sorted + 1] = bag[2]
        end
    end

    if #sorted > 0 then
        Say(('Sorted: %s.'):format(table.concat(sorted, ', ')))
    end
    return #sorted > 0
end

local tabGroups = { 'bag', 'satchel', 'wardrobe', 'house' }

-- Swaps the places of two items in the window, by the controller's Manual sort. The places of
-- everything in the group are written down as they stand first, so that the two change and nothing
-- else does. Returns whether anything changed: two stacks of the same item share a place.
local function SwapPlaces(options, group, first, second)
    if first.id == second.id then
        return false
    end

    local order, place = T{ }, 0
    for _, item in ipairs(inventories[group].all) do
        local key = OrderKey(item.id)
        if order[key] == nil then
            place = place + 1
            order[key] = place
        end
    end

    local firstKey, secondKey = OrderKey(first.id), OrderKey(second.id)
    if order[firstKey] == nil or order[secondKey] == nil then
        return false
    end
    order[firstKey], order[secondKey] = order[secondKey], order[firstKey]

    if options.manualOrder == nil then
        options.manualOrder = T{ }
    end
    options.manualOrder[group] = order
    manualOrders = options.manualOrder
    UpdateInventories()
    return true
end

-- Puts a group back in the usual order. Returns whether it had one of the player's own.
local function ClearPlaces(options, group)
    if options.manualOrder == nil or options.manualOrder[group] == nil then
        return false
    end
    options.manualOrder[group] = nil
    manualOrders = options.manualOrder
    UpdateInventories()
    return true
end

-- What is in the recycle bin, as a menu: choosing an item takes it back into the inventory
local function RecycleBinMenu()
    local entries = { }
    for _, item in ipairs(inventories.recycleBin) do
        local label = item.shortName
        if item.stackCur > 1 then
            label = ('%s x%d'):format(label, item.stackCur)
        end
        entries[#entries + 1] = { label = label, run = function() MoveItem(item, moveableBags[1]) end }
    end
    if #entries == 0 then
        entries[1] = { label = '(empty)' }
    end
    entries[#entries + 1] = { label = 'Cancel' }
    return controller.NewMenu('Recycle Bin: take back', entries)
end

-- The menu the sort button opens, as the game's own does for its item list
local function SortMenu()
    return controller.NewMenu('Sort', {
        { label = 'Auto', run = function()
            -- back to the usual order, and the server puts part stacks together. Refused, with the
            -- error sound, when there is no order to undo and the bags were sorted too short a while ago
            local cleared = ClearPlaces(pad.options, tabGroups[pad.tab])
            local sorted = SortTab()
            if not (cleared or sorted) then
                sound.Play('error')
            end
        end },
        { label = 'Manual', run = function()
            -- A then picks an item, and A on another swaps the two, until B
            pad.swap = { first = nil }
        end },
        { label = 'Recycle Bin', run = RecycleBinMenu },
    })
end

-- The controller's verbose box for the highlighted item.
--
-- The game writes the elements into an item's description as marks of its own (two bytes each),
-- which no font here has. They are drawn as dots in the elements' colours instead: there are no
-- pictures of the game's own marks to draw.
local elementColors = {
    [0x1F] = { 0.95, 0.30, 0.20, 1.0 }, -- fire
    [0x20] = { 0.60, 0.90, 1.00, 1.0 }, -- ice
    [0x21] = { 0.35, 0.85, 0.35, 1.0 }, -- wind
    [0x22] = { 0.80, 0.65, 0.25, 1.0 }, -- earth
    [0x23] = { 0.75, 0.45, 0.95, 1.0 }, -- lightning
    [0x24] = { 0.30, 0.50, 1.00, 1.0 }, -- water
    [0x25] = { 1.00, 1.00, 0.90, 1.0 }, -- light
    [0x26] = { 0.40, 0.30, 0.50, 1.0 }, -- dark
}
local elementEdge = { 1.0, 1.0, 1.0, 0.7 }

-- A description as lines, each a list of pieces: a string of text, or the number of an element
local function ParseDescription(raw)
    local lines = { }
    if raw == nil then
        return lines
    end

    raw = raw:gsub('\x81\x60', '~'):gsub('\r', '')
    for line in (raw .. '\n'):gmatch('(.-)\n') do
        local pieces = { }
        local from = 1
        while true do
            local at = line:find('\xEF[\x1F-\x26]', from)
            if at == nil then
                break
            end
            if at > from then
                pieces[#pieces + 1] = line:sub(from, at - 1)
            end
            pieces[#pieces + 1] = line:byte(at + 1)
            from = at + 2
        end
        if from <= #line then
            pieces[#pieces + 1] = line:sub(from)
        end
        if #pieces > 0 then
            lines[#lines + 1] = pieces
        end
    end
    return lines
end

local _, fontHeight = imgui.CalcTextSize('A')
fontHeight = fontHeight or 14 -- should the size come back as its width alone
local dotSize = { fontHeight, fontHeight }
local dotCenter = { 0, 0 }

local function DrawDescription(lines)
    local drawList = imgui.GetWindowDrawList()
    for _, pieces in ipairs(lines) do
        for index, piece in ipairs(pieces) do
            if index > 1 then
                imgui.SameLine(0, 0)
            end
            if type(piece) == 'number' then
                local x, y = imgui.GetCursorScreenPos()
                imgui.Dummy(dotSize)
                dotCenter[1], dotCenter[2] = x + fontHeight / 2, y + fontHeight / 2
                drawList:AddCircleFilled(dotCenter, fontHeight * 0.34, imgui.GetColorU32(elementColors[piece]), 12)
                drawList:AddCircle(dotCenter, fontHeight * 0.34, imgui.GetColorU32(elementEdge), 12)
            else
                imgui.Text(piece)
            end
        end
    end
end

-- The jobs that can wear a piece of gear, after its level, across as many lines as they need, with
-- the player's own job in yellow
local jobsWidth = fontWidth * 44

local function DrawLevelAndJobs(item)
    imgui.Text(item.levelText)

    local own = jobs[AshitaCore:GetMemoryManager():GetPlayer():GetMainJob()]
    local spacing = fontWidth
    local across = imgui.CalcTextSize(item.levelText)
    for _, job in ipairs(item.jobList) do
        local width = imgui.CalcTextSize(job)
        if across + spacing + width <= jobsWidth then
            imgui.SameLine(0, spacing)
            across = across + spacing + width
        else
            across = width
        end

        if job == own then
            imgui.TextColored(yellow, job)
        else
            imgui.Text(job)
        end
    end
end

-- Gear is set out in four parts: its name; its slot and the races that can wear it; its stats; its
-- level and the jobs that can wear it. Anything else is its name, what the game says of it, and how
-- many of how many for a stack.
local function DrawVerbose(item)
    if item.verbose == nil then
        -- worked out once for the item: it is made afresh whenever the bags change
        item.verbose = {
            description = ParseDescription(item.rawDesc),
            wearers = item.isGear and (item.slotName and ('[%s] %s'):format(item.slotName, GetRaces(item.races)) or GetRaces(item.races)) or nil,
        }
    end

    imgui.Text(item.properName)
    if item.isGear then
        imgui.Text(item.verbose.wearers)
        DrawDescription(item.verbose.description)
        DrawLevelAndJobs(item)
    else
        DrawDescription(item.verbose.description)
        if item.stack then
            imgui.Text(item.stack)
        end
    end
end

-- The item is kept to one side for the box, so that the function need not be made afresh every frame
local infoItem = nil

local function DrawInfoBox()
    DrawVerbose(infoItem)
end

-- One of the inventory's buttons has been pressed, or a held d-pad button has repeated
local function PadPress(action)
    if pad.menu ~= nil then
        pad.menu = pad.menu:Press(action)
        return
    end

    if action == 'up' or action == 'down' or action == 'left' or action == 'right' then
        pad.grid:Move(action)
    elseif action == 'previous' or action == 'next' then
        if action == 'previous' then
            pad.wantTab = (pad.tab - 2) % padTabs + 1
        else
            pad.wantTab = pad.tab % padTabs + 1
        end
        -- an item picked for swapping is of the tab being left
        if pad.swap ~= nil then
            pad.swap.first = nil
        end
        sound.Play('tab')
    elseif pad.swap ~= nil then
        -- sorting by hand: A picks an item, A on another swaps them, B unpicks or finishes
        local swap = pad.swap
        if action == 'confirm' then
            local item = pad.items[pad.grid.cursor]
            if item == nil then
                sound.Play('error')
            elseif swap.first == nil then
                swap.first = item
                sound.Play('confirm')
            elseif SwapPlaces(pad.options, tabGroups[pad.tab], swap.first, item) then
                swap.first = nil
                sound.Play('confirm')
            else
                sound.Play('error')
            end
        elseif action == 'back' then
            if swap.first ~= nil then
                swap.first = nil
            else
                pad.swap = nil
            end
            sound.Play('back')
        end
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
    elseif action == 'sort' then
        pad.menu = SortMenu()
        pad.menuItem = nil
        sound.Play('confirm')
    elseif action == 'back' then
        -- the controller goes back to the game; the window stays, until /inv closes it
        pad.focused = false
        sound.Play('back')
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

    -- the window takes the controller as it is opened, and gives it up as it is closed (with the
    -- sound of backing out, if it still had it)
    local showing = options.controller ~= nil and options.controller[1] and options.isVisible[1] or false
    if showing and not pad.showing then
        pad.focused = true
    elseif pad.showing and not showing then
        if pad.focused then
            sound.Play('back')
        end
        pad.focused = false
    end
    pad.showing = showing

    pad.options = options
    pad.drawn = os.clock()
    pad.active = PadIsActive()
    if not pad.active then
        pad.menu = nil
        pad.swap = nil
    end
    pad.grid:Begin()
end

-- Ends a frame of drawing: keeps the highlight on an item, and draws the open menu beside its item
local function PadEndFrame()
    pad.grid:End()
    if not pad.active then
        return
    end

    -- no menu open: the item the highlight is on, in a box floating under it, a little clear of the
    -- highlight's outline (an item's menu has the name at its head). The simple view is the name; the
    -- verbose one all that the mouse's tooltip says.
    if pad.menu == nil then
        local item = pad.grid.count > 0 and pad.items[pad.grid.cursor] or nil
        local x, y = pad.grid:Position()
        if item ~= nil and x ~= nil then
            if pad.options.controllerInfo == 'verbose' then
                infoItem = item
                if pad.options.controllerInfoPlace == 'item' or pad.windowX == nil then
                    controller.Label(DrawInfoBox, x, y + iconSize + 3 + labelGap, true, item.uniqueId)
                else
                    -- under the window, its left edge in line with the window's
                    controller.Label(DrawInfoBox, pad.windowX, pad.windowY + pad.windowHeight + labelGap, true, item.uniqueId)
                end
            else
                if item.label == nil then
                    -- made once for the item: it is made afresh whenever the bags change
                    item.label = item.stackCur > 1 and ('%s x%d'):format(item.shortName, item.stackCur) or item.shortName
                end
                controller.Label(item.label, x, y + iconSize + 3 + labelGap, true)
            end
        end
        return
    end

    -- an item's menu belongs to the item it was opened for: if that has gone (used up, moved), so does
    -- the menu. The sort menu belongs to no item, and stays.
    local item = pad.items[pad.grid.cursor]
    if pad.menuItem ~= nil and (item == nil or item.uniqueId ~= pad.menuItem.uniqueId) then
        pad.menu = nil
        return
    end

    -- beside the highlighted item, or at the window's corner where the tab has none
    local x, y = pad.grid:Position()
    if x == nil or pad.grid.count == 0 then
        x, y = pad.options.pos[1], pad.options.pos[2]
    end
    pad.menu:Draw(x + 40, y)
end

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

        -- the item picked to be swapped keeps a mark of its own while the other is chosen
        if inView and pad.swap ~= nil and pad.swap.first ~= nil and pad.swap.first.uniqueId == item.uniqueId then
            padMin[1], padMin[2] = curX - 1, curY - 1
            padMax[1], padMax[2] = curX + iconSize + 1, curY + iconSize + 1
            drawList:AddRect(padMin, padMax, swapColor, 0.0)
            padMin[1], padMin[2] = curX, curY
            padMax[1], padMax[2] = curX + iconSize, curY + iconSize
            drawList:AddRect(padMin, padMax, swapColor, 0.0)
        end

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
            imgui.TextColored(red, row.text)
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
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if imgui.BeginTabBar('##inv.bags.all', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if BeginTab(1, 'bag##inv.bags.all.1') then
            DrawSubInventory('inventory', 'bag', 'inv')
            DrawSubInventory('temp items', 'bag', 'temp')
            DrawCounts('bag')
            imgui.EndTabItem()
        end

        if BeginTab(2, 'satchel##inv.bags.all.2') then
            DrawSubInventory('mog satchel', 'satchel', 'satchel')
            DrawSubInventory('mog case', 'satchel', 'case')
            DrawSubInventory('mog sack', 'satchel', 'sack')
            DrawCounts('satchel')
            imgui.EndTabItem()
        end

        if BeginTab(3, 'ward##inv.bags.all.3') then
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

        if BeginTab(4, 'house##inv.bags.all.4') then
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
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if imgui.BeginTabBar('##inv.bags.unified', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if BeginTab(1, 'bag##inv.bags.unified.1') then
            DrawBag('bag', 'all')
            DrawCounts('bag')
            imgui.EndTabItem()
        end

        if BeginTab(2, 'satchel##inv.bags.unified.2') then
            DrawBag('satchel', 'all')
            DrawCounts('satchel')
            imgui.EndTabItem()
        end

        if BeginTab(3, 'ward##inv.bags.unified.3') then
            DrawBag('wardrobe', 'all')
            DrawCounts('wardrobe')
            imgui.EndTabItem()
        end

        if BeginTab(4, 'house##inv.bags.unified.4') then
            DrawBag('house', 'all')
            DrawCounts('house')
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
    imgui.PopStyleVar()
end

local topPadding = 6 -- more room above the tabs, below the title on the top edge, in pixels

-- What goes in the window
local function DrawWindow(drawOptions)
    -- once for the frame, inside the window: they take in its fade
    stackMain, stackShadow = imgui.GetColorU32(stackWhite), imgui.GetColorU32(stackBlack)

    imgui.SetCursorPosY(imgui.GetCursorPosY() + topPadding)

    if drawOptions.isUnified[1] then
        DrawInventoryUnified()
    else
        DrawInventory()
    end

    -- where the window is, for the box that goes under it
    local _, height = imgui.GetWindowSize()
    pad.windowX, pad.windowY = imgui.GetWindowPos()
    pad.windowHeight = height

    -- what the buttons do while sorting by hand, at the foot of the window
    if pad.swap ~= nil then
        if pad.swap.first ~= nil then
            imgui.TextColored(swapTextColor, 'Swap with: A.  Unpick: B.')
        else
            imgui.TextColored(swapTextColor, 'Pick an item: A.  Finish: B.')
        end
    end

    -- marked as the window the controller is working, while it is
    if pad.active then
        controller.Highlight(pad.binding)
    end
end

-- The settings, kept for each character. The shell adds its own: fading in and out, the rules for
-- hiding, the theme.
local defaults = T{
    isVisible = T{ true },
    isUnified = T{ true },
    showEmptySlots = T{ false },
    maxHeight = T{ 432 },
    pos = T{ 256, 256 },
    controller = T{ false }, -- experimental: work the window with a controller
    controllerSounds = T{ false }, -- sounds as the controller works the window
    controllerInfo = 'simple', -- what is said of the highlighted item: 'simple' or 'verbose'
    controllerInfoPlace = 'window', -- where the verbose box goes: under the 'window' or the 'item'
    controllerType = 'xinput', -- which kind: a key of winxi.controller's Layouts
    -- manualOrder: the player's own order of items, once they have made one
}

local windowName = 'winxi.inv'
local controllerTooltip = 'Work the inventory with a controller while its window is showing.\nD-pad: move the highlight.  LB / RB: change tab.\nA: open the item\'s menu, and choose from it.  B: back out of the menu, or give the controller back to the game (the window stays open: /inv closes it, /inv focus gives it the controller again).\nX (square): the sort menu. Auto puts the tab back in the usual order and part stacks together; Manual swaps the places of two items; Recycle Bin takes back what was dropped.\nThose buttons do not reach the game while the window is showing. Open it with /inv, from a macro.'

-- The inventory's own controller settings, between the sounds and the kind of controller
local function DrawControllerSettings(options)
    widgets.Label('Controller Item Info')
    local verbose = options.controllerInfo == 'verbose'
    local infoColumn = imgui.GetCursorPosX()
    if imgui.RadioButton('Simple##inv.controllerInfo', not verbose) then
        options.controllerInfo = 'simple'
    end
    imgui.SetCursorPosX(infoColumn)
    if imgui.RadioButton('Verbose##inv.controllerInfo', verbose) then
        options.controllerInfo = 'verbose'
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip('What is said of the highlighted item.\nSimple: its name, in a box under it.  Verbose: its name, stats and description; for gear, its slot, races, level and jobs as well.')
    end

    if verbose then
        widgets.Label('Verbose Info Position')
        local underItem = options.controllerInfoPlace == 'item'
        local placeColumn = imgui.GetCursorPosX()
        if imgui.RadioButton('Below Window##inv.controllerInfoPlace', not underItem) then
            options.controllerInfoPlace = 'window'
        end
        imgui.SetCursorPosX(placeColumn)
        if imgui.RadioButton('Under Item##inv.controllerInfoPlace', underItem) then
            options.controllerInfoPlace = 'item'
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Where the verbose box goes: under the inventory window, in line with its left edge, or under the highlighted item.')
        end
    end
end

local function DrawSettings(options)
    widgets.Label('Visible')
    imgui.Checkbox('##inv.visible', options.isVisible)
    widgets.Label('Position')
    if imgui.InputInt2('##inv.position', options.pos) then
        imgui.SetWindowPos(windowName, options.pos)
    end
    widgets.Label('Max Height')
    imgui.InputInt('##inv.maxHeight', options.maxHeight)

    widgets.Gap()
    widgets.Label('Draw Unified Bags')
    imgui.Checkbox('##inv.unified', options.isUnified)
    widgets.Label('Show Empty Slots')
    imgui.Checkbox('##inv.emptySlots', options.showEmptySlots)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Draws a spot for every slot of each bag, with the empty ones as faint squares after the items.')
    end

    widgets.Gap()
    shell.ControllerSettings(options, controllerTooltip, DrawControllerSettings)
end

-- The settings, the settings window, the command and the main window's frame are the shell's. The
-- inventory was a tool of xitools, which kept its settings among its own: the shell brings them over
-- once for each character, with xitools' theme and rules for hiding.
local app = shell.New({
    defaults = defaults,
    window = windowName,
    title = 'Inventory',
    configTitle = 'Inventory Settings',
    command = '/inv',
    help = '/inv shows or hides the window; /inv config opens or closes the settings; /inv focus gives the window the controller, or takes it away.',
    drawSettings = DrawSettings,
    import = {
        tool = 'inv',
        keys = {
            'isVisible', 'isUnified', 'showEmptySlots', 'maxHeight', 'pos',
            'controller', 'controllerSounds', 'controllerInfo', 'controllerInfoPlace', 'controllerType',
            'manualOrder',
        },
    },
    onSettings = function(options)
        -- the player's own order is part of the settings, which may be another character's now
        manualOrders = options.manualOrder
        if GetPlayerEntity() ~= nil then
            UpdateInventories()
        end
    end,
    commands = {
        focus = function(options)
            if not options.controller[1] then
                Say('Controller Navigation is off: switch it on in /inv config.')
            elseif not options.isVisible[1] then
                Say('The window is closed: /inv opens it.')
            else
                pad.focused = not pad.focused
            end
        end,
    },
})

local windowExtra = { constraints = { { -1, 0 }, { -1, 432 } } }

-- What is in the bags has changed: the lists are made again, once the burst of packets is over
ashita.events.register('packet_in', 'inv_packet_in', function(e)
    if e.id == packets.inbound.inventoryFinish.id then
        if packets.inbound.inventoryFinish.parse(e.data).flag == 1 then
            debounce(UpdateInventories)
        end
    elseif e.id == packets.inbound.inventoryModify.id then
        debounce(UpdateInventories)
    end
end)

ashita.events.register('d3d_present', 'inv_present', function()
    if not app:BeginFrame() then
        return
    end
    local options = app.options

    -- the player's own order, changed by sorting by hand
    if options.manualOrder ~= manualOrders then
        manualOrders = options.manualOrder
        UpdateInventories()
    end

    showEmptySlots = options.showEmptySlots[1] and true or false
    windowExtra.constraints[2][2] = options.maxHeight[1]

    PadBeginFrame(options)
    app:Window(options.isVisible, DrawWindow, windowExtra)
    PadEndFrame()
end)
