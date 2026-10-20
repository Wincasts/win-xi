-- Optional chatbox info-panel attachment. Draw on the host's list before its border/title;
-- publish its menu anchor only after successful native capture. Claims the clock and compass slots only to hide them.
local panel = require('winxi.infopanel.panel')
local fields = require('winxi.infopanel.fields')
local sourceModel = require('winxi.infopanel.source')
local M = {}
-- Window 2's own panel, under the second log while the two sit side by side: its own slots and
-- layout, the first's text and icon look. Off to start; no day or weather icon of its own.
function M.Window2Defaults()
    local p=panel.Defaults()
    p.enabled[1]=false
    p.dayPlace[1],p.weatherPlace[1]=1,1
    p.slots[1].format,p.slots[2].format,p.slots[3].format='{weather}','{level}  {exp}','{rate}'
    return p
end
M.Anchors={'Top','Bottom'} -- where attached panels sit: on the upper log, or under the logs (and the open input)
function M.Defaults()
    local p=panel.Defaults()
    p.enabled[1]=false -- opt in; installing an update never adds a duplicate clock panel
    p.slots[1].format='{time} | {zone}'
    return {layout=p,window2=M.Window2Defaults(),anchor={2},anchorMenus={true},hideClock={false},hideCompass={false},fontFile='',fontSize={0},textColor={1,1,1,1},
        iconSet='gems',iconScale={1},iconOffset={0},weatherScale={1}}
end
local function Number(value,low,high,fallback)
    value=tonumber(value)
    if not value or value~=value or math.abs(value)==math.huge then value=fallback end
    return math.max(low,math.min(high,value))
end
function M.Complete(options)
    local defaults=M.Defaults()
    if type(options)~='table' then options=defaults end
    if type(options.layout)~='table' then options.layout=defaults.layout end
    if options.layout.enabled == nil then options.layout.enabled={false} end
    panel.Complete(options.layout)
    if type(options.window2)~='table' then options.window2=M.Window2Defaults() end
    if options.window2.enabled == nil then options.window2.enabled={false} end
    panel.Complete(options.window2)
    for _,key in ipairs({'hideClock','hideCompass'}) do
        if type(options[key])~='table' then options[key]={false} end
        options[key][1]=options[key][1]==true
    end
    if type(options.anchor)~='table' then options.anchor={2} end
    options.anchor[1]=options.anchor[1]==1 and 1 or 2
    if type(options.anchorMenus)~='table' then options.anchorMenus={true} end
    options.anchorMenus[1]=options.anchorMenus[1]~=false
    if type(options.fontFile)~='string' then options.fontFile='' end
    if type(options.iconSet)~='string' then options.iconSet='gems' end
    for key,range in pairs({fontSize={0,48},iconScale={0.5,3},iconOffset={-10,10},weatherScale={0.5,3}}) do
        if type(options[key])~='table' then options[key]=defaults[key] end
        options[key][1]=Number(options[key][1],range[1],range[2],defaults[key][1])
    end
    options.fontSize[1]=math.floor(options.fontSize[1])
    options.outline=nil -- the text's edge is the theme's Text Outline now
    if type(options.textColor)~='table' then options.textColor=defaults.textColor end
    for i=1,4 do options.textColor[i]=Number(options.textColor[i],0,1,1) end
    return options
end
-- Anchored to the bottom, the lowest log owns the attachment: the primary (under a stacked split, or
-- beside one). To the top, the upper: a split stacked over the primary; side by side, the primary.
-- The split alone while the primary is hidden (passed as nil, as a split at zero lines is).
function M.Host(primary,split,top)
    if not primary then return split,1 end
    if top and split and split.bottom<=primary.top+2 and split.left<primary.left+primary.width
        and split.left+split.width>primary.left then return split,1 end
    return primary,0
end
-- Two logs side by side (not one stacked over the other): where Window 2 can have its own panel.
function M.Beside(primary,split)
    return primary~=nil and split~=nil and not (split.bottom<=primary.top+2
        and split.left<primary.left+primary.width and split.left+split.width>primary.left)
end
-- The layouts drawn this frame: the first's on its host, Window 2's on the second log beside it.
function M.Layouts(options,primary,split)
    if not options.layout.enabled[1] then return {} end
    local host,slot=M.Host(primary,split,options.anchor[1]==1)
    if not host then return {} end
    local list={{p=options.layout,host=host,slot=slot}}
    if options.window2.enabled[1] and M.Beside(primary,split) then list[2]={p=options.window2,host=split,slot=1} end
    return list
end
local function Formats(options)
    local format=panel.Format(options.layout)
    if options.window2.enabled[1] then format=format..'  '..panel.Format(options.window2) end
    return format
end
function M.Bounds(p,host,inputHeight,fontSize,contentHeight,top)
    local width=p.width[1]>0 and math.max(32,p.width[1]) or host.width
    local height=p.height[1]>0 and math.max(8,p.height[1]) or math.max(inputHeight or 0,contentHeight+2*p.padding[1])
    local x,y=p.x[1],p.y[1]
    if p.attached[1] then
        -- Top: flush over the host, its border/title drawn after so the title stays legible at the seam.
        -- Bottom: where the host's bottom was; chat is lifted by the panel's height to sit wholly above it.
        x=host.left+p.offsetX[1]
        y=(top and host.top or host.bottom)-height+p.offsetY[1]
    end
    return {left=x,top=y,width=width,height=height}
