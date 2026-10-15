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
local config = require('config')

-- Colours and spacing that were xitools' own
local red = { 0.95, 0.20, 0.20, 1.0 }
local yellow = { 1.00, 1.00, 0.00, 1.0 }
local framePadding = { 4, 2 }

local function Say(text)
    print(('\30\81[inventory]\30\01 %s'):format(text))
end

local fontWidth = imgui.CalcTextSize('A')

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

-- Every bag the window shows, in the order it shows them: its group (the tab it is in), its key in
-- the group, what it is called over its items and in the counts (title), and in the move menu and
-- what sorting says (name), and on its tab under the grid (tab, or else name). Temporary items have no slots of their own: they are not counted,
-- sorted or moved to. The wardrobes take gear alone; the house's bags cannot be moved to from afar.
-- The recycle bin is not shown as a bag: the controller's sort menu lists it.
local bagList = {
    { id = bags.inventory,  group = 'bag',      key = 'inv',       title = 'inventory',   name = 'inventory' },
    { id = bags.tempItems,  group = 'bag',      key = 'temp',      title = 'temp items',  name = 'temp items', noSlots = true },
    { id = bags.mogSatchel, group = 'satchel',  key = 'satchel',   title = 'mog satchel', name = 'satchel' },
    { id = bags.mogCase,    group = 'satchel',  key = 'case',      title = 'mog case',    name = 'case' },
    { id = bags.mogSack,    group = 'satchel',  key = 'sack',      title = 'mog sack',    name = 'sack' },
    { id = bags.wardrobe,   group = 'wardrobe', key = 'wardrobe1', title = 'wardrobe 1',  name = 'wardrobe 1', tab = '1', isGearOnly = true },
    { id = bags.wardrobe2,  group = 'wardrobe', key = 'wardrobe2', title = 'wardrobe 2',  name = 'wardrobe 2', tab = '2', isGearOnly = true },
    { id = bags.wardrobe3,  group = 'wardrobe', key = 'wardrobe3', title = 'wardrobe 3',  name = 'wardrobe 3', tab = '3', isGearOnly = true },
    { id = bags.wardrobe4,  group = 'wardrobe', key = 'wardrobe4', title = 'wardrobe 4',  name = 'wardrobe 4', tab = '4', isGearOnly = true },
    { id = bags.wardrobe5,  group = 'wardrobe', key = 'wardrobe5', title = 'wardrobe 5',  name = 'wardrobe 5', tab = '5', isGearOnly = true },
    { id = bags.wardrobe6,  group = 'wardrobe', key = 'wardrobe6', title = 'wardrobe 6',  name = 'wardrobe 6', tab = '6', isGearOnly = true },
    { id = bags.wardrobe7,  group = 'wardrobe', key = 'wardrobe7', title = 'wardrobe 7',  name = 'wardrobe 7', tab = '7', isGearOnly = true },
    { id = bags.wardrobe8,  group = 'wardrobe', key = 'wardrobe8', title = 'wardrobe 8',  name = 'wardrobe 8', tab = '8', isGearOnly = true },
    { id = bags.mogSafe,    group = 'house',    key = 'mogSafe1',  title = 'mog safe 1',  name = 'safe 1' },
    { id = bags.mogSafe2,   group = 'house',    key = 'mogSafe2',  title = 'mog safe 2',  name = 'safe 2' },
    { id = bags.storage,    group = 'house',    key = 'storage',   title = 'storage',     name = 'storage' },
    { id = bags.mogLocker,  group = 'house',    key = 'locker',    title = 'mog locker',  name = 'locker' },
}

-- The groups, in the order of their tabs
local tabGroups = { 'bag', 'satchel', 'wardrobe', 'house' }

-- In the unified view, a group of more than one bag has tabs of its own under the grid: all of its
-- bags together, or one alone. The bag chosen for each group (none: all of them), and the bags that
-- have a tab (those the player has), as of the last time the bags were read.
local shownBag = { }
local bagTabs = { }

