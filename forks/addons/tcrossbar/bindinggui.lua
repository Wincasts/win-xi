local d3d8 = require('d3d8');
local d3d8_device = d3d8.get_device();
local encoding = require('gdifonts.encoding');
local ffi = require('ffi');
local imgui = require('imgui');
local inventory = require('state.inventory');
local player = require('state.player');
local window = require('winxi.window');
local widgets = require('winxi.widgets');
local theme = require('winxi.theme');
local header = widgets.HeaderColor;
local activeHeader = header;

local function Label(text, color)
    if color then imgui.PushStyleColor(ImGuiCol_Text, color); end
    widgets.Label(text);
    if color then imgui.PopStyleColor(); end
end
local state = { IsOpen={ false } };
local wsmap = require('resources.wsmap');
local bindingcontext = require('bindingcontext');
local weaponcontext = require('weaponcontext');
local function ContextEditor(binding)
    local editors = {};
    for _,definition in ipairs(bindingcontext.Definitions) do
        local override = binding and binding.Overrides and binding.Overrides[definition.Key];
        editors[definition.Key] = {
            Enabled = { override ~= nil and override.Enabled == true },
            MacroText = { override and table.concat(override.Macro or {}, '\n') or '' },
        };
    end
    return editors;
end
-- Display order is independent of the stable scope IDs used by formatted bindings.
local scopeOrder = { 1, 2, 5, 4, 3 };
local function ScopeIndex(scope)
    for index,id in ipairs(scopeOrder) do
        if id == scope then return index; end
    end
    return 5; -- Palette
end
local Setup = {};
local Update = {};


local macroStateText = {
    [1] = 'Left Trigger',
    [2] = 'Right Trigger',
    [3] = 'Both Triggers (Left First)',
    [4] = 'Both Triggers (Right First)',
    [5] = 'Left Trigger (Double Tap)',
    [6] = 'Right Trigger (Double Tap)'
};

local buttonText = {
    'Left Grouping, Top Square',
    'Left Grouping, Right Square',
    'Left Grouping, Bottom Square',
    'Left Grouping, Left Square',
    'Right Grouping, Top Square',
    'Right Grouping, Right Square',
    'Right Grouping, Bottom Square',
    'Right Grouping, Left Square'
};

local macroComboBinds = {
    [1] = 'LT',
    [2] = 'RT',
    [3] = 'LTRT',
    [4] = 'RTLT',
    [5] = 'LT2',
    [6] = 'RT2'
};


local function GetMacroStateText(state)
    if (state == 3) and (gSettings.EnableDoubleTap == false) then
        return 'Both Triggers';
    end
    return macroStateText[state];
end

local function CheckBox(display, field)
    local displayName = display;
    local fieldName = display;
    if (field ~= nil) then
        fieldName = field;
    end
    widgets.Label(displayName);
    if (imgui.Checkbox('##Binding_' .. fieldName, { state.Components[fieldName] })) then
        state.Components[fieldName] = not state.Components[fieldName];
    end
end

local function ComboBox(displayName, varName, color)
    if (state.Combos[varName] == nil) then
        state.Combos[varName] = T{};
    end
    if (state.Indices[varName] == nil) then
        state.Indices[varName] = 1;
    end

    if (color == nil) then color = header; end
    Label(displayName, color);
    local text = state.Combos[varName][state.Indices[varName]];
    if (text == nil) then text = 'N/A'; end
    if (imgui.BeginCombo(string.format('##%s', displayName), text, ImGuiComboFlags_None)) then
        for index,entry in ipairs(state.Combos[varName]) do
            local isSelected = (index == state.Indices[varName]);
            if (imgui.Selectable(entry, isSelected)) then
                if (not isSelected) then
                    state.Indices[varName] = index;
                    local updateFunction = Update[varName];
                    if updateFunction then
                        updateFunction(state.Combos[varName][index]);
                    end
                end
            end
        end
        imgui.EndCombo();
    end
end

