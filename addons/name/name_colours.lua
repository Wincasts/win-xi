-- Optional state colours for the name, its spawn letters, and matching HP fill.
local bit = require('bit');
local plates = require('winxi.nameplates');
local types = require('name_types');
local controls = require('controls');
local widgets = require('winxi.widgets');
local imgui = require('imgui');
local colours = {};
-- The states the game colours a name by, each with the colour the picker starts from; and Looking For
-- Party, which the game shows only by its icon
colours.States = {
    playerNames = { { 'normal', 'Normal', 0xFFFFFF }, { 'party', 'Party', 0x80D0FF }, { 'alliance', 'Alliance', 0xB0E0FF }, { 'seeking', 'Looking For Party', 0xFFC060 }, { 'dead', 'Dead', 0x808080 } },
    enemyNames = { { 'unclaimed', 'Unclaimed', 0xFFFF40 }, { 'claimedParty', 'Claimed: You / Party / Alliance', 0xFF4040 }, { 'claimedOther', 'Claimed: Others', 0xC080FF }, { 'callForHelp', 'Call For Help', 0xFFA040 }, { 'dead', 'Dead', 0x808080 } },
    npcNames = { { 'normal', 'Normal', 0x80FF80 }, { 'dead', 'Dead', 0x808080 } },
};

-- Monsters a call for help was made on, by server id: told by the entity update (0x0E), whose flags
-- at 0x21 have 0x20 while it stands, sent with its HP (mask 0x04)
local calledFor = {};
local CALL_FOR_HELP = 0x20;
local function rgb(value)
    return T{ math.floor(value / 65536) % 256 / 255, math.floor(value / 256) % 256 / 255, value % 256 / 255, 1 };
end
function colours.Defaults(options)
    options.nameColours = T{};
    for _, key in ipairs(types.List) do
        options.nameColours[key] = T{};
        for _, state in ipairs(colours.States[key]) do
            options.nameColours[key][state[1]] = T{ enabled = T{ false }, color = rgb(state[3]) };
        end
    end
end
function colours.Settle(options)
    if type(options.nameColours) ~= 'table' then options.nameColours = T{}; end
    for _, key in ipairs(types.List) do
        if type(options.nameColours[key]) ~= 'table' then options.nameColours[key] = T{}; end
        local kept = {};
        for _, state in ipairs(colours.States[key]) do kept[state[1]] = true; end
        for state in pairs(options.nameColours[key]) do
            if not kept[state] then options.nameColours[key][state] = nil; end -- In Combat and Targeted, no longer kept
        end
        for _, state in ipairs(colours.States[key]) do
            local entry = options.nameColours[key][state[1]];
            if type(entry) ~= 'table' then entry = T{}; options.nameColours[key][state[1]] = entry; end
            if type(entry.enabled) ~= 'table' or type(entry.enabled[1]) ~= 'boolean' then entry.enabled = T{ false }; end
            local fallback = rgb(state[3]);
            if type(entry.color) ~= 'table' then entry.color = fallback; end
            for i = 1, 3 do
                local v = entry.color[i];
                if type(v) ~= 'number' or v ~= v then v = fallback[i]; end
                entry.color[i] = math.max(0, math.min(1, v));
            end
            entry.color[4] = 1; -- opacity always follows the client, not a saved picker alpha
        end
    end
end
local function u32(data, at)
    local a, b, c, d = data:byte(at + 1, at + 4);
    return a + b * 256 + c * 65536 + d * 16777216;
end
function colours.HandlePacket(e)
    if e.id == 0x0A then calledFor = {}; return; end -- another area
    if e.id ~= 0x0E or e.data == nil or #e.data < 0x25 then return; end
    local id, mask = u32(e.data, 0x04), e.data:byte(0x0A + 1);
    if bit.band(mask, 0x20) ~= 0 then calledFor[id] = nil; return; end -- gone
    if bit.band(mask, 0x04) ~= 0 then
        calledFor[id] = bit.band(e.data:byte(0x21 + 1), CALL_FOR_HELP) ~= 0 or nil;
    end
end
function colours.CalledFor(serverId)
    return calledFor[serverId] == true;
end
function colours.Valid(name, entities)
    return name.ServerId ~= 0 and entities ~= nil and entities.GetServerId ~= nil
        and entities:GetServerId(name.EntityIndex) == name.ServerId;
end
local function hp(name, entities)
    if not colours.Valid(name, entities) or entities.GetHPPercent == nil then return nil; end
    local value = entities:GetHPPercent(name.EntityIndex);
    if type(value) == 'number' and value >= 0 and value <= 100 then return value; end
end
function colours.InCombat(name, entities)
    local value = hp(name, entities);
    return value ~= nil and value > 0 and entities.GetStatus ~= nil and entities:GetStatus(name.EntityIndex) == 1;
end
local function picked(profile, state)
    local entry = profile and profile[state];
    if entry == nil or not entry.enabled[1] then return nil; end
    local c = entry.color;
    return 0xFF000000 + math.floor(c[1]*255+0.5)*65536 + math.floor(c[2]*255+0.5)*256 + math.floor(c[3]*255+0.5);
