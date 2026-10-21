-- Puppetmaster. Every set starts empty: put the gear on in game and save it with /lac addset <Set>.
--
-- Idle           not engaged, no automaton out
-- Idle_Pet       not engaged, automaton out and idle
-- Pet_Fighting   not engaged, automaton fighting (pet accuracy, attack, haste)
-- Resting        resting
-- Engaged        engaged
-- Engaged_Acc    engaged in Acc mode, over Engaged
-- WS             any weapon skill; a set named for the weapon skill (Asuran Fists) goes over it
-- Pet_WS         while the automaton readies a weapon skill
-- Pet_Magic      while the automaton casts; Pet_Cure, Pet_Enfeeble and Pet_Nuke go over it
-- Maneuver       any maneuver
-- Repair, Activate, Overdrive...  a set named for an ability is worn as it is used
-- Precast        fast cast, as any spell starts
-- Midcast        as a spell goes off; a set named for the spell (Utsusemi: Ni) goes over it
--
-- /lac fwd tp    cycles the TP mode: Normal, Acc

local profile = {};
local sets = {
    ['Idle'] = {
    },
    ['Idle_Pet'] = {
    },
    ['Pet_Fighting'] = {
    },
    ['Resting'] = {
    },
    ['Engaged'] = {
    },
    ['Engaged_Acc'] = {
    },
    ['WS'] = {
    },
    ['Pet_WS'] = {
    },
    ['Pet_Magic'] = {
    },
    ['Pet_Cure'] = {
    },
    ['Pet_Enfeeble'] = {
    },
    ['Pet_Nuke'] = {
    },
    ['Maneuver'] = {
    },
    ['Repair'] = {
    },
    ['Precast'] = {
    },
    ['Midcast'] = {
    },
};
profile.Sets = sets;

profile.Packer = {
};

local tpModes = { 'Normal', 'Acc' };
local tpMode = 1;

-- The set of that name, matched as /lac set matches it, or nil: for sets that need not exist
local function Find(name)
    local lower = string.lower(name);
    for setName, set in pairs(sets) do
        if (string.lower(setName) == lower) then
            return set;
        end
    end
end

local function EquipIf(name)
    local set = Find(name);
    if (set ~= nil) then
        gFunc.EquipSet(set);
    end
end

-- The automaton's weapon skill or spell. True if it is doing one, so the master's sets wait.
local function HandlePet()
    local action = gData.GetPetAction();
    if (action == nil) then
        return false;
    end

    if (action.ActionType == 'MobSkill') then
        gFunc.EquipSet(sets.Pet_WS);
    elseif (action.ActionType == 'Spell') then
        gFunc.EquipSet(sets.Pet_Magic);
        if (action.Skill == 'Healing Magic') then
            gFunc.EquipSet(sets.Pet_Cure);
        elseif (action.Skill == 'Enfeebling Magic') then
            gFunc.EquipSet(sets.Pet_Enfeeble);
        elseif (action.Skill == 'Elemental Magic') then
            gFunc.EquipSet(sets.Pet_Nuke);
        end
    else
        return false;
    end
    return true;
end

profile.OnLoad = function()
    gSettings.AllowAddSet = true;
end

profile.OnUnload = function()
end

profile.HandleCommand = function(args)
    if (args[1] == 'tp') then
        tpMode = tpMode % #tpModes + 1;
        gFunc.Message('TP mode: ' .. tpModes[tpMode]);
    end
end

profile.HandleDefault = function()
    if (HandlePet()) then
        return;
    end

    local player = gData.GetPlayer();
    local pet = gData.GetPet();
    if (player.Status == 'Engaged') then
        gFunc.EquipSet(sets.Engaged);
        if (tpModes[tpMode] == 'Acc') then
            gFunc.EquipSet(sets.Engaged_Acc);
        end
    elseif (player.Status == 'Resting') then
        gFunc.EquipSet(sets.Resting);
    elseif (pet ~= nil) and (pet.Status == 'Engaged') then
        gFunc.EquipSet(sets.Pet_Fighting);
    elseif (pet ~= nil) then
        gFunc.EquipSet(sets.Idle_Pet);
    else
        gFunc.EquipSet(sets.Idle);
    end
end

profile.HandleAbility = function()
    local action = gData.GetAction();
    if (string.find(action.Name, 'Maneuver$')) then
        gFunc.EquipSet(sets.Maneuver);
    end
    EquipIf(action.Name);
end

profile.HandleItem = function()
end

profile.HandlePrecast = function()
    gFunc.EquipSet(sets.Precast);
end

profile.HandleMidcast = function()
    local action = gData.GetAction();
    gFunc.EquipSet(sets.Midcast);
    EquipIf(action.Name);
end

profile.HandlePreshot = function()
end

profile.HandleMidshot = function()
end

profile.HandleWeaponskill = function()
    local action = gData.GetAction();
    gFunc.EquipSet(sets.WS);
    EquipIf(action.Name);
end

return profile;
