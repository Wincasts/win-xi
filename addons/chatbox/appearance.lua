-- Per-window colours of the WinXI Skin, kept separate from WinXI's shared/local theme: each window's Override
-- Colours switch and, with it on, its colours in place of the theme's. Off, the colours chosen are kept.
local M = {}
local fields = {
    {key='background',label='Background',theme='BackgroundColor',fallback={0.05,0.05,0.12,0.85}},
    {key='border',label='Border / Art Tint',theme='BorderColor',fallback={1,1,1,1}},
    {key='textColor',label='Default Text',theme='TextColor',fallback={1,1,1,1}},
    {key='titleColor',label='Title',theme='TitleColor',fallback={1,1,1,1}},
}
function M.Defaults(T, theme)
    local result = T{}
    for _, name in ipairs({'log','input'}) do
        local section = T{override=T{false},colors=T{}}
        for _, field in ipairs(fields) do
            local color = theme[field.theme] or field.fallback
            section.colors[field.key] = T{color[1],color[2],color[3],color[4]}
        end
        result[name] = section
    end
    return result
end
-- Settings from before Override Colours had an Own Color box for each colour: any of them on is the switch on.
function M.Repair(value, T, theme)
    local defaults = M.Defaults(T, theme)
    if type(value) ~= 'table' then return defaults end
    for _, name in ipairs({'log','input'}) do
        if type(value[name]) ~= 'table' then value[name] = defaults[name] end
        local section = value[name]
        if type(section.colors) ~= 'table' then section.colors = T{} end
        if type(section.override) ~= 'table' or type(section.override[1]) ~= 'boolean' then
            local any = false
            if type(section.own) == 'table' then
                for _, own in pairs(section.own) do
                    if type(own) == 'table' and own[1] == true then any = true end
                end
            end
            section.override = T{ any }
        end
        section.own = nil
        for _, field in ipairs(fields) do
            local key = field.key
            if type(section.colors[key]) ~= 'table' then section.colors[key] = T{} end
            for i=1,4 do
                local n = tonumber(section.colors[key][i])
                if not n or n ~= n or math.abs(n) == math.huge then n = defaults[name].colors[key][i] end
                section.colors[key][i] = math.max(0,math.min(1,n))
            end
        end
    end
    return value
end
function M.Apply(target, section)
    local on = section.override[1]
    for _, field in ipairs(fields) do
        target[field.key] = on and section.colors[field.key] or nil
    end
    return target
end
function M.Draw(options, save)
    local imgui = require('imgui')
    local widgets = require('winxi.widgets')
    local Tip = require('winxi.tooltip').Hover
    for _, entry in ipairs({{'log','Chat Log Window'},{'input','Input Text Box'}}) do
        local name, label = entry[1], entry[2]
        if widgets.Header(label, name == 'log') then
            local section = options[name]
            local id = '##chatbox.appearance.' .. name
            widgets.Label('Override Colours')
            if imgui.Checkbox(id .. '.override', section.override) then save() end
            Tip('Draws this window in the colours below in place of the WinXI theme\'s. Off, the theme\'s; the colours chosen are kept for another time.')
            if section.override[1] then
                for _, field in ipairs(fields) do
                    if name == 'log' or field.key ~= 'titleColor' then
                        widgets.Label(field.label)
                        imgui.ColorEdit4(id .. '.' .. field.key, section.colors[field.key], ImGuiColorEditFlags_NoInputs)
                        if imgui.IsItemDeactivatedAfterEdit() then save() end
                    end
                end
            end
        end
    end
    imgui.TextDisabled('Alpha controls background/border opacity. Border art is tinted, not replaced.')
    imgui.TextDisabled('Preserved inline colours take precedence over Default Text.')
end
return M
