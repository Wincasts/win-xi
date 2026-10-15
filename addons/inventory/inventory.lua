addon.name    = 'inventory'
addon.author  = 'lin, win'
addon.version = '1.0'
addon.desc    = 'The bags in a window: what is in them, and what can be done with it, by mouse or controller.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- The inventory window that was a tool of xitools, as an addon of its own. It needs only winxi: the
-- look of its windows, the controller, the sounds, the packets and what is asked of the game are
-- all the library's.
--
--   /inventory           opens or closes the settings (/inv does the same, as do the verbs after it)
--   /inventory toggle    shows or hides the window
--   /inventory config    opens or closes the settings
--   /inventory focus     gives the open window the controller, or takes it away again
--
-- It was called inv: the settings it kept under that name are brought over once for each character.

require('common')
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local game = require('winxi.game')
local shell = require('winxi.shell')
local packets = require('winxi.packets')
local controller = require('winxi.controller')
local sound = require('winxi.sound')
local itemicons = require('winxi.itemicons')
local tabs = require('winxi.tabs')
local pool = require('pool')
local equipment = require('equipment')

-- Colours and spacing that were xitools' own
local red = { 0.95, 0.20, 0.20, 1.0 }
local yellow = { 1.00, 1.00, 0.00, 1.0 }
local framePadding = { 4, 2 }

local function Say(text)
    print(('\30\81[inventory]\30\01 %s'):format(text))
end

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
        locker = T{},
    },
}

-- How many slots each bag has, by group and bag as inventories is (and 'all' for a group's bags
-- together). Filled in as the bags are read.
local capacities = { bag = { }, satchel = { }, wardrobe = { }, house = { } }

-- Puts together the row at the foot of each tab; defined with the row, further down
local BuildCounts

-- Whether a spot is drawn for each empty slot as well: the Show Empty Slots setting, as of this frame
local showEmptySlots = false
local previewGrid = false
local previewSlots = 0

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

-- What is known of an item whatever bag it is in and however many there are: read from the game's
-- resources the first time the item is met, and kept. Each item in the bags looks here for anything it
-- does not have itself (it has this as its metatable), so reading a bag again makes only small tables.
-- false for an item the game does not know.
local infos = { }

local function Info(res, id)
    local info = infos[id]
    if info ~= nil then
        return info
    end

    local itemRes = res:GetItemById(id)
    if itemRes == nil then
        infos[id] = false
        return false
    end

    info = {
        id = id,
        sortId = itemRes.ResourceId,
        type = itemRes.Type,
        flags = itemRes.Flags,
        targets = itemRes.Targets,
        isUsable = bit.band(1, bit.rshift(itemRes.Flags, 10)) == 1,
        isMoveable = true,
        isTradeable = true,
        isEquippable = itemRes.Type == 4 or itemRes.Type == 5,
        name = ('%s [%i]'):format(Capitalize(itemRes.LogNameSingular[1]), id),
        properName = Capitalize(itemRes.LogNameSingular[1]),
        rawDesc = itemRes.Description[1],
        shortName = itemRes.Name[1],
        longNameS = itemRes.LogNameSingular[1],
        longNameP = itemRes.LogNamePlural[1],
        desc = EscapeString(itemRes.Description[1]),
        stackMax = itemRes.StackSize,
    }

    if info.type == itemTypes.armor
    or info.type == itemTypes.weapon then
        local itemSlots = GetSlots(itemRes.Slots, itemRes.Skill)
        local itemJobs = GetJobs(itemRes.Jobs)
        info.level = ('Lv %i %s'):format(itemRes.Level, itemSlots)
        info.jobs = itemJobs:join(', ')
        info.slots = itemRes.Slots
        -- for the controller's verbose box, which sets gear out in lines of its own
        info.isGear = true
        info.levelText = ('Lv %i'):format(itemRes.Level)
        info.slotName = itemSlots
        info.jobList = itemJobs
        info.races = itemRes.Races
    end

    info.__index = info
    infos[id] = info
    return info
end

