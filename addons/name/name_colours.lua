-- Optional state colours for the name, its spawn letters, and matching HP fill.
local bit = require('bit');
local plates = require('winxi.nameplates');
local types = require('name_types');
local controls = require('controls');
local widgets = require('winxi.widgets');
local imgui = require('imgui');
local colours = {};
colours.States = {
    playerNames = { { 'normal', 'Normal', 0xFFFFFF }, { 'combat', 'In Combat', 0xFF8000 }, { 'targeted', 'Targeted', 0xFFFFFF }, { 'dead', 'Dead', 0x808080 } },
    enemyNames = { { 'unclaimed', 'Unclaimed', 0xFFFF40 }, { 'claimedParty', 'Claimed: You / Party / Alliance', 0xFF4040 }, { 'claimedOther', 'Claimed: Others', 0xC080FF }, { 'targeted', 'Targeted', 0xFFFFFF }, { 'dead', 'Dead', 0x808080 } },
    npcNames = { { 'normal', 'Normal', 0x80FF80 }, { 'targeted', 'Targeted', 0xFFFFFF } },
};
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
function colours.Context(options, memory)
    local profile = options.nameColours and options.nameColours.enemyNames;
    if profile == nil or not (profile.claimedParty.enabled[1] or profile.claimedOther.enabled[1]) then return nil; end
    local ids = {};
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
function colours.Resolve(options, name, entities, partyIds, corpse)
    local key = types.Key(name.Category);
    local profile = options.nameColours and options.nameColours[key];
    if profile == nil then return nil; end
    -- Death is terminal: never fall through to a live/target override on a corpse.
    if corpse or (profile.dead ~= nil and profile.dead.enabled[1] and hp(name, entities) == 0) then
        return picked(profile, 'dead');
    end
    -- Do not apply normal/combat overrides to dead players either.
    if key == 'playerNames' and (profile.normal.enabled[1] or profile.combat.enabled[1] or profile.targeted.enabled[1])
            and hp(name, entities) == 0 then return picked(profile, 'dead'); end
    if bit.band(name.Flags, plates.Flag.Target) ~= 0 then
        local target = picked(profile, 'targeted');
        if target ~= nil then return target; end
    end
    if key == 'enemyNames' then
        if not (profile.unclaimed.enabled[1] or profile.claimedParty.enabled[1] or profile.claimedOther.enabled[1]) then return nil; end
        if not colours.Valid(name, entities) or entities.GetClaimStatus == nil then return nil; end
        local claim = entities:GetClaimStatus(name.EntityIndex);
        if type(claim) ~= 'number' or claim < 0 or claim > 0xFFFFFFFF or claim ~= math.floor(claim) then return nil; end
        if claim == 0 then return picked(profile, 'unclaimed'); end
        if partyIds == nil then return nil; end -- unknown party data is not proof of an outside claim
        return picked(profile, partyIds[claim] and 'claimedParty' or 'claimedOther');
    end
    if profile.combat ~= nil and profile.combat.enabled[1] and colours.InCombat(name, entities) then
        return picked(profile, 'combat');
    end
    return picked(profile, 'normal');
end
function colours.Draw(options, key)
    local open = controls.More('Colour Overrides', '##name.colours.' .. key);
    controls.Mark('Applies together to name text, spawn letters and HP fill. Dead > Targeted > combat/claim > Normal. Disabled live states fall back to the underlying state or game colour. Icons and client opacity are unchanged.');
    if not open then return; end
    for _, state in ipairs(colours.States[key]) do
        local entry = options.nameColours[key][state[1]];
        local id = '##name.colours.' .. key .. '.' .. state[1];
        controls.Checkbox(state[2] .. ' Override', id .. '.enabled', entry.enabled,
            'Override this state for the name, letters and matching health-bar fill, including explicit name/letter token colours. Off preserves the underlying state or game colour.');
        imgui.BeginDisabled(not entry.enabled[1]);
        widgets.Label(state[2] .. ' Colour'); controls.Width();
        imgui.ColorEdit4(id .. '.color', entry.color, ImGuiColorEditFlags_NoAlpha or 0);
        controls.Mark('RGB only. Opacity, distance fading, target text pulse and disappearance fading remain controlled by the renderer.');
        imgui.EndDisabled();
    end
    if imgui.Button('Use Game Colours##name.colours.reset.' .. key) then
        for _, state in ipairs(colours.States[key]) do options.nameColours[key][state[1]].enabled[1] = false; end
    end
    imgui.TreePop();
end
return colours;
