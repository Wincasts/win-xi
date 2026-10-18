-- Chatbox's Info Panel tab. Layout/data/icon placement controls are shared with clock.
local imgui=require('imgui')
local widgets=require('winxi.widgets')
local controls=require('winxi.infopanel.panel_settings')
local fields=require('winxi.infopanel.fields')
local fonts=require('winxi.fonts')
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
        if imgui.Checkbox('Anchor Above Chat##chatbox.panel.menus',options.anchorMenus) then Changed() end
        Tip('Moves the native action-menu family using its own layout, including cursor/hit regions. Requires updated uihook; unsupported menus remain native.')
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
            imgui.TextDisabled('Drawn on top of or under the compact chatbox (Layout, Anchor); hidden with chat or expanded history.')
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
            widgets.Label('Font')
            if imgui.BeginCombo('##chatbox.panel.font',options.fontFile~='' and options.fontFile or 'Chat Font') then
                if imgui.Selectable('Chat Font##chatbox.panel.font',options.fontFile=='') then options.fontFile=''; Changed() end
                for _,file in ipairs(fonts.Files()) do
                    if imgui.Selectable(file..'##chatbox.panel.font',file==options.fontFile) then options.fontFile=file; Changed() end
                end
                imgui.EndCombo()
            end
            widgets.Label('Font Size')
            if imgui.SliderInt('##chatbox.panel.fontSize',options.fontSize,0,48,options.fontSize[1]==0 and 'Chat Size' or '%d px') then Changed() end
            widgets.Label('Text Color')
            if imgui.ColorEdit4('##chatbox.panel.textColor',options.textColor,ImGuiColorEditFlags_NoInputs) then Changed() end
            widgets.Label('Outline')
            if imgui.SliderInt('##chatbox.panel.outline',options.outline,0,3,'%d px') then Changed() end
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
            Tip('Icon sets live in addons\\libs\\winxi\\infopanel\\icons. Missing pictures use bundled gems.')
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