-- Where each bag is shown: its group (the tab) and its name within it. The recycle bin is not shown as
-- a bag: the controller's sort menu lists it.
local bagPlaces = {
    [bags.inventory] = { 'bag', 'inv' },
    [bags.tempItems] = { 'bag', 'temp' },
    [bags.mogSatchel] = { 'satchel', 'satchel' },
    [bags.mogCase] = { 'satchel', 'case' },
    [bags.mogSack] = { 'satchel', 'sack' },
    [bags.wardrobe] = { 'wardrobe', 'wardrobe1' },
    [bags.wardrobe2] = { 'wardrobe', 'wardrobe2' },
    [bags.wardrobe3] = { 'wardrobe', 'wardrobe3' },
    [bags.wardrobe4] = { 'wardrobe', 'wardrobe4' },
    [bags.wardrobe5] = { 'wardrobe', 'wardrobe5' },
    [bags.wardrobe6] = { 'wardrobe', 'wardrobe6' },
    [bags.wardrobe7] = { 'wardrobe', 'wardrobe7' },
    [bags.wardrobe8] = { 'wardrobe', 'wardrobe8' },
    [bags.mogSafe] = { 'house', 'mogSafe1' },
    [bags.mogSafe2] = { 'house', 'mogSafe2' },
    [bags.storage] = { 'house', 'storage' },
    [bags.mogLocker] = { 'house', 'locker' },
}

-- The bags of each group, in the order they are put together before sorting
local groupBags = {
    bag = { bags.inventory, bags.tempItems },
    satchel = { bags.mogSatchel, bags.mogCase, bags.mogSack },
    wardrobe = { bags.wardrobe, bags.wardrobe2, bags.wardrobe3, bags.wardrobe4, bags.wardrobe5, bags.wardrobe6, bags.wardrobe7, bags.wardrobe8 },
    house = { bags.mogSafe, bags.mogSafe2, bags.storage, bags.mogLocker },
}

