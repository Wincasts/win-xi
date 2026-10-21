-- Loads the PUP LuAshitacast profile against a stand-in for gData, gFunc and gSettings and prints which
-- sets each handler wears. A line ending in false, or an error, is something to look at.
--   luajit tests/lac_pup_check.lua
local worn;
local state = { player = { Status = 'Idle' } };

gSettings = {};
gFunc = {
    EquipSet = function(set) worn[#worn + 1] = set; end,
    Message = function(text) state.message = text; end,
};
gData = {
    GetPlayer = function() return state.player; end,
    GetPet = function() return state.pet; end,
    GetPetAction = function() return state.petAction; end,
    GetAction = function() return state.action; end,
};

local profile = dofile('luashitacast/Win_4458/PUP.lua');
profile.OnLoad();

-- Gives every set its own name, so what is worn can be read back
local names = {};
for name, set in pairs(profile.Sets) do names[set] = name; end
profile.Sets['Asuran Fists'] = {};
names[profile.Sets['Asuran Fists']] = 'Asuran Fists';

local function run(handler)
    worn = {};
    profile[handler]();
    local out = {};
    for _, set in ipairs(worn) do out[#out + 1] = names[set] or '?'; end
    return table.concat(out, ',');
end

local function check(label, got, want)
    print(label .. ': ' .. got .. ' ' .. tostring(got == want));
end

check('idle', run('HandleDefault'), 'Idle');
state.pet = { Status = 'Idle' };
check('idle, pet out', run('HandleDefault'), 'Idle_Pet');
state.pet.Status = 'Engaged';
check('pet fighting', run('HandleDefault'), 'Pet_Fighting');
state.player.Status = 'Engaged';
check('engaged', run('HandleDefault'), 'Engaged');
profile.HandleCommand({ 'tp' });
check('tp mode message', state.message, 'TP mode: Acc');
check('engaged, Acc', run('HandleDefault'), 'Engaged,Engaged_Acc');
profile.HandleCommand({ 'tp' });
check('tp mode back', state.message, 'TP mode: Normal');
state.player.Status = 'Resting';
check('resting', run('HandleDefault'), 'Resting');

state.player.Status = 'Engaged';
state.petAction = { ActionType = 'MobSkill', Name = 'Slapstick' };
check('pet weapon skill', run('HandleDefault'), 'Pet_WS');
state.petAction = { ActionType = 'Spell', Skill = 'Elemental Magic', Name = 'Thunder II' };
check('pet nuke', run('HandleDefault'), 'Pet_Magic,Pet_Nuke');
state.petAction = { ActionType = 'Spell', Skill = 'Healing Magic', Name = 'Cure III' };
check('pet cure', run('HandleDefault'), 'Pet_Magic,Pet_Cure');
state.petAction = { ActionType = 'Spell', Skill = 'Enfeebling Magic', Name = 'Slow' };
check('pet enfeeble', run('HandleDefault'), 'Pet_Magic,Pet_Enfeeble');
state.petAction = { ActionType = 'Spell', Skill = 'Dark Magic', Name = 'Drain' };
check('pet other magic', run('HandleDefault'), 'Pet_Magic');
state.petAction = { ActionType = 'Ability', Name = 'Provoke' };
check('pet ability, master sets', run('HandleDefault'), 'Engaged');
state.petAction = nil;

state.action = { Name = 'Fire Maneuver' };
check('maneuver', run('HandleAbility'), 'Maneuver');
state.action = { Name = 'Repair' };
check('repair', run('HandleAbility'), 'Repair');
state.action = { Name = 'Deploy' };
check('ability with no set', run('HandleAbility'), '');
state.action = { Name = 'Asuran Fists' };
check('named weapon skill', run('HandleWeaponskill'), 'WS,Asuran Fists');
state.action = { Name = 'Raging Fists' };
check('weapon skill', run('HandleWeaponskill'), 'WS');
state.action = { Name = 'Utsusemi: Ni' };
check('precast', run('HandlePrecast'), 'Precast');
check('midcast', run('HandleMidcast'), 'Midcast');
check('addset allowed', tostring(gSettings.AllowAddSet), 'true');
