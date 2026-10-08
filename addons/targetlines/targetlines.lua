addon.name    = 'targetlines';
addon.author  = 'Jyouya, Win (and Claude)';
addon.version = '1.2';
addon.desc    = 'FFXII style target lines';

require('common');

local arcRenderer = require('drawArc');
local drawArc  = arcRenderer.draw;
local arcs     = require('tracker');
local helpers  = require('helpers');
local settings = require('settings');
local arcState = require('arcstate');

local config   = require('config');


-- The sources of the lines from or to the party (or alliance) and their pets, plus everything connected
-- to those, as a set: source index -> true.
-- Arcs are indexed by destination once, then each member's connections are walked from that.
local function getPartyArcs(alliance)
    local byDst = {};
    for src, v in pairs(arcs) do
        local incoming = byDst[v.dst];
        if (not incoming) then
            incoming = {};
            byDst[v.dst] = incoming;
        end
        incoming[#incoming + 1] = src;
    end

    local res = {};
    local visited = {};

    -- Takes every line pointing at index, then follows index's own line to its target and repeats
    local function collect(index)
        while (index and not visited[index]) do
            visited[index] = true;

            local incoming = byDst[index];
            if (incoming) then
                for _, src in ipairs(incoming) do
                    res[src] = true;
                end
            end

            local own = arcs[index];
            if (own) then
                res[index] = true;
                index = own.dst;
            else
                index = nil;
            end
        end
    end

    local party = AshitaCore:GetMemoryManager():GetParty();
    local entity = AshitaCore:GetMemoryManager():GetEntity();
    for i = 0, alliance and 17 or 5 do
        if (party:GetMemberIsActive(i) ~= 0) then
            local targetIndex = party:GetMemberTargetIndex(i);
            collect(targetIndex);

            -- A pet's own line starts at the pet, so it is not reached through its owner
            local petIndex = targetIndex ~= 0 and entity:GetPetTargetIndex(targetIndex) or 0;
            if (petIndex ~= 0) then
                collect(petIndex);
            end
        end
    end

    return res;
end

-- The party filter's result is kept and worked out again only when the lines have changed, the filter has
-- been switched, or partyFilterMaxAge has passed (the party itself, or a pet, may have changed).
local partyFilterMaxAge = 0.25;
local partyFilter = { sources = nil, version = -1, alliance = nil, time = 0 };

local function getPartySources(alliance, now)
    local cache = partyFilter;
    if (cache.sources == nil or cache.version ~= arcState.version or cache.alliance ~= alliance
            or now - cache.time >= partyFilterMaxAge) then
        cache.sources = getPartyArcs(alliance);
        cache.version = arcState.version;
        cache.alliance = alliance;
        cache.time = now;
    end
    return cache.sources;
end

-- Quiet mode: the only lines drawn are those to or from the player and the player's pet, and from the mob
-- the player is targeting. Returns their entity indices, 0 for any that does not apply.
local function getQuietSources()
    local memory = AshitaCore:GetMemoryManager();
    local entity = memory:GetEntity();

    local myIndex = memory:GetParty():GetMemberTargetIndex(0);
    local myPetIndex = myIndex ~= 0 and entity:GetPetTargetIndex(myIndex) or 0;

    -- While a sub target is being chosen it takes the first slot and the main target moves to the second
    local target = memory:GetTarget();
    local targetIndex = target:GetTargetIndex(target:GetIsSubTargetActive());
    if (targetIndex ~= 0 and bit.band(entity:GetSpawnFlags(targetIndex), 0x10) == 0) then
        targetIndex = 0; -- not a mob
    end

    return myIndex, myPetIndex, targetIndex;
end

-- Used for any line type the settings hold no colour for
local defaultColor = T {
    player = 0xFF0088FF,
    enemy = 0xFFFF1133,
    playerFriendly = 0xFF00FF66,
    enemyFriendly = 0xFFFF8800,
    pet = 0xFFFA8072 -- salmon
};

local function channel(value)
    return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5);
end

-- The colour chosen in the settings for a line type, as the opaque ARGB number the renderer takes
local function getLineColor(s, lineType)
    local chosen = s.colors and s.colors[lineType];
    if (type(chosen) ~= 'table' or not (chosen[1] and chosen[2] and chosen[3])) then
        return defaultColor[lineType];
    end

    return 0xFF000000 + channel(chosen[1]) * 0x10000 + channel(chosen[2]) * 0x100 + channel(chosen[3]);
end

-- This frame's colour for each line type, refilled each frame so the colour pickers apply live
local lineColors = {};

local timeouts = T {
    player = 6,
    enemy = 6,
    playerFriendly = 2,
    enemyFriendly = 2,
    pet = 6
};

-- The most of a line's length the nameplate mode gap may take from each end, so that a line between
-- close entities is not cut away
local nameplateMaxInset = 0.10;