-- Reads one bag from the game's memory. The items that were in it are marked as gone, for a menu still
-- open on one of them.
local function ReadBag(inv, res, bagId)
    local place = bagPlaces[bagId]
    local old = place and inventories[place[1]][place[2]] or inventories.recycleBin
    for _, item in ipairs(old) do
        item.gone = true
    end

    local list = T{ }
    for i = 0, inv:GetContainerCountMax(bagId) do
        local invItem = inv:GetContainerItem(bagId, i)
        local id = invItem ~= nil and invItem.Id or 0
        local info = id ~= 0 and id ~= 65535 and Info(res, id)
        if info then
            local item = setmetatable({
                bagId = bagId,
                slotId = invItem.Index,
                uniqueId = ('%i.%i.%s'):format(bagId, invItem.Index, info.shortName),
                isLocked = bit.band(1, invItem.Flags) == 1 or bagId > 0,
                stackCur = invItem.Count,
            }, info)
            if info.stackMax > 1 then
                item.stack = ('%i / %i'):format(item.stackCur, info.stackMax)
                item.stackText = tostring(item.stackCur or 0) -- drawn over the icon
            end
            list[#list + 1] = item
        end
    end

    if place then
        inventories[place[1]][place[2]] = list
    else
        inventories.recycleBin = list
    end
end

-- Sorts a group's bags, each and all together, in the usual order or the player's own
local function Regroup(group)
    local sorter = sorters[group]
    local all = T{ }
    for _, bagId in ipairs(groupBags[group]) do
        local list = inventories[group][bagPlaces[bagId][2]]
        list:sort(sorter)
        all:extend(list)
    end
    inventories[group].all = all:sort(sorter)
end

-- How many slots each bag has, which bags can be used, the gil, and the row at the foot of each tab:
-- cheap, and done whenever any bag is read
local function UpdateCounts(inv)
    for _, bag in ipairs(moveableBags) do
        if bag.id > 10 then
            bag.hasAccess = game.HasBagAccess(bag.id)
        else
            bag.hasAccess = inv:GetContainerCountMax(bag.id) > 0
        end
    end

    inventories.gil = FormatGil(inv:GetContainerItem(0, 0).Count)

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

-- Which bags are to be read again, and when the last packet came that said so. The game is told of a
-- change by packets that come in bursts, and an addon sees each before the game has made the change:
-- the bags are read once the burst has been quiet for a moment.
local settle = 0.15 -- seconds
local stale = { }
local staleAt = nil

local function MarkStale(bagId)
    if bagId == nil then
        for id = 0, bags.recycleBin do
            stale[id] = true
        end
    elseif bagId >= 0 and bagId <= bags.recycleBin then
        stale[bagId] = true
    end
    staleAt = os.clock()
end
MarkStale(nil)
staleAt = 0

-- Reads the bags marked as changed, once they have settled (or at once, with now). Returns whether
-- anything was read. Until the game has the bags (as the character is loading) they stay marked.
local function RefreshInventories(now)
    if staleAt == nil or (not now and os.clock() - staleAt < settle) then
        return false
    end
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local gil = inv:GetContainerItem(0, 0)
    if gil == nil or inv:GetContainerCountMax(0) == 0 then
        return false
    end

    local res = AshitaCore:GetResourceManager()
    local changed = { }
    for id = 0, bags.recycleBin do
        if stale[id] then
            stale[id] = nil
            ReadBag(inv, res, id)
            local place = bagPlaces[id]
            if place then
                changed[place[1]] = true
            end
        end
    end
    staleAt = nil

    for group in pairs(changed) do
        Regroup(group)
    end
    UpdateCounts(inv)
    return true
end

-- The player's own order has changed: every group is sorted again, with nothing read
local function Resort()
    for group in pairs(groupBags) do
        Regroup(group)
    end
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
local highlightMin, highlightMax = { 0, 0 }, { 0, 0 }
local function AddHighlight(posX, posY, size, drawList)
    local pad = 2
    highlightMin[1], highlightMin[2] = posX - pad, posY - pad
    highlightMax[1], highlightMax[2] = posX + size + pad, posY + size + pad
    drawList:AddRect(highlightMin, highlightMax, highlightColor, 0.0)
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

-- The right-click menu. There is one for the whole window, opened on the item under the mouse; what it
-- offers depends on the group of bags the item is in.
local function FullMenu(item)
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
end

local function WardrobeMenu(item)
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
end

local function SatchelMenu(item)
    if item.isMoveable then
        TryToMove(item)
    end
    if not item.isLocked then
        TryToDrop(item)
    end
end

local itemMenus = { bag = FullMenu, satchel = SatchelMenu, wardrobe = WardrobeMenu }

-- Whether an item has anything in its menu, in the given group of bags
local function HasMenu(item, group)
    if group == 'bag' or group == 'wardrobe' then
        return item.isUsable or item.isMoveable or item.isEquippable or not item.isLocked
    elseif group == 'satchel' then
        return item.isMoveable or not item.isLocked
    end
    return false
end

local menuName = '##inv.itemMenu'
local itemMenu = { item = nil, group = nil, open = false }

-- The item a menu was opened on, as the bags are now: the same slot of the same bag, with the same
-- item in it. A bag is read again whenever anything in it changes, and its items with it.
local function FindAgain(item, group)
    for _, other in ipairs(inventories[group].all) do
        if other.uniqueId == item.uniqueId then
            return other
        end
    end
    return nil
end

-- Opens the menu on an item, from the right-click
local function OpenItemMenu(item, group)
    itemMenu.item, itemMenu.group = item, group
    imgui.OpenPopup(menuName)
end

-- The open menu, once a frame, in the tab it was opened in. It closes if its item has gone.
local function DrawItemMenu()
    itemMenu.open = false
    if itemMenu.item == nil then
        return
    end
    if itemMenu.item.gone then
        itemMenu.item = FindAgain(itemMenu.item, itemMenu.group)
    end
    if imgui.BeginPopup(menuName) then
        itemMenu.open = true
        if itemMenu.item == nil then
            imgui.CloseCurrentPopup()
        else
            itemMenus[itemMenu.group](itemMenu.item)
            if imgui.Selectable('Cancel') then
                imgui.CloseCurrentPopup()
            end
        end
        imgui.EndPopup()
    else
        itemMenu.item = nil
    end
end

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
local tabKeys = { 'bag', 'satchel', 'wardrobe', 'house' }
local tabNames = { 'Bag', 'Satchel', 'Wardrobe', 'House' }

local function TabEnabled(options, index)
    return options.bagTabs[tabKeys[index]][1]
end

local function NextTab(options, index, direction)
    for _ = 1, padTabs do
        index = (index - 1 + direction) % padTabs + 1
        if TabEnabled(options, index) then
            return index
        end
    end
end
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
    Resort()
    return true
end

-- Puts a group back in the usual order. Returns whether it had one of the player's own.
local function ClearPlaces(options, group)
    if options.manualOrder == nil or options.manualOrder[group] == nil then
        return false
    end
    options.manualOrder[group] = nil
    manualOrders = options.manualOrder
    Resort()
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
        pad.wantTab = NextTab(pad.options, pad.tab, action == 'previous' and -1 or 1)
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
    elseif action == 'sort' and TabEnabled(pad.options, pad.tab) then
        pad.menu = SortMenu()
        pad.menuItem = nil
        sound.Play('confirm')
    elseif action == 'back' then
        -- the controller goes back to the game; the window stays, until /inv toggle closes it
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
    if not TabEnabled(options, pad.tab) then
        pad.wantTab = NextTab(options, pad.tab, 1)
        pad.menu, pad.swap = nil, nil
        pad.grid:Reset()
    elseif pad.wantTab ~= nil and not TabEnabled(options, pad.wantTab) then
        pad.wantTab = nil
    end
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

local padMin, padMax = { 0, 0 }, { 0, 0 }

-- Drawn each frame: the sheet the icons are on (winxi.itemicons), their tint (white, with the window's
-- fade), and the item under the mouse, for its tooltip
local iconSheet = nil
local iconFramed = false -- whether itemicons.Frame has been called this frame
local iconWhite = { 1, 1, 1, 1 }

-- The icon sheet for this frame. itemicons.Frame starts a new frame of the sheet, so it is called
-- once a frame, by whichever window draws first, and only if one does.
local function IconSheet()
    if not iconFramed then
        iconFramed = true
        iconSheet = itemicons.Frame()
    end
    return iconSheet
end
local iconTint = 0
local hoveredItem = nil

-- An empty slot: a faint square the size of an item's icon
local emptyFill = { 1.0, 1.0, 1.0, 0.04 }
local emptyEdge = { 1.0, 1.0, 1.0, 0.18 }

-- How many empty slots a bag (or a group's bags together) has to show: none unless they are being shown
local function EmptySlots(bagId, subId)
    local count = #inventories[bagId][subId]
    local slots = showEmptySlots and (capacities[bagId][subId] or 0) or count
    if previewGrid then
        slots = math.max(slots, previewSlots)
    end
    return math.max(0, slots - count)
end

-- A bag's items are laid out here rather than by imgui, a grid of them in rows: the room for the whole
-- grid is kept in one go, and the item under the mouse is worked out from where it is. Only what is in
-- view is drawn, the icons all together and then the stack sizes over them, so that imgui draws the
-- icons in one go (they share winxi.itemicons' sheet) and the text in another.
local rowLengthIsh = 6 -- updated from the Columns setting each frame
local itemGap = { 8, 4 } -- between items, across and down: the shell's spacing for its windows
local stepX, stepY = iconSize + itemGap[1], iconSize + itemGap[2]
local gridSize = { 0, 0 }
local viewportSize = { 0, 0 }
local gridPadding = { 0, 0 }
local viewportMin, viewportMax = { 0, 1 }, { 0, 0 }
local iconMin, iconMax, uvMin, uvMax = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local firstShown, lastShown = 0, -1 -- the items of the bag being drawn that are in view

-- Where the i-th place of a grid at left, top is
local function Spot(left, top, i)
    local index = i - 1
    return left + index % rowLengthIsh * stepX, top + math.floor(index / rowLengthIsh) * stepY
end

-- With the controller: notes where each item is, marks the one picked for swapping and the one the
-- highlight is on, and scrolls that into view as it moves
local function PadItems(items, group, left, top, drawList, windowY)
    for i, item in ipairs(items) do
        local x, y = Spot(left, top, i)
        local inView = i >= firstShown and i <= lastShown
        local index = pad.grid:Add(x, y)
        pad.items[index], pad.groups[index] = item, group

        -- the item picked to be swapped keeps a mark of its own while the other is chosen
        if inView and pad.swap ~= nil and pad.swap.first ~= nil and pad.swap.first.uniqueId == item.uniqueId then
            padMin[1], padMin[2] = x - 1, y - 1
            padMax[1], padMax[2] = x + iconSize + 1, y + iconSize + 1
            drawList:AddRect(padMin, padMax, swapColor, 0.0)
            padMin[1], padMin[2] = x, y
            padMax[1], padMax[2] = x + iconSize, y + iconSize
            drawList:AddRect(padMin, padMax, swapColor, 0.0)
        end

        if pad.grid:IsOn(index) then
            if inView then
                -- two outlines, one inside the other, for a border two pixels thick
                padMin[1], padMin[2] = x - 2, y - 2
                padMax[1], padMax[2] = x + iconSize + 2, y + iconSize + 2
                drawList:AddRect(padMin, padMax, padColor, 0.0)
                padMin[1], padMin[2] = x - 3, y - 3
                padMax[1], padMax[2] = x + iconSize + 3, y + iconSize + 3
                drawList:AddRect(padMin, padMax, padColor, 0.0)
            end
            if pad.grid.moved then
                if imgui.SetScrollFromPosY ~= nil then
                    imgui.SetScrollFromPosY(y - windowY + iconSize / 2, 0.5)
                elseif imgui.SetScrollHereY ~= nil then
                    -- the cursor taken to the item for a moment, and back
                    local cursorX, cursorY = imgui.GetCursorScreenPos()
                    padMin[1], padMin[2] = x, y
                    imgui.SetCursorScreenPos(padMin)
                    imgui.SetScrollHereY(0.5)
                    padMin[1], padMin[2] = cursorX, cursorY
                    imgui.SetCursorScreenPos(padMin)
                end
            end
        end
    end
end

local function DrawBag(bagId, subId)
    local items = inventories[bagId][subId]
    local count = #items
    local total = count + EmptySlots(bagId, subId)
    if total == 0 then
        return
    end

    local left, top = imgui.GetCursorScreenPos()
    gridSize[1] = (math.min(total, rowLengthIsh) - 1) * stepX + iconSize
    gridSize[2] = math.ceil(total / rowLengthIsh) * stepY - itemGap[2]
    imgui.Dummy(gridSize)

    -- the rows in view: the window's, less what is scrolled out of sight
    local _, windowY = imgui.GetWindowPos()
    local _, windowHeight = imgui.GetWindowSize()
    local firstRow = math.max(0, math.floor((windowY - top - iconSize) / stepY) + 1)
    local lastRow = math.floor((windowY + windowHeight - top) / stepY)
    firstShown, lastShown = firstRow * rowLengthIsh + 1, (lastRow + 1) * rowLengthIsh
    local drawList = imgui.GetWindowDrawList()

    -- the item under the mouse, from where the mouse is
    local hovered = nil
    if imgui.IsWindowHovered() then
        local mx, my = imgui.GetMousePos()
        if mx ~= nil and mx >= left and my >= top then
            local column, row = math.floor((mx - left) / stepX), math.floor((my - top) / stepY)
            local i = row * rowLengthIsh + column + 1
            if column < rowLengthIsh and mx - left - column * stepX < iconSize and my - top - row * stepY < iconSize and i <= count then
                hovered = items[i]
            end
        end
    end
    if hovered ~= nil then
        hoveredItem = hovered
        if imgui.IsMouseClicked(1) and HasMenu(hovered, bagId) then
            OpenItemMenu(hovered, bagId)
        end
    end

    -- the icons, then the stack sizes over them, then the marks
    local last = math.min(count, lastShown)
    if iconSheet ~= nil then
        for i = firstShown, last do
            local place = itemicons.Place(items[i].id)
            if place ~= nil then
                local x, y = Spot(left, top, i)
                iconMin[1], iconMin[2], iconMax[1], iconMax[2] = x, y, x + iconSize, y + iconSize
                uvMin[1], uvMin[2], uvMax[1], uvMax[2] = place[1], place[2], place[3], place[4]
                drawList:AddImage(iconSheet, iconMin, iconMax, uvMin, uvMax, iconTint)
            end
        end
    end
    for i = firstShown, last do
        local item = items[i]
        if item.stackText then
            local x, y = Spot(left, top, i)
            AddStackSize(x, y, item.stackText, drawList)
        end
        if item == hovered or (itemMenu.open and item == itemMenu.item) then
            local x, y = Spot(left, top, i)
            AddHighlight(x, y, iconSize, drawList)
        end
    end

    -- the empty slots carry on from the last item, in the same rows
    if total > count then
        local fill, edge = imgui.GetColorU32(emptyFill), imgui.GetColorU32(emptyEdge)
        for i = math.max(count + 1, firstShown), math.min(total, lastShown) do
            local x, y = Spot(left, top, i)
            iconMin[1], iconMin[2], iconMax[1], iconMax[2] = x, y, x + iconSize, y + iconSize
            drawList:AddRectFilled(iconMin, iconMax, fill, 2)
            drawList:AddRect(iconMin, iconMax, edge, 2)
        end
    end

    if pad.active then
        PadItems(items, bagId, left, top, drawList, windowY)
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
-- What the row says only changes when the bags do, so it is put together then (as they are read)
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

local function DrawCountsRow(bagId)
    -- Align to the requested grid width, not the previous frame's window width: using
    -- GetContentRegionAvail here creates a feedback loop that prevents shrinking.
    local countsRight = imgui.GetCursorPosX() + viewportSize[1]
    -- a little room between the slots and this row
    imgui.Dummy(countBuffer)

    -- the gil against the left edge, on the same row as the first (or only) count
    imgui.Text(gilText)

    for index, row in ipairs(countRows[bagId]) do
        if index == 1 then
            imgui.SameLine()
        end

        -- against the right edge, by hand: the text starts its own width short of it
        local width = imgui.CalcTextSize(row.text)
        imgui.SetCursorPosX(math.max(imgui.GetCursorPosX(), countsRight - width))

        if row.full then
            imgui.TextColored(red, row.text)
        else
            imgui.Text(row.text)
        end
    end
end

-- The end of a tab: the tooltip of the item under the mouse, the menu if it is open, and the row of
-- counts at the foot
local function FinishTab(group)
    imgui.EndChild()
    if hoveredItem ~= nil and not itemMenu.open then
        AddTooltip(hoveredItem)
    end
    DrawItemMenu()
    DrawCountsRow(group)
end

-- Begins one of the four tabs. With the controller it is also where a change of tab is asked for and
-- where the tab that is showing is noted.
local function BeginTab(index, label)
    if not TabEnabled(pad.options, index) then
        return false
    end
    local showing
    if pad.wantTab == index then
        showing = tabs.Begin(label, ImGuiTabItemFlags_SetSelected)
    else
        showing = tabs.Begin(label)
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
            if pad.swap ~= nil then
                pad.swap.first = nil
            end
        end
        -- Preview the full chosen size in settings; otherwise fit the content up to that height.
        -- NoBackground leaves the base Winxi window visible through the scrolling region.
        viewportMin[1], viewportMax[1] = viewportSize[1], viewportSize[1]
        viewportMin[2] = previewGrid and viewportMax[2] or 1
        imgui.SetNextWindowSizeConstraints(viewportMin, viewportMax)
        -- The parent already supplies Winxi padding; keep the child's outer width fixed.
        -- Its available content width excludes the scrollbar when one is needed.
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, gridPadding)
        local shown = imgui.BeginChild('##inv.grid.' .. index, viewportSize,
            ImGuiChildFlags_AutoResizeY,
            ImGuiWindowFlags_NoBackground)
        imgui.PopStyleVar()
        if not shown then
            imgui.EndChild()
            imgui.EndTabItem()
            return false
        end
        local availableWidth = imgui.GetContentRegionAvail()
        local normalWidth = rowLengthIsh * (iconSize + itemGap[1]) - itemGap[1]
        local fittedWidth = math.max(rowLengthIsh * iconSize, math.min(normalWidth, availableWidth))
        -- Fit the same number of full-sized icons by reducing only their horizontal gaps.
        -- Use this pitch consistently for drawing, mouse hit testing and controller positions.
        stepX = (fittedWidth - iconSize) / (rowLengthIsh - 1)
    end
    return showing
end

local function DrawInventory()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if tabs.BeginBar('##inv.bags.all', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if BeginTab(1, 'bag##inv.bags.all.1') then
            DrawSubInventory('inventory', 'bag', 'inv')
            DrawSubInventory('temp items', 'bag', 'temp')
            FinishTab('bag')
            imgui.EndTabItem()
        end

        if BeginTab(2, 'satchel##inv.bags.all.2') then
            DrawSubInventory('mog satchel', 'satchel', 'satchel')
            DrawSubInventory('mog case', 'satchel', 'case')
            DrawSubInventory('mog sack', 'satchel', 'sack')
            FinishTab('satchel')
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
            FinishTab('wardrobe')
            imgui.EndTabItem()
        end

        if BeginTab(4, 'house##inv.bags.all.4') then
            DrawSubInventory('mog safe 1', 'house', 'mogSafe1')
            DrawSubInventory('mog safe 2', 'house', 'mogSafe2')
            DrawSubInventory('storage', 'house', 'storage')
            DrawSubInventory('mog locker', 'house', 'locker')
            FinishTab('house')
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
    imgui.PopStyleVar()
end

local function DrawInventoryUnified()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if tabs.BeginBar('##inv.bags.unified', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if BeginTab(1, 'bag##inv.bags.unified.1') then
            DrawBag('bag', 'all')
            FinishTab('bag')
            imgui.EndTabItem()
        end

        if BeginTab(2, 'satchel##inv.bags.unified.2') then
            DrawBag('satchel', 'all')
            FinishTab('satchel')
            imgui.EndTabItem()
        end

        if BeginTab(3, 'ward##inv.bags.unified.3') then
            DrawBag('wardrobe', 'all')
            FinishTab('wardrobe')
            imgui.EndTabItem()
        end

        if BeginTab(4, 'house##inv.bags.unified.4') then
            DrawBag('house', 'all')
            FinishTab('house')
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
    iconTint = imgui.GetColorU32(iconWhite)
    IconSheet()
    hoveredItem = nil

    imgui.SetCursorPosY(imgui.GetCursorPosY() + topPadding)

    if drawOptions.isUnified[1] then
        DrawInventoryUnified()
    else
        DrawInventory()
    end

    -- where the window is, for the box that goes under it and the treasure pool beside it
    local width, height = imgui.GetWindowSize()
    pad.windowX, pad.windowY = imgui.GetWindowPos()
    pad.windowWidth, pad.windowHeight = width, height

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
    maxHeight = T{ 432 }, -- retained for legacy settings import; no longer controls the window
    lockMovement = T{ false },
    gridRows = T{ 8 },
    gridColumns = T{ 6 },
    bagTabs = T{ bag = T{ true }, satchel = T{ true }, wardrobe = T{ true }, house = T{ true } },
    pos = T{ 256, 256 },
    controller = T{ false }, -- experimental: work the window with a controller
    controllerSounds = T{ false }, -- sounds as the controller works the window
    controllerInfo = 'simple', -- what is said of the highlighted item: 'simple' or 'verbose'
    controllerInfoPlace = 'window', -- where the verbose box goes: under the 'window' or the 'item'
    controllerType = 'xinput', -- which kind: a key of winxi.controller's Layouts
    treasurePool = T{ true }, -- the treasure pool, beside the window
    treasureShowEmpty = T{ false }, -- sample treasure in an empty pool, to see it
    treasureDetached = T{ false }, -- the treasure pool as a window of its own
    treasurePos = T{ 256, 100 }, -- where it is, detached
    treasureWidth = T{ 300 }, -- how wide it is
    equipment = T{
        enabled = T{ false },
        pos = T{ 100, 100 },
        lockMovement = T{ false },
        scale = T{ 1 },
        spacing = T{ 4 },
        opacity = T{ 1 },
        background = T{ true },
        slotBackgrounds = T{ true },
        qualityBorders = T{ true },
        wardrobeMarkers = T{ true },
        showEncumbrance = T{ true },
        showAmmoCount = T{ true },
    },
    -- manualOrder: the player's own order of items, once they have made one
}

local windowName = 'winxi.inventory'
local controllerTooltip = 'Work the inventory with a controller while its window is showing.\nD-pad: move the highlight.  LB / RB: change tab.\nA: open the item\'s menu, and choose from it.  B: back out of the menu, or give the controller back to the game (the window stays open: /inv toggle closes it, /inv focus gives it the controller again).\nX (square): the sort menu. Auto puts the tab back in the usual order and part stacks together; Manual swaps the places of two items; Recycle Bin takes back what was dropped.\nThose buttons do not reach the game while the window is showing. Open it with /inv toggle, from a macro.'

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

-- General holds movement, window and controller settings; the shell appends Visibility.
-- Bags and treasure have their own settings tabs.
local function DrawGeneralSettings(options)
    widgets.Label('Lock Drag to Move')
    imgui.Checkbox('##inv.lockMovement', options.lockMovement)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Prevent dragging the inventory window. The Position fields can still move it.')
    end

    if widgets.Header('Window', true) then
        widgets.Label('Visible')
        imgui.Checkbox('##inv.visible', options.isVisible)
        widgets.Label('Position')
        imgui.SetNextItemWidth(widgets.NumberWidth(2))
        if imgui.InputInt2('##inv.position', options.pos) then
            imgui.SetWindowPos(windowName, options.pos)
        end
        widgets.Label('Fade In And Out')
        imgui.Checkbox('##inv.fade', options.fadeInOut)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('The window fades in as it is shown and out as it is hidden, in place of appearing and going at once.')
        end
    end

    if widgets.Header('Controller') then
        shell.ControllerSettings(options, controllerTooltip, DrawControllerSettings)
    end
end

local function DrawBagSettings(options)
    if widgets.Header('Bags', true) then
        widgets.Label('Rows')
        imgui.SetNextItemWidth(widgets.NumberWidth(1))
        imgui.InputInt('##inv.gridRows', options.gridRows, 0, 0)
        options.gridRows[1] = math.max(5, math.min(30, options.gridRows[1]))
        widgets.Label('Columns')
        imgui.SetNextItemWidth(widgets.NumberWidth(1))
        imgui.InputInt('##inv.gridColumns', options.gridColumns, 0, 0)
        options.gridColumns[1] = math.max(6, math.min(30, options.gridColumns[1]))
        for index, key in ipairs(tabKeys) do
            widgets.Label('Show ' .. tabNames[index] .. ' Tab')
            imgui.Checkbox('##inv.tab.' .. key, options.bagTabs[key])
        end
        widgets.Label('Draw Unified Bags')
        imgui.Checkbox('##inv.unified', options.isUnified)
        widgets.Label('Show Empty Slots')
        imgui.Checkbox('##inv.emptySlots', options.showEmptySlots)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Draws a spot for every slot of each bag, with the empty ones as faint squares after the items.')
        end
    end

end

-- The settings, the settings window, the command and the main window's frame are the shell's. The
-- inventory was a tool of xitools, which kept its settings among its own: the shell brings them over
-- once for each character, with xitools' theme and rules for hiding.
local app = shell.New({
    defaults = defaults,
    window = windowName,
    title = 'Inventory',
    configTitle = 'Inventory Settings',
    command = '/inventory',
    aliases = { '/inv' },
    formerName = 'inv',
    help = '/inventory (or /inv) opens or closes the settings; /inv toggle shows or hides the window; /inv focus gives the window the controller, or takes it away.',
    bareOpensConfig = true,
    settingsLabel = 'General',
    drawSettings = DrawGeneralSettings,
    tabs = {
        { label = 'Bags', draw = DrawBagSettings },
        { label = 'Treasure', draw = pool.DrawSettings },
        { label = 'Equipment', draw = equipment.DrawSettings },
    },
    hideAppearance = true,
    hideHeader = 'Visibility',
    import = {
        tool = 'inv',
        keys = {
            'isVisible', 'isUnified', 'showEmptySlots', 'maxHeight', 'pos',
            'controller', 'controllerSounds', 'controllerInfo', 'controllerInfoPlace', 'controllerType',
            'manualOrder',
        },
    },
    onSettings = function(options)
        equipment.Reset()
        -- the player's own order is part of the settings, which may be another character's now
        manualOrders = options.manualOrder
        MarkStale(nil)
        if GetPlayerEntity() ~= nil then
            RefreshInventories(true)
        end
    end,
    commands = {
        focus = function(options)
            if not options.controller[1] then
                Say('Controller Navigation is off: switch it on in /inv config.')
            elseif not options.isVisible[1] then
                Say('The window is closed: /inv toggle opens it.')
            else
                pad.focused = not pad.focused
            end
        end,
    },
})

local windowExtra = { flags = 0 }
local invFrame = { x = 0, y = 0, width = 0, height = 0 } -- where the window is, for the treasure pool

-- The packets that change what is in the bags, and where in each the bag's number is: true for those
-- that change every bag. An item used up, dropped or traded away to the last of it comes as 0x020
-- alone; a move as 0x020 for each bag, then 0x01D.
local bagPackets = {
    [0x00A] = true, -- in a new area
    [0x01C] = true, -- the bags' sizes
    [0x01E] = 0x08, -- how many of an item are in a slot
    [0x01F] = 0x0A, -- an item put in a slot
    [0x020] = 0x0E, -- an item in a slot, with all there is to it
}

-- What is in the bags has changed: the bags named are read again, once the burst of packets is over
ashita.events.register('packet_in', 'inv_packet_in', function(e)
    local at = bagPackets[e.id]
    if at == true then
        MarkStale(nil)
    elseif at ~= nil then
        MarkStale(struct.unpack('B', e.data, at + 1))
    elseif e.id == packets.inbound.inventoryFinish.id then
        -- a bag finished loading names the bag; the end of a change names none, and is all that says
        -- so when nothing else has
        local finish = packets.inbound.inventoryFinish.parse(e.data)
        if finish.container >= 0 and finish.container <= bags.recycleBin then
            MarkStale(finish.container)
        elseif staleAt == nil then
            MarkStale(nil)
        end
    end
end)

ashita.events.register('d3d_present', 'inv_present', function()
    if not app:BeginFrame() then
        return
    end
    local options = app.options

    -- Give combat gear changes first access to the icon upload budget and read them before
    -- any debounced bag scans/sorting. Equipment never waits for inventory packets to settle.
    iconFramed = false
    if options.equipment.enabled[1] then
        equipment.Draw(options, IconSheet())
    end

    -- the player's own order, changed by sorting by hand
    if options.manualOrder ~= manualOrders then
        manualOrders = options.manualOrder
        Resort()
    end

    RefreshInventories()

    showEmptySlots = options.showEmptySlots[1] and true or false
    previewGrid = app.showConfig[1]
    -- Normalize loaded settings too, so older characters also obey the minimums.
    options.gridColumns[1] = math.max(6, math.min(30, math.floor(options.gridColumns[1])))
    options.gridRows[1] = math.max(5, math.min(30, math.floor(options.gridRows[1])))
    rowLengthIsh = options.gridColumns[1]
    local rows = options.gridRows[1]
    viewportSize[1] = rowLengthIsh * (iconSize + itemGap[1]) - itemGap[1]
    previewSlots = rows * rowLengthIsh
    viewportSize[2] = 0 -- AutoResizeY fits actual content, bounded by the selected rows
    viewportMax[2] = rows * stepY - itemGap[2]

    PadBeginFrame(options)
    windowExtra.flags = options.lockMovement[1] and ImGuiWindowFlags_NoMove or 0
    app:Window(options.isVisible, DrawWindow, windowExtra)
    if pad.windowX ~= nil then
        invFrame.x, invFrame.y = pad.windowX, pad.windowY
        invFrame.width, invFrame.height = pad.windowWidth, pad.windowHeight
        pool.Draw(options, invFrame, options.isVisible[1])
    else
        pool.Draw(options, nil, options.isVisible[1])
    end
    PadEndFrame()
end)