local function AdvanceCombo(varName)
    local index = state.Indices[varName] + 1;
    if (index > #state.Combos[varName]) then
        index = 1;
    end
    state.Indices[varName] = index;
    local updateFunction = Update[varName];
    if updateFunction then
        updateFunction(state.Combos[varName][index]);
    end
end

local function DecrementCombo(varName)
    local index = state.Indices[varName] - 1;
    if (index == 0) then
        index = #state.Combos[varName];
    end

    state.Indices[varName] = index;
    local updateFunction = Update[varName];
    if updateFunction then
        updateFunction(state.Combos[varName][index]);
    end
end

local function UpdateMacroImage()
    state.Texture = nil;
    if (state.MacroImage == nil) then
        return;
    end
    local tx = gTextureCache:GetTexture(state.MacroImage[1]);
    if tx then
        state.Texture = tx.Texture;
    end
end

local function NamedResource(res)
    local name = res and res.Name and res.Name[1];
    return type(name) == 'string' and string.find(name, '%S') ~= nil and name ~= '.';
end

local blockedAbilities = T{
    567, --Pet Commands
    603, --Blood Pact: Rage
    609, --Phantom Roll
    636, --Quick Draw
    684, --Blood Pact: Ward
    694, --Sambas
    695, --Waltzes
    710, --Jigs
    711, --Steps
    712, --Flourishes I
    725, --Flourishes II
    735, --Stratagems
    763, --Ready
    775, --Flourishes III
    869, --Rune Enchantment
    891, --Ward
    892, --Effusion
};
Setup.Ability = function(skipUpdate)
    state.ActionResources = T{};
    local resMgr = AshitaCore:GetResourceManager();

    for i = 0x200,0x600 do
        if (not blockedAbilities:contains(i)) then
            local res = resMgr:GetAbilityById(i);
            if NamedResource(res) and (gSettings.ShowUnavailableActions or player:KnowsAbility(res.Id)) then
                state.ActionResources:append(res);
            end
        end
    end

    table.sort(state.ActionResources, function(a,b)
        return a.Name[1] < b.Name[1];
    end);

    state.Combos.Action = T{};
    for _,res in ipairs(state.ActionResources) do
        state.Combos.Action:append(encoding:ShiftJIS_To_UTF8(res.Name[1]));
    end

    state.Indices.Action = 1;
    if not skipUpdate then
        Update.Action(state.Combos.Action[1]);
    end
end

Setup.Command = function(skipUpdate)
    state.Combos.Action = T{};
    state.Indices.Action = 0;
    if not skipUpdate then
        Update.Command();
    end
end

Setup.Empty = function()
    state.Combos.Action = T{};
    state.Indices.Action = 0;
    Update.Empty();
end

Setup.Item = function(skipUpdate)
    state.ActionResources = T{};
    
    local resMgr = AshitaCore:GetResourceManager();
    local bags = T{0, 3};
    for _,bag in ipairs(bags) do
        for i = 1,80 do
            local item = inventory:GetItemTable(bag, i);
            if (item ~= nil) then
                local res = resMgr:GetItemById(item.Id);
                if (res ~= nil) and (bit.band(res.Flags, 0x200) == 0x200) then
                    if (not state.ActionResources:contains(res)) then
                        state.ActionResources:append(res);
                    end
                end
            end
        end
    end

    bags = T{ 0, 8, 10, 11, 12, 13, 14, 15, 16 };
    for _,bag in ipairs(bags) do
        for i = 1,80 do
            local item = inventory:GetItemTable(bag, i);
            if (item ~= nil) then
                local res = resMgr:GetItemById(item.Id);
                if (res ~= nil) and (bit.band(res.Flags, 0x400) == 0x400) then
                    if (not state.ActionResources:contains(res)) then
                        state.ActionResources:append(res);
                    end
                end
            end
        end
    end

    table.sort(state.ActionResources, function(a,b)
        return a.Name[1] < b.Name[1];
    end);

    state.Combos.Action = T{};
    for index,res in ipairs(state.ActionResources) do
        local prev = state.ActionResources[index - 1];
        local next = state.ActionResources[index + 1];

        --Show item id if multiple matching items..
        local name = encoding:ShiftJIS_To_UTF8(res.Name[1]);
        if (prev) and (prev.Name[1] == name) then
            state.Combos.Action:append(string.format('%s[%u]', name, res.Id));            
        elseif (next) and (next.Name[1] == name) then
            state.Combos.Action:append(string.format('%s[%u]', name, res.Id));
        else
            state.Combos.Action:append(name);
        end
    end

    if not skipUpdate then
        state.Indices.Action = 1;
        Update.Action(state.Combos.Action[1]);
    end
end

Setup.Spell = function(skipUpdate)
    state.ActionResources = T{};
    local resMgr = AshitaCore:GetResourceManager();
    local jobData = player:GetJobData();
    local mainJob = jobData.MainJob;
    local mainJobLevel = jobData.MainJobLevel;
    local subJob = jobData.SubJob;
    local subJobLevel = jobData.SubJobLevel;

    for i = 1,0x400 do
        local res = resMgr:GetSpellById(i);
        if NamedResource(res) and (gSettings.ShowUnavailableActions or player:HasSpell(res)) then
            local levelRequired = res.LevelRequired;
            --Maybe not best workaround, but trust are all usable at WAR1.
            if (levelRequired[2] ~= 1) then
                local hasSpell = gSettings.ShowUnavailableActions;
                local jpMask = res.JobPointMask;
                if (bit.band(bit.rshift(jpMask, mainJob), 1) == 1) then
                    if (mainJobLevel == 99) and (player:GetJobPointTotal(mainJob) >= levelRequired[mainJob + 1]) then
                        hasSpell = true;
                    end
                elseif (levelRequired[mainJob + 1] ~= -1) and (mainJobLevel >= levelRequired[mainJob + 1]) then
                    hasSpell = true;
                end

                if (bit.band(bit.rshift(jpMask, subJob), 1) == 0) then
                    if (levelRequired[subJob + 1] ~= -1) and (subJobLevel >= levelRequired[subJob + 1]) then
                        hasSpell = true;
                    end
                end

                if (hasSpell) then
                    state.ActionResources:append(res);
                end
            end
        end
    end

    table.sort(state.ActionResources, function(a,b)
        return a.Name[1] < b.Name[1];
    end);

    state.Combos.Action = T{};
    for _,res in ipairs(state.ActionResources) do
        state.Combos.Action:append(encoding:ShiftJIS_To_UTF8(res.Name[1]));
    end

    if (not skipUpdate) then
        state.Indices.Action = 1;
        Update.Action(state.Combos.Action[1]);
    end
end

Setup.Trust = function(skipUpdate)
    state.ActionResources = T{};
    local resMgr = AshitaCore:GetResourceManager();
    local jobData = player:GetJobData();
    local mainJob = jobData.MainJob;
    local mainJobLevel = jobData.MainJobLevel;
    local subJob = jobData.SubJob;
    local subJobLevel = jobData.SubJobLevel;

    for i = 1,0x400 do
        local res = resMgr:GetSpellById(i);
        if NamedResource(res) and (gSettings.ShowUnavailableActions or player:HasSpell(res)) then
            local levelRequired = res.LevelRequired;

            --Maybe not best workaround, but trust are all usable at WAR1.
            if (levelRequired[2] == 1) then
                local hasSpell = gSettings.ShowUnavailableActions;
                local jpMask = res.JobPointMask;
                if (bit.band(bit.rshift(jpMask, mainJob), 1) == 1) then
                    if (mainJobLevel == 99) and (player:GetJobPointTotal(mainJob) >= levelRequired[mainJob + 1]) then
                        hasSpell = true;
                    end
                elseif (levelRequired[mainJob + 1] ~= -1) and (mainJobLevel >= levelRequired[mainJob + 1]) then
                    hasSpell = true;
                end

                if (bit.band(bit.rshift(jpMask, subJob), 1) == 0) then
                    if (levelRequired[subJob + 1] ~= -1) and (subJobLevel >= levelRequired[subJob + 1]) then
                        hasSpell = true;
                    end
                end

                if (hasSpell) then
                    state.ActionResources:append(res);
                end
            end
        end
    end

    table.sort(state.ActionResources, function(a,b)
        return a.Name[1] < b.Name[1];
    end);

    state.Combos.Action = T{};
    for _,res in ipairs(state.ActionResources) do
        state.Combos.Action:append(encoding:ShiftJIS_To_UTF8(res.Name[1]));
    end

    if (not skipUpdate) then
        state.Indices.Action = 1;
        Update.Action(state.Combos.Action[1]);
    end
end

Setup.Weaponskill = function(skipUpdate)
    state.ActionResources = T{};
    local resMgr = AshitaCore:GetResourceManager();
    for i = 1,0x200 do
        local res = resMgr:GetAbilityById(i);
        if NamedResource(res) and (gSettings.ShowUnavailableActions or player:KnowsAbility(res.Id)) then
            state.ActionResources:append(res);
        end
    end

    table.sort(state.ActionResources, function(a,b)
        return a.Name[1] < b.Name[1];
    end);

    state.Combos.Action = T{};
    for _,res in ipairs(state.ActionResources) do
        state.Combos.Action:append(encoding:ShiftJIS_To_UTF8(res.Name[1]));
    end

    if (not skipUpdate) then
        state.Indices.Action = 1;
        Update.Action(state.Combos.Action[1]);
    end
end

-- Refresh the catalog without replacing a custom macro, its context overrides, or its
-- selected resource. A selected unavailable entry stays editable when the filter is hidden.
local function RefreshActionCatalog()
    local actionType = state.Combos.Type[state.Indices.Type];
    if actionType == 'Command' or actionType == 'Empty' or actionType == 'Item' then return; end
    local selected = state.ActionResources[state.Indices.Action];
    Setup[actionType](true);
    if selected then
        for index,res in ipairs(state.ActionResources) do
            if (actionType == 'Spell' or actionType == 'Trust') and res.Index == selected.Index
                or (actionType ~= 'Spell' and actionType ~= 'Trust' and res.Id == selected.Id) then
                state.Indices.Action = index;
                return;
            end
        end
        state.ActionResources:append(selected);
        state.Combos.Action:append(encoding:ShiftJIS_To_UTF8(selected.Name[1]));
        state.Indices.Action = #state.ActionResources;
    elseif #state.ActionResources > 0 then
        state.Indices.Action = 1;
        Update.Action(state.Combos.Action[1]);
    end
end

Update.Type = function(newValue)
    Setup[newValue]();
end

Update.Action = function(newValue)
    local type = state.Combos.Type[state.Indices.Type];
    if (state.Indices.Action > #state.ActionResources) then
        Update.Empty();
    else
        Update[type](state.Indices.Action);
    end
end

Update.Ability = function(index)
    local res = state.ActionResources[index];
    local name = encoding:ShiftJIS_To_UTF8(res.Name[1]);
    if (bit.band(res.Targets, 0xFC) ~= 0) then
        if (gSettings.DefaultSelectTarget) then
            state.MacroText = { string.format('/ja \"%s\" <st>', name) };
        else
            state.MacroText = { string.format('/ja \"%s\" <t>', name) };
        end
    else
        state.MacroText = { string.format('/ja \"%s\" <me>', name) };
    end
    state.MacroLabel = { name };
    if ((res.RecastTimerId == 0) or (res.RecastTimerId == 254)) then
        state.MacroImage = { 'abilities/1hr.png' };
    else
        state.MacroImage = { string.format('abilities/%u.png', res.Id - 0x200) };
    end
    state.CostOverride = { '' };
    UpdateMacroImage();
end

Update.Command = function(index)
    if (gSettings.DefaultSelectTarget) then
        state.MacroText = { '/attack <st>' };
    else
        state.MacroText = { '/attack <t>' };
    end
    state.MacroLabel = { 'Attack' };
    state.MacroImage = { 'misc/command.png' };
    state.CostOverride = { '' };
    UpdateMacroImage();
end

Update.Empty = function(index)
    state.MacroText = nil;
    state.MacroLabel = nil;
    state.MacroImage = { 'misc/empty.png' };
    state.CostOverride = nil;
    UpdateMacroImage();
end

Update.Item = function(index)
    local res = state.ActionResources[index];
    local name = encoding:ShiftJIS_To_UTF8(res.Name[1]);
    if (bit.band(res.Targets, 0xFC) ~= 0) then
        if (gSettings.DefaultSelectTarget) then
            state.MacroText = { string.format('/item \"%s\" <st>', name) };
        else
            state.MacroText = { string.format('/item \"%s\" <t>', name) };
        end
    else
        state.MacroText = { string.format('/item \"%s\" <me>', name) };
    end
    state.MacroLabel = { name };
    state.MacroImage = { string.format('ITEM:%u', res.Id) };
    state.CostOverride = nil;
    UpdateMacroImage();
end

Update.Spell = function(index)
    local res = state.ActionResources[index];
    local name = encoding:ShiftJIS_To_UTF8(res.Name[1]);
    if (bit.band(res.Targets, 0xFC) ~= 0) then
        if (gSettings.DefaultSelectTarget) then
            state.MacroText = { string.format('/ma \"%s\" <st>', name) };
        else
            state.MacroText = { string.format('/ma \"%s\" <t>', name) };
        end
    else
        state.MacroText = { string.format('/ma \"%s\" <me>', name) };
    end
    state.MacroLabel = { name };
    state.MacroImage = { string.format('spells/%u.png', res.Index) };
    state.CostOverride = { '' };
    UpdateMacroImage();
end

Update.Trust = function(index)
    local res = state.ActionResources[index];
    local name = encoding:ShiftJIS_To_UTF8(res.Name[1]);
    state.MacroText = { string.format('/ma \"%s\" <me>', name) };
    state.MacroLabel = { name };
    state.MacroImage = { string.format('spells/%u.png', res.Index) };
    state.CostOverride = { '' };
    UpdateMacroImage();
end

Update.Weaponskill = function(index)
    local res = state.ActionResources[index];
    local name = encoding:ShiftJIS_To_UTF8(res.Name[1]);
    if (bit.band(res.Targets, 0xFC) ~= 0) then
        if (gSettings.DefaultSelectTarget) then
            state.MacroText = { string.format('/ws \"%s\" <st>', name) };
        else
            state.MacroText = { string.format('/ws \"%s\" <t>', name) };
        end
    else
        state.MacroText = { string.format('/ws \"%s\" <me>', name) };
    end
    state.MacroLabel = { name };
    state.MacroImage = { wsmap[res.Id] or '' };
    state.CostOverride = { '' };
    UpdateMacroImage();
end

local function GetBindResource()
    local type = state.Combos.Type[state.Indices.Type];
    if T{'Ability', 'Item', 'Spell', 'Trust', 'Weaponskill'}:contains(type) then
        local res = state.ActionResources[state.Indices.Action];
        return res;
    else
        return true;
    end
end

local function AttemptBind()
    local scope = scopeOrder[state.Indices.Scope];
    local bindResource = GetBindResource();
    if (bindResource == nil) then
        return false;
    end

    if (state.Combos.Type[state.Indices.Type] == 'Empty') then
        if (scope == 1) then
            gBindings:BindGlobal(state.Hotkey, nil);
        elseif (scope == 2) then
            gBindings:BindJob(state.Hotkey, nil);
        elseif (scope == 3) then
            gBindings:BindPalette(state.Hotkey, nil);
        elseif (scope == 4) then
            gBindings:BindSubjob(state.Hotkey, nil);
        elseif (scope == 5) then
            gBindings:BindWeapon(state.Hotkey, nil, state.WeaponSkill);
        else
            return false;
        end
        return true;
    end

    local binding = {};
    binding.ActionType = state.Combos.Type[state.Indices.Type];
    if T{'Ability', 'Item', 'Spell', 'Trust', 'Weaponskill'}:contains(binding.ActionType) then
        if (binding.ActionType == 'Spell') or (binding.ActionType == 'Trust') then
            binding.Id = bindResource.Index;
        else
            binding.Id = bindResource.Id;
        end
    end
    if ((state.CostOverride ~= nil) and (state.CostOverride[1] ~= '')) then
        local ids = T{};
        local compString = string.gsub(state.CostOverride[1], ' ', '');
        if (string.find(compString, ',')) then
            for entry in string.gmatch(compString, '([^,]+)') do
                local id = tonumber(entry);
                if type(id) == 'number' then
                    local res = AshitaCore:GetResourceManager():GetItemById(id);
                    if (res ~= nil) and (string.len(res.Name[1]) > 0) then
                        ids:append(id);
                    end
                end
            end
        else
            local id = tonumber(compString);
            if type(id) == 'number' then
                local res = AshitaCore:GetResourceManager():GetItemById(id);
                if (res ~= nil) and (string.len(res.Name[1]) > 0) then
                    ids:append(id);
                end
            end
        end
        if (#ids > 0) then
            binding.CostOverride = ids;
        end
    end
    if (state.MacroLabel == nil) then
        binding.Label = '';
    else
        binding.Label = state.MacroLabel[1];
    end
    if (state.MacroText == nil) then
        binding.Macro = T{};
    else
        binding.Macro = T{};
        for line in string.gmatch(state.MacroText[1], "[^\r\n]+") do
            binding.Macro:append(line);
        end
    end
    for _,definition in ipairs(bindingcontext.Definitions) do
        local editor = state.ContextEditors[definition.Key];
        local macro = T{};
        for line in string.gmatch(editor.MacroText[1], '[^\r\n]+') do
            if string.find(line, '%S') then macro:append(line); end
        end
        if editor.Enabled[1] and #macro == 0 then
            Error('Enter a ' .. definition.Label .. ' Override macro, or disable the override.');
            return false;
        end
        if editor.Enabled[1] or #macro > 0 then
            binding.Overrides = binding.Overrides or {};
            binding.Overrides[definition.Key] = { Enabled = editor.Enabled[1], Macro = macro };
        end
    end
    binding.Image = state.MacroImage[1];
    binding.ShowCost = state.Components.Cost;
    binding.ShowCross = state.Components.Cross;
    binding.ShowFade = state.Components.Fade;
    binding.ShowRecast = state.Components.Recast;
    binding.ShowName = state.Components.Name;
    binding.ShowTrigger = state.Components.Trigger;
    binding.ShowReadyPulse = state.Components.ReadyPulse;
    binding.ShowSkillchainIcon = state.Components.SkillchainIcon;
    binding.ShowSkillchainAnimation = state.Components.SkillchainAnimation;
    binding.ShowHotkey = state.Components.Hotkey;
    if (scope == 1) then
        gBindings:BindGlobal(state.Hotkey, binding);
    elseif (scope == 2) then
        gBindings:BindJob(state.Hotkey, binding);
    elseif (scope == 3) then
        gBindings:BindPalette(state.Hotkey, binding);
    elseif (scope == 4) then
        gBindings:BindSubjob(state.Hotkey, binding);
    elseif (scope == 5) then
        return gBindings:BindWeapon(state.Hotkey, binding, state.WeaponSkill);
    else
        return false;
    end
    return true;
end

local exposed = {};

function exposed:Close()
    state = { IsOpen = { false } };
end

function exposed:GetActive()
    return (state.IsOpen[1] == true);
end

function exposed:GetMacroState()
    if (state.IsOpen[1] == true) then
        return state.MacroState;
    end
    return 0;
end

function exposed:HandleButton(button, pressed)
    if (pressed) then
        if (button == state.RepeatButton) then
            if (state.RepeatDelay > 0.05) then
                state.RepeatDelay = state.RepeatDelay - 0.05;
            end
            state.RepeatTime = os.clock();
        else
            state.RepeatButton = button;
            state.RepeatTime = os.clock();
            state.RepeatDelay = 0.3;
        end
        
        if (state.Tab == 1) then
            if (button == 'BindingUp') then
                if (state.SelectedIndex > 1) then
                    state.SelectedIndex = state.SelectedIndex - 1;
                end
            end

            if (button == 'BindingDown') then
                if (state.SelectedIndex < 3) then
                    state.SelectedIndex = state.SelectedIndex + 1;
                end
            end

            if (button == 'BindingNext') then
                if (state.SelectedIndex == 1) then
                    AdvanceCombo('Scope');
                elseif (state.SelectedIndex == 2) then
                    AdvanceCombo('Type');
                elseif (state.SelectedIndex == 3) then
                    AdvanceCombo('Action');
                end
            end
            
            if (button == 'BindingPrevious') then
                if (state.SelectedIndex == 1) then
                    DecrementCombo('Scope');
                elseif (state.SelectedIndex == 2) then
                    DecrementCombo('Type');
                elseif (state.SelectedIndex == 3) then
                    DecrementCombo('Action');
                end
            end
        end

        if (button == 'BindingTab') then
            state.ForceTab = (state.Tab % 3) + 1;
        end

        if (button == 'BindingConfirm') then
            if (AttemptBind()) then
                state = { IsOpen = { false } };
            end
        end
        if (button == 'BindingCancel') then
            state = { IsOpen = { false } };
        end
    elseif (button == state.RepeatButton) then
        state.RepeatButton = nil;
    end
end

function exposed:Render()
    if (state.RepeatButton ~= nil) and (os.clock() > (state.RepeatTime + state.RepeatDelay)) then
        self:HandleButton(state.RepeatButton, true);
    end

    if (state.IsOpen[1]) then
        local look = theme.Get();
        header = look.SettingsHeaderColor or widgets.HeaderColor;
        activeHeader = look.SettingsTextColor or header;
        window.Full(string.format('%s Binding##tCrossBarBinding', addon.name), state.IsOpen, 0, function()
            widgets.BeginLabels('tcrossbar.binding');
            widgets.PushControlWidth();
            if imgui.BeginTabBar('##TabBar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then

                if imgui.BeginTabItem('Binding##BindingTab', 0, (state.ForceTab == 1) and 6 or 4) then
                    state.Tab = 1;
                    if (state.ForceTab == 1) then
                        state.ForceTab = nil;
                    end
                    widgets.BeginLabels('tcrossbar.binding');
                    Label('Combo Type');
                    imgui.Text(GetMacroStateText(state.MacroState));
                    Label('Macro Button');
                    imgui.Text(buttonText[state.MacroButton]); 
                    widgets.Label('Show Unavailable Actions');
                    local showUnavailable = { gSettings.ShowUnavailableActions == true };
                    if imgui.Checkbox('##ShowUnavailableActions', showUnavailable) then
                        gSettings.ShowUnavailableActions = showUnavailable[1];
                        settings.save();
                        RefreshActionCatalog();
                    end
                    imgui.ShowHelp('Browse named abilities, spells, trusts and weaponskills from all jobs, including unlearned spells and pet commands while no pet is present. Does not bypass use requirements. Items still use your current inventory. Your selected action and custom macro are preserved when toggling this filter.');
                    ComboBox('Scope', 'Scope', state.SelectedIndex == 1 and activeHeader or header);
                    imgui.ShowHelp('Priority: Weapon (Palette), Subjob (Palette), Palette, Job, Global. Weapon bindings belong to the main-hand weapon type within this main job and palette, and switch automatically with equipment. Subjob detection is configured in Configuration > Behavior.');
                    if scopeOrder[state.Indices.Scope] == 4 then
                        local subjob = gBindings:GetSelectedSubjob();
                        imgui.Text('Subjob: ' .. (subjob > 0 and AshitaCore:GetResourceManager():GetString('jobs.names_abbr', subjob) or 'None (select in Configuration)'));
                    end
                    if scopeOrder[state.Indices.Scope] == 5 then
                        imgui.Text('Weapon: ' .. weaponcontext.Label(state.WeaponSkill));
                        imgui.ShowHelp('This edit is saved for the weapon type equipped when the editor opened. Changing equipment will not change the category of an unsaved draft. Reopen the editor to bind another type.');
                    end
                    ComboBox('Action Type', 'Type', state.SelectedIndex == 2 and activeHeader or header);
                    if (#state.Combos.Action > 0) then
                        ComboBox('Action', 'Action', state.SelectedIndex == 3 and activeHeader or header);
                    else
                        Label('Action', state.SelectedIndex == 3 and activeHeader or header);
                        imgui.Text('N/A');
                    end
                    widgets.Gap();
                    imgui.TextColored(header, 'Macro');
                    if (state.MacroText ~= nil) then
                        imgui.InputTextMultiline('##MacroText', state.MacroText, 4096, { 0, 116 });
                    else
                        imgui.Text('N/A');
                    end
                    Label('Label');
                    if (state.MacroLabel ~= nil) then
                        imgui.InputText('##MacroLabel', state.MacroLabel, 32);
                    else
                        imgui.Text('N/A');
                    end
                    imgui.EndTabItem();
                end                

                if imgui.BeginTabItem('Appearance##AppearanceTab', 0, (state.ForceTab == 2) and 6 or 4) then
                    state.Tab = 2;
                    if (state.ForceTab == 2) then
                        state.ForceTab = nil;
                    end
                    local layout = gSingleDisplay.Layout;
                    local width = 32;
                    local height = 32;
                    if layout then
                        width = layout.Icon.Width;
                        height = layout.Icon.Height;
                    end
                    widgets.BeginLabels('tcrossbar.binding.appearance');
                    imgui.TextColored(header, 'Image');
                    imgui.ShowHelp('While the image file and size are correct, rendering here is done with ImGui instead of GdiPlus and may vary slightly in appearance.');
                    local posY = imgui.GetCursorPosY();
                    if (state.Texture ~= nil) then
                        imgui.Image(tonumber(ffi.cast("uint32_t", state.Texture)),
                        { width, height },
                        { 0, 0 }, { 1, 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 });
                    end
                    imgui.SetCursorPos({imgui.GetCursorPosX(), posY + height});
                    if (state.Combos.Type[state.Indices.Type] ~= 'Empty') then
                        imgui.InputText('##MacroImage', state.MacroImage, 256);
                        imgui.SameLine();
                        if (imgui.Button('Preview', { 60, 0 })) then
                            UpdateMacroImage();
                        end
                    end
                    imgui.TextColored(header, 'Components');
                    if (state.Combos.Type[state.Indices.Type] ~= 'Empty') then
                        CheckBox('Cost');
                        imgui.ShowHelp('Display action cost indicators.');
                        CheckBox('Cross');
                        imgui.ShowHelp('Displays a X over actions you don\'t currently know.');
                        CheckBox('Fade');
                        imgui.ShowHelp('Fades the icon for actions where cooldown is not 0 or cost is not met.');
                        CheckBox('Recast');
                        imgui.ShowHelp('Shows action recast timers.');
                        CheckBox('Hotkey');
                        imgui.ShowHelp('Shows hotkey label.');
                        CheckBox('Name');
                        imgui.ShowHelp('Shows action names.');
                        CheckBox('Trigger');
                        imgui.ShowHelp('Shows an overlay when you activate an action.');
                        CheckBox('Ready Pulse', 'ReadyPulse');
                        imgui.ShowHelp('Pulses the icon brightness while the action is off cooldown and usable. Best on long-cooldown abilities like Steal, Mug, Provoke.');
                        CheckBox('SC Icon', 'SkillchainIcon');
                        imgui.ShowHelp('Overrides weaponskill icons when a skillchain would be formed.');
                        CheckBox('SC Animation', 'SkillchainAnimation');
                        imgui.ShowHelp('Animates a border around weaponskill icons when a skillchain would be formed.');
                    else
                        imgui.Text('N/A');
                    end
                    widgets.Gap();
                    Label('Cost Override');
                    imgui.ShowHelp('Entering an item ID, or multiple item IDs seperated by commas, will make cost display as the total amount of those items in your inventory and wardrobes(if equippable) or temporary items(if not).  This can be useful for actions like Call Beast or Reward that use an item, but not always the same item.  Actions like angon and ninjutsu with fixed items are automatically handled without specifying this.');
                    if (state.CostOverride ~= nil) then
                        imgui.InputText('##MacroCostOverride', state.CostOverride, 256);
                    else
                        imgui.Text('N/A');
                    end
                    imgui.EndTabItem();
                end
                
                if imgui.BeginTabItem('Context##ContextTab', 0, (state.ForceTab == 3) and 6 or 4) then
                    state.Tab = 3;
                    if state.ForceTab == 3 then state.ForceTab = nil; end
                    widgets.BeginLabels('tcrossbar.binding.context');
                    local definition = bindingcontext.Definitions[state.SelectedContext];
                    Label('Player Context');
                    if imgui.BeginCombo('##PlayerContext', definition.Label) then
                        for index,option in ipairs(bindingcontext.Definitions) do
                            if imgui.Selectable(option.Label, state.SelectedContext == index) then
                                state.SelectedContext = index;
                            end
                        end
                        imgui.EndCombo();
                    end
                    definition = bindingcontext.Definitions[state.SelectedContext];
                    local editor = state.ContextEditors[definition.Key];
                    widgets.Label('Enable Override');
                    imgui.Checkbox('##ContextEnabled', editor.Enabled);
                    imgui.ShowHelp('Each context has its own toggle and macro. The selected context is only for editing; the player status at the button press selects the macro. Disabling an override keeps its text for later.');
                    imgui.TextColored(header, definition.Label .. ' Macro');
                    imgui.InputTextMultiline('##ContextMacroText' .. definition.Key, editor.MacroText, 4096, { 0, 145 });
                    imgui.TextWrapped('Resting / Healing means kneeling with /heal, not casting healing magic. Idle means status 0, not every non-combat state.');
                    imgui.TextWrapped('Replaces the normal macro, not appended to it. Uses the same commands and /wait support. Icon, label, cost and recast display stay unchanged.');
                    imgui.EndTabItem();
                end
                imgui.EndTabBar();
            end
            widgets.Gap();

            if imgui.Button('Cancel', { 60, 0 }) then
                state.IsOpen[1] = false;
            end
            local bindResource = GetBindResource();
            if (bindResource ~= nil) then
                imgui.SameLine();
                if imgui.Button('Bind', { 60, 0 }) then
                    if (AttemptBind()) then
                        state = { IsOpen = { false } };
                    end
                end
            end
            widgets.PopControlWidth();
        end, { kind = window.Settings });
    end
    if (state.IsOpen[1] == false) then
        self.ForceDisplay = nil;
    else
        self.ForceDisplay = gSingleDisplay;
        self.ForceState = state.MacroState;
    end
end

function exposed:Show(macroState, macroButton)
    local square = gSingleDisplay:GetElementByMacro(macroState, macroButton);
    if square == nil then
        state = { IsOpen = { false } };
        return;
    end

    local hotkey =  string.format('%s:%s', macroComboBinds[macroState], macroButton);
    local binding = square.Binding;
    local weaponSkill = gBindings:GetWeaponSkill();
    if (binding == nil) then
        state = {
            IsOpen = { true },
            SelectedIndex = 1,
            Tab = 1,
            ForceTab = 1,
            MacroState = macroState,
            MacroButton = macroButton,
            Hotkey = hotkey,
            ActionResources = T{},
            Combos = {
                ['Scope'] = T{ 'Global', 'Job', 'Weapon (Palette)', 'Subjob (Palette)', 'Palette' },
                ['Type'] = T{ 'Ability', 'Command', 'Empty', 'Item', 'Spell', 'Trust', 'Weaponskill' },
                ['Action'] = T{ },
            },
            Components = {
                Cost = true,
                Cross = true,
                Fade = true,
                Recast = true,
                Name = true,
                Trigger = true,
                ReadyPulse = false,
                SkillchainIcon = true,
                SkillchainAnimation = true,
                Hotkey = false,
            },
            Indices = {
                ['Scope'] = ScopeIndex(3),
                ['Type'] = 1,
            },
            CostOverride = { '' },
            MacroText = { '' },
            MacroLabel = { '' },
            SelectedContext = 1,
            ContextEditors = ContextEditor(nil),
            WeaponSkill = weaponSkill,
        };
        Setup.Ability();
        return;
    end

    state = {
        IsOpen = { true },
        SelectedIndex = 1,
        MacroState = macroState,
        MacroButton = macroButton,
        Hotkey = hotkey,
        Tab = 1,
        ForceTab = 1,
        ActionResources = T{},
        Combos = {
            ['Scope'] = T{ 'Global', 'Job', 'Weapon (Palette)', 'Subjob (Palette)', 'Palette' },
            ['Type'] = T{ 'Ability', 'Command', 'Empty', 'Item', 'Spell', 'Trust', 'Weaponskill' },
            ['Action'] = T{ },
        },
        Components = {
            Cost = binding.ShowCost,
            Cross = binding.ShowCross,
            Fade = binding.ShowFade,
            Recast = binding.ShowRecast,
            Name = binding.ShowName,
            Trigger = binding.ShowTrigger,
            ReadyPulse = binding.ShowReadyPulse,
            SkillchainIcon = binding.ShowSkillchainIcon,
            SkillchainAnimation = binding.ShowSkillchainAnimation,
            Hotkey = binding.ShowHotkey,
        },
        Indices = {
            ['Scope'] = ScopeIndex(binding.Scope)
        },
        CostOverride = { '' },
        MacroText = { '' },
        MacroLabel = { binding.Label },
        SelectedContext = 1,
        ContextEditors = ContextEditor(binding),
        WeaponSkill = weaponSkill,
        MacroImage = { binding.Image }
    };
    UpdateMacroImage();
    
    for index,entry in ipairs(state.Combos.Type) do
        if (entry == binding.ActionType) then
            state.Indices.Type = index;
            Setup[entry](true);
        end
    end

    if (binding.ActionType == 'Ability') or (binding.ActionType == 'Weaponskill') then
        local res = AshitaCore:GetResourceManager():GetAbilityById(binding.Id);

        if not state.ActionResources:contains(res) then
            state.ActionResources:append(res);
            
            table.sort(state.ActionResources, function(a,b)
                return a.Name[1] < b.Name[1];
            end);

            state.Combos.Action = T{};
            for _,res in ipairs(state.ActionResources) do
                state.Combos.Action:append(encoding:ShiftJIS_To_UTF8(res.Name[1]));
            end
        end
        
        for index,match in ipairs(state.ActionResources) do
            if (match == res) then
                state.Indices.Action = index;
                break;
            end
        end
    elseif (binding.ActionType == 'Spell') or (binding.ActionType == 'Trust') then
        local res = AshitaCore:GetResourceManager():GetSpellById(binding.Id);

        if not state.ActionResources:contains(res) then
            state.ActionResources:append(res);
            
            table.sort(state.ActionResources, function(a,b)
                return a.Name[1] < b.Name[1];
            end);

            state.Combos.Action = T{};
            for _,res in ipairs(state.ActionResources) do
                state.Combos.Action:append(encoding:ShiftJIS_To_UTF8(res.Name[1]));
            end
        end
        
        for index,match in ipairs(state.ActionResources) do
            if (match == res) then
                state.Indices.Action = index;
                break;
            end
        end
    elseif (binding.ActionType == 'Item') then
        local res = AshitaCore:GetResourceManager():GetItemById(binding.Id);

        if not state.ActionResources:contains(res) then
            state.ActionResources:append(res);
            
            table.sort(state.ActionResources, function(a,b)
                return a.Name[1] < b.Name[1];
            end);

            state.Combos.Action = T{};
            for index,res in ipairs(state.ActionResources) do
                local prev = state.ActionResources[index - 1];
                local next = state.ActionResources[index + 1];
        
                local name = encoding:ShiftJIS_To_UTF8(res.Name[1]);
                --Show item id if multiple matching items..
                if (prev) and (prev.Name[1] == name) then
                    state.Combos.Action:append(string.format('%s[%u]', name, res.Id));            
                elseif (next) and (next.Name[1] == name) then
                    state.Combos.Action:append(string.format('%s[%u]', name, res.Id));
                else
                    state.Combos.Action:append(name);
                end
            end
        end
        
        for index,match in ipairs(state.ActionResources) do
            if (match == res) then
                state.Indices.Action = index;
                break;
            end
        end
    end

    if (type(binding.CostOverride) == 'table') then
        local output = '';
        for _,item in ipairs(binding.CostOverride) do
            if (output ~= '') then
                output = output .. ',';
            end
            output = output .. tostring(item);
        end
        state.CostOverride = { output };
    end

    if (type(binding.Macro) == 'table') then
        local output = '';
        for _,line in ipairs(binding.Macro) do
            if (output ~= '') then
                output = output .. '\n';
            end
            output = output .. line;
        end
        state.MacroText = { output };
    end
end

function exposed:UpdatePalette()
    self:Show(state.MacroState, state.MacroButton);
end

return exposed;