-- Chatbox's Info Panel tab. Layout/data/icon placement controls are shared with clock.
local imgui=require('imgui')
local widgets=require('winxi.widgets')
local controls=require('winxi.infopanel.panel_settings')
local fields=require('winxi.infopanel.fields')
local M={}
function M.Draw(options,service,save)
    local function Changed() service.Invalidate(); save() end
    local function Tip(text) if imgui.IsItemHovered() then imgui.SetTooltip(text) end end
    if not imgui.BeginTabBar('chatbox.infopanel.tabs',ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then return end
    local function Tab(label,draw)
        if imgui.BeginTabItem(label..'##chatbox.infopanel') then
            if widgets.BeginLabels then widgets.BeginLabels('chatbox.infopanel.'..label) end
            draw(); imgui.EndTabItem()
        end
    end
    Tab('General',function()
        controls(options.layout,fields,Changed,'general','chatbox')
        widgets.Label('Native Menus')
        if imgui.Checkbox('Anchor Above Info Panel##chatbox.panel.menus',options.anchorMenus) then Changed() end
        Tip('Anchors native combat/action menus and their supported submenus directly above the visible info panel, not above the chat frame. Uses the game\'s layout, including cursor/hit regions. Requires updated uihook; unsupported menus remain native.')
        widgets.Label('Hide Game Clock')
        if imgui.Checkbox('##chatbox.panel.hideClock',options.hideClock) then Changed() end
        Tip('Hides the game\'s clock, its day and weather icons with it, while chatbox runs; works with the panel on or off. Needs uihook; unload the clock addon and hidecompass, which use the same object.')
        widgets.Label('Hide Compass')
        if imgui.Checkbox('##chatbox.panel.hideCompass',options.hideCompass) then Changed() end
        Tip('Hides the game\'s compass and radar while chatbox runs; the clock is not affected. Needs uihook; unload the clock addon and hidecompass, which use the same object.')
        widgets.Label('Window 2 Panel')
        if imgui.Checkbox('##chatbox.panel.window2',options.window2.enabled) then Changed() end
        Tip('A second panel under Window 2 while the game shows the two log windows side by side. Its slots and layout are in the Window 2 tab; text and icons follow this panel.')
        if widgets.Header('About',true) then
            imgui.TextDisabled('Drawn above or below compact chat (Layout, Anchor); stays when both logs collapse, hides during expanded history.')
            imgui.TextDisabled('Unload the clock addon to avoid displaying two panels.')
            imgui.TextDisabled('Native action-menu anchoring requires the updated uihook DLL; /uihook menus reports readiness.')
            imgui.TextDisabled(service.Status())
        end
    end)
    Tab('Layout',function()
        if options.layout.enabled[1] and widgets.Header('Anchor',true) then
            widgets.Label('Anchor')
            if imgui.BeginCombo('##chatbox.panel.anchor',require('winxi.infopanel.chat').Anchors[options.anchor[1]]) then
                for i,name in ipairs(require('winxi.infopanel.chat').Anchors) do
                    if imgui.Selectable(name..'##chatbox.panel.anchor'..i,options.anchor[1]==i) then options.anchor[1]=i; Changed() end
                end
                imgui.EndCombo()
            end
            Tip('Top: on the upper chat window; chat and input stay where the game puts them.\nBottom: under the chat windows, which are lifted above it; the open input sits on it.\nApplies while Attach To Chat is on, to both panels.')
        end
        controls(options.layout,fields,Changed,'layout','chatbox')
    end)
    Tab('Data',function() controls(options.layout,fields,Changed,'data','chatbox') end)
    Tab('Window 2',function()
        local p=options.window2
        if not options.layout.enabled[1] or not p.enabled[1] then
            imgui.TextDisabled('Enable Info Panel and Window 2 Panel in General to set up the second panel.')
            return
        end
        imgui.TextDisabled('Shown on Window 2, by Anchor, while the two log windows sit side by side.')
        controls(p,fields,Changed,'layout','chatbox')
        controls(p,fields,Changed,'data','chatbox')
        controls(p,fields,Changed,'icons','chatbox')
    end)
    Tab('Text',function()
        if widgets.Header('Text',true) then
            if widgets.FontFile(options,'fontFile','##chatbox.panel.font',{theme='Chat Font',tooltip='The panel\'s font: the chat\'s, or one of C:\\Windows\\Fonts.'}) then Changed() end
            if widgets.FontSize(options,'fontSize','##chatbox.panel.fontSize',{max=48,theme='Chat Size',tooltip='How large the panel\'s text is, in pixels; Chat Size (0) is the chat\'s.'}) then Changed() end
            widgets.Label('Text Color')
            if imgui.ColorEdit4('##chatbox.panel.textColor',options.textColor,ImGuiColorEditFlags_NoInputs) then Changed() end
            imgui.TextDisabled('The dark edge round the text is Winxi Theme\'s Text Outline, in winxisettings.')
        end
    end)
    Tab('Timetable',function()
        local schedule=require('winxi.infopanel.schedule')
        local lines=schedule.Lines()
        if widgets.Header('Ships And Airships',true) then
            imgui.TextDisabled(('Resting the mouse on the {zone} words shows the next %d ships and airships to leave, of the lines ticked here.'):format(schedule.Count))
            if not lines then imgui.TextDisabled('The timetable\'s tables are missing: update Winxi.'); return end
            local group
            for _,line in ipairs(lines) do
                if line.group~=group then group=line.group; imgui.TextDisabled(group) end
                local value=options.timetable[line.key]
                if not value then value={true}; options.timetable[line.key]=value end
                widgets.Label(('%s To %s'):format(line.from,line.to))
                if imgui.Checkbox('##chatbox.panel.timetable.'..line.key,value) then Changed() end
            end
            if imgui.Button('All##chatbox.panel.timetable') then for _,line in ipairs(lines) do options.timetable[line.key][1]=true end; Changed() end
            imgui.SameLine()
            if imgui.Button('None##chatbox.panel.timetable') then for _,line in ipairs(lines) do options.timetable[line.key][1]=false end; Changed() end
        end
    end)
    Tab('Icons',function()
        if widgets.Header('Icon Appearance',true) then
            local icons=require('winxi.infopanel.icons')
            widgets.Label('Icon Set')
            if imgui.BeginCombo('##chatbox.panel.iconSet',options.iconSet~='' and options.iconSet or 'Default (Gems)') then
                if imgui.Selectable('Default (Gems)##chatbox.panel.iconSet',options.iconSet=='') then options.iconSet=''; icons.Forget(); Changed() end
                for _,set in ipairs(icons.Sets()) do
                    if imgui.Selectable(set.label..'##chatbox.panel.iconSet',options.iconSet==set.key) then options.iconSet=set.key; icons.Forget(); Changed() end
                end
                imgui.EndCombo()
            end
            Tip('Gems: the days cut as gemstones, the weather drawn bold. Classic: drawn after the game\'s own, its mottled day\nballs and soft weather sprites. Sets live in addons\\libs\\winxi\\infopanel\\icons; a picture a set lacks is the Gems one.')
            widgets.Label('Icon Scale')
            if imgui.SliderFloat('##chatbox.panel.iconScale',options.iconScale,0.5,3,'%.2fx') then Changed() end
            widgets.Label('Icon Offset')
            if imgui.SliderInt('##chatbox.panel.iconOffset',options.iconOffset,-10,10,'%d px') then Changed() end
            widgets.Label('Weather Scale')
            if imgui.SliderFloat('##chatbox.panel.weatherScale',options.weatherScale,0.5,3,'%.2fx') then Changed() end
        end
        controls(options.layout,fields,Changed,'icons','chatbox')
        imgui.TextDisabled('Native does not add an icon to the panel; native HUD visibility is left unchanged.')
    end)
    imgui.EndTabBar()
end
return M
