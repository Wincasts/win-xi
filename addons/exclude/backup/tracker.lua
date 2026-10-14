local settings = require('settings');

local arcs = T {};

-- Who each actor last acted on. Outlives the arc itself, so a line that shows briefly on a new
-- target (player lines, and mob lines in brief mode) is not shown again for every later action.
local lastTargets = T {};

-- local function isMob(id)
--     return bit.band(id, 0xFF000000) ~= 0;
-- end

-- Entity indices of the player and the player's pet (0 when there is none)
local function getOwnIndices()
    local myIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    local myPetIndex = myIndex ~= 0 and AshitaCore:GetMemoryManager():GetEntity():GetPetTargetIndex(myIndex) or 0;
    return myIndex, myPetIndex;
end

-- Played when a line is drawn to the player or the player's pet, at most once per aggroSoundGap seconds
local aggroSoundGap = 1;
local lastAggroSound = 0;

local function playAggroSound(targetIndex)
    local s = settings.get();
    if (not s or not s.aggroSound) then
        return;
    end

    local myIndex, myPetIndex = getOwnIndices();
    if (targetIndex == 0 or (targetIndex ~= myIndex and targetIndex ~= myPetIndex)) then
        return;
    end

    local now = os.clock();
    if (now - lastAggroSound < aggroSoundGap) then
        return;
    end
    lastAggroSound = now;

    ashita.misc.play_sound(addon.path .. 'assets/aggro.wav');
end

local function isMob(spawnFlags)
    return bit.band(spawnFlags, 0x10) ~= 0;
end

local function isPet(spawnFlags)
    return bit.band(spawnFlags, 0x100) ~= 0;
end