end
function M.New(deps)
    deps=deps or {}
    local source=deps.source or sourceModel.New(deps)
    local samples,nextSample=nil,0
    local menus,menuReason=deps.menus,nil
    local service={}
    local hoveredText,hoveredSlot,drawingSlot
    local captures={}
    local hoveredOptions
    local function Tooltip(text) hoveredText,hoveredSlot=text,drawingSlot end
    function service.Invalidate() samples,nextSample,menuReason=nil,0,nil end
    function service.BeginFrame()
        hoveredText,hoveredSlot=nil,nil
        captures[0],captures[1]=false,false
        if menus then menus.Stop() end
    end
    -- Shown after the native captures, never inside a captured log/panel draw list: words as they are, a
    -- calendar ({ calendar = month }) drawn by winxi.infopanel.calendar, the day pictures of the Icon Set
    -- across its top and the theme's tooltip colours for today and the days gone.
    local calendarStyle={}
    function service.Tooltip()
        if not hoveredText or not captures[hoveredSlot] then return end
        local tooltip=require('winxi.tooltip')
        if type(hoveredText)~='table' then tooltip.Show(hoveredText); return end
        if not hoveredText.calendar or not tooltip.Begin() then return end
        local imgui=require('imgui')
        local calendar=deps.calendar or require('winxi.infopanel.calendar')
        local icons=deps.icons or require('winxi.infopanel.icons')
        local theme=require('winxi.theme')
        local shared=theme.Shared and theme.Shared() or {}
        local set=hoveredOptions and hoveredOptions.iconSet or 'gems'
        local text=shared.TooltipTextColor or {1,1,1,1}
        calendarStyle.icon=function(weekday) return icons.Day(set,weekday) or icons.Day('gems',weekday) end
        calendarStyle.dim={text[1],text[2],text[3],(text[4] or 1)*0.55}
        calendarStyle.highlight=shared.TooltipBorderColor
        local ok,err=pcall(calendar.Draw,imgui,hoveredText.calendar,calendarStyle)
        tooltip.End()
        if not ok then error(err,0) end
    end
    function service.Reset() service.BeginFrame(); service.Invalidate(); source.Reset() end
    -- Hide Game Clock and Hide Compass: an empty replacement in uihook's clock or compass slot, renewed
    -- each frame. The clock's takes its text, and HideIcons its day and weather icons with it; the game
    -- still runs both, so the grid and weather stay readable. nil options (or off) gives each back at once.
    local hud={clock={key='hideClock',slot='Clock'},compass={key='hideCompass',slot='Compass'}}
    function service.Hud(options)
        for name,h in pairs(hud) do
            if not options or not options[h.key][1] then
                if h.hook then h.hook.Stop() end
            else
                if not h.hook then
                    local ok,module=pcall(require,'winxi.nativehud')
                    if ok then
                        h.hook=deps[name] or module.new(module[h.slot])
                        h.mask=name=='clock' and (module.HideDay or 1)+(module.HideWeather or 2) or nil
                    end
                end
                if not h.hook then h.reason='Update Winxi to hide the game\'s '..name..'.'
                elseif h.hook.Begin() then
                    if h.mask then h.hook.HideIcons(h.mask) end
                    -- not nativehud's Status: an empty replacement is never stamped as drawn, so it would read as failed
                    h.reason=name=='clock' and 'hidden: its text and icons, through uihook\'s clock slot.'
                        or 'hidden, with its radar, through uihook\'s compass slot.'
                else h.reason=h.hook.Status() end
            end
        end
    end
    function service.HudStatus(options,name)
        local h=hud[name]
        if not options[h.key][1] then return 'shown.' end
        return h.reason or 'waiting for uihook.'
    end
    function service.Status() return source.Status() or menuReason or 'Panel follows compact chat, independently of native clock visibility.' end
    function service.Captured(attachment,slot,captured)
        captures[slot]=captured
        if not attachment or attachment.slot~=slot then return end -- the menu anchor's slot: the first panel's
        if not captured or not attachment.options.anchorMenus[1] then
            if menus then menus.Stop() end
            return
        end
        if not menus then
            local ok,module=pcall(require,'winxi.nativemenus')
            if not ok then menuReason='Update Winxi/uihook for native menu anchoring.'; return end
            menus=module.new()
        end
        local ok,ready=pcall(menus.Set,attachment.menus,slot)
        if not ok then menuReason='Native menu anchor unavailable; menus unchanged.'
        elseif not ready then menuReason=menus.Status()
        else menuReason='Native action menus anchor above the info panel.' end
    end
    function service.Packet(options,id,data)
        local enabled=options.layout.enabled[1]
        if not enabled and id~=0x00a and id~=0x00b and id~=0x057 then return end
        local format=enabled and id==0x02D and Formats(options) or ''
        source.Packet(id,data,format,enabled)
        if id==0x00a or id==0x00b or id==0x057 then service.Invalidate() end
    end
    -- floor: where attached panels end, while the input is open its bottom (the input is lifted to sit
    -- on them); nil, each host's bottom.
    function service.Prepare(options,primary,split,inputHeight,chatFontSize,chatFontFile,floor)
        local layouts=M.Layouts(options,primary,split)
        if #layouts==0 then return nil end
        local now=os.clock()
        -- the fields read four times a second (at once for another set of layouts); where they cannot be read,
        -- tried again then, not every frame
        if now>=nextSample or (samples and #samples~=#layouts) then
            nextSample=now+0.25
            local context=source.Context(Formats(options),now)
            if not context then samples=nil; return nil end
            local icons=deps.icons or require('winxi.infopanel.icons')
            context.dayIcon=icons.Day(options.iconSet,context.weekday) or icons.Day('gems',context.weekday)
            context.weatherIcon=icons.Weather(options.iconSet,context.weatherId) or icons.Weather('gems',context.weatherId)
            samples={}
            for i,l in ipairs(layouts) do samples[i]=panel.Build(l.p,fields,context) end
        end
        if not samples then return nil end
        local size=options.fontSize[1]>0 and options.fontSize[1] or chatFontSize
        local function Content(built)
            local height=size
            for _,group in ipairs(built) do
                for _,s in ipairs(group) do
                    if type(s)=='table' and s.icon then
                        height=math.max(height,size*options.iconScale[1]*(s.kind=='weather' and options.weatherScale[1] or 1))
                    end
                end
            end
            return height
        end
        local top=options.anchor[1]==1
        local panels,lift={},0
        for i,l in ipairs(layouts) do
            panels[i]={slot=l.slot,p=l.p,samples=samples[i],rect=M.Bounds(l.p,l.host,inputHeight,chatFontSize,Content(samples[i]),top)}
            if l.p.attached[1] then lift=math.max(lift,panels[i].rect.height) end
        end
        if top then
            -- Over the logs: chat and input stay where the game puts them, native menus anchor above the
            -- first panel; attached panels share one height
            for i,l in ipairs(layouts) do
                if l.p.attached[1] then panels[i].rect.top,panels[i].rect.height=l.host.top-lift+l.p.offsetY[1],lift end
            end
            return {slot=panels[1].slot,rect=panels[1].rect,panels=panels,lift=0,inputLift=0,menus=panels[1].rect,size=size,
                fontFile=options.fontFile~='' and options.fontFile or chatFontFile,options=options}
        end
        -- Attached panels share one height, so side-by-side logs keep one bottom; every drawn log is
        -- lifted by it to sit wholly above them. Native menus always anchor to the visible first
        -- panel, never the chat stack's reserved/empty height. None attached: chat stays.
        local first,anchor,logLift=panels[1],panels[1].rect,lift
        if lift>0 then
            for i,l in ipairs(layouts) do
                if l.p.attached[1] then panels[i].rect.top,panels[i].rect.height=(floor or l.host.bottom)-lift+l.p.offsetY[1],lift end
            end
            local host=layouts[1].host
            -- Open, the input is lifted by the panels' height; the logs only as far as clears it
            if floor then logLift=math.max(0,host.bottom-(floor-lift-(inputHeight or 0))) end
            local top=host.top
            if primary and split then top=math.min(primary.top,split.top) end
            top=top-logLift
            if top<0 then return nil end -- no room to lift chat over the panel: no panel
            -- Keep anchor pointing at first.rect: lifting chat must not lift combat submenus
            -- above its full frame (including rows which are empty or fading away).
        end
        -- lift: the logs'; inputLift: the open input's, onto the panels
        return {slot=first.slot,rect=first.rect,panels=panels,lift=logLift,inputLift=floor and lift or 0,menus=anchor,size=size,
            fontFile=options.fontFile~='' and options.fontFile or chatFontFile,options=options}
    end
    local drawOptions={reserve=false} -- filled afresh for each panel drawn
    function service.Draw(attachment,slot)
        if not attachment then return end
        local imgui=require('imgui')
        local fonts=require('winxi.fonts')
        local frame=deps.frame or require('winxi.frame')
        local options=attachment.options
        for _,drawn in ipairs(attachment.panels) do
            if drawn.slot==slot then
                frame.Draw(drawn.rect,function()
                    imgui.PushFont(fonts.Get(attachment.fontFile),attachment.size)
                    drawingSlot=slot
                    hoveredOptions=options
                    drawOptions.tooltip=Tooltip
                    drawOptions.textColor,drawOptions.iconScale=options.textColor,options.iconScale
                    drawOptions.iconOffset,drawOptions.weatherScale=options.iconOffset,options.weatherScale
                    local ok,err=pcall(panel.Draw,drawn.p,drawn.samples,drawn.rect,drawOptions)
                    imgui.PopFont()
                    if not ok then error(err,0) end
                end)
            end
        end
    end
    return service
end
return M
