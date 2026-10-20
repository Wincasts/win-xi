-- What the parts of mobcast have between them: the app, and the making good of a setting.

-- app is winxi.shell's, which holds the settings (app.options): there once mobcast.lua has made it
local shared = { app = nil }

-- The kinds of thing an enemy does that the box says, in the order the settings list them: what
-- each is called, the setting that switches it, and the setting of its colour
shared.kinds = {
    { key = 'spell', label = 'Spells', single = 'Spell', show = 'showSpells', color = 'spellColor' },
    { key = 'skill', label = 'Weaponskills', single = 'Weaponskill', show = 'showSkills', color = 'skillColor' },
    { key = 'ability', label = 'Abilities', single = 'Ability', show = 'showAbilities', color = 'abilityColor' },
}

-- A setting kept in a table of one, for imgui to change: made good where it is not there, or holds
-- the wrong kind of thing
function shared.Boxed(options, key, kind, default)
    local box = options[key]
    if type(box) ~= 'table' or type(box[1]) ~= kind then
        options[key] = T{ default }
    end
end

-- A colour, four numbers from 0 to 1 as imgui keeps them: made good from the default where it is not
function shared.Colored(options, key, default)
    local color = options[key]
    if type(color) ~= 'table' then
        color = T{ }
        options[key] = color
    end
    for index = 1, 4 do
        local part = tonumber(color[index])
        if part == nil or part < 0 or part > 1 then
            color[index] = default[index]
        end
    end
end

return shared