-- What is put together from the list: each bag by the game's number for it, the bags of each group,
-- those an item can be moved to, what is in each (as read, and each group's all together) and how
-- many slots each has
local bagsById, groupBags, moveableBags = { }, { }, { }
local inventories = T{ gil = 0, recycleBin = T{ } }
local capacities = { }
for _, group in ipairs(tabGroups) do
    groupBags[group], inventories[group], capacities[group] = { }, T{ all = T{ } }, { all = 0 }
end
for _, bag in ipairs(bagList) do
    bag.slots, bag.hasAccess = 0, false -- filled in as the bags are read
    bag.tabId = ('%s##inv.bags.sub.%s'):format(bag.tab or bag.name, bag.key)
    bagsById[bag.id] = bag
    local inGroup = groupBags[bag.group]
    inGroup[#inGroup + 1] = bag
    inventories[bag.group][bag.key] = T{ }
    capacities[bag.group][bag.key] = 0
    if not bag.noSlots and bag.group ~= 'house' then
        moveableBags[#moveableBags + 1] = bag
    end
end

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
            local left = order[lhs.orderKey] or unplaced
            local right = order[rhs.orderKey] or unplaced
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
-- false for an item the game does not know. The equipment window looks here too.
local infos = { }

local function Info(id)
    local info = infos[id]
    if info ~= nil then
        return info
    end

    local itemRes = AshitaCore:GetResourceManager():GetItemById(id)
    if itemRes == nil then
        infos[id] = false
        return false
    end

    info = {
        id = id,
        orderKey = OrderKey(id), -- its key in the player's own order, made once rather than at each comparison
        sortId = itemRes.ResourceId,
        type = itemRes.Type,
        flags = itemRes.Flags,
        targets = itemRes.Targets,
        isUsable = bit.band(1, bit.rshift(itemRes.Flags, 10)) == 1,
        isEquippable = itemRes.Type == 4 or itemRes.Type == 5,
        name = ('%s [%i]'):format(Capitalize(itemRes.LogNameSingular[1]), id),
        properName = Capitalize(itemRes.LogNameSingular[1]),
        rawDesc = itemRes.Description[1],
        shortName = itemRes.Name[1],
        longNameS = itemRes.LogNameSingular[1],
        longNameP = itemRes.LogNamePlural[1],
        desc = EscapeString(itemRes.Description[1]),
        stackMax = itemRes.StackSize,
        -- high quality, for the equipment window's border: the game has no mark for it, but names an
        -- item's HQ as a separate item, with +1 (or +2, +3) after the name
        isHQ = itemRes.Name[1]:match(' %+%d$') ~= nil,
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
equipment.SetItemInfo(Info)

-- Reads one bag from the game's memory. The items that were in it are marked as gone, for a menu still
-- open on one of them.
local function ReadBag(inv, bagId)
    local bag = bagsById[bagId]
    local old = bag and inventories[bag.group][bag.key] or inventories.recycleBin
    for _, item in ipairs(old) do
        item.gone = true
    end

    local list = T{ }
    for i = 0, inv:GetContainerCountMax(bagId) do
        local invItem = inv:GetContainerItem(bagId, i)
        local id = invItem ~= nil and invItem.Id or 0
        local info = id ~= 0 and id ~= 65535 and Info(id)
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

    if bag then
        inventories[bag.group][bag.key] = list
    else
        inventories.recycleBin = list
    end
end

-- Sorts a group's bags, each and all together, in the usual order or the player's own
local function Regroup(group)
    local sorter = sorters[group]
    local all = T{ }
    for _, bag in ipairs(groupBags[group]) do
        local list = inventories[group][bag.key]
        list:sort(sorter)
        all:extend(list)
    end
    inventories[group].all = all:sort(sorter)
end

-- How many slots a bag has: none for one the player cannot use (wardrobes 3 to 8 must be unlocked)
local function BagSlots(inv, bagId)
    if bagId >= bags.wardrobe3 and bagId <= bags.wardrobe8 and not game.HasBagAccess(bagId) then
        return 0
    end
    return math.max(0, inv:GetContainerCountMax(bagId))
end

-- How many slots each bag has, which bags can be used, the gil, and the row at the foot of each tab:
-- cheap, and done whenever any bag is read. Temporary items have no fixed slots worth showing.
local function UpdateCounts(inv)
    inventories.gil = FormatGil(inv:GetContainerItem(0, 0).Count)

    for _, group in ipairs(tabGroups) do
        capacities[group].all = 0 -- the unified view of a group has the slots of all its bags together
    end
    for _, bag in ipairs(bagList) do
        bag.slots = not bag.noSlots and BagSlots(inv, bag.id) or 0
        bag.hasAccess = bag.slots > 0
        local inGroup = capacities[bag.group]
        inGroup[bag.key] = bag.slots
        inGroup.all = inGroup.all + bag.slots
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

    local changed = { }
    for id = 0, bags.recycleBin do
        if stale[id] then
            stale[id] = nil
            ReadBag(inv, id)
            local bag = bagsById[id]
            if bag then
                changed[bag.group] = true
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

-- What can be done with an item from the given group of bags, as menu entries: the rules for both
-- the right-click menu and the controller's. Each entry has its label and what it does (run). In the
-- right-click menu moving and dropping are in submenus of their own: submenu names it, and short is
-- the entry's label there. Dropping is asked about first with the controller (run gives the menu that
-- asks), and done at once from the right-click menu's Drop submenu (direct).
local function ItemEntries(item, group)
    local entries = { }
    if group == 'house' then
        return entries
    end

    local carried = (group == 'bag')
    local worn = (group == 'wardrobe')

    if (carried or worn) and item.isUsable then
        entries[#entries + 1] = { label = 'Use', run = function() UseItem(item) end }
    end
    if carried then
        entries[#entries + 1] = { label = 'Trade', run = function() TradeItem(item) end }
    end
    if (carried or worn) and item.isEquippable then
        for _, slotName in ipairs(EquipSlots(item)) do
            entries[#entries + 1] = { label = ('Equip to %s'):format(slotName), run = function() EquipItem(item, slotName) end }
        end
    end
    for _, bag in ipairs(moveableBags) do
        if CanMoveTo(item, bag) then
            entries[#entries + 1] = {
                label = ('Move to %s'):format(bag.name), submenu = 'Move', short = ('to %s'):format(bag.name),
                run = function() MoveItem(item, bag) end,
            }
        end
    end
    if not item.isLocked then
        -- TODO: add quantity picker
        local drop = function() DropItem(item) end
        entries[#entries + 1] = {
            label = 'Drop...', submenu = 'Drop', short = DropLabel(item), direct = drop,
            run = function()
                -- with Cancel the choice that is highlighted
                return controller.NewMenu(item.shortName, {
                    { label = 'Cancel' },
                    { label = DropLabel(item), run = drop },
                })
            end,
        }
    end

    return entries
end

-- The right-click menu's entries: each in a line of its own, or together in its submenu
local function DrawEntries(entries)
    local i = 1
    while i <= #entries do
        local entry = entries[i]
        if entry.submenu == nil then
            if imgui.Selectable(entry.label) then
                entry.run()
            end
            i = i + 1
        else
            local submenu = entry.submenu
            local open = imgui.BeginMenu(submenu)
            while i <= #entries and entries[i].submenu == submenu do
                local inner = entries[i]
                if open and imgui.MenuItem(inner.short) then
                    (inner.direct or inner.run)()
                end
                i = i + 1
            end
            if open then
                imgui.EndMenu()
            end
        end
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

local highlightBlue = { 0.23, 0.67, 0.91, 1.0 }
local highlightColor = 0
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
local menuName = '##inv.itemMenu'
local itemMenu = { item = nil, group = nil, entries = nil, open = false, opening = false }

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

-- Opens the menu on an item, from the right-click. The click is seen in the grid's scrolling region,
-- but the menu is begun in the window around it, after the region ends; imgui knows a popup by its
-- name and the window it was opened in, so it is opened there too, as the menu is drawn.
local function OpenItemMenu(item, group, entries)
    itemMenu.item, itemMenu.group, itemMenu.entries = item, group, entries
    itemMenu.opening = true
end

-- The open menu, once a frame, in the tab it was opened in. It closes if its item has gone.
local function DrawItemMenu()
    itemMenu.open = false
    if itemMenu.item == nil then
        return
    end
    if itemMenu.item.gone then
        itemMenu.item = FindAgain(itemMenu.item, itemMenu.group)
        itemMenu.entries = itemMenu.item and ItemEntries(itemMenu.item, itemMenu.group)
    end
    if itemMenu.opening then
        itemMenu.opening = false
        imgui.OpenPopup(menuName)
    end
    if imgui.BeginPopup(menuName) then
        itemMenu.open = true
        if itemMenu.item == nil then
            imgui.CloseCurrentPopup()
        else
            DrawEntries(itemMenu.entries)
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

local padTabs = #tabGroups
local tabNames = { 'Bag', 'Satchel', 'Wardrobe', 'House' }
config.tabGroups, config.tabNames = tabGroups, tabNames

local function TabEnabled(options, index)
    return options.bagTabs[tabGroups[index]][1]
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
local padYellow = { 1.0, 0.85, 0.3, 1.0 }
local swapTextColor = { 0.3, 0.9, 0.4, 1.0 }
local padColor, swapColor = 0, 0 -- packed once a frame, in the window

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

    local group = tabGroups[pad.tab]
    for _, bag in ipairs(groupBags[group] or { }) do
        local id = bag.id
        local chosen = shownBag[group] == nil or shownBag[group] == bag
        if chosen and not bag.noSlots and BagSlots(inv, id) > 0 and now - (sortedAt[id] or -sortCooldown) >= sortCooldown then
            sortedAt[id] = now
            AshitaCore:GetPacketManager():AddOutgoingPacket(packets.outbound.inventorySort:make(id))
            sorted[#sorted + 1] = bag.name
        end
    end

    if #sorted > 0 then
        Say(('Sorted: %s.'):format(table.concat(sorted, ', ')))
    end
    return #sorted > 0
end

-- Swaps the places of two items in the window, by the controller's Manual sort. The places of
-- everything in the group are written down as they stand first, so that the two change and nothing
-- else does. Returns whether anything changed: two stacks of the same item share a place.
local function SwapPlaces(options, group, first, second)
    if first.id == second.id then
        return false
    end

    local order, place = T{ }, 0
    for _, item in ipairs(inventories[group].all) do
        local key = item.orderKey
        if order[key] == nil then
            place = place + 1
            order[key] = place
        end
    end

    local firstKey, secondKey = first.orderKey, second.orderKey
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
        local entries = item ~= nil and ItemEntries(item, pad.groups[pad.grid.cursor]) or nil
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
                    -- under the window, its left edge in line with the window's, and under the
                    -- equipment monitor if that is there
                    local monitor = equipment.Rect()
                    local below = monitor ~= nil and monitor[2] + monitor[4] or (pad.windowY + pad.windowHeight)
                    controller.Label(DrawInfoBox, pad.windowX, below + labelGap, true, item.uniqueId)
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

-- A slot, full or empty: a faint square the size of an item's icon, under the icon
local slotFill = { 1.0, 1.0, 1.0, 0.04 }
local slotEdge = { 1.0, 1.0, 1.0, 0.18 }
local slotFillColor, slotEdgeColor = 0, 0 -- packed once a frame, in the window

-- Dragging an item with the mouse, while Lock holds the window still: dropped on another
-- item of the tab, the two swap places (the player's own order, as the controller's Manual sort);
-- dropped on another tab's name at the top, it is moved to that group's bag with room (the one chosen
-- under the grid, if any, first). The item picked up, its group and where the mouse was, and whether
-- it has moved far enough to be a drag rather than a click.
local drag = {
    item = nil, group = nil, x = 0, y = 0, moving = false,
    start = 4, -- pixels the mouse moves before a press on an item is a drag
    white = { 1, 1, 1, 0.75 }, min = { 0, 0 }, max = { 0, 0 },
}
local tabRects = { } -- each main tab's name, where it was drawn this frame: { left, top, right, bottom }
for index = 1, #tabGroups do
    tabRects[index] = { shown = false, 0, 0, 0, 0 }
end

-- How many empty slots a bag (or a group's bags together) has to show: none unless they are being shown
local function EmptySlots(group, key)
    local count = #inventories[group][key]
    local slots = showEmptySlots and capacities[group][key] or count
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
-- The grid's scrolling region is as wide as its slots, so the window, and the tabs above and the row
-- below, are as wide as the slots too. The outlines drawn just outside a slot (the mouse's 2 pixels
-- out, the controller's 3) would be cut off at the region's edge: they are drawn with the region's
-- clip widened by this much.
local outline = { room = 3, min = { 0, 0 }, max = { 0, 0 } }
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

local function DrawBag(group, key)
    local items = inventories[group][key]
    local count = #items
    local total = count + EmptySlots(group, key)
    if total == 0 then
        return
    end

    local left, top = imgui.GetCursorScreenPos()
    gridSize[1] = (math.min(total, rowLengthIsh) - 1) * stepX + iconSize
    gridSize[2] = math.ceil(total / rowLengthIsh) * stepY - itemGap[2]
    imgui.Dummy(gridSize)

    -- the rows in view: the window's, less what is scrolled out of sight
    local windowX, windowY = imgui.GetWindowPos()
    local windowWidth, windowHeight = imgui.GetWindowSize()
    local firstRow = math.max(0, math.floor((windowY - top - iconSize) / stepY) + 1)
    local lastRow = math.floor((windowY + windowHeight - top) / stepY)
    firstShown, lastShown = firstRow * rowLengthIsh + 1, (lastRow + 1) * rowLengthIsh
    local drawList = imgui.GetWindowDrawList()
    outline.min[1], outline.min[2] = windowX - outline.room, windowY - outline.room
    outline.max[1], outline.max[2] = windowX + windowWidth + outline.room, windowY + windowHeight + outline.room

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
        if imgui.IsMouseClicked(1) then
            local entries = ItemEntries(hovered, group)
            if #entries > 0 then
                OpenItemMenu(hovered, group, entries)
            end
        elseif imgui.IsMouseClicked(0) and pad.options.lockMovement[1] then
            drag.item, drag.group, drag.moving = hovered, group, false
            drag.x, drag.y = imgui.GetMousePos()
        end
    end

    -- a faint square for every slot, the items' and the empty ones' that carry on after them in the
    -- same rows; then the icons over them, the stack sizes over those, and the marks
    for i = firstShown, math.min(total, lastShown) do
        local x, y = Spot(left, top, i)
        iconMin[1], iconMin[2], iconMax[1], iconMax[2] = x, y, x + iconSize, y + iconSize
        drawList:AddRectFilled(iconMin, iconMax, slotFillColor, 2)
        drawList:AddRect(iconMin, iconMax, slotEdgeColor, 2)
    end

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
        if item == hovered or (itemMenu.open and item == itemMenu.item) or (drag.moving and item == drag.item) then
            local x, y = Spot(left, top, i)
            drawList:PushClipRect(outline.min, outline.max, false)
            AddHighlight(x, y, iconSize, drawList)
            drawList:PopClipRect()
        end
    end

    if pad.active then
        drawList:PushClipRect(outline.min, outline.max, false)
        PadItems(items, group, left, top, drawList, windowY)
        drawList:PopClipRect()
    end
end

local function DrawSubInventory(title, group, key)
    -- a bag with nothing in it is left out, unless its empty slots are being shown
    if #inventories[group][key] == 0 and EmptySlots(group, key) == 0 then
        return
    end

    imgui.Text(title)
    imgui.Separator()
    DrawBag(group, key)
    imgui.NewLine()
end

-- The row at the foot of a tab: the gil on the left and, on the right, how full each of the tab's bags
-- is, as 08/30. In the unified view it is one count, of the bag chosen under the grid or, on the all
-- tab, of the group's bags together. In the separate view a tab with one bag shows the count alone;
-- one with several names each, one to a row under the first. A full count is red. Bags the player
-- does not have, and temporary items, which have no slots of their own to fill, are left out.
--
-- What the row says only changes when the bags do, so it is put together then (as they are read)
-- and only drawn here.
local countBuffer = { 0, 3 } -- between the slots and the row
local countRows = { bag = { }, satchel = { }, wardrobe = { }, house = { } } -- each: { text, full }
-- the unified view's all tab: the group's bags as one count, how many used of how many there are
local allRows = { bag = { }, satchel = { }, wardrobe = { }, house = { } }
local gilText = '0 G'

BuildCounts = function()
    gilText = ('%s G'):format(inventories.gil)

    for group, inGroup in pairs(groupBags) do
        local shown = 0
        for _, bag in ipairs(inGroup) do
            if bag.slots > 0 then
                shown = shown + 1
            end
        end

        local rows, withTabs = { }, { }
        local allUsed, allSlots = 0, 0
        for _, bag in ipairs(inGroup) do
            if bag.slots > 0 then
                local used = #inventories[group][bag.key]
                allUsed, allSlots = allUsed + used, allSlots + bag.slots
                local text = ('%02d/%02d'):format(used, bag.slots)
                -- the bag's count alone, for when its tab is chosen
                bag.countRows = { { text = text, full = used >= bag.slots } }
                if shown > 1 then
                    text = ('%s %s'):format(bag.title, text)
                end
                rows[#rows + 1] = { text = text, full = used >= bag.slots }
                withTabs[#withTabs + 1] = bag
            end
        end
        countRows[group] = rows
        allRows[group] = allSlots > 0
            and { { text = ('%02d/%02d'):format(allUsed, allSlots), full = allUsed >= allSlots } } or { }
        bagTabs[group] = withTabs
        -- a chosen bag the player no longer has is no longer chosen
        if shownBag[group] ~= nil and shownBag[group].slots == 0 then
            shownBag[group] = nil
        end
    end
end

local function DrawCountsRow(group, unified)
    -- Align to the requested grid width, not the previous frame's window width: using
    -- GetContentRegionAvail here creates a feedback loop that prevents shrinking.
    local countsRight = imgui.GetCursorPosX() + viewportSize[1]
    -- a little room between the slots and this row
    imgui.Dummy(countBuffer)

    -- the gil against the left edge, on the same row as the first (or only) count
    imgui.Text(gilText)

    -- unified: the chosen bag's count, or all of the group's as one; otherwise each bag's, named
    local rows = countRows[group]
    if unified then
        rows = shownBag[group] and shownBag[group].countRows or allRows[group]
    end
    for index, row in ipairs(rows) do
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

-- The tabs under the grid, for a group of more than one bag: all of them, then each alone. The bag
-- chosen here is drawn from the next frame on.
local allTabIds = { }
for _, group in ipairs(tabGroups) do
    allTabIds[group] = {
        region = '##inv.bags.sub.region.' .. group,
        bar = '##inv.bags.sub.' .. group,
        all = 'all##inv.bags.sub.all.' .. group,
    }
end
local bagTabsRow = {
    size = { 0, 0 },
    line = 4, -- room under the tabs for the line the theme draws along a bar's foot
    flags = bit.bor(ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse),
    barFlags = bit.bor(ImGuiTabBarFlags_NoCloseWithMiddleMouseButton, ImGuiTabBarFlags_FittingPolicyShrink),
}

local function DrawBagTabs(group)
    local withTabs = bagTabs[group]
    if withTabs == nil or #withTabs < 2 then
        return
    end
    local ids = allTabIds[group]
    local chosen = shownBag[group]
    -- in a region as wide as the grid: imgui widens a window to a tab bar's tabs at their full
    -- width, and the house's would be wider than a few columns of slots; here they shrink to fit
    local row = bagTabsRow
    local frame = imgui.GetFrameHeight() or (imgui.GetFontSize() + 2 * framePadding[2])
    row.size[1], row.size[2] = viewportSize[1], frame + row.line
    imgui.BeginChild(ids.region, row.size, 0, row.flags)
    if tabs.BeginBar(ids.bar, row.barFlags) then
        if tabs.Begin(ids.all) then
            chosen = nil
            imgui.EndTabItem()
        end
        for _, bag in ipairs(withTabs) do
            if tabs.Begin(bag.tabId) then
                chosen = bag
                imgui.EndTabItem()
            end
        end
        imgui.EndTabBar()
    end
    imgui.EndChild()
    if chosen ~= shownBag[group] then
        -- other items: the highlight starts again from the first
        shownBag[group] = chosen
        pad.grid:Reset()
        pad.menu = nil
    end
end

-- The end of a tab: the tooltip of the item under the mouse, the menu if it is open, the row of
-- counts, and in the unified view the tabs of the group's bags, at the foot
-- The grid's scroll bar, slim, just outside its right edge in the window's padding, where it takes no
-- room from the slots: how far down the grid is scrolled, and how much of it is in view. Drawn only
-- while it scrolls. It is measured in the grid and drawn in the window around it. The strip beside the
-- grid, from its right edge to the window's, is where the bar is dragged: a press on the bar takes
-- hold of it where it is pressed, and a press elsewhere in the strip brings its middle to the mouse
-- first. The window is not moved by a press there, locked or not.
local scrollBar = {
    width = 2, gap = 2, white = { 1, 1, 1, 0.35 }, bright = { 1, 1, 1, 0.7 }, min = { 0, 0 }, max = { 0, 0 },
    zone = { shown = false, 0, 0, 0, 0 }, -- the strip, this frame: { left, top, right, bottom }
    grab = nil, -- while dragged: how far below the bar's top the mouse holds it
    top = 0, length = 0, height = 0, most = 0, hovered = false,
}

-- in the grid, before it ends: whether it scrolls, and where the bar goes; while the bar is dragged,
-- the grid is scrolled to follow the mouse
local function MeasureScrollBar()
    local bar = scrollBar
    local most = imgui.GetScrollMaxY ~= nil and imgui.GetScrollMaxY() or 0
    if most <= 0 then
        bar.grab = nil
        return false
    end
    local scrolled = imgui.GetScrollY() or 0
    local x, y = imgui.GetWindowPos()
    local width, height = imgui.GetWindowSize()
    local length = math.max(8, height * height / (height + most))
    if bar.grab ~= nil then
        if imgui.IsMouseDown(0) then
            local _, my = imgui.GetMousePos()
            local room = height - length
            if my ~= nil and room > 0 then
                scrolled = math.max(0, math.min(most, (my - bar.grab - y) * most / room))
                imgui.SetScrollY(scrolled)
            end
        else
            bar.grab = nil
        end
    end
    local right = x + width
    bar.top, bar.length, bar.height, bar.most = y, length, height, most
    bar.min[1], bar.min[2] = right + bar.gap, y + (height - length) * scrolled / most
    bar.max[1], bar.max[2] = right + bar.gap + bar.width, bar.min[2] + length
    local zone = bar.zone
    zone[1], zone[2], zone[4] = right, y, y + height
    return true
end

-- in the window, once the grid has ended: the strip beside the grid reaches the window's right edge,
-- and a press in it takes hold of the bar
local function HoldScrollBar()
    local bar, zone = scrollBar, scrollBar.zone
    local x = imgui.GetWindowPos()
    local width = imgui.GetWindowSize()
    zone[3], zone.shown = x + width, true
    local mx, my = imgui.GetMousePos()
    bar.hovered = mx ~= nil and imgui.IsWindowHovered()
        and mx >= zone[1] and mx < zone[3] and my >= zone[2] and my < zone[4]
    if bar.hovered and bar.grab == nil and imgui.IsMouseClicked(0) then
        if my >= bar.min[2] and my < bar.max[2] then
            bar.grab = my - bar.min[2]
        else
            bar.grab = bar.length / 2
        end
    end
end

local function FinishTab(group, unified)
    local scrolls = MeasureScrollBar()
    imgui.EndChild()
    if scrolls then
        HoldScrollBar()
        local color = (scrollBar.hovered or scrollBar.grab ~= nil) and scrollBar.bright or scrollBar.white
        imgui.GetWindowDrawList():AddRectFilled(scrollBar.min, scrollBar.max, imgui.GetColorU32(color), 1)
    end
    if hoveredItem ~= nil and not itemMenu.open and not drag.moving then
        AddTooltip(hoveredItem)
    end
    DrawItemMenu()
    DrawCountsRow(group, unified)
    if unified then
        DrawBagTabs(group)
    end
end

local gridIds = { }
for index = 1, #tabGroups do
    gridIds[index] = '##inv.grid.' .. index
end
local gridFlags = bit.bor(ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoScrollbar)

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
    local rect = tabRects[index]
    rect[1], rect[2] = imgui.GetItemRectMin()
    rect[3], rect[4] = imgui.GetItemRectMax()
    rect.shown = true

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
        -- The parent supplies Winxi padding; the child, with no border, has none of its own, and is
        -- exactly as wide as the slots. It has no scrollbar of its own, which would take room from
        -- the slots and look like padding (the theme's track is clear): the wheel still scrolls it,
        -- and FinishTab draws a slim bar just outside its right edge in its place.
        local shown = imgui.BeginChild(gridIds[index], viewportSize, ImGuiChildFlags_AutoResizeY, gridFlags)
        if not shown then
            imgui.EndChild()
            imgui.EndTabItem()
            return false
        end
    end
    return showing
end

-- The tabs, one for each group: its bags one under another, each with its title, or (unified) all
-- of them together in one grid. The ids are made once, for each kind of tab bar.
local tabLabels = { 'bag', 'satchel', 'ward', 'house' }
local tabBars = { }
for _, kind in ipairs({ 'all', 'unified' }) do
    local ids = { bar = '##inv.bags.' .. kind }
    for index, label in ipairs(tabLabels) do
        ids[index] = ('%s##inv.bags.%s.%d'):format(label, kind, index)
    end
    tabBars[kind] = ids
end

local function DrawTabs(unified)
    local ids = tabBars[unified and 'unified' or 'all']
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding)
    if tabs.BeginBar(ids.bar, ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        for index, group in ipairs(tabGroups) do
            if BeginTab(index, ids[index]) then
                if unified then
                    local chosen = shownBag[group]
                    DrawBag(group, chosen and chosen.key or 'all')
                else
                    for _, bag in ipairs(groupBags[group]) do
                        DrawSubInventory(bag.title, group, bag.key)
                    end
                end
                FinishTab(group, unified)
                imgui.EndTabItem()
            end
        end
        imgui.EndTabBar()
    end
    imgui.PopStyleVar()
end

-- Moves an item to the group of another tab: to the bag chosen under its grid if that has room, or
-- else to the first of the group's bags that can take it and has room
local function MoveToGroup(item, group)
    local chosen, best = shownBag[group], nil
    for _, bag in ipairs(moveableBags) do
        if bag.group == group and CanMoveTo(item, bag) and #inventories[group][bag.key] < bag.slots then
            if bag == chosen then
                best = bag
                break
            end
            best = best or bag
        end
    end
    if best == nil then
        Say(('No room for %s in the %s tab, or it cannot go there.'):format(item.shortName, group))
        sound.Play('error')
        return
    end
    MoveItem(item, best)
end

-- Carries an item being dragged under the mouse, and drops it where the button is let go
local function DrawDrag()
    if drag.item == nil then
        return
    end
    local mx, my = imgui.GetMousePos()
    if imgui.IsMouseDown(0) then
        if not drag.moving and mx ~= nil and math.abs(mx - drag.x) + math.abs(my - drag.y) >= drag.start then
            drag.moving = true
        end
        local place = drag.moving and iconSheet ~= nil and itemicons.Place(drag.item.id) or nil
        if place ~= nil then
            drag.min[1], drag.min[2] = mx - iconSize / 2, my - iconSize / 2
            drag.max[1], drag.max[2] = drag.min[1] + iconSize, drag.min[2] + iconSize
            uvMin[1], uvMin[2], uvMax[1], uvMax[2] = place[1], place[2], place[3], place[4]
            imgui.GetForegroundDrawList():AddImage(iconSheet, drag.min, drag.max, uvMin, uvMax,
                imgui.GetColorU32(drag.white))
        end
        return
    end

    -- let go: on another item of the tab, or on another tab's name
    local item, group, moving = drag.item, drag.group, drag.moving
    drag.item, drag.group, drag.moving = nil, nil, false
    if not moving or item.gone then
        return
    end
    if hoveredItem ~= nil and hoveredItem ~= item then
        if not SwapPlaces(pad.options, group, item, hoveredItem) then
            sound.Play('error') -- two stacks of the same item share a place
        end
        return
    end
    for index, rect in ipairs(tabRects) do
        if rect.shown and tabGroups[index] ~= group and mx ~= nil
            and mx >= rect[1] and mx < rect[3] and my >= rect[2] and my < rect[4] then
            MoveToGroup(item, tabGroups[index])
            return
        end
    end
end

local topPadding = 6 -- more room above the tabs, below the title on the top edge, in pixels

-- What goes in the window
local function DrawWindow(drawOptions)
    -- once for the frame, inside the window: they take in its fade
    stackMain, stackShadow = imgui.GetColorU32(stackWhite), imgui.GetColorU32(stackBlack)
    iconTint = imgui.GetColorU32(iconWhite)
    highlightColor, padColor, swapColor = imgui.GetColorU32(highlightBlue), imgui.GetColorU32(padYellow), imgui.GetColorU32(swapTextColor)
    slotFillColor, slotEdgeColor = imgui.GetColorU32(slotFill), imgui.GetColorU32(slotEdge)
    IconSheet()
    hoveredItem = nil
    for _, rect in ipairs(tabRects) do
        rect.shown = false
    end
    if not drawOptions.lockMovement[1] then
        drag.item, drag.moving = nil, false -- items are dragged only while the window is held still
    end

    imgui.SetCursorPosY(imgui.GetCursorPosY() + topPadding)

    DrawTabs(drawOptions.isUnified[1])
    DrawDrag()

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
    isPinned = T{ false }, -- the window stays when /inv toggle hides the rest
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
    treasurePinned = T{ false }, -- it stays when /inv toggle hides the inventory
    treasureLock = T{ false }, -- detached, it cannot be dragged
    treasurePos = T{ 256, 100 }, -- where it is, detached
    treasureWidth = T{ 300 }, -- how wide it is
    equipment = T{
        enabled = T{ false },
        detached = T{ false }, -- a window of its own, rather than under the inventory window
        pinned = T{ false }, -- it stays when /inv toggle hides the inventory
        pos = T{ 100, 100 }, -- where it is, detached
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
    drawSettings = config.General,
    tabs = {
        { label = 'Bags', draw = config.Bags },
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
-- Whether the window is shown this frame: switched on by /inv toggle, or pinned. The treasure pool and
-- equipment monitor are shown with it, or pinned without it.
-- And where the attached treasure pool and equipment monitor go: beside the window and under it
-- while it is on screen; while it is not, the pinned ones take its place, the monitor at its top-left
-- corner and the pool there too, or beside the monitor if that is there.
local attached = {
    shown = { true },
    gap = 6, -- between the window and those attached to it
    pool = { 0, 0 }, equipment = { 0, 0 },
    fade = require('winxi.fade'),
}

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
    attached.shown[1] = options.isVisible[1] or options.isPinned[1]
    if options.equipment.enabled[1] and options.equipment.detached[1] then
        equipment.Draw(options, IconSheet, nil, attached.shown[1])
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
    -- held still while locked, and while the mouse is over the strip where the grid's scroll bar is
    -- dragged (where it was last frame), or the bar is held, so that a press there does not move it
    local zone, mx, my = scrollBar.zone, imgui.GetMousePos()
    local overBar = scrollBar.grab ~= nil or (zone.shown and mx ~= nil
        and mx >= zone[1] and mx < zone[3] and my >= zone[2] and my < zone[4])
    windowExtra.flags = (options.lockMovement[1] or overBar) and ImGuiWindowFlags_NoMove or 0
    zone.shown = false
    local shown = attached.shown[1]
    app:Window(attached.shown, DrawWindow, windowExtra)
    attached.shown[1] = shown

    -- where the window is this frame, or was last; still fading out, it is on screen
    local x, y = options.pos[1], options.pos[2]
    local onScreen = shown or (options.fadeInOut[1] and attached.fade.Lingering(windowName))
    if onScreen and pad.windowX ~= nil then
        attached.equipment[1], attached.equipment[2] = x, y + pad.windowHeight + attached.gap
    else
        attached.equipment[1], attached.equipment[2] = x, y
    end
    if options.equipment.enabled[1] and not options.equipment.detached[1] then
        equipment.Draw(options, IconSheet, attached.equipment, shown)
    end
    local beside = equipment.Rect()
    if onScreen and pad.windowX ~= nil then
        attached.pool[1], attached.pool[2] = x + pad.windowWidth + attached.gap, y
    elseif not onScreen and beside ~= nil then
        attached.pool[1], attached.pool[2] = beside[1] + beside[3] + attached.gap, y
    else
        attached.pool[1], attached.pool[2] = x, y
    end
    pool.Draw(options, attached.pool, shown)
    PadEndFrame()
end)
