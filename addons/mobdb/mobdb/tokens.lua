local memMgr = AshitaCore:GetMemoryManager();
local entMgr = memMgr:GetEntity();
local partyMgr = memMgr:GetParty();
local playMgr = memMgr:GetPlayer();
local resMgr = AshitaCore:GetResourceManager();
local cache = require('cache');

-- A percent sign as it has to be written to show one (doubled on older addon versions)
local percentSign = cache.PercentSign;

gTokenState = {
    FirstElement = true,
    LineBreak = false,
    DrawImage = function(this, fileName)
        this:ProcessSameLines();
        gTextures:Draw(fileName, 13 * gSettings.Scale);
        if imgui.IsItemHovered() then
            imgui.SetTooltip(fileName);
        end
    end,
    DrawText = function(this, text)
        if (text ~= nil) then
            this:ProcessSameLines();
            imgui.Text(text);
        end
    end,
    ProcessSameLines = function(this)
        if this.FirstElement then
            if this.LineBreak then
                imgui.Text('');
                this.LineBreak = false;
            end
            this.FirstElement = false;
        else
            if not this.LineBreak then
                imgui.SameLine();
            else
                this.LineBreak = false;
            end
        end
    end
}

local function PrintIcons(icons)
    for _, icon in ipairs(icons) do
        if (gTextures.Cache[icon] ~= nil) then
            gTokenState:DrawImage(icon);
        end
    end
end

local function PrintAllImmunities()
    for _, flag in ipairs(cache.AllImmunityFlags) do
        if (gTextures.Cache[flag.icon] ~= nil) then
            gTokenState:DrawImage(flag.icon);
        end
    end
end

-- A sorted modifier list from the cache: each icon, and the figure after the last of each strength
local function PrintMods(mods)
    for _, mod in ipairs(mods) do
        if mod.HasIcon then
            gTokenState:DrawImage(mod.Type);
        end
        if mod.Text then
            gTokenState:DrawText(mod.Text);
        end
    end
end