-- Where a line attaches to an entity: midway between its feet and a bone near its head, or, with
-- nameplate set, that many world units above that point, towards where the entity's name is drawn.
-- The client's own nameplate position is not read.
-- Returns nothing when the entity is not loaded.
local function readAnchor(entity, index, nameplate)
    local pointer = entity:GetActorPointer(index);
    if (not pointer or pointer == 0) then
        return nil;
    end

    local x, y, z, feet = helpers.getBone(pointer, 2);
    local up = z < feet and -1 or 1; -- whichever way the head lies from the feet
    z = (feet + z) / 2;
    if (nameplate) then
        z = z + up * nameplate;
    end

    return x, y, z;
end

-- Each entity's anchor is read once a frame however many lines start or end on it. anchorFrame holds the
-- frame an index was last read in, and anchorX holds false for an entity that was not loaded.
local anchorFrame, anchorX, anchorY, anchorZ = {}, {}, {}, {};
local frameNumber = 0;

local function getAnchor(entity, index, nameplate)
    if (anchorFrame[index] ~= frameNumber) then
        local x, y, z = readAnchor(entity, index, nameplate);
        anchorFrame[index] = frameNumber;
        anchorX[index], anchorY[index], anchorZ[index] = x or false, y, z;
    end

    local x = anchorX[index];
    if (not x) then
        return nil;
    end
    return x, anchorY[index], anchorZ[index];
end

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
                arcState.version = arcState.version + 1;
            end
        end

        -- No lines at all: nothing to filter or draw
        if (next(arcs) == nil) then
            return;
        end

        -- With a filter on, the sources of the lines to draw; nil means every line
        local sources = nil;
        if (s.filter ~= 'All') then
            sources = getPartySources(s.filter == 'Alliance', now);

            -- Nothing to draw: skip the camera and colour setup entirely
            if (next(sources) == nil) then
                return;
            end
        end

        frameNumber = frameNumber + 1;

        arcRenderer.beginFrame(1 - (tonumber(s.transparency) or 10) / 100, (tonumber(s.orbScale) or 100) / 100);

        for lineType in pairs(defaultColor) do
            lineColors[lineType] = getLineColor(s, lineType);
        end

        local entity = AshitaCore:GetMemoryManager():GetEntity();

        -- Stored as a whole number of tenths of a world unit
        local nameplate = s.nameplateAnchor and (tonumber(s.nameplateOffset) or 10) / 10 or nil;

        -- In nameplate mode a line starts and ends this far short of its two anchors, in world units
        -- (stored in tenths), and never by more than nameplateMaxInset of its length at each end
        local nameplateInset = math.max(0, tonumber(s.nameplateInset) or 5) / 10;

        local quiet = s.quietMode;
        local myIndex, myPetIndex, myTargetIndex;
        if (quiet) then
            myIndex, myPetIndex, myTargetIndex = getQuietSources();
        end

        for src, v in pairs(arcs) do
            local dTime = now - v.clock;
            local timeout = timeouts[v.color];
            local dFirstTime = v.firstClock and now - v.firstClock;
            local lineType = v.color;

            -- Work out how the line looks first, so nothing is read from memory for one that is hidden
            local progress, alpha = 1, 1;
            if ((lineType == 'player' or lineType == 'pet' or (lineType == 'enemy' and s.mobBrief)) and dFirstTime and dFirstTime > 2.5) then
                -- Brief lines stay connected and fade out over their last half second
                alpha = math.max((3 - dFirstTime) * 2, 0);
            elseif (dTime > timeout - 0.5) then
                alpha = math.min(math.max((timeout - dTime) * 2, 0), 1);
            else
                progress = math.min(1 - (0.5 - math.min(dTime, 1)) * 2, 1);
                -- Slight fade-in while the arc extends: 20% to full opacity over the same half second
                alpha = math.min(0.2 + math.max(dTime, 0) * 1.6, 1);
            end

            if (quiet and src ~= myIndex and src ~= myPetIndex and src ~= myTargetIndex
                    and (v.dst == 0 or (v.dst ~= myIndex and v.dst ~= myPetIndex))) then
                alpha = 0;
            end

            if (sources and not sources[src]) then
                alpha = 0; -- filtered out
            end

            if (alpha > 0) then
                local x1, y1, z1 = getAnchor(entity, src, nameplate);
                local x2, y2, z2 = getAnchor(entity, v.dst, nameplate);

                if (x1 and x2 and nameplate) then
                    -- Pull both ends in along the line so it stops short of the nameplates
                    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1;
                    local length = math.sqrt(dx * dx + dy * dy + dz * dz);
                    if (length > 0) then
                        local inset = math.min(nameplateInset, length * nameplateMaxInset) / length;
                        x1, y1, z1 = x1 + dx * inset, y1 + dy * inset, z1 + dz * inset;
                        x2, y2, z2 = x2 - dx * inset, y2 - dy * inset, z2 - dz * inset;
                    end
                end

                if (x1 and x2) then
                    drawArc(x1, y1, z1, x2, y2, z2, lineColors[v.color], progress, true, alpha);
                end
            end
        end

        -- The lines were only written out above: this draws them all
        arcRenderer.endFrame();
    end);
end);
