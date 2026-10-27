local Updater = {};

local inventory            = require('state.inventory');
local player               = require('state.player');
local AbilityRecastPointer = ashita.memory.find('FFXiMain.dll', 0, '894124E9????????8B46??6A006A00508BCEE8', 0x19, 0);
AbilityRecastPointer       = ashita.memory.read_uint32(AbilityRecastPointer);

local function ItemCost(updater, items)
    local containers = updater.Containers;
    if (updater.Containers == nil) then
        containers = T{ 0 };
        local useTemporary = false;
        local useWardrobes = false;
        for _,itemId in ipairs(items) do
            local resource = AshitaCore:GetResourceManager():GetItemById(itemId);
            if (bit.band(resource.Flags, 0x800) ~= 0) then
                useWardrobes = true;
            else
                useTemporary = true;
            end
        end
        if (useWardrobes) then
            containers = T { 0, 8, 10, 11, 12, 13, 14, 15, 16 };
        end
        if (useTemporary) then
            containers:append(3);
        end
        updater.Containers = containers;
    end

    local itemCount = 0;
    for _,item in ipairs(items) do
        local itemData = inventory:GetItemData(item);
        if (itemData ~= nil) then
            for _,itemEntry in ipairs(itemData.Locations) do
                if (updater.Containers:contains(itemEntry.Container)) then
                    itemCount = itemCount + inventory:GetItemTable(itemEntry.Container, itemEntry.Index).Count;
                end
            end
        end
    end

    return tostring(itemCount), (itemCount > 0);
end

local function ChargeCost(updater, recastReady)
    return tostring(recastReady), (recastReady > 0);
end

-- fork: made once, where it was made on every call
local moveMap = {
    [381] = 1,
    [382] = 2,
    [383] = 3,
    [384] = 4,
    [385] = 5,
    [588] = 6
};

local function FinishingMoveCost(updater, minimumMoves)
    local finishingMoves = 0;

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local buffs = player:GetBuffs();
    for i=1,32 do
        local count = moveMap[buffs[i]];
        if count ~= nil then
            finishingMoves = count;
        end
    end

    return tostring(finishingMoves), (finishingMoves >= minimumMoves);
end

local function RuneEnchantmentCost(updater)
    local runeCount = 0;

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local buffs = player:GetBuffs();
    for i=1,32 do
        local buff = buffs[i];
        if (buff > 522) and (buff < 531) then
            runeCount = runeCount + 1;
        end
    end

    return tostring(runeCount), (runeCount > 0);
end

local function GetAbilityTimerData(id)
    for i = 1,31 do
        local compId = ashita.memory.read_uint8(AbilityRecastPointer + (i * 8) + 3);
        if (compId == id) then
            return {
                Modifier = ashita.memory.read_int16(AbilityRecastPointer + (i * 8) + 4);
                Recast = ashita.memory.read_uint32(AbilityRecastPointer + (i * 4) + 0xF8);
            };
        end
    end
    
    return {
        Modifier = 0,
        Recast = 0
    };
end

