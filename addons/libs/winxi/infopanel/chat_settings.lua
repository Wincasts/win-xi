-- Chatbox's Info Panel tab. Layout/data/icon placement controls are shared with clock. Its own settings are
-- described rows (winxi 65); their specs, choices and sentences are made once, here.
local imgui=require('imgui')
local widgets=require('winxi.widgets')
local controls=require('winxi.infopanel.panel_settings')
local fields=require('winxi.infopanel.fields')
local M={}
local anchorChoices -- { key = its index, label }, from chat.Anchors, made once
local function AnchorChoices()
    if anchorChoices==nil then
        anchorChoices={}
        for i,name in ipairs(require('winxi.infopanel.chat').Anchors) do anchorChoices[i]={key=i,label=name} end
    end
    return anchorChoices
end
local iconChoices -- Default (Gems), then the sets found in their folders; looked for afresh as the list opens
local function IconSets()
    local list={{key='',label='Default (Gems)'}}
    for _,set in ipairs(require('winxi.infopanel.icons').Sets()) do list[#list+1]={key=set.key,label=set.label} end
    iconChoices=list
    return list
end
local anchorSpec,window2Spec={},{}
local fontSpec={theme='Chat Font',description='The panel\'s font. Chat Font is the chat\'s, and the rest come from Windows.'}
local fontSizeSpec={max=48,theme='Chat Size',description='How large the panel\'s text is. Chat Size is the chat\'s.'}
local iconSetSpec={onOpen=IconSets}
local scaleSpec={float=true,format='%.2fx'}
local lineRows={} -- a timetable line's key -> its row's name and id
local lineSentence='Its next departures show in the tooltip on the zone name.'
local function LineRow(line)
    local row=lineRows[line.key]
    if row==nil then
        row={name=('%s To %s'):format(line.from,line.to),id='##chatbox.panel.timetable.'..line.key}
        lineRows[line.key]=row
    end
    return row
end
function M.Draw(options,service,save)
    local function Changed() service.Invalidate(); save() end
    if not imgui.BeginTabBar('chatbox.infopanel.tabs',ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then return end
    local function Tab(label,draw)
        if imgui.BeginTabItem(label..'##chatbox.infopanel') then
            if widgets.BeginLabels then widgets.BeginLabels('chatbox.infopanel.'..label) end
            draw(); widgets.EndSub(); imgui.EndTabItem()
        end
    end
    Tab('General',function()
        controls(options.layout,fields,Changed,'general','chatbox')
        if widgets.Header('Anchor And Game Clock') then
            anchorSpec.parent=options.layout.enabled
            local chosen=widgets.Dropdown('Anchor','Top puts the panel on the upper chat window, Bottom under the chat windows, which rise above it. It applies while Attach To Chat is on.',AnchorChoices(),options.anchor[1],'##chatbox.panel.anchor',anchorSpec)
            if chosen~=nil then options.anchor[1]=chosen; Changed() end
            if widgets.Check('Hide Game Clock','Hides the game default clock, its day and weather icons with it, panel or no panel. Unload the clock addon and hidecompass, which hide the same thing.',options.hideClock,'##chatbox.panel.hideClock') then Changed() end
            if widgets.Check('Hide Compass','Hides the game default compass and radar. The clock is left alone.',options.hideCompass,'##chatbox.panel.hideCompass') then Changed() end
        end
        widgets.Status(service.Status())
    end)
    Tab('Layout',function() controls(options.layout,fields,Changed,'layout','chatbox') end)
    Tab('Data',function() controls(options.layout,fields,Changed,'data','chatbox') end)
    Tab('Window 2',function()
        local p=options.window2
        if widgets.Header('Window 2 Panel',true) then
            window2Spec.parent=options.layout.enabled
            if widgets.Check('Window 2 Panel','A second panel under Window 2 while the game shows two log windows side by side. Its text and icons follow the first panel.',p.enabled,'##chatbox.panel.window2',window2Spec) then Changed() end
        end
        if not options.layout.enabled[1] or not p.enabled[1] then return end
        controls(p,fields,Changed,'layout','chatbox')
        controls(p,fields,Changed,'data','chatbox')
        controls(p,fields,Changed,'icons','chatbox')
    end)
    Tab('Text',function()
        if widgets.Header('Text',true) then
            if widgets.FontFile(options,'fontFile','##chatbox.panel.font',fontSpec) then Changed() end
            if widgets.FontSize(options,'fontSize','##chatbox.panel.fontSize',fontSizeSpec) then Changed() end
            if widgets.Color('Text Color','The panel\'s text. Its dark edge is the Winxi Theme\'s Text Outline.',options.textColor,'##chatbox.panel.textColor') then Changed() end
        end
    end)
    Tab('Timetable',function()
        local schedule=require('winxi.infopanel.schedule')
        local lines=schedule.Lines()
        if widgets.Header('Ships And Airships',true) then
            if not lines then widgets.Note('The timetable\'s tables are missing: update Winxi.'); return end
            local group,open=nil,false
            for index,line in ipairs(lines) do
                if line.group~=group then group=line.group; open=widgets.SubHeader(group,index==1) end
                if open then
                    local value=options.timetable[line.key]
                    if not value then value={true}; options.timetable[line.key]=value end
                    local row=LineRow(line)
                    if widgets.Check(row.name,lineSentence,value,row.id) then Changed() end
                end
            end
            widgets.EndSub()
            widgets.Gap()
            if widgets.Action('Every Line','Ticks every line.','All##chatbox.panel.timetable') then for _,line in ipairs(lines) do options.timetable[line.key][1]=true end; Changed() end
            if widgets.Action('No Lines','Unticks every line.','None##chatbox.panel.timetable') then for _,line in ipairs(lines) do options.timetable[line.key][1]=false end; Changed() end
        end
    end)
    Tab('Icons',function()
        if widgets.Header('Icon Appearance',true) then
            local chosen=widgets.Dropdown('Icon Set','Gems cuts the days as gemstones and draws the weather bold. Classic draws them as the game default does.',iconChoices or IconSets(),options.iconSet,'##chatbox.panel.iconSet',iconSetSpec)
            if chosen~=nil then options.iconSet=chosen; require('winxi.infopanel.icons').Forget(); Changed() end
            if widgets.Slider('Icon Scale','How big the day and weather icons are, against the text.',options.iconScale,0.5,3,'##chatbox.panel.iconScale',scaleSpec) then Changed() end
            if widgets.Slider('Icon Offset','Moves the icons up or down on their row.',options.iconOffset,-10,10,'##chatbox.panel.iconOffset',widgets.Pixels) then Changed() end
            if widgets.Slider('Weather Scale','How big the weather icon is, on top of Icon Scale.',options.weatherScale,0.5,3,'##chatbox.panel.weatherScale',scaleSpec) then Changed() end
        end
        controls(options.layout,fields,Changed,'icons','chatbox')
    end)
    imgui.EndTabBar()
end
return M
