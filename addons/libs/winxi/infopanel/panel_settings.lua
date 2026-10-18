-- Settings for the info panel; changes invalidate the sampled slot contents immediately.
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local panel = require('winxi.infopanel.panel')
local buffers = setmetatable({}, { __mode = 'k' }) -- each slot's text being edited, by slot (chatbox has two panels)
return function(p, fields, changed, section, host)
    local function Save() changed() end
    local function Check(label,key)
        widgets.Label(label)
        if imgui.Checkbox('##panel.'..key,p[key]) then Save() end
    end
    local function Slider(label,key,low,high,format)
        widgets.Label(label)
        if imgui.SliderInt('##panel.'..key,p[key],low,high,format or '%d px') then Save() end
    end
    local function Combo(label,id,value,choices)
        widgets.Label(label)
        if imgui.BeginCombo('##panel.'..id,choices[value[1]]) then
            for i,name in ipairs(choices) do
                if imgui.Selectable(name..'##panel.'..id..i,value[1]==i) then value[1]=i; Save() end
            end
            imgui.EndCombo()
        end
    end
    if section == 'general' then
        if widgets.Header('Display Mode',true) then
            Check('Enable Info Panel','enabled')
            imgui.TextDisabled(host == 'chatbox' and 'Off hides the info panel; chat and input remain unchanged.'
                or 'Off uses your saved legacy single-line clock.')
        end
        return
    end
    if not p.enabled[1] then
        if section == 'layout' then imgui.TextDisabled('Enable Info Panel in General to adjust panel layout.') end
        return
    end
    if section == 'layout' then
        if widgets.Header('Size',true) then
            Slider('Width (0 = Chat Width)','width',0,4096)
            Slider('Height (0 = Input Height)','height',0,512)
            Slider('Padding','padding',1,32)
        end
        if widgets.Header('Position',true) then
            Check(host == 'chatbox' and 'Attach To Chat' or 'Attach Above Chat','attached')
            if p.attached[1] then
                Slider('Horizontal Offset','offsetX',-2048,2048)
                Slider('Vertical Offset','offsetY',-2048,2048)
            else
                Slider('Position X','x',-4096,8192)
                Slider('Position Y','y',-4096,8192)
            end
            imgui.TextDisabled('Position X/Y is the top-left corner. Attached offsets move with chat.')
            imgui.TextDisabled(host == 'chatbox' and 'Visibility follows the compact chat log, not the native clock.'
                or 'Custom placement still follows native clock visibility and menu layering.')
        end
    end
    if section == 'layout' and widgets.Header('Separators',true) then
        Check('Slot Separators','separators')
        Combo('Separator Style','separatorStyle',p.separatorStyle,{'Fine','Beveled','Ornament'})
        Slider('Separator Inset','separatorInset',0,64)
        imgui.TextDisabled('Pipes ( | ) inside a slot use this style too. Colours follow the Winxi border.')
    end
    if section == 'icons' and widgets.Header('Icon Placement',true) then
        imgui.TextDisabled('Icons use Icon Set; missing pictures fall back to the bundled gems set.')
        for _,kind in ipairs({'day','weather'}) do
            local label = kind=='day' and 'Day' or 'Weather'
            Combo(label..' Icon Slot',kind..'Place',p[kind..'Place'],panel.IconPlaces)
            Check(label..' Icon After Data',kind..'After')
            Slider(label..' Icon X',kind..'X',-128,128)
            Slider(label..' Icon Y',kind..'Y',-128,128)
        end
        imgui.TextDisabled('For exact order, add {dayicon} or {weathericon} directly to a slot format.')
        imgui.TextDisabled('A token overrides automatic placement; Native keeps the game icon outside the panel.')
    end
    if section ~= 'data' then return end
    if fields.Uses(panel.Format(p),'exp') and widgets.Header('Experience Tracking',true) then
        widgets.Label('EXP Per Hour')
        if imgui.SmallButton('Begin Again##panel.expReset') then require('winxi.infopanel.exp').Reset(); Save() end
    end
    for i,name in ipairs(panel.Names) do
        if widgets.Header(name..' Data Slot') then
            local s = p.slots[i]
            buffers[s] = buffers[s] or {s.format}
            local buffer = buffers[s]
            if not imgui.IsAnyItemActive() then buffer[1]=s.format end
            widgets.Label('Data Format')
            imgui.SetNextItemWidth(360)
            if imgui.InputText('##panel.format'..i,buffer,1024) then s.format=buffer[1]; Save() end
            Combo('Alignment','align'..i,s.align,panel.Alignments)
            widgets.Label('Relative Width')
            if imgui.SliderFloat('##panel.weight'..i,s.weight,0.1,10,'%.1f') then Save() end
            widgets.Label('Add Data')
            if imgui.BeginCombo('##panel.field'..i,'Choose A Field') then
                for _,field in ipairs(fields.All) do
                    if imgui.Selectable(field.label..'##panel.field'..i..field.token,false) then
                        s.format=s.format..(s.format~='' and '  ' or '')..'{'..field.token..'}'
                        buffer[1]=s.format; Save()
                    end
                    if imgui.IsItemHovered() then imgui.SetTooltip(field.tip) end
                end
                imgui.EndCombo()
            end
            widgets.Label('Add Separator')
            if imgui.SmallButton('|##panel.divider'..i) then
                s.format=s.format..' | '; buffer[1]=s.format; Save()
            end
        end
    end
end
