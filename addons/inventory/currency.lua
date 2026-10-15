-- Gil and the game's currencies, one or two of which are shown in the gil's place at the foot of the
-- inventory window: '12,345 G', or '12,345 G, 4,500 CP' with a second. The server says what the player
-- has of a currency only when asked: the game asks as its Currencies menus open (0x10F for the first,
-- 0x115 for the second) and is answered with all of them at once (0x113, 0x118). This asks the same
-- way, for the menu a chosen currency is in, while the inventory window is shown: as it is shown, and
-- again every minute while it stays; and reads the answer whenever it comes, the game's own as well.
--
-- Which can be chosen: a server does not say which currencies it has, and its answers carry every one
-- the game knows, so the player picks a list (currency.filters). Retail has every one. Phoenix has
-- those of its era, and any other the server has said the player has some of: Treasures of Aht
-- Urhgan, its modules/init.txt (references/Phoenix) loading era/sql/wotg, which takes back Wings of
-- the Goddess' changes. Gil is in every list. As the choices are opened both menus are asked about, so
-- that what the player has is known.
--
--   currency.list                    every currency the game knows, gil first: { key, name, short, ... }
--   currency.filters                 the lists to choose from: { key, label, tip }
--   currency.Choices(filter)         those a list (a filter's key) has, in the menus' order
--   currency.Name(key)               a currency's name, or nil for none (or one no longer known)
--   currency.Line(first, second)     what goes in the gil's place: '12,345 G, 4,500 CP', or '' for none
--   currency.SetGil(count)           how much gil the player has, as the bags are read
--   currency.Update(first, second, shown)   once a frame: the two chosen keys ('' for none), and
--                                    whether the window is shown
--   currency.Survey()                as the choices are opened: ask about both menus, now and then
--   currency.Reset()                 another character: nothing is known
--
-- Where each is in its answer, from the server's packets (references/Phoenix, s2c 0x113 and 0x118):
-- the byte after the packet's 4-byte header, and its size: 'i' 4 bytes, 'H' 2, 'B' 1. era: true for
-- those of the server's era.

local currency = {}

local requests = { 0x10F, 0x115 } -- each menu's question
local answers = { [0x113] = 1, [0x118] = 2 } -- and its answer
local refresh = 60   -- seconds between questions while the window stays shown
local settle = 5     -- seconds after a new area before asking, while the area's own packets come
local header = 4

--               key, name, short (as shown), menu, where, size, era
currency.list = {
    { 'gil', 'Gil', 'G', 0, 0, nil, true },
    -- the first menu (0x113)
    { 'conquestSandoria', "Conquest Points (San d'Oria)", 'CP', 1, 0, 'i', true },
    { 'conquestBastok', 'Conquest Points (Bastok)', 'CP', 1, 4, 'i', true },
    { 'conquestWindurst', 'Conquest Points (Windurst)', 'CP', 1, 8, 'i', true },
    { 'beastmenSeals', "Beastmen's Seals", "Beastmen's Seals", 1, 12, 'H', true },
    { 'kindredSeals', "Kindred's Seals", "Kindred's Seals", 1, 14, 'H', true },
    { 'kindredCrests', "Kindred's Crests", "Kindred's Crests", 1, 16, 'H' },
    { 'highKindredCrests', "High Kindred's Crests", "High Kindred's Crests", 1, 18, 'H' },
    { 'sacredKindredCrests', "Sacred Kindred's Crests", "Sacred Kindred's Crests", 1, 20, 'H' },
    { 'ancientBeastcoins', 'Ancient Beastcoins', 'Beastcoins', 1, 22, 'H', true },
    { 'valorPoints', 'Valor Points', 'Valor', 1, 24, 'H' },
    { 'scyldes', 'Scyldes', 'Scyldes', 1, 26, 'H' },
    { 'guildFishing', 'Guild Points (Fishing)', 'GP', 1, 28, 'i', true },
    { 'guildWoodworking', 'Guild Points (Woodworking)', 'GP', 1, 32, 'i', true },
    { 'guildSmithing', 'Guild Points (Smithing)', 'GP', 1, 36, 'i', true },
    { 'guildGoldsmithing', 'Guild Points (Goldsmithing)', 'GP', 1, 40, 'i', true },
    { 'guildClothcraft', 'Guild Points (Clothcraft)', 'GP', 1, 44, 'i', true },
    { 'guildLeathercraft', 'Guild Points (Leathercraft)', 'GP', 1, 48, 'i', true },
    { 'guildBonecraft', 'Guild Points (Bonecraft)', 'GP', 1, 52, 'i', true },
    { 'guildAlchemy', 'Guild Points (Alchemy)', 'GP', 1, 56, 'i', true },
    { 'guildCooking', 'Guild Points (Cooking)', 'GP', 1, 60, 'i', true },
    { 'cinders', 'Cinders', 'Cinders', 1, 64, 'i' },
    { 'ballistaPoints', 'Ballista Points', 'Ballista', 1, 76, 'i', true },
    { 'fellowPoints', 'Fellow Points', 'Fellow', 1, 80, 'i', true },
    { 'dailyTally', 'Daily Tally', 'Tally', 1, 90, 'H' },
    { 'researchMarks', 'Research Marks', 'Marks', 1, 92, 'i' },
    { 'moblinMarbles', 'Moblin Marbles', 'Marbles', 1, 100, 'i' },
    { 'infamy', 'Infamy', 'Infamy', 1, 104, 'H' },
    { 'prestige', 'Prestige', 'Prestige', 1, 106, 'H' },
    { 'legionPoints', 'Legion Points', 'Legion', 1, 108, 'i' },
    { 'sparks', 'Sparks of Eminence', 'Sparks', 1, 112, 'i' },
    { 'shiningStars', 'Shining Stars', 'Stars', 1, 116, 'i' },
    { 'imperialStanding', 'Imperial Standing', 'IS', 1, 120, 'i', true },
    { 'assaultLeujaoam', 'Assault Points (Leujaoam)', 'AP', 1, 124, 'i', true },
    { 'assaultMamool', 'Assault Points (Mamool Ja)', 'AP', 1, 128, 'i', true },
    { 'assaultLebros', 'Assault Points (Lebros)', 'AP', 1, 132, 'i', true },
    { 'assaultPeriqia', 'Assault Points (Periqia)', 'AP', 1, 136, 'i', true },
    { 'assaultIlrusi', 'Assault Points (Ilrusi)', 'AP', 1, 140, 'i', true },
    { 'nyzulTokens', 'Nyzul Isle Tokens', 'Tokens', 1, 144, 'i', true },
    { 'zeni', 'Zeni', 'Zeni', 1, 148, 'i' },
    { 'jettons', 'Jettons', 'Jettons', 1, 152, 'i' },
    { 'therionIchor', 'Therion Ichor', 'Ichor', 1, 156, 'i' },
    { 'alliedNotes', 'Allied Notes', 'Notes', 1, 160, 'i' },
    { 'copperVouchers', 'Copper A.M.A.N. Vouchers', 'Copper', 1, 164, 'H' },
    { 'loginPoints', 'Login Points', 'Login', 1, 166, 'H' },
    { 'cruor', 'Cruor', 'Cruor', 1, 168, 'i' },
    { 'resistanceCredits', 'Resistance Credits', 'Credits', 1, 172, 'i' },
    { 'dominionNotes', 'Dominion Notes', 'Dominion', 1, 176, 'i' },
    { 'idTags', 'Imperial Army ID Tags', 'ID Tags', 1, 186, 'B', true },
    { 'traverserStones', 'Traverser Stones', 'Stones', 1, 188, 'i' },
    { 'voidstones', 'Voidstones', 'Voidstones', 1, 192, 'i' },
    { 'corundums', "Kupofried's Corundums", 'Corundums', 1, 196, 'i' },
    { 'reclamationMarks', 'Reclamation Marks', 'Reclamation', 1, 220, 'H' },
    { 'unityAccolades', 'Unity Accolades', 'Accolades', 1, 224, 'i' },
    { 'deeds', 'Deeds', 'Deeds', 1, 244, 'H' },
    -- the second menu (0x118)
    { 'bayld', 'Bayld', 'Bayld', 2, 0, 'i' },
    { 'kineticUnits', 'Kinetic Units', 'Units', 2, 4, 'H' },
    { 'obsidianFragments', 'Obsidian Fragments', 'Fragments', 2, 8, 'i' },
    { 'mweyaPlasm', 'Mweya Plasm Corpuscles', 'Plasm', 2, 16, 'i' },
    { 'eschaBeads', 'Escha Beads', 'Beads', 2, 70, 'H' },
    { 'eschaSilt', 'Escha Silt', 'Silt', 2, 72, 'i' },
    { 'potpourri', 'Potpourri', 'Potpourri', 2, 76, 'i' },
    { 'hallmarks', 'Hallmarks', 'Hallmarks', 2, 80, 'i' },
    { 'gallantry', 'Badges of Gallantry', 'Gallantry', 2, 88, 'i' },
    { 'crafterPoints', 'Crafter Points', 'Crafter', 2, 92, 'i' },
    { 'silverVouchers', 'Silver A.M.A.N. Vouchers', 'Silver', 2, 124, 'i' },
    { 'domainPoints', 'Domain Points', 'Domain', 2, 128, 'i' },
    { 'mogSegments', 'Mog Segments', 'Segments', 2, 136, 'i' },
    { 'gallimaufry', 'Gallimaufry', 'Gallimaufry', 2, 140, 'i' },
    { 'temenosUnits', 'Temenos Units', 'Temenos', 2, 148, 'i' },
    { 'apollyonUnits', 'Apollyon Units', 'Apollyon', 2, 152, 'i' },
}

local byKey = {}
for _, entry in ipairs(currency.list) do
    entry.key, entry.name, entry.short, entry.menu, entry.at, entry.size, entry.era =
        entry[1], entry[2], entry[3], entry[4], entry[5], entry[6], entry[7] or false
    byKey[entry.key] = entry
end

currency.filters = {
    { key = 'phoenix', label = 'Phoenix',
        tip = 'Phoenix\'s era, Treasures of Aht Urhgan, and any other currency you have some of.' },
    { key = 'retail', label = 'Retail', tip = 'Every currency the game knows.' },
}
local filterKeys = {}
for _, filter in ipairs(currency.filters) do filterKeys[filter.key] = filter end

local values = {}  -- key -> how many, once an answer has said (gil, once the bags have)
local texts = {}   -- key -> what is shown, made as the value changes
local lines = {}   -- first .. '|' .. second -> the line, made as either changes
local choices = {} -- filter -> what it lets be chosen, made again as it may change
local asked = { -math.huge, -math.huge } -- each menu: when it was last asked about
local wasShown = false
local settledAt = 0 -- not before this, after a new area

local function Grouped(number)
    local text = tostring(number)
    local sign, digits = text:match('^(-?)(%d+)$')
    if digits == nil then return text end
    return sign .. digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

-- A value has changed: what is shown for it, the lines it is in, and perhaps the choices
local function Changed(key, value)
    if values[key] == value then return end
    local entry = byKey[key]
    if not entry.era and (value or 0) ~= 0 and (values[key] or 0) == 0 then
        choices.phoenix = nil -- the player has some of one outside the era: it can be chosen now
    end
    values[key], texts[key] = value, nil
    lines = {}
end

function currency.Choices(filter)
    if filterKeys[filter] == nil then filter = 'phoenix' end
    local list = choices[filter]
    if list == nil then
        list = {}
        for _, entry in ipairs(currency.list) do
            if filter == 'retail' or entry.era or (values[entry.key] or 0) ~= 0 then
                list[#list + 1] = entry
            end
        end
        choices[filter] = list
    end
    return list
end

function currency.Name(key)
    local entry = byKey[key]
    return entry and entry.name or nil
end

local function Text(key)
    local entry = byKey[key]
    if entry == nil then return nil end
    local text = texts[key]
    if text == nil then
        local value = values[key]
        text = ('%s %s'):format(value ~= nil and Grouped(value) or '-', entry.short)
        texts[key] = text
    end
    return text
end

function currency.Line(first, second)
    local id = first .. '|' .. second
    local line = lines[id]
    if line == nil then
        local a, b = Text(first), Text(second)
        if a ~= nil and b ~= nil then
            line = a .. ', ' .. b
        else
            line = a or b or ''
        end
        lines[id] = line
    end
    return line
end

function currency.SetGil(count)
    Changed('gil', count)
end

local function Ask(menu, now)
    asked[menu] = now
    AshitaCore:GetPacketManager():AddOutgoingPacket(requests[menu], { 0, 0, 0, 0 })
end

local function Wanted(menu, first, second)
    local a, b = byKey[first], byKey[second]
    return (a ~= nil and a.menu == menu) or (b ~= nil and b.menu == menu)
end

function currency.Update(first, second, shown)
    local now = os.clock()
    local opened = shown and not wasShown
    wasShown = shown
    if not shown or now < settledAt then return end
    -- as the window is shown (not more than once in a few seconds), and every minute while it stays
    for menu = 1, 2 do
        local since = now - asked[menu]
        if (since >= refresh or (opened and since >= settle)) and Wanted(menu, first, second) then
            Ask(menu, now)
        end
    end
end

function currency.Survey()
    local now = os.clock()
    if now < settledAt then return end
    for menu = 1, 2 do
        if now - asked[menu] >= refresh then
            Ask(menu, now)
        end
    end
end

function currency.Reset()
    local gil = values.gil
    values, texts, lines, choices = { gil = gil }, {}, {}, {}
    asked[1], asked[2] = -math.huge, -math.huge
end

ashita.events.register('packet_in', 'inv_currency_packet', function(e)
    if e.id == 0x00A then
        -- a new area: ask again once it has settled, the values may have changed on the way
        settledAt = os.clock() + settle
        asked[1], asked[2] = -math.huge, -math.huge
        return
    end
    local menu = answers[e.id]
    if menu == nil then return end
    local data = e.data
    for _, entry in ipairs(currency.list) do
        if entry.menu == menu and #data >= header + entry.at + (entry.size == 'i' and 4 or entry.size == 'H' and 2 or 1) then
            Changed(entry.key, struct.unpack(entry.size, data, header + entry.at + 1))
        end
    end
end)

return currency
