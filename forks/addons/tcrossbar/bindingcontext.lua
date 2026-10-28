-- One registry for context detection, editor options and persistence. These statuses
-- are mutually exclusive; unknown states and missing player data use the normal macro.
local context = {};
context.Definitions = {
    { Key = 'Engaged', Label = 'Engaged', Status = 1 },
    { Key = 'Idle', Label = 'Idle', Status = 0 },
    { Key = 'Resting', Label = 'Resting / Healing', Status = 33 },
};

function context.Capture()
    local memory = AshitaCore:GetMemoryManager();
    local index = memory:GetParty():GetMemberTargetIndex(0);
    local status;
    if index ~= nil and index > 0 then status = memory:GetEntity():GetStatus(index); end
    local current = {};
    for _,definition in ipairs(context.Definitions) do
        current[definition.Key] = status ~= nil and status == definition.Status;
    end
    return current;
end

function context.ResolveMacro(binding, current)
    if not binding then return {}; end
    for _,definition in ipairs(context.Definitions) do
        local override = binding.Overrides and binding.Overrides[definition.Key];
        if current and current[definition.Key] and override and override.Enabled == true
            and type(override.Macro) == 'table' and #override.Macro > 0 then
            return override.Macro;
        end
    end
    return binding.Macro or {};
end

return context;