end
-- The server ids of the party and alliance, for whose claim a monster is under: one table, filled
-- again each frame it is wanted, and good for that frame
local ids = {};
function colours.Context(options, memory)
    local profile = options.nameColours and options.nameColours.enemyNames;
    if profile == nil or not (profile.claimedParty.enabled[1] or profile.claimedOther.enabled[1]) then return nil; end
    for id in pairs(ids) do ids[id] = nil; end
    local party = memory.GetParty ~= nil and memory:GetParty() or nil;
    if party ~= nil and party.GetMemberServerId ~= nil then
        for slot = 0, 17 do
            local active = party.GetMemberIsActive == nil or party:GetMemberIsActive(slot);
            if active == true or active == 1 then
                local id = party:GetMemberServerId(slot);
                if type(id) == 'number' and id > 0 and id <= 0xFFFFFFFF and id == math.floor(id) then ids[id] = true; end
            end
        end
    end
    return next(ids) ~= nil and ids or nil;
end
-- Each state is the game's own, and the game's colour stands for any not overridden. Dead is first:
-- a corpse never keeps a live state's colour.
local PARTY, ALLIANCE = plates.Category.Party, plates.Category.Alliance;
local function dead(key, name, entities, corpse)
    if corpse then return true; end
    if not colours.Valid(name, entities) then return false; end
    if key == 'npcNames' then -- an NPC's HP is always 100: its status says
        local status = entities.GetStatus ~= nil and entities:GetStatus(name.EntityIndex) or nil;
        return status == 2 or status == 3;
    end
    return hp(name, entities) == 0;
end
-- Whether a player's icons say they are looking for a party: the icon alone, or with its star
local SEEKING, SEEKING_STAR = 0x91, 0xAC;
local function seeking(icons)
    if icons == nil then return false; end
    for index = 1, #icons do
        if icons[index] == SEEKING or icons[index] == SEEKING_STAR then return true; end
    end
    return false;
end
-- Whether any state of a profile is overridden: with none, nothing is asked of the entity
local function overridden(profile)
    for _, entry in pairs(profile) do
        if type(entry) == 'table' and type(entry.enabled) == 'table' and entry.enabled[1] then return true; end
    end
    return false;
end
function colours.Resolve(options, name, entities, partyIds, corpse, icons)
    local key = types.Key(name.Category);
    local profile = options.nameColours and options.nameColours[key];
    if profile == nil or not overridden(profile) then return nil; end
    if dead(key, name, entities, corpse) then return picked(profile, 'dead'); end
    if key == 'enemyNames' then
        if colours.CalledFor(name.ServerId) then return picked(profile, 'callForHelp'); end
        if not (profile.unclaimed.enabled[1] or profile.claimedParty.enabled[1] or profile.claimedOther.enabled[1]) then return nil; end
        if not colours.Valid(name, entities) or entities.GetClaimStatus == nil then return nil; end
        local claim = entities:GetClaimStatus(name.EntityIndex);
        if type(claim) ~= 'number' or claim < 0 or claim > 0xFFFFFFFF or claim ~= math.floor(claim) then return nil; end
        if claim == 0 then return picked(profile, 'unclaimed'); end
        if partyIds == nil then return nil; end -- unknown party data is not proof of an outside claim
        return picked(profile, partyIds[claim] and 'claimedParty' or 'claimedOther');
    end
    if key == 'playerNames' then
        -- the game has no colour for it: off, the name is coloured as its other state would be
        if profile.seeking.enabled[1] and seeking(icons) then return picked(profile, 'seeking'); end
        if name.Category == PARTY then return picked(profile, 'party'); end
        if name.Category == ALLIANCE then return picked(profile, 'alliance'); end
    end
    return picked(profile, 'normal');
end
function colours.Draw(options, key)
    local open = controls.More('Colour Overrides', '##name.colours.' .. key);
    controls.Mark('The states the game colours names by. An override applies together to name text, spawn letters and HP fill; a state not overridden keeps the game\'s colour. Icons and client opacity are unchanged.');
    if not open then return; end
    for _, state in ipairs(colours.States[key]) do
        local entry = options.nameColours[key][state[1]];
        local id = '##name.colours.' .. key .. '.' .. state[1];
        controls.Checkbox(state[2] .. ' Override', id .. '.enabled', entry.enabled,
            'Override this state for the name, letters and matching health-bar fill, including explicit name/letter token colours. Off: the game\'s colour for it.');
        imgui.BeginDisabled(not entry.enabled[1]);
        widgets.Label(state[2] .. ' Colour'); controls.Width();
        imgui.ColorEdit4(id .. '.color', entry.color, ImGuiColorEditFlags_NoAlpha or 0);
        controls.Mark('RGB only. Opacity, distance fading and disappearance fading remain controlled by the renderer; a target\'s name does not pulse.');
        imgui.EndDisabled();
    end
    if imgui.Button('Use Game Colours##name.colours.reset.' .. key) then
        for _, state in ipairs(colours.States[key]) do options.nameColours[key][state[1]].enabled[1] = false; end
    end
    imgui.TreePop();
end
return colours;