-- fork: a charged ability's charges and the seconds each takes to come back, as the server has them
-- (winxi.abilities' Charges, made from its abilities_charges table) for a job at a level, or nil
-- where winxi's data is not installed or has none
local chargesByRecast = nil;
local function ServerCharges(recastId, job, level)
    if (chargesByRecast == nil) then
        chargesByRecast = {};
        local ok, abilities = pcall(require, 'winxi.abilities');
        if ok then
            for _, id in ipairs(abilities.Ids()) do
                local record = abilities.Get(id);
                for _, row in ipairs(record and record.Charges or {}) do
                    local list = chargesByRecast[row.recastId] or {};
                    chargesByRecast[row.recastId] = list;
                    list[#list + 1] = row;
                end
            end
        end
    end
    local best = nil;
    for _, row in ipairs(chargesByRecast[recastId] or {}) do
        if (row.job == job) and (row.level <= level) and ((best == nil) or (row.level > best.level)) then
            best = row;
        end
    end
    return best;
end

-- fork: the level the player has a job at, main or sub, or nil
local function JobLevel(job)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player:GetMainJob() == job) then
        return player:GetMainJobLevel();
    elseif (player:GetSubJob() == job) then
        return player:GetSubJobLevel();
    end
    return nil;
end

-- The most of a charged ability and the seconds of the whole recast, the server's where it has them
local function Charges(recastId, job, fallbackCount, fallbackSeconds)
    local level = JobLevel(job);
    if (level == nil) then
        return 0, 0;
    end
    local row = ServerCharges(recastId, job, level);
    if row then
        return row.maxCharges, row.maxCharges * row.chargeTime;
    end
    return fallbackCount(level), fallbackSeconds;
end

local function GetMaxStratagems()
    return (Charges(231, 20, function (lvl) return math.floor((lvl - 10) / 20) + 1; end, 240));
end

local function GetRecastTimer(timerId)
    local mmRecast  = AshitaCore:GetMemoryManager():GetRecast();

    if (timerId == 0) then
        return mmRecast:GetAbilityTimer(0);
    end

    for x = 1, 31 do
        local id = mmRecast:GetAbilityTimerId(x);
        local timer = mmRecast:GetAbilityTimer(x);

        if (id == timerId) then
            return timer;
        end
    end

    return 0;
end

local function RecastToString(timer)
    if (timer >= 216000) then
        local h = math.floor(timer / (216000));
        local m = math.floor(math.fmod(timer, 216000) / 3600);
        return string.format('%i:%02i', h, m);
    elseif (timer >= 3600) then
        local m = math.floor(timer / 3600);
        local s = math.floor(math.fmod(timer, 3600) / 60);
        return string.format('%i:%02i', m, s);
    else
        if (timer < 60) then
            return '1';
        else
            return string.format('%i', math.floor(timer / 60));
        end
    end
end

--This call returns two values.
--First value is true/false for whether ability can be used based on current recast, to be used for dimming icons.
--Second value is a string to be displayed on recast element, or nil if the element should not be shown.
--winxi: a third, the timer itself (in 60ths of a second), for the cooldown swipe.
local function GetRecastData(resource)
    local timer = GetRecastTimer(resource.RecastTimerId);
    if (timer == 0) then
        return true, '', 0;
    else
        return false, RecastToString(timer), timer;
    end
end


--Each of these calls returns two values.
--First value is number of charges available.
--Second value is time until next charge.
--winxi: then that time and a charge's whole time (in 60ths of a second), for the cooldown swipe.
local function GetStratagemData()
    local maxCount = GetMaxStratagems();
    if (maxCount == 0) then
        return 0, '', 0;
    end

    local data = GetAbilityTimerData(231);
    if (data.Recast == 0) then
        return maxCount, '', 0;
    end
    
    local _, seconds = Charges(231, 20, function (lvl) return maxCount; end, 240);
    local baseRecast = 60 * (seconds + data.Modifier);
    local chargeValue = baseRecast / maxCount;
    local remainingCharges = math.floor((baseRecast - data.Recast) / chargeValue);
    local timeUntilNextCharge = math.fmod(data.Recast, chargeValue);
    return remainingCharges, RecastToString(timeUntilNextCharge), timeUntilNextCharge, chargeValue;
end

local function GetQuickDrawData()
    local count, seconds = Charges(195, 17, function () return 2; end, 120);
    if (count == 0) then count, seconds = 2, 120; end -- a Quick Draw on the bar of a job that has none
    local data = GetAbilityTimerData(195);
    if (data.Recast == 0) then
        return count, '', 0;
    end
    
    local baseRecast = 60 * (seconds + data.Modifier);
    local chargeValue = baseRecast / count;
    local remainingCharges = math.floor((baseRecast - data.Recast) / chargeValue);
    local timeUntilNextCharge = math.fmod(data.Recast, chargeValue);
    return remainingCharges, RecastToString(timeUntilNextCharge), timeUntilNextCharge, chargeValue;
end

local function GetReadyData()
    local count, seconds = Charges(102, 9, function () return 3; end, 90);
    if (count == 0) then count, seconds = 3, 90; end -- a Ready on the bar of a job that has none
    local data = GetAbilityTimerData(102);
    if (data.Recast == 0) then
        return count, '', 0;
    end

    local baseRecast = 60 * (seconds + data.Modifier);
    local chargeValue = baseRecast / count;
    local remainingCharges = math.floor((baseRecast - data.Recast) / chargeValue);
    local timeUntilNextCharge = math.fmod(data.Recast, chargeValue);
    return remainingCharges, RecastToString(timeUntilNextCharge), timeUntilNextCharge, chargeValue;
end

function Updater:New()
    local o = {};
    setmetatable(o, self);
    self.__index = self;
    return o;
end

function Updater:Initialize(element, binding)
    self.Resource      = AshitaCore:GetResourceManager():GetAbilityById(binding.Id);
    self.State         = element.State;
    
    --Set cost and recast function for charge-based abilities.
    if (self.Resource.RecastTimerId == 102) then
        self.RecastFunction = GetReadyData;
        self.CostFunction = ChargeCost;
    elseif (self.Resource.RecastTimerId == 195) then
        self.RecastFunction = GetQuickDrawData;
        self.CostFunction = ChargeCost;
    elseif (self.Resource.RecastTimerId == 231) then
        self.RecastFunction = GetStratagemData;
        self.CostFunction = ChargeCost;
    else
        self.RecastFunction = GetRecastData;
        if (self.Resource.ManaCost > 0) then
            self.CostKind = 'MP'; -- winxi: for the low MP tint
            self.CostFunction = (function(a)
                return tostring(a), (AshitaCore:GetMemoryManager():GetParty():GetMemberMP(0) >= a);
            end):bind1(self.Resource.ManaCost);
        elseif (self.Resource.TPCost < 1) then
            self.CostFunction = function()
                return '', true;
            end
        else
            self.CostKind = 'TP'; -- winxi: for the low TP tint
            self.CostFunction = (function(a)
                return tostring(a), (AshitaCore:GetMemoryManager():GetParty():GetMemberTP(0) >= a);
            end):bind1(self.Resource.TPCost);
        end
    end

    --Other cost overrides.
    local flourishes = T{
        [716] = 1,
        [717] = 1,
        [718] = 1,
        [719] = 1,
        [720] = 1,
        [721] = 2,
        [776] = 1,
        [825] = 2,
        [826] = 3
    };
    -- fork: the server's (winxi.rules' abilityCosts, from its abilities' scripts; the client's number is
    -- the server's and 512), the table above where winxi's data is not installed
    local thrown = { [682] = 18259, [662] = 18258 };
    local ok, rules = pcall(require, 'winxi.rules');
    local costs = ok and rules.Get('abilityCosts') or nil;
    if costs then
        flourishes, thrown = T{}, {};
        for id, moves in pairs(costs.Flourishes or {}) do flourishes[id + 512] = moves; end
        for id, item in pairs(costs.Thrown or {}) do thrown[id + 512] = item; end
    end
    local flourish = flourishes[binding.Id];

    --Custom (for use with jugs and such)
    if (binding.CostOverride) then
        self.CostKind = nil; -- winxi: the cost is no longer MP or TP
        self.CostFunction = ItemCost:bind2(binding.CostOverride);

    --Angon, Tomahawk: the item each throws
    elseif (thrown[binding.Id] ~= nil) then
        self.CostKind = nil;
        self.CostFunction = ItemCost:bind2(T{ thrown[binding.Id] });

    --Finishing Moves
    elseif flourish ~= nil then
        self.CostKind = nil;
        self.CostFunction = FinishingMoveCost:bind2(flourish);

    --Rune Enchantment
    elseif T{ 856, 878, 880, 881, 883, 884, 885, 887, 888 }:contains(binding.Id) then
        self.CostKind = nil;
        self.CostFunction = RuneEnchantmentCost;
    end
end

function Updater:Destroy()

end

function Updater:Tick()
    --RecastReady will hold number of charges for charged abilities.
    local recastReady, recastDisplay, recastTimer, recastLength = self.RecastFunction(self.Resource);
    local abilityAvailable            = player:KnowsAbility(self.Resource.Id);
    local abilityCostDisplay, costMet = self:CostFunction(recastReady);
    if (type(recastReady) == 'number') then
        recastReady = (recastReady > 0);
    end

    self.State.Available = abilityAvailable;
    self.State.Cost = abilityCostDisplay;
    self.State.Ready = (costMet == true) and (recastReady == true);
    self.State.Recast = recastDisplay;
    self.State.Skillchain = nil;
    -- winxi: the recast in seconds for the swipe, and which cost is not met for the tints
    self.State.RecastLeft = (recastTimer or 0) / 60;
    self.State.RecastLength = recastLength and (recastLength / 60) or nil;
    self.State.LowMP = (self.CostKind == 'MP') and (costMet ~= true);
    self.State.LowTP = (self.CostKind == 'TP') and (costMet ~= true);
end

return Updater;