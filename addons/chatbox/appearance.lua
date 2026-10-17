-- Per-window colours, kept separate from WinXI's shared/local theme.
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
        local section = T{own=T{},colors=T{}}
        for _, field in ipairs(fields) do
            local color = theme[field.theme] or field.fallback
            section.own[field.key] = T{false}
            section.colors[field.key] = T{color[1],color[2],color[3],color[4]}
        end
        result[name] = section
    end
    return result
end
function M.Repair(value, T, theme)
    local defaults = M.Defaults(T, theme)
    if type(value) ~= 'table' then return defaults end
    for _, name in ipairs({'log','input'}) do
        if type(value[name]) ~= 'table' then value[name] = defaults[name] end
        local section = value[name]
        if type(section.own) ~= 'table' then section.own = T{} end
        if type(section.colors) ~= 'table' then section.colors = T{} end
        for _, field in ipairs(fields) do
            local key = field.key
            if type(section.own[key]) ~= 'table' or type(section.own[key][1]) ~= 'boolean' then section.own[key] = T{false} end
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
    for _, field in ipairs(fields) do
        target[field.key] = section.own[field.key][1] and section.colors[field.key] or nil
    end
    return target
end
function M.Draw(options, save)
    local imgui = require('imgui')
    local widgets = require('winxi.widgets')
    for _, entry in ipairs({{'log','Chat Log Window'},{'input','Input Text Box'}}) do
        local name, label = entry[1], entry[2]
        if widgets.Header(label, true) then
            local section = options[name]
            for _, field in ipairs(fields) do
                if name == 'log' or field.key ~= 'titleColor' then
                    local id = '##chatbox.appearance.' .. name .. '.' .. field.key
                    widgets.Label(field.label)
                    if imgui.Checkbox('Own Color' .. id, section.own[field.key]) then save() end
                    if section.own[field.key][1] then
                        imgui.SameLine()
                        imgui.ColorEdit4(id, section.colors[field.key], ImGuiColorEditFlags_NoInputs)
                        if imgui.IsItemDeactivatedAfterEdit() then save() end
                    end
                end
            end
            if imgui.Button('Follow WinXI Theme##chatbox.appearance.' .. name .. '.reset') then
                for _, own in pairs(section.own) do own[1] = false end
                save()
            end
        end
    end
    imgui.TextDisabled('Unchecked colours follow WinXI. Alpha controls background/border opacity.')
    imgui.TextDisabled('Border art is tinted, not replaced. Preserved inline colours take precedence over Default Text.')
end
return M