-- One kind of modifier list for a mob, if it has any. Returns whether anything was drawn.
local function PrintModList(resource, kind)
    local mods = cache.Mods(resource, kind);
    if (#mods > 0) then
        PrintMods(mods);
        return true;
    end
    return false;
end

local debugFlagIcons = {
    'AggroHQ', 'PassiveHQ', 'AggroNQ', 'PassiveNQ',
    'Link', 'TrueSight', 'Sight', 'Sound', 'Scent', 'Magic', 'JA', 'Blood',
    'H2H', 'Impact', 'Piercing', 'Slashing',
    'Fire', 'Earth', 'Water', 'Wind', 'Ice', 'Lightning', 'Light', 'Dark',
};

-- The party slot (1-17) of the member at an entity index who is in the player's zone, or nil. Looked for
-- at most once a second for the same index, rather than through every slot on every frame.
local slotIndex, slotResult, slotTime = nil, nil, 0;

local function GetPartySlot(index)
    local now = os.clock();
    if (index == slotIndex) and (now - slotTime < 1) then
        return slotResult;
    end

    local found = nil;
    local zone = partyMgr:GetMemberZone(0);
    for i = 1, 17 do
        if (partyMgr:GetMemberZone(i) == zone) and (partyMgr:GetMemberTargetIndex(i) == index) then
            found = i;
            break;
        end
    end

    slotIndex, slotResult, slotTime = index, found, now;
    return found;
end

local function IsPlayerIndex(index)
    return (index > 0x3FF) and (index < 0x700);
end

local function JobName(job)
    return resMgr:GetString(gCompatibility.Resource.Jobs, job);
end

-- An entity's speed relative to normal: 1 is normal. nil if the entity is not loaded.
local function GetRelativeSpeed(index)
    if entMgr:GetRawEntity(index) == nil then
        return nil;
    end
    if IsPlayerIndex(index) then
        return entMgr:GetMovementSpeed(index) / 5;
    end
    return entMgr:GetAnimationSpeed(index) / 4;
end

return {
    ['$name'] = function(mob, resource)
        if resource and resource.Name then
            gTokenState:DrawText(resource.Name);
        else
            local name = entMgr:GetName(mob);
            if (name ~= nil) then
                gTokenState:DrawText(name);
            end
        end
    end,
    ['$hexindex'] = function(mob)
        gTokenState:DrawText(string.format('0x%X', mob));
    end,
    ['$hexid'] = function(mob)
        gTokenState:DrawText(string.format('0x%X', entMgr:GetServerId(mob)));
    end,
    ['$index'] = function(mob)
        gTokenState:DrawText(tostring(mob));
    end,
    ['$id'] = function(mob)
        gTokenState:DrawText(tostring(entMgr:GetServerId(mob)));
    end,
    ['$zone'] = function(mob)
        local zoneId = partyMgr:GetMemberZone(0);
        local string = resMgr:GetString(gCompatibility.Resource.Zone, zoneId);
        if string then
            gTokenState:DrawText(string);
        else
            gTokenState:DrawText('Unknown');
        end
    end,
    ['$job'] = function(mob, resource)
        if resource and resource.Job > 0 then
            gTokenState:DrawText(cache.Job(resource));
        elseif IsPlayerIndex(mob) then
            if (mob == partyMgr:GetMemberTargetIndex(0)) then
                gTokenState:DrawText(string.format('%s/%s', JobName(playMgr:GetMainJob()), JobName(playMgr:GetSubJob())));
            else
                -- a party member's job where it is known, otherwise ??? (and not both)
                local slot = GetPartySlot(mob);
                local mainJob = slot and partyMgr:GetMemberMainJob(slot) or 0;
                local subJob = slot and partyMgr:GetMemberSubJob(slot) or 0;
                if ((mainJob ~= 0) or (subJob ~= 0)) then
                    gTokenState:DrawText(string.format('%s/%s', JobName(mainJob), JobName(subJob)));
                else
                    gTokenState:DrawText('???');
                end
            end
        else
            gTokenState:DrawText('???');
        end
    end,
    ['$level'] = function(mob, resource)
        if resource then
            if resource.Level then
                gTokenState:DrawText(tostring(resource.Level));
            else
                gTokenState:DrawText(string.format('%d-%d', resource.MinLevel, resource.MaxLevel));
            end
        elseif IsPlayerIndex(mob) then
            if (mob == partyMgr:GetMemberTargetIndex(0)) then
                gTokenState:DrawText(tostring(playMgr:GetMainJobLevel()));
            else
                local slot = GetPartySlot(mob);
                local level = slot and partyMgr:GetMemberMainJobLevel(slot) or 0;
                if (level > 0) then
                    gTokenState:DrawText(tostring(level));
                else
                    gTokenState:DrawText('???');
                end
            end
        else
            gTokenState:DrawText('???');
        end
    end,
    ['$joblevel'] = function(mob, resource)
        if resource then
            gTokenState:DrawText(cache.JobLevel(resource));
        elseif IsPlayerIndex(mob) then
            if (mob == partyMgr:GetMemberTargetIndex(0)) then
                local output = string.format('[%s%u/%s%u]',
                    JobName(playMgr:GetMainJob()),
                    playMgr:GetMainJobLevel(),
                    JobName(playMgr:GetSubJob()),
                    playMgr:GetSubJobLevel());
                gTokenState:DrawText(output);
            else
                local slot = GetPartySlot(mob);
                local level = slot and partyMgr:GetMemberMainJobLevel(slot) or 0;
                if (level > 0) then
                    local output = string.format('[%s%u/%s%u]',
                        JobName(partyMgr:GetMemberMainJob(slot)),
                        level,
                        JobName(partyMgr:GetMemberSubJob(slot)),
                        partyMgr:GetMemberSubJobLevel(slot));
                    gTokenState:DrawText(output);
                end
            end
        end
        return false;
    end,
    ['$position1'] = function(mob)
        gTokenState:DrawText(string.format('(%.2f,%.2f) Z:%.2f',
            entMgr:GetLocalPositionX(mob),
            entMgr:GetLocalPositionY(mob),
            entMgr:GetLocalPositionZ(mob)));
    end,
    ['$position2'] = function(mob)
        gTokenState:DrawText(string.format('(%.0f,%.0f) Z:%.0f',
            entMgr:GetLocalPositionX(mob),
            entMgr:GetLocalPositionY(mob),
            entMgr:GetLocalPositionZ(mob)));
    end,
    ['$position3'] = function(mob)
        gTokenState:DrawText(string.format('X:%.2f Y:%.2f Z:%.2f',
            entMgr:GetLocalPositionX(mob),
            entMgr:GetLocalPositionY(mob),
            entMgr:GetLocalPositionZ(mob)));
    end,
    ['$position4'] = function(mob)
        gTokenState:DrawText(string.format('X:%.0f Y:%.0f Z:%.0f',
            entMgr:GetLocalPositionX(mob),
            entMgr:GetLocalPositionY(mob),
            entMgr:GetLocalPositionZ(mob)));
    end,
    ['$strength'] = function(mob, resource)
        if resource then
            PrintModList(resource, 'strength');
        end
    end,
    ['$weakness'] = function(mob, resource)
        if resource then
            PrintModList(resource, 'weakness');
        end
    end,
    ['$physical'] = function(mob, resource)
        if resource then
            PrintModList(resource, 'physical');
        end
    end,
    ['$magical'] = function(mob, resource)
        if resource then
            PrintModList(resource, 'magical');
        end
    end,
    ['$physmagic'] = function(mob, resource)
        if resource then
            local foundPhysical = PrintModList(resource, 'physical');
            if (#cache.Mods(resource, 'magical') > 0) then
                if (foundPhysical) then
                    gTokenState:DrawText(' ');
                end
                PrintModList(resource, 'magical');
            end
        end
    end,
    ['$hpp'] = function(mob)
        gTokenState:DrawText(tostring(entMgr:GetHPPercent(mob)));
    end,
    ['$aggro'] = function(mob, resource)
        if resource then
            PrintIcons(cache.Flags(resource));
        end
    end,
    ['$debugflags'] = function(mob)
        PrintIcons(debugFlagIcons);
    end,
    ['$spawncount'] = function(mob)

    end,
    ['$immunity'] = function(mob, resource)
        if resource then
            PrintIcons(cache.Immunities(resource));
        end
    end,
    ['$debugimmunity'] = function(mob)
        PrintAllImmunities();
    end,
    ['$statusresist'] = function(mob, resource)
        if resource then
            PrintModList(resource, 'statusresist');
        end
    end,
    ['$dynamic'] = function(mob)
        if (mob >= 0x700) and (mob < 0x900) then
            gTokenState:DrawText('Dynamic');
        else
            gTokenState:DrawText('Static');
        end
    end,
    ['$speed'] = function(mob)
        local speed = GetRelativeSpeed(mob);
        if speed == nil then
            gTokenState:DrawText('??' .. percentSign);
        else
            gTokenState:DrawText(string.format('%.2d', speed * 100) .. percentSign);
        end
    end,
    ['$speedrelative'] = function(mob)
        local speed = GetRelativeSpeed(mob);
        if speed == nil then
            gTokenState:DrawText('??' .. percentSign);
        elseif (speed == 1) then
            gTokenState:DrawText('+0' .. percentSign);
        elseif (speed < 1) then
            gTokenState:DrawText(string.format('-%.2d', math.floor((1 - speed) * 100)) .. percentSign);
        else
            gTokenState:DrawText(string.format('+%.2d', math.floor((speed - 1) * 100)) .. percentSign);
        end
    end,
    ['$direction'] = function(mob)
        if (entMgr:GetRawEntity(mob) == nil) then
            return;
        end

        local myIndex = partyMgr:GetMemberTargetIndex(0);
        local rads = math.atan2(
            entMgr:GetLocalPositionX(mob) - entMgr:GetLocalPositionX(myIndex),
            entMgr:GetLocalPositionY(mob) - entMgr:GetLocalPositionY(myIndex));

        if (rads > 2.74) then
            gTokenState:DrawText('South');
        elseif (rads > 1.96) then
            gTokenState:DrawText('SouthEast');
        elseif (rads > 1.17) then
            gTokenState:DrawText('East');
        elseif (rads > 0.39) then
            gTokenState:DrawText('NorthEast');
        elseif (rads > -0.39) then
            gTokenState:DrawText('North');
        elseif (rads > -1.17) then
            gTokenState:DrawText('NorthWest');
        elseif (rads > -1.96) then
            gTokenState:DrawText('West');
        elseif (rads > -2.7) then
            gTokenState:DrawText('SouthWest');
        else
            gTokenState:DrawText('South');
        end
    end,
    ['$drops'] = function(mob, resource)
        if resource and (resource.Drops) and (resource.Drops[1]) then
            gTokenState:DrawText(cache.DropText(resource));
        end
    end,
    ['$dropssplit'] = function(mob, resource)
        if resource and (resource.Drops) and (resource.Drops[1]) then
            gTokenState:ProcessSameLines();
            for _,drop in ipairs(cache.DropNames(resource)) do
                imgui.Text(drop);
            end
        end
    end,
    ['$notes'] = function(mob, resource)
        if resource then
            if (resource.Notes) and (#resource.Notes > 0) then
                for _, note in ipairs(resource.Notes) do
                    gTokenState:DrawText(note);
                end
            end
        end
    end
};