local function GetIndexFromId(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();

    --Shortcut for monsters/static npcs..
    if (bit.band(id, 0x1000000) ~= 0) then
        local index = bit.band(id, 0xFFF);
        if (index >= 0x900) then
            index = index - 0x100;
        end

        if (index < 0x900) and (entMgr:GetServerId(index) == id) then
            return index;
        end
    end

    for i = 1, 0x8FF do
        if entMgr:GetServerId(i) == id then
            return i;
        end
    end

    return 0;
end

local timeouts = T {
    player = 10,
    enemy = 10,
    playerFriendly = 5,
    enemyFriendly = 5,
    pet = 10
};

-- The player's pet and what the server says it is attacking: { pet = index, dst = index }.
-- Comes from the pet sync packet, which only the owner receives.
local petLine = nil;

local function handleActionPacket(e)
    local actorId = ashita.bits.unpack_be(e.data_raw, 0, 40, 32);
    local targetCount = ashita.bits.unpack_be(e.data_raw, 0, 72, 6);
    local targetId = ashita.bits.unpack_be(e.data_raw, 0, 150, 32);

    local type = ashita.bits.unpack_be(e.data_raw, 82, 4);

    if (targetCount > 0 and actorId ~= targetId) then
        local color;

        local actorIndex = GetIndexFromId(actorId);
        local targetIndex = GetIndexFromId(targetId);

        -- The player's own actions on their pet draw nothing
        local myIndex, myPetIndex = getOwnIndices();
        if (myIndex ~= 0 and actorIndex == myIndex and targetIndex == myPetIndex) then
            return;
        end

        -- The pet's attacks on its target are already covered by its own line
        if (petLine and actorIndex == petLine.pet and targetIndex == petLine.dst
                and arcs[actorIndex] and arcs[actorIndex].color == 'pet') then
            return;
        end

        local actorFlags = AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(actorIndex);
        local targetFlags = AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(targetIndex);

        if (isMob(actorFlags) and not isPet(actorFlags)) then
            if (isMob(targetFlags)) then
                color = 'enemyFriendly';
            else
                color = 'enemy';
            end
        elseif (isMob(targetFlags)) then
            color = 'player';
        else
            color = 'playerFriendly';
        end

        local clock = os.clock();
        local firstClock = clock;
        local isNewTarget = lastTargets[actorIndex] ~= targetIndex;
        if (not isNewTarget and (color == 'player' or color == 'enemy')) then
            -- Same target as the previous action: start already expired unless a live arc says otherwise
            firstClock = clock - 10;
        end
        -- A mob has turned to a target it was not on before. enemyFriendly is included because a pet
        -- can carry the mob flag, which gives a mob's line to it that colour.
        if (isNewTarget and (color == 'enemy' or color == 'enemyFriendly')) then
            playAggroSound(targetIndex);
        end
        -- A green line from someone else, sounded only when they have newly switched to this target
        if (isNewTarget and color == 'playerFriendly' and actorIndex ~= myIndex) then
            playAggroSound(targetIndex);
        end
        lastTargets[actorIndex] = targetIndex;
        if (arcs[actorIndex]) then
            local arc = arcs[actorIndex];

            if (type == 4 and color == 'playerFriendly') then
                clock = clock - timeouts.playerFriendly + 0.5;
            elseif (arc.dst == targetIndex and os.clock() - arc.clock < timeouts[color]) then
                if (arc.color == 'player' or arc.color == 'enemy') then
                    -- clock = arc.clock;
                    firstClock = arc.firstClock or clock;
                end
                clock = clock - 1;
            end
        end


        arcs[actorIndex] = {
            dst = targetIndex,
            clock = clock,
            color = color,
            firstClock = firstClock
        };
    end
end

local deathMes = T { 6, 20, 97, 113, 406, 605, 646 };
local function handleMessagePacket(data)
    local message = struct.unpack('i2', data, 0x18 + 1);

    if (deathMes:contains(message)) then
        local target = struct.unpack('i2', data, 0x14 + 1);
        local sender = struct.unpack('i2', data, 0x16 + 1);

        -- The index may be reused by a respawn, which should count as a new target
        lastTargets[target] = nil;
        for actor, dst in pairs(lastTargets) do
            if (dst == target) then
                lastTargets[actor] = nil;
            end
        end

        if (arcs[target]) then
            arcs[target].clock = os.clock() - timeouts[arcs[target].color] + 0.5;
            if (arcs[sender]) then
                if (arcs[sender].dst == target) then
                    arcs[sender].clock = os.clock() - timeouts[arcs[target].color] + 0.5;
                end
            end
        end
    end
end

-- The server never tells the client who holds enmity, so threat is inferred: a mob is taken to be on
-- whoever it last acted on, or on its claimer until it has acted, for as long as it stays engaged.
local threatScanInterval = 0.25;
local mobFadeAt = 5.5; -- the render timeout for mob lines (6s) less its half second fade
local lastThreatScan = 0;

local function isAlive(entMgr, index)
    return index > 0 and entMgr:GetRawEntity(index) ~= nil and entMgr:GetHPPercent(index) > 0;
end

local function updateThreat()
    local now = os.clock();
    if (now - lastThreatScan < threatScanInterval) then
        return;
    end
    lastThreatScan = now;

    local s = settings.get();
    if (not s or not s.mobThreat) then
        return;
    end

    local entMgr = AshitaCore:GetMemoryManager():GetEntity();

    -- Hold existing mob lines for as long as the mob is engaged, and start their fade once it is not
    for src, arc in pairs(arcs) do
        if (arc.color == 'enemy') then
            local engaged = isAlive(entMgr, src) and entMgr:GetStatus(src) == 1;
            if (engaged and isAlive(entMgr, arc.dst)) then
                if (now - arc.clock > 1) then
                    arc.clock = now - 1;
                end
            elseif (now - arc.clock < mobFadeAt) then
                arc.clock = now - mobFadeAt;
            end
        end
    end

    -- An engaged mob that has not acted yet is assumed to be on whoever claimed it
    for index = 1, 0x8FF do
        if (not arcs[index] and entMgr:GetRawEntity(index) ~= nil) then
            local flags = entMgr:GetSpawnFlags(index);
            if (isMob(flags) and not isPet(flags) and entMgr:GetStatus(index) == 1 and entMgr:GetHPPercent(index) > 0) then
                local claimId = entMgr:GetClaimStatus(index);
                local claimIndex = claimId ~= 0 and GetIndexFromId(claimId) or 0;
                if (claimIndex ~= 0 and claimIndex ~= index and isAlive(entMgr, claimIndex)) then
                    local firstClock = now;
                    if (lastTargets[index] == claimIndex) then
                        firstClock = now - 10; -- already shown for this target
                    else
                        playAggroSound(claimIndex);
                    end
                    lastTargets[index] = claimIndex;
                    arcs[index] = {
                        dst = claimIndex,
                        clock = now,
                        color = 'enemy',
                        firstClock = firstClock
                    };
                end
            end
        end
    end
end

local petFadeAt = 5.5; -- the render timeout for the pet line (6s) less its half second fade

local function fadePetLine(petIndex)
    local arc = arcs[petIndex];
    if (arc and arc.color == 'pet' and os.clock() - arc.clock < petFadeAt) then
        arc.clock = os.clock() - petFadeAt;
    end
end

-- Pet sync: the owner's id, the pet's index and, while the pet is attacking, its target's id
local function handlePetSyncPacket(data)
    if (bit.band(struct.unpack('B', data, 0x04 + 1), 0x3F) ~= 0x04) then
        return;
    end

    local ownerId = struct.unpack('I', data, 0x08 + 1);
    if (ownerId ~= AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) or #data < 0x18) then
        return;
    end

    local petIndex = struct.unpack('H', data, 0x0C + 1);
    local targetId = struct.unpack('I', data, 0x14 + 1);
    local targetIndex = targetId ~= 0 and GetIndexFromId(targetId) or 0;

    if (petIndex == 0 or targetIndex == 0 or targetIndex == petIndex) then
        if (petLine) then
            fadePetLine(petLine.pet);
            petLine = nil;
        end
        return;
    end

    if (petLine and petLine.pet ~= petIndex) then
        fadePetLine(petLine.pet);
    end
    petLine = { pet = petIndex, dst = targetIndex };
end

-- Holds the pet's line for as long as the server reports that target, redrawing it for a new one
local function updatePetLine()
    if (not petLine) then
        return;
    end

    local s = settings.get();
    if (not s or not s.petLine) then
        -- Switched off: let any line fade, but keep the target so switching back on restores it
        fadePetLine(petLine.pet);
        return;
    end

    local now = os.clock();
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();
    local _, myPetIndex = getOwnIndices();

    if (myPetIndex ~= petLine.pet or not isAlive(entMgr, petLine.pet) or not isAlive(entMgr, petLine.dst)) then
        fadePetLine(petLine.pet);
        petLine = nil;
        return;
    end

    local arc = arcs[petLine.pet];
    if (arc == nil or (arc.color == 'pet' and arc.dst ~= petLine.dst)) then
        arcs[petLine.pet] = {
            dst = petLine.dst,
            clock = now,
            color = 'pet',
            firstClock = now
        };
    elseif (arc.color == 'pet' and now - arc.clock > 1) then
        arc.clock = now - 1;
    end
    -- A line of another colour (the pet acting on someone else) is left to finish first
end

ashita.events.register('d3d_present', 'threat_tracker_cb', function()
    updatePetLine();
    updateThreat();
end);

ashita.events.register('packet_in', 'action_tracker_cb', function(e)
    if (e.id == 0x0028) then
        handleActionPacket(e);
    elseif (e.id == 0x0029) then
        handleMessagePacket(e.data);
    elseif (e.id == 0x0068) then
        handlePetSyncPacket(e.data);
    elseif (e.id == 0x000A) then
        -- Zoning: entity indices mean something else now. arcs is shared with the renderer, so it is
        -- emptied in place rather than replaced.
        for index in pairs(arcs) do
            arcs[index] = nil;
        end
        lastTargets = T {};
        petLine = nil;
    end
end);

return arcs;
