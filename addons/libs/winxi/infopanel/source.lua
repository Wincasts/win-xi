-- Data for a chat-owned panel. Native HUD access is optional and READ-ONLY: it supplies
-- the native map grid when fresh, never gates time/zone/EXP or panel rendering.
local fields = require('winxi.infopanel.fields')
local exp = require('winxi.infopanel.exp')
local M = {}
local function U16(data,offset)
    if type(data)~='string' or #data<offset+2 then return nil end
    local a,b=data:byte(offset+1,offset+2); return a+b*256
end
function M.New(deps)
    deps=deps or {}
    local time, hud, weather, problem
    local source = {}
    function source.Reset()
        time,hud,weather,problem=nil,nil,nil,nil
        exp.Reset()
    end
    function source.Packet(id,data,format,enabled)
        -- Phoenix/XiPackets: weather at 0x68 in login (0x00A), 0x08 in weather (0x057).
        -- Clear on zone departure even if the panel is currently disabled.
        if id==0x00b then weather=nil
        elseif id==0x00a or id==0x057 then
            local value=U16(data,id==0x00a and 0x68 or 0x08)
            weather=value and value<=19 and value or nil
        end
        if enabled and id==0x02D and fields.Uses(format,'exp') then exp.Packet(id,data) end
    end
    function source.Context(format,now)
        if not time then
            local ok,value=pcall(function() return deps.time or require('ffxi.time') end)
            if not ok then problem='Time unavailable: '..tostring(value); return nil end
            time=value
        end
        local grid, currentWeather
        -- A missing/hidden/disabled clock can omit grid, but never hides the panel.
        pcall(function()
            if not hud then
                local native=deps.native or require('winxi.nativehud')
                hud=native.new(native.Clock)
            end
            grid=hud.Grid()
            currentWeather=hud.Weather()
        end)
        local id=weather or currentWeather
        local name
        if id and id>0 and fields.Has(format,'weather') then
            local ok,value=pcall(function() return AshitaCore:GetResourceManager():GetString('weather',id) end)
            name=ok and type(value)=='string' and value~='' and value or ('Weather '..id)
        end
        local ok,context=pcall(fields.Context,time,grid,name)
        if not ok then problem='Time unavailable: '..tostring(context); return nil end
        context.weekday=time.get_game_weekday(context.raw)
        context.weatherId=id
        context.exp=fields.Uses(format,'exp') and exp.Snapshot(now,3600) or nil
        problem=nil
        return context
    end
    function source.Status() return problem end
    return source
end
return M
