-- The game's currencies, as its Currencies menu has them, two of which can be shown under the gil at
-- the foot of the inventory window. The server says what the player has of each only when asked: the
-- game asks as its Currencies menus open (0x10F for the first, 0x115 for the second) and is answered
-- with all of them at once (0x113, 0x118). This asks the same way, for the menu a chosen currency is
-- in, while the inventory window is shown: as it is shown, and again every minute while it stays; and
-- reads the answer whenever it comes, the game's own as well.
--
--   currency.list                    the currencies, in the menus' order: { key, name, menu }
--   currency.Name(key)               a currency's name, or nil for none (or one no longer known)
--   currency.Text(key)               what is shown for it: '45,000 Sparks', or '- Sparks' before it is known
--   currency.Update(first, second, shown)   once a frame: the two chosen keys ('' for none), and
--                                    whether the window is shown
--   currency.Reset()                 another character: nothing is known
--
-- Where each is in its answer, from the server's packet (references/Phoenix, s2c 0x113 and 0x118):
-- the byte after the packet's 4-byte header, and its size: 'i' 4 bytes, 'H' 2, 'B' 1.
local currency = {}

local requests = { 0x10F, 0x115 } -- each menu's question
local answers = { [0x113] = 1, [0x118] = 2 } -- and its answer
local refresh = 60   -- seconds between questions while the window stays shown
local settle = 5     -- seconds after a new area before asking, while the area's own packets come
local header = 4

