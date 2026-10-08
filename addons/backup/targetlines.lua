addon.name    = 'targetlines';
addon.author  = 'Jyouya, Win (and Claude)';
addon.version = '1.2';
addon.desc    = 'FFXII style target lines';

require('common');

local drawArc  = require('drawArc');
local arcs     = require('tracker');
local helpers  = require('helpers');
local settings = require('settings');

local config   = require('config');


local function getArcsForIndex(targetIndex, res)
    res = res or T {};
    for k, v in pairs(arcs) do
        if (k == targetIndex or v.dst == targetIndex) then
            if (not res[k]) then
                res[k] = v;
                getArcsForIndex(v.dst, res);
            end
        end
    end

    return res;
end

local function getPartyArcs(alliance)
    local party = AshitaCore:GetMemoryManager():GetParty()
    local res = T {};
    for i = 0, alliance and 17 or 5 do
        if (party:GetMemberIsActive(i) ~= 0) then
            local targetIndex = party:GetMemberTargetIndex(i);
            getArcsForIndex(targetIndex, res);

            -- A pet's own line starts at the pet, so it is not reached through its owner
            local petIndex = targetIndex ~= 0 and AshitaCore:GetMemoryManager():GetEntity():GetPetTargetIndex(targetIndex) or 0;
            if (petIndex ~= 0) then
                getArcsForIndex(petIndex, res);
            end
        end
    end

    return res;
end

local color    = T {
    player = 0xFF0088FF,
    enemy = 0xFFFF1133,
    playerFriendly = 0xFF00FF66,
    enemyFriendly = 0xFFFF8800,
    pet = 0xFFFF00AA
};

local timeouts = T {
    player = 6,
    enemy = 6,
    playerFriendly = 2,
    enemyFriendly = 2,
    pet = 6
};

ashita.events.register('load', 'load_cb', function()
    ashita.events.register('d3d_present', 'present_cb', function()
        -- Fetched each frame: the settings table is replaced when the character changes
        local s = settings.get();
        if (not s) then
            return;
        end

        -- Expire lines here, for every line, so ones the filter hides do not pile up
        local now = os.clock();
        for src, v in pairs(arcs) do
            if (now - v.clock > timeouts[v.color]) then
                arcs[src] = nil;
            end
        end

        local filteredArcs
        if (s.filter == 'All') then
            filteredArcs = arcs;
        else
            filteredArcs = getPartyArcs(s.filter == 'Alliance');
        end

        for src, v in pairs(filteredArcs) do
            local dTime = os.clock() - v.clock;
            local timeout = timeouts[v.color];

            local dFirstTime = v.firstClock and os.clock() - v.firstClock;

            local lineType = v.color;

            if (dTime > timeout) then
                arcs[src] = nil;
            elseif ((lineType == 'player' or (lineType == 'enemy' and s.mobBrief)) and dFirstTime and dFirstTime > 2.5) then
                local entity = AshitaCore:GetMemoryManager():GetEntity();

                local srcPointer = entity:GetActorPointer(src);
                local x1, y1, z1 = helpers.getBone(srcPointer, 2);
                z1 = (ashita.memory.read_float(srcPointer + 0x67C) + z1) / 2;

                local dstPointer = entity:GetActorPointer(v.dst);

                local x2, y2, z2 = helpers.getBone(dstPointer, 2);
                z2 = (ashita.memory.read_float(dstPointer + 0x67C) + z2) / 2;

                -- The connected arc stays in place and fades out over the last half second
                local alpha = math.max((3 - dFirstTime) * 2, 0);

                if (alpha > 0) then
                    drawArc(x1, y1, z1, x2, y2, z2, color[v.color], 1, true, alpha);
                end
            elseif (dTime > timeout - 0.5) then
                local entity = AshitaCore:GetMemoryManager():GetEntity();

                local srcPointer = entity:GetActorPointer(src);
                local x1, y1, z1 = helpers.getBone(srcPointer, 2);
                z1 = (ashita.memory.read_float(srcPointer + 0x67C) + z1) / 2;

                local dstPointer = entity:GetActorPointer(v.dst);

                local x2, y2, z2 = helpers.getBone(dstPointer, 2);
                z2 = (ashita.memory.read_float(dstPointer + 0x67C) + z2) / 2;

                local alpha = math.min(math.max((timeout - dTime) * 2, 0), 1);

                drawArc(x1, y1, z1, x2, y2, z2, color[v.color], 1, true, alpha);
            else
                local entity = AshitaCore:GetMemoryManager():GetEntity();

                local srcPointer = entity:GetActorPointer(src);
                local x1, y1, z1 = helpers.getBone(srcPointer, 2);
                z1 = (ashita.memory.read_float(srcPointer + 0x67C) + z1) / 2;

                local dstPointer = entity:GetActorPointer(v.dst);

                local x2, y2, z2 = helpers.getBone(dstPointer, 2);
                z2 = (ashita.memory.read_float(dstPointer + 0x67C) + z2) / 2;

                local t = math.min(1 - (0.5 - math.min(dTime, 1)) * 2, 1);

                -- Slight fade-in while the arc extends: 20% to full opacity over the same half second
                local alpha = math.min(0.2 + math.max(dTime, 0) * 1.6, 1);

                drawArc(x1, y1, z1, x2, y2, z2, color[v.color], t, true, alpha);
            end
        end
    end);
end);