currency.list = {
    -- the first menu (0x113)
    { 'conquestSandoria', "Conquest Points (San d'Oria)", 1, 0, 'i' },
    { 'conquestBastok', 'Conquest Points (Bastok)', 1, 4, 'i' },
    { 'conquestWindurst', 'Conquest Points (Windurst)', 1, 8, 'i' },
    { 'beastmenSeals', "Beastmen's Seals", 1, 12, 'H' },
    { 'kindredSeals', "Kindred's Seals", 1, 14, 'H' },
    { 'kindredCrests', "Kindred's Crests", 1, 16, 'H' },
    { 'highKindredCrests', "High Kindred's Crests", 1, 18, 'H' },
    { 'sacredKindredCrests', "Sacred Kindred's Crests", 1, 20, 'H' },
    { 'ancientBeastcoins', 'Ancient Beastcoins', 1, 22, 'H' },
    { 'valorPoints', 'Valor Points', 1, 24, 'H' },
    { 'scyldes', 'Scyldes', 1, 26, 'H' },
    { 'guildFishing', 'Guild Points (Fishing)', 1, 28, 'i' },
    { 'guildWoodworking', 'Guild Points (Woodworking)', 1, 32, 'i' },
    { 'guildSmithing', 'Guild Points (Smithing)', 1, 36, 'i' },
    { 'guildGoldsmithing', 'Guild Points (Goldsmithing)', 1, 40, 'i' },
    { 'guildClothcraft', 'Guild Points (Clothcraft)', 1, 44, 'i' },
    { 'guildLeathercraft', 'Guild Points (Leathercraft)', 1, 48, 'i' },
    { 'guildBonecraft', 'Guild Points (Bonecraft)', 1, 52, 'i' },
    { 'guildAlchemy', 'Guild Points (Alchemy)', 1, 56, 'i' },
    { 'guildCooking', 'Guild Points (Cooking)', 1, 60, 'i' },
    { 'cinders', 'Cinders', 1, 64, 'i' },
    { 'ballistaPoints', 'Ballista Points', 1, 76, 'i' },
    { 'fellowPoints', 'Fellow Points', 1, 80, 'i' },
    { 'dailyTally', 'Daily Tally', 1, 90, 'H' },
    { 'researchMarks', 'Research Marks', 1, 92, 'i' },
    { 'moblinMarbles', 'Moblin Marbles', 1, 100, 'i' },
    { 'infamy', 'Infamy', 1, 104, 'H' },
    { 'prestige', 'Prestige', 1, 106, 'H' },
    { 'legionPoints', 'Legion Points', 1, 108, 'i' },
    { 'sparks', 'Sparks of Eminence', 1, 112, 'i' },
    { 'shiningStars', 'Shining Stars', 1, 116, 'i' },
    { 'imperialStanding', 'Imperial Standing', 1, 120, 'i' },
    { 'assaultLeujaoam', 'Assault Points (Leujaoam)', 1, 124, 'i' },
    { 'assaultMamool', "Assault Points (Mamool Ja)", 1, 128, 'i' },
    { 'assaultLebros', 'Assault Points (Lebros)', 1, 132, 'i' },
    { 'assaultPeriqia', 'Assault Points (Periqia)', 1, 136, 'i' },
    { 'assaultIlrusi', 'Assault Points (Ilrusi)', 1, 140, 'i' },
    { 'nyzulTokens', 'Nyzul Isle Tokens', 1, 144, 'i' },
    { 'zeni', 'Zeni', 1, 148, 'i' },
    { 'jettons', 'Jettons', 1, 152, 'i' },
    { 'therionIchor', 'Therion Ichor', 1, 156, 'i' },
    { 'alliedNotes', 'Allied Notes', 1, 160, 'i' },
    { 'copperVouchers', 'Copper A.M.A.N. Vouchers', 1, 164, 'H' },
    { 'loginPoints', 'Login Points', 1, 166, 'H' },
    { 'cruor', 'Cruor', 1, 168, 'i' },
    { 'resistanceCredits', 'Resistance Credits', 1, 172, 'i' },
    { 'dominionNotes', 'Dominion Notes', 1, 176, 'i' },
    { 'traverserStones', 'Traverser Stones', 1, 188, 'i' },
    { 'voidstones', 'Voidstones', 1, 192, 'i' },
    { 'corundums', "Kupofried's Corundums", 1, 196, 'i' },
    { 'reclamationMarks', 'Reclamation Marks', 1, 220, 'H' },
    { 'unityAccolades', 'Unity Accolades', 1, 224, 'i' },
    { 'deeds', 'Deeds', 1, 244, 'H' },
    -- the second menu (0x118)
    { 'bayld', 'Bayld', 2, 0, 'i' },
    { 'kineticUnits', 'Kinetic Units', 2, 4, 'H' },
    { 'obsidianFragments', 'Obsidian Fragments', 2, 8, 'i' },
    { 'mweyaPlasm', 'Mweya Plasm Corpuscles', 2, 16, 'i' },
    { 'eschaBeads', 'Escha Beads', 2, 70, 'H' },
    { 'eschaSilt', 'Escha Silt', 2, 72, 'i' },
    { 'potpourri', 'Potpourri', 2, 76, 'i' },
    { 'hallmarks', 'Hallmarks', 2, 80, 'i' },
    { 'gallantry', 'Badges of Gallantry', 2, 88, 'i' },
    { 'crafterPoints', 'Crafter Points', 2, 92, 'i' },
    { 'silverVouchers', 'Silver A.M.A.N. Vouchers', 2, 124, 'i' },
    { 'domainPoints', 'Domain Points', 2, 128, 'i' },
    { 'mogSegments', 'Mog Segments', 2, 136, 'i' },
    { 'gallimaufry', 'Gallimaufry', 2, 140, 'i' },
    { 'temenosUnits', 'Temenos Units', 2, 148, 'i' },
    { 'apollyonUnits', 'Apollyon Units', 2, 152, 'i' },
}

local byKey = {}
for _, entry in ipairs(currency.list) do
    entry.key, entry.name, entry.menu, entry.at, entry.size = entry[1], entry[2], entry[3], entry[4], entry[5]
    byKey[entry.key] = entry
end

local values = {}  -- key -> how many, once an answer has said
local texts = {}   -- key -> what is shown, made as the value changes
local asked = { -math.huge, -math.huge } -- each menu: when it was last asked about
local wasShown = false
local settledAt = 0 -- not before this, after a new area

local function Grouped(number)
    local text = tostring(number)
    local sign, digits = text:match('^(-?)(%d+)$')
    if digits == nil then return text end
    return sign .. digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

function currency.Name(key)
    local entry = byKey[key]
    return entry and entry.name or nil
end

function currency.Text(key)
    local entry = byKey[key]
    if entry == nil then return nil end
    local text = texts[key]
    if text == nil then
        local value = values[key]
        text = ('%s %s'):format(value ~= nil and Grouped(value) or '-', entry.name)
        texts[key] = text
    end
    return text
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

function currency.Reset()
    values, texts = {}, {}
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
            local value = struct.unpack(entry.size, data, header + entry.at + 1)
            if values[entry.key] ~= value then
                values[entry.key], texts[entry.key] = value, nil
            end
        end
    end
end)

return currency
